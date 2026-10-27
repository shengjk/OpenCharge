import Foundation
import Darwin
import Security
import ServiceManagement

public enum NativeHelperRemovalError: Error, LocalizedError {
 case rejected(String)
 public var errorDescription: String? { if case .rejected(let reason) = self { return "Service removal refused: "+reason }; return nil }
}

/// Identity is captured from the running blessed helper, never from request parameters.
public struct NativeHelperRemovalIdentity {
 public static let label = "org.opencharge.charged"
 public static let path = "/Library/PrivilegedHelperTools/"+label
 public let team: String
 private let cdhash: Data
 private var clientRequirement: String { "identifier \"org.opencharge.app\" and anchor apple generic and certificate leaf[subject.OU] = \""+team+"\"" }
 public static func current() throws -> Self {
  var live: SecCode?, code: SecStaticCode?, location: CFURL?, info: CFDictionary?
  guard geteuid() == 0, SecCodeCopySelf([],&live) == errSecSuccess, let live,
        SecCodeCopyStaticCode(live,[],&code) == errSecSuccess, let code,
        SecCodeCopyPath(code,[],&location) == errSecSuccess, let location,
        (location as URL).standardizedFileURL.path == path,
        SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
        let values = info as? [String:Any], values[kSecCodeInfoIdentifier as String] as? String == label,
        let team = values[kSecCodeInfoTeamIdentifier as String] as? String, team.range(of:"^[A-Z0-9]{10}$",options:.regularExpression) != nil,
        let cdhash = values[kSecCodeInfoUnique as String] as? Data,
        let embedded = values[kSecCodeInfoPList as String] as? [String:Any],
        embedded["CFBundleIdentifier"] as? String == label, embedded["OpenChargeInstallRoute"] as? String == "blessedV1" else { throw NativeHelperRemovalError.rejected("running helper identity") }
  let identity = Self(team:team,cdhash:cdhash)
  guard embedded["SMAuthorizedClients"] as? [String] == [identity.clientRequirement], identity.matchesInstalledCode(URL(fileURLWithPath:path)) else { throw NativeHelperRemovalError.rejected("helper signing relationship") }
  return identity
 }
 public func matchesInstalledCode(_ url: URL) -> Bool {
  var code: SecStaticCode?, requirement: SecRequirement?, info: CFDictionary?
  let value = "identifier \""+Self.label+"\" and anchor apple generic and certificate leaf[subject.OU] = \""+team+"\""
  guard SecStaticCodeCreateWithPath(url as CFURL,[],&code) == errSecSuccess, let code,
        SecRequirementCreateWithString(value as CFString,[],&requirement) == errSecSuccess, let requirement,
        SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSStrictValidate),requirement) == errSecSuccess,
        SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
        let values = info as? [String:Any] else { return false }
  return values[kSecCodeInfoUnique as String] as? Data == cdhash
 }
 public func authorize(peer socket: Int32, externalForm data: Data) throws {
  var token = audit_token_t(), size = socklen_t(MemoryLayout<audit_token_t>.size)
  guard getsockopt(socket,SOL_LOCAL,LOCAL_PEERTOKEN,&token,&size) == 0, size == MemoryLayout<audit_token_t>.size else { throw NativeHelperRemovalError.rejected("peer audit token") }
  var guest: SecCode?, requirement: SecRequirement?
  let audit = Data(bytes:&token,count:Int(size))
  guard SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributeAudit as String:audit] as CFDictionary,[],&guest) == errSecSuccess, let guest,
        SecRequirementCreateWithString(clientRequirement as CFString,[],&requirement) == errSecSuccess, let requirement,
        SecCodeCheckValidity(guest,[],requirement) == errSecSuccess else { throw NativeHelperRemovalError.rejected("requesting app signature") }
  try Self.verifyAuthorization(data)
 }
 private static func verifyAuthorization(_ data: Data) throws {
  guard data.count == MemoryLayout<AuthorizationExternalForm>.size else { throw NativeHelperRemovalError.rejected("authorization length") }
  var form = AuthorizationExternalForm()
  _ = withUnsafeMutableBytes(of:&form) { data.copyBytes(to:$0) }
  var reference: AuthorizationRef?
  guard AuthorizationCreateFromExternalForm(&form,&reference) == errAuthorizationSuccess, let reference else { throw NativeHelperRemovalError.rejected("authorization reference") }
  defer { AuthorizationFree(reference,[]) }
  let status = kSMRightModifySystemDaemons.withCString { name -> OSStatus in
   var item = AuthorizationItem(name:name,valueLength:0,value:nil,flags:0)
   return withUnsafeMutablePointer(to:&item) { pointer in
    var rights = AuthorizationRights(count:1,items:pointer)
    // Only verify the caller's previously granted right; the root helper never prompts or extends it.
    return AuthorizationCopyRights(reference,&rights,nil,[],nil)
   }
  }
  guard status == errAuthorizationSuccess else { throw NativeHelperRemovalError.rejected("administrator right") }
 }
}

