import Foundation
import Darwin
import Security

/// A filesystem/signature snapshot, not launchd liveness or installation authorization.
enum HelperInstallation: Equatable {
 case none, developmentLayout, olderNative(ownedByApp: Bool), unrecognized
 var present: Bool { self != .none }
}

struct HelperSliceIdentity {
 let identifier: String
 let team: String?
 let info: [String: Any]
}

struct HelperInstallationInspector {
 static let label = "org.opencharge.charged"
 private let plistDirectory: URL
 private let helperDirectory: URL
 private let owner: uid_t
 private let expectedProgram: String
 private let identities: (URL, [(Int32, Int32)]) -> [HelperSliceIdentity]?
 private let matches: (URL, String) -> Bool
 private let app: Bundle

 init(app: Bundle, plistDirectory: URL = URL(fileURLWithPath: "/Library/LaunchDaemons"),
      helperDirectory: URL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), owner: uid_t = 0,
      expectedProgram: String = "/Library/PrivilegedHelperTools/org.opencharge.charged",
      identities: @escaping (URL, [(Int32, Int32)]) -> [HelperSliceIdentity]? = Self.codeIdentities,
      matches: @escaping (URL, String) -> Bool = Self.matchesRequirement) {
  self.app = app; self.plistDirectory = plistDirectory; self.helperDirectory = helperDirectory
  self.owner = owner; self.expectedProgram = expectedProgram; self.identities = identities; self.matches = matches
 }
 private struct Entry {
  let fd: Int32
  let attributes: stat
 }
 private enum InspectionError: Error { case invalid }
 private func openDirectory(_ url: URL) throws -> Int32? {
  let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  if fd < 0 { if errno == ENOENT { return nil }; throw InspectionError.invalid }
  var attributes = stat()
  guard fstat(fd, &attributes) == 0, attributes.st_uid == owner,
        attributes.st_mode & (S_IWGRP | S_IWOTH) == 0 else { close(fd); throw InspectionError.invalid }
  return fd
 }
 private func safe(_ value: stat, executable: Bool, limit: Int) -> Bool {
  value.st_uid == owner && value.st_mode & S_IFMT == S_IFREG && value.st_nlink == 1 &&
   value.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX) == 0 &&
   (!executable || value.st_mode & S_IXUSR != 0) && value.st_size > 0 && value.st_size <= limit
 }
 private func openEntry(_ directory: Int32?, name: String, executable: Bool, limit: Int) throws -> Entry? {
  guard let directory else { return nil }
  var before = stat()
  if fstatat(directory, name, &before, AT_SYMLINK_NOFOLLOW) != 0 {
   if errno == ENOENT { return nil }; throw InspectionError.invalid
  }
  guard safe(before, executable: executable, limit: limit) else { throw InspectionError.invalid }
  let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
  guard fd >= 0 else { throw InspectionError.invalid }
  var after = stat()
  guard fstat(fd, &after) == 0, same(before, after) else { close(fd); throw InspectionError.invalid }
  return Entry(fd: fd, attributes: after)
 }
 private func same(_ a: stat, _ b: stat) -> Bool {
  a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode &&
   a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
   a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
   a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
 }
 private func stable(_ entry: Entry, directory: Int32, name: String) -> Bool {
  var current = stat(), opened = stat()
  return fstat(entry.fd, &opened) == 0 && fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
   same(entry.attributes, opened) && same(entry.attributes, current)
 }
 private func bytes(_ entry: Entry, count: Int) throws -> [UInt8] {
  var data = [UInt8](repeating: 0, count: count)
  let actual = data.withUnsafeMutableBytes { pread(entry.fd, $0.baseAddress, count, 0) }
  guard actual == count else { throw InspectionError.invalid }; return data
 }
 private func architectures(_ entry: Entry) throws -> [(Int32, Int32)] {
  let data = try bytes(entry, count: min(4096, Int(entry.attributes.st_size)))
  func integer(_ offset: Int, big: Bool) throws -> UInt32 {
   guard offset >= 0, offset + 4 <= data.count else { throw InspectionError.invalid }
   let b = Array(data[offset..<(offset + 4)])
   return (big ? b : b.reversed()).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }
  let magic = try integer(0, big: true)
  var values: [(Int32, Int32)] = []
  if magic == 0xcffaedfe { // little-endian 64-bit Mach-O
   values = [(Int32(bitPattern: try integer(4, big: false)), Int32(bitPattern: try integer(8, big: false)))]
  } else if magic == 0xcafebabe || magic == 0xcafebabf {
   let count = Int(try integer(4, big: true)), stride = magic == 0xcafebabe ? 20 : 32
   guard (1...2).contains(count), 8 + count * stride <= data.count else { throw InspectionError.invalid }
   for index in 0..<count {
    let offset = 8 + index * stride
    values.append((Int32(bitPattern: try integer(offset, big: true)), Int32(bitPattern: try integer(offset + 4, big: true))))
   }
  } else { throw InspectionError.invalid }
  guard values.allSatisfy({ ($0.0 == 0x0100000c && $0.1 == 0) || ($0.0 == 0x01000007 && $0.1 == 3) }),
        Set(values.map { $0.0 }).count == values.count else { throw InspectionError.invalid }
  return values
 }
 private func boolean(_ value: Any?, equals expected: Bool) -> Bool {
  guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
  return value.boolValue == expected
 }
 func inspect() -> HelperInstallation {
  do {
   let plistFD = try openDirectory(plistDirectory); defer { if let plistFD { close(plistFD) } }
   let helperFD = try openDirectory(helperDirectory); defer { if let helperFD { close(helperFD) } }
   let plist = try openEntry(plistFD, name: Self.label + ".plist", executable: false, limit: 16384)
   defer { if let plist { close(plist.fd) } }
   let helper = try openEntry(helperFD, name: Self.label, executable: true, limit: 64 * 1024 * 1024)
   defer { if let helper { close(helper.fd) } }
   if plist == nil && helper == nil { return .none }
   guard let plist, let helper, let plistFD, let helperFD,
         let object = try PropertyListSerialization.propertyList(from: Data(bytes(plist, count: Int(plist.attributes.st_size))), format: nil) as? [String: Any],
         object["Label"] as? String == Self.label, object["ProgramArguments"] as? [String] == [expectedProgram],
         boolean(object["RunAtLoad"], equals: true), boolean(object["KeepAlive"], equals: true),
         let interval = object["ThrottleInterval"] as? NSNumber, CFGetTypeID(interval) != CFBooleanGetTypeID(), interval.doubleValue == 30, !["f", "d"].contains(String(cString: interval.objCType)),
         let slices = identities(helperDirectory.appendingPathComponent(Self.label), try architectures(helper)), !slices.isEmpty else { return .unrecognized }
   let base = Set(["Label", "ProgramArguments", "RunAtLoad", "KeepAlive", "ThrottleInterval"])
   let helperURL = helperDirectory.appendingPathComponent(Self.label)
   let result: HelperInstallation
   if Set(object.keys) == base,
      slices.allSatisfy({ ($0.identifier == "charged" || $0.identifier.hasPrefix("charged-")) && $0.info.isEmpty }) {
    result = .developmentLayout
   } else if Set(object.keys) == base.union(["ProcessType"]), object["ProcessType"] as? String == "Interactive",
             let first = slices.first, let team = first.team, team.utf8.count == 10, team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
             let version = first.info["CFBundleVersion"] as? String, version.range(of: "^[0-9]+(?:\\.[0-9]+){0,2}$", options: .regularExpression) == version.startIndex..<version.endIndex {
    let common = " and anchor apple generic and certificate leaf[subject.OU] = \"" + team + "\""
    let helperRequirement = "identifier \"" + Self.label + "\"" + common
    let clientRequirement = "identifier \"org.opencharge.app\"" + common
    guard slices.allSatisfy({ slice in
     slice.identifier == Self.label && slice.team == team && slice.info["CFBundleIdentifier"] as? String == Self.label &&
      slice.info["OpenChargeInstallRoute"] as? String == "blessedV1" && slice.info["CFBundleVersion"] as? String == version &&
      slice.info["SMAuthorizedClients"] as? [String] == [clientRequirement]
    }), matches(helperURL, helperRequirement) else { return .unrecognized }
    let ownership = (app.infoDictionary?["SMPrivilegedExecutables"] as? [String: String])?[Self.label] == helperRequirement &&
     app.bundleIdentifier == "org.opencharge.app" && matches(app.bundleURL, clientRequirement)
    result = .olderNative(ownedByApp: ownership)
   } else { return .unrecognized }
   guard stable(plist, directory: plistFD, name: Self.label + ".plist"), stable(helper, directory: helperFD, name: Self.label) else { return .unrecognized }
   return result
  } catch { return .unrecognized }
 }
 static func codeIdentities(_ url: URL, _ architectures: [(Int32, Int32)]) -> [HelperSliceIdentity]? {
  var result: [HelperSliceIdentity] = []
  for (cpu, subtype) in architectures {
   var code: SecStaticCode?, information: CFDictionary?
   let attributes = [kSecCodeAttributeArchitecture as String: NSNumber(value: cpu), kSecCodeAttributeSubarchitecture as String: NSNumber(value: subtype)] as CFDictionary
   guard SecStaticCodeCreateWithPathAndAttributes(url as CFURL, [], attributes, &code) == errSecSuccess, let code,
         SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
         SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
         let dictionary = information as? [String: Any], let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String else { return nil }
   result.append(HelperSliceIdentity(identifier: identifier, team: dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
    info: dictionary[kSecCodeInfoPList as String] as? [String: Any] ?? [:]))
  }
  return result
 }
 static func matchesRequirement(_ url: URL, _ value: String) -> Bool {
  var code: SecStaticCode?, requirement: SecRequirement?
  guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
        SecRequirementCreateWithString(value as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
  return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess
 }
}
