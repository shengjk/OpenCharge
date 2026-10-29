# Using a compiled OpenCharge preview

Version 0.3.52 declares macOS 11 or later; macOS 11/12 runtime remains unverified. Published 0.3.46 packages require macOS 13. Native Shortcuts require macOS 13 or later. Choose the arm64 archive for Apple silicon, or the universal archive for Apple silicon and Intel. Hardware support depends on the model and service capabilities; a universal executable does not validate all firmware.

1. Verify the archive against `SHA256SUMS.txt`, then extract it.
2. Open `dist/OpenCharge.app`. You can copy the complete app to `/Applications`. Keep the extracted directory if you need the helper scripts or CLI.
3. New installations start in monitoring mode. Review `docs/HELPER-SETUP.md` before installing or updating the root service. The current preview uses ad-hoc signatures and is not notarized; in-app service registration is unavailable for these builds.

The compiled download includes `dist/bin/charged`, `dist/bin/chargectl`, the two service scripts and the setup/status documentation. No Swift compiler is needed to use these binaries. From the extracted directory, read-only CLI status is available with:

```sh
./dist/bin/chargectl status --json
```

Optional service installation is a separate administrator action. Review the scripts and setup guide first. A fresh installation without recovery records does not enable hardware control; an updated service may restore previously owned changes during startup.

```sh
sudo /bin/bash Scripts/install-helper.sh
```

The service scripts use `dist/bin/charged` from the same extracted directory. Keep that layout when using them. Installing the service does not enable the app's hardware-control switch. Complete any pending recovery before removing or downgrading a service. See the setup guide for the removal procedure; do not delete recovery records manually.

The interface includes only Simplified Chinese and English, selected through macOS language preferences. Release notes and checksums are on the [GitHub release page](https://github.com/shengjk/OpenCharge/releases).

# 使用编译好的 OpenCharge 预览版

0.3.48 声明最低 macOS 11，但尚未在 macOS 11/12 实机验证。已发布的 0.3.46 包仍要求 macOS 13。原生快捷指令要求 macOS 13 或更新版本。Apple 芯片可选择 arm64 包，或选择同时包含 Apple 芯片和 Intel 可执行文件的 universal 包。通用架构不代表所有机型固件都已验证。

核对 `SHA256SUMS.txt` 后解压，打开 `dist/OpenCharge.app`，也可将完整应用复制到“应用程序”。如需使用命令行和服务脚本，请保留解压目录。编译包已包含应用、命令行、后台服务、安装／移除脚本和说明，不需要安装 Swift 编译器。

首次使用为监测模式。安装或更新 root 服务前，请先阅读 `docs/HELPER-SETUP.md` 并审阅脚本，再在解压目录运行上方的安装命令。当前预览版使用本地签名，尚未公证，不支持应用内注册。服务安装不会自动开启应用的硬件控制开关；更新后的服务启动时可能先恢复此前拥有的修改。

脚本需要同一解压目录内的 `dist/bin/charged`，请保持目录结构。移除或降级服务前必须完成恢复，不要手动删除恢复记录。界面仅保留简体中文和英文，跟随 macOS 语言偏好。
