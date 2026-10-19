import SwiftUI
import AppKit
import ChargeCore

@MainActor final class AppUpdates: ObservableObject {
 private let defaults: UserDefaults
 let currentVersion: String
 @Published var automaticChecks: Bool { didSet { defaults.set(automaticChecks, forKey: "updatesAutomatic"); if automaticChecks { checkIfDue() } } }
 @Published var includePreviews: Bool { didSet {
  defaults.set(includePreviews, forKey: "updatesPreviews"); generation += 1; candidate = nil; downloaded = nil
  if !busy { status = "渠道已更改，请重新检查" }; defaults.removeObject(forKey: "updatesLastAttempt")
 } }
 @Published private(set) var status = "尚未检查更新"
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
   let view = NSWindow(contentViewController: content); view.title = "OpenCharge · 软件更新"; view.identifier = NSUserInterfaceItemIdentifier("OpenChargeUpdates")
   view.styleMask = [.titled, .closable]; view.isReleasedWhenClosed = false; view.center(); window = NSWindowController(window: view)
  }
  window?.showWindow(nil); window?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
 func showAndCheck() { show(); Task { await check() } }
 func check() async {
  guard !busy else { return }
  guard ReleaseVersion(currentVersion) != nil else { status = "开发运行未标记版本，请从发布包打开应用"; return }
  guard ReleaseCheckCadence.due(now: Date().timeIntervalSince1970, lastAttempt: defaults.object(forKey: "updatesLastAttempt") as? Double, interval: 60) else { status = "刚刚检查过，请稍后再试"; return }
  busy = true; candidate = nil; downloaded = nil; progress = nil; status = "正在连接 GitHub 检查发布版本…"
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
   guard token == generation else { status = "渠道已更改，请重新检查"; return }
   checkedAt = Date()
   switch result {
   case .available(let package): candidate = package; status = "发现新版本 \(package.version)"
   case .current(let version): status = "当前渠道已是最新版本（\(version)）"
   case .ahead(let version): status = "本机版本高于当前已发布版本（\(version)）"
   case .noReleases: status = preview ? "尚无可识别的已发布版本" : "尚无正式版；可选择包含开发预览版本"
   case .missingPackage(let version, _): status = "版本 \(version) 暂无适用此 Mac 的完整下载包，请在 GitHub 查看"
   }
  } catch { status = "检查失败：" + error.localizedDescription }
 }
 func download() async {
  guard !busy, let candidate else { return }
  let token = UUID(); downloadToken = token
  busy = true; progress = 0; status = "正在下载并校验 \(candidate.version)…"; downloaded = nil
  defer { busy = false; progress = nil; downloadToken = nil }
  do {
   let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("org.opencharge.app/Updates", isDirectory: true)
   downloaded = try await ReleaseHTTP.verifiedDownload(candidate, directory: base) { [weak self] value in Task { @MainActor in guard let self, self.downloadToken == token else { return }; self.progress = value } }
   status = "SHA-256 校验通过，压缩包已保存"
  } catch { status = "下载失败：" + error.localizedDescription }
 }
 func reveal() {
  if let downloaded, FileManager.default.fileExists(atPath: downloaded.path) { NSWorkspace.shared.activateFileViewerSelecting([downloaded]) }
  else { downloaded = nil; status = "缓存已被系统清理，请重新下载" }
 }
 func openReleases() { NSWorkspace.shared.open(candidate?.releaseURL ?? ReleaseCatalog.repositoryURL) }
}
struct UpdateView: View {
 @ObservedObject var updates: AppUpdates
 var body: some View {
  Card("软件更新") {
   Text("当前版本 \(updates.currentVersion)").font(.subheadline.bold())
   Toggle("自动检查更新（每 12 小时）", isOn: $updates.automaticChecks)
   Toggle("包含开发预览版本", isOn: $updates.includePreviews).disabled(updates.busy)
   Text("更新检查会连接 GitHub，不发送电池读数或本机标识。自动检查默认关闭；发现更新时提示，下载需由你明确选择。").font(.caption).foregroundStyle(.secondary)
   Text(updates.status).font(.callout).textSelection(.enabled)
   if let date = updates.checkedAt { Text("上次成功检查于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
   if let candidate = updates.candidate { Text("可用版本 \(candidate.version) · \(candidate.filename) · \(ByteCountFormatter.string(fromByteCount: Int64(candidate.size), countStyle: .file))").font(.caption).foregroundStyle(.secondary) }
   if let progress = updates.progress { ProgressView(value: progress) }
   HStack {
    Button("检查更新") { Task { await updates.check() } }.disabled(updates.busy)
    if updates.candidate != nil && updates.downloaded == nil { Button("下载并校验") { Task { await updates.download() } }.disabled(updates.busy) }
    if updates.downloaded != nil { Button("在访达中显示") { updates.reveal() } }
    Button("在 GitHub 查看") { updates.openReleases() }
   }
   Text("校验通过后请自行解压并更新应用。当前开发包尚未公证，暂不自动替换应用或硬件服务。").font(.caption).foregroundStyle(.secondary)
  }
 }
}
