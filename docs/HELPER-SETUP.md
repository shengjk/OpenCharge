# OpenCharge 硬件服务安装与移除

服务以 root 运行，只接受当前控制台用户的固定充电、灯光及电源模式动作。不接受任意 SMC 键、字节、路径或 shell 命令。首次安装且没有恢复日志时不会开启充电控制；新版服务启动时会先尝试恢复同一次开机中遗留的充电与灯光修改。请先退出其他充电控制器，再明确启用新的控制。

## 正式签名、公证版本

macOS 13+ 使用 SMAppService。应用包含 Contents/Library/LaunchDaemons/org.opencharge.charged.plist 和 Contents/MacOS/charged。先把完整应用放入 /Applications，打开“设置与诊断”，点击“注册硬件服务”，再由管理员在系统“登录项与扩展”批准后台项目。注册状态“可运行”不保证服务已经连接，需另外检查服务能力。

Apple 的 SDK 要求包含 LaunchDaemon 的应用公证。当前本地 ad-hoc 构建不满足应用内注册条件；按钮会禁用并显示原因。开发者签名预检通过后，最终公证与授权仍由系统决定。不会自动请求凭据、接受许可或绕过系统检查。

## 源码开发安装

在源码项目根目录审阅并构建后，手动运行：

```sh
bash Scripts/build-app.sh
sudo bash Scripts/install-helper.sh
```

安装脚本将服务复制到 root 拥有、普通用户不可写的 /Library/PrivilegedHelperTools/org.opencharge.charged，并写入 /Library/LaunchDaemons/org.opencharge.charged.plist。它使用固定绝对 ProgramArguments，不把 root launchd 指向用户可修改的源码目录。手动脚本安装和 SMAppService 注册不能同时使用；应用检测到前者时会提示先卸载。

## 移除与更新

应用内注销先请求恢复本进程拥有的充电、灯光与睡眠控制状态，再等待 SMAppService 的异步注销完成；设置与历史保留。若运行中的服务无法连接，应用不会声称已经完成恢复和移除。

开发脚本安装版本使用：

```sh
sudo bash Scripts/uninstall-helper.sh
```

更新原生注册的服务时，先注销旧服务、等待完成，再替换完整应用并重新注册。Apple 文档说明更改可执行文件或 plist 后需要重新注册。开发脚本更新会先停止旧服务，再替换 root 副本。不要在运行中的 helper 上原地覆写二进制。

45 秒心跳在服务仍存活且机器清醒时提供尽力恢复；睡眠期间暂停计时。0.3.7 新增同次开机的充电恢复日志，新服务重启时会先恢复记录，再接受新的充电操作；这也会释放旧服务保留的停充状态。充电与灯光的跨开机记录只丢弃、不写硬件。损坏记录会阻止充电控制，请勿在未完成恢复时删除日志。移除脚本保留恢复目录，以免丢失未完成记录。灯光崩溃恢复、真实硬件恢复、断电及固件私有权限仍未验证。详见 HARDWARE.md。

依据：
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
- 当前 SDK 的 SMAppService.h（LaunchDaemon 公证要求、BundleProgram、批准及更新生命周期）。

0.3.8 将同次开机恢复扩展到独立的灯光记录，共享私有目录与独占锁；不会自动继续旧闪烁模式。灯光恢复失败或记录损坏时暂停新的灯光写入，恢复完成后才接受新的控制。实际硬件恢复仍需验收。


0.3.13 adds a separate sleep recovery record. Global SleepDisabled preferences persist across reboot and must be restored even for a previous boot; the kernel lid flag is released only within its recorded boot. The development uninstall script refuses to delete helper files while any sleep recovery marker remains and requests the existing job restart for recovery. Do not downgrade to a helper without sleep recovery support or delete its record while an override is pending. Resolve recovery with the compatible service before retrying removal. The application does not update the installed service automatically. See [sleep control](SLEEP.md).

0.3.15 uses schema 2 for new sleep journals; released schema-1-only helpers refuse these records. The current helper still reads schema 1 and migrates uncertain compensation before writing. Complete pending recovery before downgrading or removing any helper. Calibration requires compatible full sleep control independently of the optional until-limit setting; ordinary clamshell-discharge opt-in also pre-acquires full protection. Unsupported preflight or a failed sleep request stops control and attempts cleanup. Optional lid locking runs only in the foreground application session and adds no root helper action.
