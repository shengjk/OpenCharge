import Foundation
import Darwin

@main struct HelperInstallationChecks {
 static func main() throws {
  let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("org.opencharge.installation-test." + UUID().uuidString)
  try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporary) }
  let plists = temporary.appendingPathComponent("LaunchDaemons"), helpers = temporary.appendingPathComponent("PrivilegedHelperTools")
  for folder in [plists, helpers] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); chmod(folder.path, 0o700) }
  let label = HelperInstallationInspector.label
  let plist = plists.appendingPathComponent(label + ".plist"), helper = helpers.appendingPathComponent(label)
  let helperRequirement = "identifier \"org.opencharge.charged\" and anchor apple generic and certificate leaf[subject.OU] = \"TESTTEAM01\""
  let clientRequirement = "identifier \"org.opencharge.app\" and anchor apple generic and certificate leaf[subject.OU] = \"TESTTEAM01\""
  let appURL = temporary.appendingPathComponent("Fixture.app")
  try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
  try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"org.opencharge.app", "SMPrivilegedExecutables":[label:helperRequirement]], format:.xml, options:0).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
  let app = Bundle(url:appURL)!
  var identities = [HelperSliceIdentity(identifier:"charged-fixture",team:nil,info:[:])]
  var helperMatches = true, appMatches = true
  var onIdentity: (() throws -> Void)?
  func inspector(owner: uid_t = getuid()) -> HelperInstallationInspector {
   HelperInstallationInspector(app:app,plistDirectory:plists,helperDirectory:helpers,owner:owner,
    identities:{ _, arches in
     try! onIdentity?()
     return arches.indices.map { identities[min($0, identities.count - 1)] }
    }, matches:{ url, requirement in
     if url.standardizedFileURL.path == helper.standardizedFileURL.path { precondition(requirement == helperRequirement); return helperMatches }
     precondition(url.standardizedFileURL.path == appURL.standardizedFileURL.path && requirement == clientRequirement); return appMatches
    })
  }
  let base: [String:Any] = ["Label":label,"ProgramArguments":["/Library/PrivilegedHelperTools/"+label],"RunAtLoad":true,"KeepAlive":true,"ThrottleInterval":30]
  func write(_ value: [String:Any] = base) throws {
   try PropertyListSerialization.data(fromPropertyList:value,format:.xml,options:0).write(to:plist)
   chmod(plist.path,0o600)
  }
  func binary() throws {
   // Thin arm64 header; cryptographic evidence is injected separately.
   var data = Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1,0,0,0,0]); data.append(Data(repeating:0,count:52))
   try data.write(to:helper); chmod(helper.path,0o700)
  }
  precondition(inspector().inspect() == .none)
  try write(); precondition(inspector().inspect() == .unrecognized,"orphan plist cannot mean absent")
  try binary(); precondition(inspector().inspect() == .developmentLayout)
  let original = try Data(contentsOf:plist)
  for mutation in ["program","boolean","interval","float","extra"] {
   var value = base
   switch mutation { case "program": value["ProgramArguments"]=["/tmp/foreign"]
    case "boolean": value["KeepAlive"]=1
    case "interval": value["ThrottleInterval"]=30.5
    case "float": value["ThrottleInterval"]=30.0
    default: value["UserName"]="other" }
   try write(value); precondition(inspector().inspect() == .unrecognized)
  }
  try write()
  chmod(helper.path,0o720); precondition(inspector().inspect() == .unrecognized); chmod(helper.path,0o700)
  chmod(plists.path,0o777); precondition(inspector().inspect() == .unrecognized); chmod(plists.path,0o700)
  precondition(inspector(owner:getuid()+1).inspect() == .unrecognized)
  let alias = temporary.appendingPathComponent("alias")
  precondition(link(helper.path,alias.path)==0); precondition(inspector().inspect() == .unrecognized); unlink(alias.path)
  try FileManager.default.removeItem(at:plist); try FileManager.default.createSymbolicLink(at:plist,withDestinationURL:helper)
  precondition(inspector().inspect() == .unrecognized); try FileManager.default.removeItem(at:plist); try write()
  try Data(repeating:65,count:16385).write(to:plist); precondition(inspector().inspect() == .unrecognized); try write()
  var blessed = base; blessed["ProcessType"]="Interactive"; try write(blessed)
  let info: [String:Any] = ["CFBundleIdentifier":label,"CFBundleVersion":"49","OpenChargeInstallRoute":"blessedV1","SMAuthorizedClients":[clientRequirement]]
  identities=[HelperSliceIdentity(identifier:label,team:"TESTTEAM01",info:info)]
  precondition(inspector().inspect() == .olderNative(ownedByApp:true))
  appMatches=false; precondition(inspector().inspect() == .olderNative(ownedByApp:false)); appMatches=true
  helperMatches=false; precondition(inspector().inspect() == .unrecognized); helperMatches=true
  var broad = info; broad["SMAuthorizedClients"]=["always"]
  identities=[HelperSliceIdentity(identifier:label,team:"TESTTEAM01",info:broad)]
  precondition(inspector().inspect() == .unrecognized)
  identities=[HelperSliceIdentity(identifier:label,team:"TESTTEAM01",info:info)]
  // A nonhost slice must satisfy exactly the same identity policy.
  var fat = Data([0xca,0xfe,0xba,0xbe,0,0,0,2])
  fat.append(Data([1,0,0,12,0,0,0,0])); fat.append(Data(repeating:0,count:12))
  fat.append(Data([1,0,0,7,0,0,0,3])); fat.append(Data(repeating:0,count:12))
  try fat.write(to:helper)
  identities=[HelperSliceIdentity(identifier:label,team:"TESTTEAM01",info:info),HelperSliceIdentity(identifier:label,team:"OTHERTEAM1",info:info)]
  precondition(inspector().inspect() == .unrecognized)
  identities=[HelperSliceIdentity(identifier:label,team:"TESTTEAM01",info:info)]
  precondition(inspector().inspect() == .olderNative(ownedByApp:true))
  try binary()
  onIdentity={ try Data("changed".utf8).write(to:plist) }
  precondition(inspector().inspect() == .unrecognized,"changes during validation must invalidate the snapshot")
  onIdentity=nil; try write(); identities=[HelperSliceIdentity(identifier:"charged-fixture",team:nil,info:[:])]
  let before = try Data(contentsOf:plist), helperBefore = try Data(contentsOf:helper)
  precondition(inspector().inspect() == .developmentLayout)
  let after = try Data(contentsOf:plist), helperAfter = try Data(contentsOf:helper)
  precondition(after == before && helperAfter == helperBefore)
  precondition(original == before)
  // Actual on-disk service is inspected only; no service/IPC API is invoked.
  let observed = HelperInstallationInspector(app:app).inspect()
  print("PASS helper installation snapshots: absence/orphans/layout/permissions/links/types/signature-policy/ownership/race; isolated files only; actual read-only snapshot: \(observed)")
 }
}