/// Fixed, descriptor-relative installed-file removal. Hardware restoration and empty journals precede unlink.
/// The process remains alive for a reply/retry; its caller must then unregister the launchd job.
public final class NativeHelperFileRemoval {
 private let plistDirectory: URL, helperDirectory: URL
 private let owner: uid_t
 private let signature: (URL) -> Bool
 private let remove: (Int32,String) throws -> Void
 private var snapshot: Snapshot?
 public private(set) var completed = false
 public var pending: Bool { snapshot != nil }
 private struct Entry { let fd: Int32; let attributes: stat }
 private final class Snapshot {
  let plistDir: Int32, helperDir: Int32, plist: Entry, helper: Entry
  var restored = false, plistRemoved = false, helperRemoved = false
  init(plistDir:Int32,helperDir:Int32,plist:Entry,helper:Entry) { self.plistDir=plistDir;self.helperDir=helperDir;self.plist=plist;self.helper=helper }
  deinit { for fd in [plist.fd,helper.fd,plistDir,helperDir] { close(fd) } }
 }
 public init(plistDirectory:URL = URL(fileURLWithPath:"/Library/LaunchDaemons"), helperDirectory:URL = URL(fileURLWithPath:"/Library/PrivilegedHelperTools"), owner:uid_t = 0, signature:@escaping(URL)->Bool,
             remove:@escaping(Int32,String)throws->Void = { fd,name in guard unlinkat(fd,name,0) == 0 else { throw NativeHelperRemovalError.rejected("unlink errno \(errno)") } }) {
  self.plistDirectory=plistDirectory;self.helperDirectory=helperDirectory;self.owner=owner;self.signature=signature;self.remove=remove
 }
 public func removeFiles(restore:()throws->Void, recoveryPending:()throws->Bool) throws {
  if completed { guard try !recoveryPending() else { throw NativeHelperRemovalError.rejected("hardware recovery pending") }; try ensureAbsent(); return }
  if snapshot == nil { snapshot = try capture() }
  guard let snapshot else { throw NativeHelperRemovalError.rejected("installation snapshot") }
  if !snapshot.restored {
   try restore()
   guard try !recoveryPending() else { throw NativeHelperRemovalError.rejected("hardware recovery pending") }
   snapshot.restored = true
  }
  guard try !recoveryPending() else { throw NativeHelperRemovalError.rejected("hardware recovery pending") }
  let plistName = NativeHelperRemovalIdentity.label+".plist", helperName = NativeHelperRemovalIdentity.label
  if !snapshot.plistRemoved {
   guard stable(snapshot.plist,in:snapshot.plistDir,name:plistName), stable(snapshot.helper,in:snapshot.helperDir,name:helperName) else { throw NativeHelperRemovalError.rejected("installed files changed") }
   try remove(snapshot.plistDir,plistName); snapshot.plistRemoved = true
  }
  guard absent(in:snapshot.plistDir,name:plistName) else { throw NativeHelperRemovalError.rejected("plist reappeared") }
  if !snapshot.helperRemoved {
   guard stable(snapshot.helper,in:snapshot.helperDir,name:helperName) else { throw NativeHelperRemovalError.rejected("helper changed") }
   try remove(snapshot.helperDir,helperName); snapshot.helperRemoved = true
  }
  guard fsync(snapshot.plistDir) == 0, fsync(snapshot.helperDir) == 0 else { throw NativeHelperRemovalError.rejected("directory sync") }
  try ensureAbsent(); completed = true
 }
 private func capture() throws -> Snapshot {
  let pd = try directory(plistDirectory)
  var hd: Int32 = -1, pf: Entry?, hf: Entry?
  do {
   hd = try directory(helperDirectory)
   pf = try entry(pd,name:NativeHelperRemovalIdentity.label+".plist",executable:false,limit:16384)
   hf = try entry(hd,name:NativeHelperRemovalIdentity.label,executable:true,limit:64*1024*1024)
   guard let pf,let hf, signature(helperDirectory.appendingPathComponent(NativeHelperRemovalIdentity.label)) else { throw NativeHelperRemovalError.rejected("installed helper signature") }
   var data = Data(count:Int(pf.attributes.st_size))
   let count = data.withUnsafeMutableBytes { pread(pf.fd,$0.baseAddress,$0.count,0) }
   guard count == data.count, let plist = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
         Set(plist.keys) == Set(["Label","ProgramArguments","RunAtLoad","KeepAlive","ThrottleInterval","ProcessType"]),
         plist["Label"] as? String == NativeHelperRemovalIdentity.label,
         plist["ProgramArguments"] as? [String] == [NativeHelperRemovalIdentity.path],
         boolean(plist["RunAtLoad"]),boolean(plist["KeepAlive"]),
         let interval=plist["ThrottleInterval"] as? NSNumber,CFGetTypeID(interval) != CFBooleanGetTypeID(),interval.intValue == 30,!["f","d"].contains(String(cString:interval.objCType)),
         plist["ProcessType"] as? String == "Interactive",
         stable(pf,in:pd,name:NativeHelperRemovalIdentity.label+".plist"),stable(hf,in:hd,name:NativeHelperRemovalIdentity.label) else { throw NativeHelperRemovalError.rejected("installed file metadata") }
   return Snapshot(plistDir:pd,helperDir:hd,plist:pf,helper:hf)
  } catch { if let pf {close(pf.fd)}; if let hf {close(hf.fd)}; close(pd); if hd >= 0 {close(hd)}; throw error }
 }
 private func boolean(_ value:Any?) -> Bool { guard let n=value as? NSNumber,CFGetTypeID(n) == CFBooleanGetTypeID() else{return false};return n.boolValue }
 private func directory(_ url:URL) throws -> Int32 {
  let fd = open(url.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
  guard fd >= 0 else {throw NativeHelperRemovalError.rejected("installation directory")}
  var value=stat()
  guard fstat(fd,&value) == 0,value.st_uid == owner,value.st_mode & 0o022 == 0 else {close(fd);throw NativeHelperRemovalError.rejected("directory ownership")}
  return fd
 }
 private func entry(_ dir:Int32,name:String,executable:Bool,limit:Int) throws -> Entry {
  let fd = openat(dir,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
  guard fd >= 0 else {throw NativeHelperRemovalError.rejected("installation entry")}
  var value=stat()
  guard fstat(fd,&value) == 0,value.st_uid == owner,value.st_mode & S_IFMT == S_IFREG,value.st_nlink == 1,
        value.st_mode & 0o7022 == 0,(!executable || value.st_mode & S_IXUSR != 0),value.st_size > 0,value.st_size <= limit else {close(fd);throw NativeHelperRemovalError.rejected("entry ownership/type")}
  return Entry(fd:fd,attributes:value)
 }
 private func stable(_ entry:Entry,in dir:Int32,name:String)->Bool {
  var value=stat(),opened=stat()
  func equal(_ a:stat,_ b:stat)->Bool { a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink && a.st_size == b.st_size && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec }
  return fstat(entry.fd,&opened) == 0 && fstatat(dir,name,&value,AT_SYMLINK_NOFOLLOW) == 0 && equal(entry.attributes,opened) && equal(entry.attributes,value)
 }
 private func absent(in dir:Int32,name:String)->Bool {var value=stat();return fstatat(dir,name,&value,AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT}
 private func ensureAbsent() throws {
  guard let snapshot,absent(in:snapshot.plistDir,name:NativeHelperRemovalIdentity.label+".plist"),absent(in:snapshot.helperDir,name:NativeHelperRemovalIdentity.label) else {throw NativeHelperRemovalError.rejected("installed files remain")}
 }
}
