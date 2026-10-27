import Foundation
import Darwin
import ChargeCore
import ChargeHardware

@main struct NativeRemovalChecks {
 static func main() throws {
  let wire = ServiceFileRemovalRequest(externalForm:Data(repeating:0,count:32))!
  precondition(ServiceFileRemovalRequest.parse(wire.wireValue)?.externalForm == wire.externalForm && wire.wireValue.utf8.count < 128)
  for value in ["",wire.wireValue+"\n",wire.wireValue+" ","removeServiceFiles:"+Data(repeating:0,count:31).base64EncodedString(),"removeServiceFiles:"+Data(repeating:0,count:33).base64EncodedString(),"removeServiceFiles:../tmp",wire.wireValue+"="] {
   precondition(ServiceFileRemovalRequest.parse(value) == nil)
   do { _ = try HelperClient.request(value); preconditionFailure("invalid removal request reached IPC") } catch HelperError.rejected { }
  }
  for value in ["serviceRemoval:ownedV1","other:yes, serviceRemoval:pendingV1"] { precondition(ServiceFileRemovalRequest.supports(value)) }
  for value in ["serviceRemoval:unavailable","serviceRemoval:ownedV2","serviceRemoval:ownedV10","serviceRemoval:ownedV1,serviceRemoval:unavailable","notserviceRemoval:ownedV1",""] { precondition(!ServiceFileRemovalRequest.supports(value)) }
  precondition(ServiceFileRemovalRequest.permitsWhilePending(wire.wireValue))
  for command in ["capabilities","restore","sleepOverrideRestore","firmwareStatus","magSafeStatus","lowPowerStatus"] { precondition(ServiceFileRemovalRequest.permitsWhilePending(command)) }
  for command in ["allowCharge","inhibitCharge","forceDischarge","lowPowerOn","magSafeGreen","sleepOverrideOn","firmwareAllow","firmwareLimit:80"] { precondition(!ServiceFileRemovalRequest.permitsWhilePending(command)) }
  do { _ = try NativeHelperRemovalIdentity.current(); preconditionFailure("fixture executable qualified as installed root helper") } catch NativeHelperRemovalError.rejected { }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("opencharge-removal-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let fm = FileManager.default, label = NativeHelperRemovalIdentity.label
  func fixture(_ tag:String) throws -> (URL,URL,URL,URL) {
   let pd=root.appendingPathComponent(tag+"/LaunchDaemons"),hd=root.appendingPathComponent(tag+"/PrivilegedHelperTools")
   for d in [pd,hd] { try fm.createDirectory(at:d,withIntermediateDirectories:true);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:d.path) }
   let pf=pd.appendingPathComponent(label+".plist"),hf=hd.appendingPathComponent(label)
   let value:[String:Any] = ["Label":label,"ProgramArguments":[NativeHelperRemovalIdentity.path],"RunAtLoad":true,"KeepAlive":true,"ThrottleInterval":30,"ProcessType":"Interactive"]
   try PropertyListSerialization.data(fromPropertyList:value,format:.xml,options:0).write(to:pf)
   try Data("inert helper fixture".utf8).write(to:hf);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:hf.path)
   return (pd,hd,pf,hf)
  }
  func rejects(_ body:()throws->Void) { do {try body();preconditionFailure("unsafe removal accepted")}catch{} }
  do {
   let (pd,hd,pf,hf)=try fixture("success");var restored=0,checked=0
   let removal=NativeHelperFileRemoval(plistDirectory:pd,helperDirectory:hd,owner:getuid(),signature:{_ in true})
   try removal.removeFiles(restore:{precondition(fm.fileExists(atPath:pf.path)&&fm.fileExists(atPath:hf.path));restored+=1},recoveryPending:{checked+=1;precondition(restored==1);return false})
   precondition(removal.completed && removal.pending && !fm.fileExists(atPath:pf.path) && !fm.fileExists(atPath:hf.path))
   try removal.removeFiles(restore:{preconditionFailure("completed operation restored twice")},recoveryPending:{false})
   rejects { try removal.removeFiles(restore:{},recoveryPending:{true}) }
   try Data("foreign file".utf8).write(to:hf)
   rejects { try removal.removeFiles(restore:{},recoveryPending:{false}) }
   let foreign = try Data(contentsOf:hf); precondition(foreign == Data("foreign file".utf8))
   precondition(restored==1 && checked>=1)
  }
  for failure in ["signature","restore","journal","mode","owner","symlink","hardlink","directory","bad-program","integer-bool","extra-key","replacement"] {
   let (pd,hd,pf,hf)=try fixture(failure)
   if failure=="mode" {try fm.setAttributes([.posixPermissions:0o777],ofItemAtPath:hf.path)}
   if failure=="symlink" {try fm.removeItem(at:hf);try fm.createSymbolicLink(atPath:hf.path,withDestinationPath:"missing")}
   if failure=="hardlink" {try fm.linkItem(at:hf,to:hd.appendingPathComponent("other"))}
   if failure=="directory" {try fm.removeItem(at:hf);try fm.createDirectory(at:hf,withIntermediateDirectories:false)}
   if ["bad-program","integer-bool","extra-key"].contains(failure) {
    var p=try PropertyListSerialization.propertyList(from:Data(contentsOf:pf),format:nil) as! [String:Any]
    if failure=="bad-program" {p["ProgramArguments"]=["/bin/sh"]}
    if failure=="integer-bool" {p["RunAtLoad"]=1}
    if failure=="extra-key" {p["Program"]="/bin/sh"}
    try PropertyListSerialization.data(fromPropertyList:p,format:.xml,options:0).write(to:pf)
   }
   let removal=NativeHelperFileRemoval(plistDirectory:pd,helperDirectory:hd,owner:failure=="owner" ? getuid()+1:getuid(),signature:{_ in failure != "signature"})
   rejects { try removal.removeFiles(restore:{
    if failure=="restore" {throw CocoaError(.fileReadUnknown)}
    if failure=="replacement" {try fm.removeItem(at:hf);try Data("replacement".utf8).write(to:hf)}
   },recoveryPending:{failure=="journal"}) }
   precondition(fm.fileExists(atPath:pf.path),"pre-delete failure removed plist: "+failure)
   if ["restore","journal"].contains(failure) { precondition(removal.pending,"validated removal must block new writes while restoration remains incomplete") }
  }
  do {
   let (pd,hd,pf,hf)=try fixture("partial");var fail=true,restored=0
   let removal=NativeHelperFileRemoval(plistDirectory:pd,helperDirectory:hd,owner:getuid(),signature:{_ in true},remove:{fd,name in
    if fail && name==label {throw CocoaError(.fileWriteNoPermission)}
    precondition(unlinkat(fd,name,0)==0)
   })
   rejects {try removal.removeFiles(restore:{restored+=1},recoveryPending:{false})}
   precondition(removal.pending && !removal.completed && !fm.fileExists(atPath:pf.path) && fm.fileExists(atPath:hf.path))
   rejects {try removal.removeFiles(restore:{preconditionFailure("retry restored twice")},recoveryPending:{true})}
   fail=false
   try removal.removeFiles(restore:{preconditionFailure("retry restored twice")},recoveryPending:{false})
   precondition(removal.completed && restored==1 && !fm.fileExists(atPath:hf.path))
  }
  for kind in ["file","symlink","directory"] {
   let dir=root.appendingPathComponent("record-"+kind);try fm.createDirectory(at:dir,withIntermediateDirectories:true)
   try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:dir.path)
   let store=try ChargeRecoveryFileStore(directory:dir.path,owner:getuid())
   let empty = try store.hasPendingRecovery(); precondition(!empty)
   let record=dir.appendingPathComponent("firmware-recovery.json")
   if kind=="file" {try Data().write(to:record)}
   if kind=="symlink" {try fm.createSymbolicLink(atPath:record.path,withDestinationPath:"missing")}
   if kind=="directory" {try fm.createDirectory(at:record,withIntermediateDirectories:false)}
   let present = try store.hasPendingRecovery(); precondition(present)
  }
  print("PASS native helper file removal: canonical bounded authorization wire, pending mutation admission, installed-file identity/permission/link/type/race guards, restore-before-delete, journal refusal, partial retry and idempotence; temporary files only, no real authorization/service/hardware operation")
 }
}
