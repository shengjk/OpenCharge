import SwiftUI
import AppKit
import ChargeCore

@MainActor final class AppUpdates: ObservableObject {
 private let defaults: UserDefaults
 let currentVersion: String
 @Published var automaticChecks: Bool { didSet { defaults.set(automaticChecks, forKey: "updatesAutomatic"); if automaticChecks { checkIfDue() } } }
 @Published var includePreviews: Bool { didSet {
  defaults.set(includePreviews, forKey: "updatesPreviews"); generation += 1; candidate = nil; downloaded = nil
  if !busy { status = NSLocalizedString("渠道已更改，请重新检查", comment: "") }; defaults.removeObject(forKey: "updatesLastAttempt")
 } }
 @Published private(set) var status = NSLocalizedString("尚未检查更新", comment: "")
 @Published private(set) var candidate: ReleasePackage?
 @Published private(set) var downloaded: URL?
 @Published private(set) var busy = false
 @Published private(set) var progress: Double?
 @Published private(set) var checkedAt: Date?
 private var generation = 0
 private var downloadToken: UUID?
 private var timer: Timer?
 private var window: NSWindowController?
 init(defaults: UserDefaults = .standard, currentVersion: String? = nil) {
  self.defaults = defaults; self.currentVersion = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")
  automaticChecks = defaults.bool(forKey: "updatesAutomatic")
  includePreviews = defaults.object(forKey: "updatesPreviews") as? Bool ?? true
 }
 func start() {
  guard timer == nil else { return }
  timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkIfDue() } }
  checkIfDue()
 }
 private func checkIfDue() {
  guard automaticChecks, !busy, ReleaseCheckCadence.due(now: Date().timeIntervalSince1970, lastAttempt: defaults.object(forKey: "updatesLastAttempt") as? Double, interval: 12 * 3600) else { return }
  Task { await check(); if automaticChecks && candidate != nil { show() } }
 }
 private func show() {
  if window == nil {
   let content = NSHostingController(rootView: ScrollView { UpdateView(updates: self).padding(24) }.frame(width: 540, height: 390))
   let view = NSWindow(contentViewController: content); view.title = NSLocalizedString("OpenCharge · 软件更新", comment: ""); view.identifier = NSUserInterfaceItemIdentifier("OpenChargeUpdates")
   view.styleMask = [.titled, .closable]; view.isReleasedWhenClosed = false; view.center(); window = NSWindowController(window: view)
  }
  window?.showWindow(nil); window?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
 func showAndCheck() { show(); Task { await check() } }
 func check() async {
  guard !busy else { return }
  guard ReleaseVersion(currentVersion) != nil else { status = NSLocalizedString("开发运行未标记版本，请从发布包打开应用", comment: ""); return }
  guard ReleaseCheckCadence.due(now: Date().timeIntervalSince1970, lastAttempt: defaults.object(forKey: "updatesLastAttempt") as? Double, interval: 60) else { status = NSLocalizedString("刚刚检查过，请稍后再试", comment: ""); return }
  busy = true; candidate = nil; downloaded = nil; progress = nil; status = NSLocalizedString("正在连接 GitHub 检查发布版本…", comment: "")
  let preview = includePreviews, token = generation
  defaults.set(Date().timeIntervalSince1970, forKey: "updatesLastAttempt")
  defer { busy = false }
  do {
   let pages = try await ReleaseHTTP.pages()
   #if arch(arm64)
   let architecture = UpdateArchitecture.appleSilicon
   #else
   let architecture = UpdateArchitecture.intel
   #endif
   let result = try ReleaseCatalog.evaluate(pages: pages, currentVersion: currentVersion, includePreviews: preview, architecture: architecture)
   guard token == generation else { status = NSLocalizedString("渠道已更改，请重新检查", comment: ""); return }
   checkedAt = Date()
   switch result {
   case .available(let package): candidate = package; status = String.localizedStringWithFormat(NSLocalizedString("发现新版本 %@", comment: ""), package.version)
   case .current(let version): status = String.localizedStringWithFormat(NSLocalizedString("当前渠道已是最新版本（%@）", comment: ""), version)
   case .ahead(let version): status = String.localizedStringWithFormat(NSLocalizedString("本机版本高于当前已发布版本（%@）", comment: ""), version)
   case .noReleases: status = preview ? NSLocalizedString("尚无可识别的已发布版本", comment: "") : NSLocalizedString("尚无正式版；可选择包含开发预览版本", comment: "")
   case .missingPackage(let version, _): status = String.localizedStringWithFormat(NSLocalizedString("版本 %@ 暂无适用此 Mac 的完整下载包，请在 GitHub 查看", comment: ""), version)
   }
  } catch { status = NSLocalizedString("检查失败：", comment: "") + error.localizedDescription }
 }
 func download() async {
  guard !busy, let candidate else { return }
  let token = UUID(); downloadToken = token
  busy = true; progress = 0; status = String.localizedStringWithFormat(NSLocalizedString("正在下载并校验 %@…", comment: ""), candidate.version); downloaded = nil
  defer { busy = false; progress = nil; downloadToken = nil }
  do {
   let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.opencharge.app/Updates", isDirectory: true)
   downloaded = try await ReleaseHTTP.verifiedDownload(candidate, directory: base) { [weak self] value in Task { @MainActor in guard let self, self.downloadToken == token else { return }; self.progress = value } }
   status = NSLocalizedString("SHA-256 校验通过，压缩包已保存", comment: "")
  } catch { status = NSLocalizedString("下载失败：", comment: "") + error.localizedDescription }
 }
 func reveal() {
  if let downloaded, FileManager.default.fileExists(atPath: downloaded.path) { NSWorkspace.shared.activateFileViewerSelecting([downloaded]) }
  else { downloaded = nil; status = NSLocalizedString("缓存已被系统清理，请重新下载", comment: "") }
 }
 func openReleases() { NSWorkspace.shared.open(candidate?.releaseURL ?? ReleaseCatalog.repositoryURL) }
}
struct UpdateView: View {
 @ObservedObject var updates: AppUpdates
 var body: some View {
  Card(NSLocalizedString("软件更新", comment: "")) {
   Text(String.localizedStringWithFormat(NSLocalizedString("当前版本 %@", comment: ""), updates.currentVersion)).font(.subheadline.bold())
   Toggle(NSLocalizedString("自动检查更新（每 12 小时）", comment: ""), isOn: $updates.automaticChecks)
   Toggle(NSLocalizedString("包含开发预览版本", comment: ""), isOn: $updates.includePreviews).disabled(updates.busy)
   Text(NSLocalizedString("更新检查会连接 GitHub，不发送电池读数或本机标识。自动检查默认关闭；发现更新时提示，下载需由你明确选择。", comment: "")).font(.caption).foregroundStyle(.secondary)
   Text(updates.status).font(.callout).textSelection(.enabled)
   if let date = updates.checkedAt { Text(String.localizedStringWithFormat(NSLocalizedString("上次成功检查于 %@", comment: ""), DateDisplay.string(date, style:.abbreviated))).font(.caption).foregroundStyle(.secondary) }
   if let candidate = updates.candidate { Text(String.localizedStringWithFormat(NSLocalizedString("可用版本 %@ · %@ · %@", comment: ""), candidate.version, candidate.filename, ByteCountFormatter.string(fromByteCount: Int64(candidate.size), countStyle: .file))).font(.caption).foregroundStyle(.secondary) }
   if let progress = updates.progress { ProgressView(value: progress) }
   HStack {
    Button(NSLocalizedString("检查更新", comment: "")) { Task { await updates.check() } }.disabled(updates.busy)
    if updates.candidate != nil && updates.downloaded == nil { Button(NSLocalizedString("下载并校验", comment: "")) { Task { await updates.download() } }.disabled(updates.busy) }
    if updates.downloaded != nil { Button(NSLocalizedString("在访达中显示", comment: "")) { updates.reveal() } }
    Button(NSLocalizedString("在 GitHub 查看", comment: "")) { updates.openReleases() }
   }
   Text(NSLocalizedString("校验通过后请自行解压并更新应用。当前开发包尚未公证，暂不自动替换应用或硬件服务。", comment: "")).font(.caption).foregroundStyle(.secondary)
  }
 }
}
