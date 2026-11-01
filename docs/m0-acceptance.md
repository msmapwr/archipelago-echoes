# M0 正式验收

2026-11-01，Windows / Godot 4.7.2 Compatibility。结论：**M0 项目奠基完成**。范围与接口见 [M0 基础规范](m0-foundation.md)；M1 玩家试玩、M2 后续玩法和发布认证不由此结论代替。

## 已执行并通过

证据保存在 `artifacts/m0/`，属于本地构建产物，不提交大型二进制。

| 门槛 | 证据 |
|---|---|
| 无缓存源码首次导入、全量检查 | `m0-20261101T004316Z-b802ff55/clean-check/`：29 Godot、26 Python 通过；源码 SHA256 清单位于同级 `clean-source-sources.json` |
| 基础交互图形回归 | 同目录 `clean-test/`：M0 故障恢复、菜单、M1 CRT 输入、雷达、任务指引五项通过 |
| 第一次启动即缺失舰艇资源 | 同目录 `fault/recovery/`：阻断启动、显示原因、恢复资源后按钮重试成功；探针仅修改新建源码副本 |
| Windows release 导出与包审计 | 最终 `export-windows-20261101T004534Z-b0c20c10/export/summary.json`：资源 ZIP 131 项，无测试、文档、工具或技能泄入；exe 与 pck SHA256 已记录 |
| 真正导出程序启动 | 同上 `installed-headless/`、`installed-graphics/`：只读安装验证成功标记、退出码、原生错误扫描同时通过 |
| 最新工具回归 | 26 Python unittest 通过，包括无缓存副本保护和包内容拒绝检查 |
| UI 检查 | 默认／弱 CRT × 三种 16:9 分辨率错误页成功生成；最终缩短状态铭牌后补拍 1280，见 [错误页](reference/m0-qa/startup-error.webp) |

运行 `python tools/dev.py m0` 可重复主要门槛；`export-windows` 单独导出验证。最终分发 ZIP 位于本机 `exports/M0-20261101/`，未签名，是开发验收包。

## 修复的问题及失败记录

- 数据重载失败曾丢弃旧字典；现在保留原资源对象并记录错误，禁止进入新任务。首次缺失关键身份时不再访问空舰艇资源。
- 初始化错误界面保留暂停、显示文件原因并支持修复后重试。恢复后重新初始化并回到正常菜单。
- WorldClock 拒绝 NaN／Infinity，防止模拟时间污染。
- 首个导出包实际发现舰机兼容列表为空（`m0-20261101T003843Z-06f5031a/export/`），未将“编辑器通过”当成导出通过。将舰艇 PackedStringArray 默认值改为明确构造函数后，真实 release 的资源校验通过。
- 首次新增 SceneTree 测试直接引用 Autoload 名称编译失败，改用 root.get_node 后通过，未绕过原检查。

预期警告仍保留：故障恢复两项及原有主动非法输入测试的告警。早期在项目内生成副本造成的嵌套 project.godot 导入告警，已用本地 artifacts/.gdignore 隔离；最终导入无告警。

## 限制与非本阶段门槛

验收针对本机 Windows x86_64；未声称跨机器、长时 GPU 性能、代码签名或完整游戏发布认证完成。M1 真人记录仍待玩家填写。静态测试配对分析器缺少 tree-sitter-language-pack，未安装新依赖；实际行为测试与构建门槛已执行，不以静态配对替代验证。

官方模板来源：[Godot 4.7.2 下载归档](https://godotengine.org/download/archive/4.7.2-stable/)。本机只安装所需 Windows release 成员及 ICU 数据，经 ZIP CRC／长度核对；没有声称完整 1.28 GB 模板归档通过 SHA512 校验。

原工作区的 AGENTS.md 删除、.agents/ 和 SVG 导入文件保留并排除本批提交。
