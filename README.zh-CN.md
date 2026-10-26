# OpenCharge

本地运行的 macOS 开源电池管理器，提供原生仪表盘、菜单栏、命令行和快捷指令。

[下载开发预览版编译包](https://github.com/shengjk/OpenCharge/releases) · [编译包使用说明](docs/DOWNLOADS.md)
[English](README.md) · [文档](docs/README.md) · [功能状态](docs/STATUS.md) · [参与贡献](CONTRIBUTING.md)

## 主要功能

- 充电上限、航行保持、温控窗口、临时充满、放电与可恢复的校准策略。
- 区分空闲与系统睡眠，主动放电与校准时自动选择必要保护；提供恢复日志和可选合盖锁屏。
- 重复任务、出行充电估算、预设、决策历史和 JSON 配置备份。
- 仪表盘与弹窗组件独立配置，实测功率流和可选高耗能应用卡片。
- 12 个原生 App Intents、5 个 App Shortcuts、CLI 和 URL 操作。
- 仅提供简体中文和英文界面，跟随 macOS 语言偏好。
- 历史与诊断保存在本机，无账户、遥测或云服务。

## 从源码运行

需要 macOS 13+、Swift 5.9+ 和 Apple 命令行开发工具。打包原生快捷指令还需要已安装的 App Intents 元数据处理器，通常由 Xcode 提供。

```sh
git clone https://github.com/shengjk/OpenCharge.git
cd OpenCharge
bash Scripts/build-app.sh
open dist/OpenCharge.app
./dist/bin/chargectl status --json
```

首次启动为监测模式。硬件控制需要单独安装服务并明确启用，详见[安装指南](docs/HELPER-SETUP.md)。启用前退出其他充电管理器。

## 当前状态

0.3.38 为开发版本。策略、隔离测试和只读能力已有验证；真实充放电、灯光效果、睡眠恢复和更多机型仍待实机验收。通用构建支持 arm64/x86_64，不代表所有机型固件均已验证。完整范围见[功能状态](docs/STATUS.md)。

```sh
bash Scripts/check.sh
bash Scripts/build-universal.sh
```

原生包位于 `dist/`，通用包位于 `dist-universal/`；本地包采用 ad-hoc 签名，尚未公证。源码、测试、脚本和文档分开维护，目录说明见英文 README。

## 文档与贡献

[软件更新](docs/UPDATES.md) · [使用指南](docs/USAGE.md) · [架构](docs/ARCHITECTURE.md) · [验证](docs/TESTING.md) · [更新记录](CHANGELOG.md)

数据目录为 `~/Library/Application Support/OpenCharge/`。导出由用户主动选择，不自动上传。[安全与隐私](SECURITY.md)。MIT 许可；第三方声明保留在 `docs/licenses/`。

更新检查与校验下载见[软件更新说明](docs/UPDATES.md)。自动检查默认关闭；检查会连接 GitHub，不发送电池数据或本机标识，下载需明确点击。
