# Restore default settings

In **Settings → Restore Defaults**, choose **Restore Defaults…** and review the confirmation. Cancel is the default button. Export a configuration backup first if you want to retain your policies and schedules.

Restoration resets charge policies, scheduled tasks, notification/history preferences, appearance, dashboard/popover components, menu actions, energy sensitivity and update preferences. Charge control and system-mode actions end disabled. Battery history, last calibration and task execution history remain available. Managed preferences and unrelated stored keys are retained; an administrator charging-settings lock prevents reset.

The application saves disabled control permissions before attempting to release the charge, LED and sleep sessions it owns. It writes the default configuration only after cleanup succeeds, then refreshes the existing interface objects. If a save or cleanup fails, it reports the failure, preserves the remaining settings for retry and pauses automatic policy/task processing in the current process. Resolve the reported issue and retry; backup import is blocked while this live reset is pending. This pause is not a cross-process or crash-atomic reset transaction: if the first save fails, the previous disk configuration remains; otherwise the disabled control permissions persist across relaunch.

Update checks/downloads must finish before resetting. Installed services, login startup, macOS notification permissions, system Low Power Mode and downloaded files have their own management controls. Reset does not invoke their installation/removal or permission interfaces.

## 恢复默认设置

在**设置 → 恢复默认设置**中点击**恢复默认设置…**，查看确认内容。默认按钮为“取消”；若需保留当前策略和任务，请先导出配置备份。

重置范围包括充电策略、定时任务、通知与历史记录偏好、外观、仪表盘和弹窗组件、菜单操作、能耗敏感度以及更新偏好。充电控制与系统模式操作会关闭。电池历史、上次校准时间和任务执行历史会保留；受管理的偏好与无关键值也会保留，管理员充电设置锁会阻止重置。

应用先保存关闭控制的权限，再尝试结束自身持有的充电、灯光和睡眠会话。清理成功后才保存默认配置并刷新界面。保存或清理失败时会报告原因，保留其余设置以便重试，并暂停当前进程的自动策略和任务处理。解决问题后请重试；当前重置未完成时，备份导入入口会被阻止。此暂停不属于跨进程或崩溃原子事务：首次保存失败时磁盘仍保留旧配置；首次保存成功后，关闭的控制权限可跨重启保留。

请等待更新检查或下载结束后再重置。已安装服务、登录启动、系统通知权限、系统低电量模式和下载文件均有各自的管理入口。
