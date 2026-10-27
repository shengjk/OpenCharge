# Setup wizard

New configurations open the wizard at first launch. Existing configurations retain their startup behavior. An unfinished first-run wizard can reopen after relaunch; choose **Skip Setup** or close it to stop the prompt. Reopen it from **Settings → Setup Wizard** whenever needed.

The welcome page links to service setup and Apple's charging documentation. Registration remains an explicit action through the existing service interface. The wizard does not enable hardware control or system-mode permission. If control is already enabled, applying a preset uses that permission through the normal policy loop.

## Preset rules

| Use on the go | Daily limit | Sailing width | Optional automatic calibration |
| --- | --- | --- | --- |
| Rarely | 70% | 5% | Every two weeks |
| Sometimes | 80% | 5% | Monthly |
| Often | 90% | 10% | No new task |

The temperature selector accepts 15–40°C or 59–104°F. The generated pause threshold is ambient temperature plus 10°C, so the full policy range is 25–50°C. Fahrenheit inputs are converted before adding 10°C. The wizard enables heat protection and selects macOS percentage as the control reference. It preserves the existing Sailing enable switch while setting its width.

Regular shutdown/user switching selects pause-on-sleep. It also selects automatic discharge when the lid is open at application time. Existing keep-awake policy precedence still applies. The final page shows the effective merged settings; a changed lid state requires reviewing the refreshed proposal.

Optional calibration begins two weeks after the preview is generated, with the interval above. An expired first-run date refreshes the preview instead of importing a past-due calibration. Existing automatic-calibration tasks retain their names, dates, recurrence and enabled state. A stable task identifier prevents duplication after renaming or changing interface language. Choosing no new plan retains other existing tasks.

Task names are optional. Names appear in task editing and execution history, survive backup import/export, and old configurations without names retain their action labels.

## Apply and cancellation

Only **Apply Preset and Finish** saves answers to policy/task configuration. Cancelling or skipping changes wizard-presentation state without replacing charge policy. Administrator locking, a pending settings reset, active/interrupted calibration, invalid answers and configuration write failure prevent application. Existing histories and unrelated settings remain intact. First-run presentation metadata is local; no answers are sent to a service.

Apple's current [charging settings guide](https://support.apple.com/102338) describes Optimized Battery Charging and the system Charge Limit option. The latter requires Apple silicon and macOS 26.4 or later, and accepts 80–100%. Review these settings when choosing a charging controller; the wizard opens their instructions and never changes them automatically.

The native app still requires macOS 13. Implementation, injected tests, offscreen view rendering and package verification do not establish actual hardware charging, lid/sleep behavior or a completed calibration cycle.

## 设置向导

首次使用新配置时会打开向导；已有配置继续沿用原启动行为。未完成的首次向导可在下次启动继续提示；选择“暂不设置”或关闭窗口后停止提示，也可从**设置 → 设置向导**重新打开。

很少外出、有时外出、经常外出三个选项分别生成 70%、80%、90% 的日常上限，以及 5%、5%、10% 的航行宽度。向导保留原航行开关，开启热保护，并选择 macOS 电量作为控制基准。

环境温度范围为 15–40°C／59–104°F，暂停阈值按换算后的摄氏温度加 10°C 生成，完整范围为 25–50°C。经常关机或切换用户时建议睡眠停充；完成时若合盖，则不启用自动放电。原有保持唤醒设置的优先级仍有效，最终预览显示合并后的实际设置。

选择自动校准后，很少外出时每两周一次，有时外出时按月重复，经常外出时不新增任务；首次任务为生成预览时的两周后。过期预览会先刷新，避免导入已逾期的校准。已有自动校准任务保留其名称、日期、周期和启用状态，重命名或切换界面语言后也不会重复添加。

任务名称为可选字段，可在任务列表与执行历史中查看，并随配置备份保留。旧配置没有名称时继续显示操作名称。

只有点击“应用预设并完成”才会保存策略与任务。管理员锁定、未完成的设置重置、进行中或中断的校准以及保存失败都会阻止应用。向导保留已有控制许可、历史和未涉及的设置；向导答案不上传。硬件控制、服务注册和系统充电设置由各自入口管理。以上流程尚未完成真实硬件与完整校准周期验收。
