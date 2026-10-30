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


## macOS 11/12 原生注册后端（开发源码）

0.3.42 的旧系统后端通过 Authorization Services 请求管理员安装权，再调用 SMJobBless。应用和内嵌服务必须具备相同开发团队的 Apple 签名及匹配的双向签名要求；本地 ad-hoc 包会在授权前被拒绝。初始化和状态刷新只读，不请求管理员密码。授权与等待服务退出在后台队列执行；同一服务操作完成前拒绝再次注册或注销。取消与系统错误会反馈给界面，已取得的授权在所有结束路径释放。

此后端的“注销”调用 SMJobRemove 并等待任务退出，**不会删除已安装的二进制或 plist**。文件仍按旧原生布局显示；完整移除请使用下文 0.3.43 的签名服务入口，不要使用开发卸载脚本处理原生安装。不会自动迁移到 SMAppService。只允许操作已确认签名归属的旧原生服务，不覆盖开发脚本或未知来源安装。注销前仍需通过现有应用流程恢复充电、灯光和睡眠状态；注销失败不自动重新启用控制。

发布包仍要求 macOS 13。旧系统后端目前只完成源码可用性编译和隔离测试，尚未在 macOS 11/12 上执行管理员安装、注销或重装，也没有生产开发者签名与公证验收。

The macOS 11/12 source backend uses Authorization Services and SMJobBless after reciprocal app/helper signing checks. Explicit unregistration uses SMJobRemove with an exit wait on a background queue. It stops the job and retains installed files; use the compatible signed full-removal action described below for file removal. Development scripts refuse native-service configurations. Installation does not enable charging control. Ad-hoc builds are rejected before authorization. Current packages declare a macOS 11 minimum; real legacy-system authorization, installation, reinstallation and migration remain unverified.

Apple API references: [SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless(_:_:_:_:)) and [SMJobRemove](https://developer.apple.com/documentation/servicemanagement/smjobremove(_:_:_:_:_:)).

Normal application termination is refused while a service operation is pending. A model already preparing to quit cannot start registration. The isolated dashboard fixture checks the actual delegate replies without requesting application termination.


## 0.3.43：移除旧原生服务及文件

“注销服务”只停止旧原生任务；新增的“移除旧服务与文件”会清理旧原生安装，并等待任务注销。此入口只针对当前应用已验证签名归属的 OpenCharge 旧原生服务，需要匹配签名的新应用、支持 `serviceRemoval:ownedV1` 的新版运行中服务及系统管理员授权。本地 ad-hoc 包和开发脚本安装仍使用前面的手动卸载方式。旧服务未运行或版本不兼容时，先按注册与更新说明恢复兼容服务，再尝试完整移除。

服务通过内核提供的连接审计令牌确认客户端代码身份，要求同一开发团队的固定应用标识，再验证应用传递的管理员授权。授权数据只有固定长度的系统外部表示，不接受文件路径、SMC 键或 shell 命令。根服务自身不会弹出授权窗口，也不会扩展客户端未取得的权限。

文件删除前先恢复本服务拥有的充电、固件、灯光和睡眠状态，再确认四种恢复记录均不存在；损坏文件、符号链接、目录等同样视为待恢复。只删除已核验的 `/Library/LaunchDaemons/org.opencharge.charged.plist` 与 `/Library/PrivilegedHelperTools/org.opencharge.charged`，不删除用户设置、历史或恢复目录。删除期间拒绝新的硬件操作，保留检查和恢复请求。文件确认移除后，应用才注销系统任务并确认安装文件与任务均已不存在。

部分删除或任务注销失败会在当前进程中保留重试状态。此状态尚未实现跨应用/服务崩溃的持久事务恢复：如重开后无法重试、出现缺失或来源不明的文件，请按手动卸载与兼容服务恢复说明处理，不要删除恢复记录。macOS 13+ 完成旧安装移除后会切换至 SMAppService 注册入口，仍需用户显式注册；不会自动安装新服务或开启控制。

The full legacy-removal action requires a compatible signed, running helper and administrator authorization. The helper validates the peer's kernel audit token and app signing requirement, verifies the granted right without root-side interaction, restores owned state and refuses deletion while any recovery path exists. Only the two fixed installation files are unlinked; the caller then unregisters the job and checks final absence. Process-local retry state handles partial deletion and failed job removal, but crash/relaunch recovery is not a durable transaction. Successful removal on macOS 13+ exposes the modern registration route without automatically registering it. Real signed authorization, removal, migration and macOS 11/12 execution remain unverified.

Apple references: [Authorization Services](https://developer.apple.com/documentation/security/authorization-services), [guest attributes](https://developer.apple.com/documentation/security/guest-attribute-dictionary-keys), and [SecCodeCopyGuestWithAttributes](https://developer.apple.com/documentation/security/seccodecopyguestwithattributes(_:_:_:_:)).


## 0.3.46：开发服务的分阶段更新

开发安装脚本与 `uninstall-helper.sh` 必须来自同一版本。安装前会核验源文件和暂存副本的代码签名，拒绝源文件符号链接、安装目标的符号链接或硬链接、可被普通用户修改的安装目录或文件，以及不完整的旧安装。升级时，现有 plist 必须与开发安装脚本生成的固定配置完全一致；原生安装或手动改过的配置会保留供检查，不会被覆盖。

脚本先暂存文件并备份旧副本，再通过 `uninstall-helper.sh --prepare-update` 确认任务、进程和待恢复记录已清理。此模式在成功时保留安装文件。确认后才替换文件并请求服务加载；替换或加载失败会先重新确认服务已停止，再尝试回滚。如果无法安全回滚，会保留当前文件和备份并输出恢复路径。请先解决恢复记录和服务状态，不要删除备份或恢复记录。

这是开发用的脚本更新流程，并非应用内自动更新。突然断电、进程被强制终止、并发 root 修改，以及真实管理员环境中的回滚仍待验证；暂存和备份不能代替持久事务日志。成功输出表示安装及服务加载请求完成，连接和能力仍需单独只读核验。

The development installer stages and verifies files, checks fixed installation paths, and reuses the remover's stop-and-recovery gate before replacement. Failure attempts rollback only after the service is confirmed stopped; uncertain recovery preserves files and backup paths. Use matching scripts from the same release. Native or modified configurations require their own maintenance route. This is not a durable crash-recovery transaction or an automatic in-app updater; real root installation and rollback remain unverified.
