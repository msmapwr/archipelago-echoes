# M0 项目奠基：接口与验收

2026-11-01。范围限定为可靠启动、数据管线、状态基础、CRT 输入和可复现的 Windows 开发构建。M1 玩家体验、完整战役、存档、音画内容与性能发布认证仍按后续里程碑验收。

## 固定接口

- Godot 4.7.2 Compatibility；入口 `scenes/main/console_shell.tscn`。自动加载顺序由 project.godot 维护，场景不重复创建单例。
- GameDefinition 资源格式版本 1，唯一非空 ID、显示名；舰机武器任务引用及数值加载时校验。当前固定首关 ID 包括 ship.haven、aircraft.kestrel、contact.alpha、task.first_recon 和武器／三种弹药，变更需同步控制器及测试。
- DataManager.reload 返回成功与否，失败保留原字典与资源对象，errors 保留原因；startup_error 检查启动必需身份。文件缺失／无效阻断新会话。数据重载不等于保存游戏。
- MissionController.restart_scenario 返回 bool；初始化失败不进入模拟，界面显示故障并允许修复文件后重试。正常菜单仍只有开始游戏按钮。
- EventBus.record 的 kind、details、simulation_seconds 是日志／归档边界；details 深复制。WorldClock.advance 只接受有限正时间，暂停不推进；倍率仅 1×／10×。
- 设置与教程记录是独立版本化文件，写入临时文件后替换；读取错误保留默认／已有值并提示。只有显式应用才写设置；诊断不授予资源或修改进度。

## 可重复验收

```powershell
$env:GODOT_BIN = 'H:\Godot_v4.7.2-stable_win64.exe'
python tools/dev.py m0
python tools/dev.py export-windows
```

m0 创建新的无 .godot 缓存源码副本，记录 SHA256 文件清单，执行全量检查、五项基础图形检查、Windows release 导出、ZIP 资源排除审计、导出程序 headless／图形安装验证，再在第二份源码中移除首关舰艇并修复重试。原工作区和玩家设置不被故障探针改写。目录保留完整证据。

export-windows 在独立诊断目录生成 exe、pck、可分发 ZIP 与文件 SHA256，不覆盖旧包。使用官方匹配版本 Windows x86_64 release 模板；代码签名暂未启用。包排除 tests、tools、docs、技能与开发说明。运行 exe -- --verify-install 可执行只读安装诊断并退出；这不替代真人试玩。

## 完成标准

干净源码首次导入成功；有效目录可加载，错误目录拒绝并能恢复；雷达选择、状态门与暂停回归通过；导出包中运行资源完整、开发文件排除，真实 release 程序两种模式启动通过。实际结果见 M0 验收报告；M1 真人记录仍独立保留。
