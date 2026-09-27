# AGENTS.md

> 本文件是项目的通用 AI Agent 开发规范。
>
> Agent 在分析项目、修改代码、执行 Git 操作、设计功能、测试、发布版本以及处理远程仓库时，MUST 遵循本文件。
>
> 本规范优先保证：安全、正确、可验证、可维护，并尽量减少不必要的操作和用户打扰。

---

# 1. 核心原则

Agent 的工作原则按以下优先级处理：

1. **安全性（Safety）**
2. **正确性（Correctness）**
3. **保护用户已有工作（Preserve User Work）**
4. **兼容性（Compatibility）**
5. **可验证性（Verifiability）**
6. **可维护性（Maintainability）**
7. **性能（Performance）**
8. **开发效率（Speed）**

当规则发生冲突时，优先级高的规则覆盖优先级低的规则。

核心要求：

- 不得为了速度牺牲正确性或安全性。
- 不得覆盖、删除或破坏用户已有工作。
- 不得把猜测描述成用户已经提出的需求。
- 不得把未验证的结果描述成“已完成”。
- 不得为了通过测试而绕过、删除或篡改测试。
- 不得无理由扩大任务范围。
- 对高风险、不可逆或可能影响用户数据的操作必须谨慎处理。

---

# 2. Agent 工作模型

所有开发任务遵循以下基本模型：

```text
Understand
    ↓
Inspect
    ↓
Scope + Risk
    ↓
Resolve Critical Uncertainty
    ↓
Plan
    ↓
Implement
    ↓
Verify
    ↓
Review Diff
    ↓
Commit
    ↓
Push（需要时）
    ↓
Release（需要时）
```

并不是所有任务都需要经过所有步骤。

例如：

- 小型代码修复可以直接进入 Implement → Verify → Commit。
- UI 小修改可以分析后直接实施。
- 数据库迁移、架构重构、Breaking Change 等高风险任务必须增加方案与风险确认。

Agent 应根据实际任务决定所需流程，不得为了形式机械执行流程。

---

# 3. 项目启动检查

开始处理一个新的项目或新的开发任务时，Agent SHOULD 检查项目环境。

在正式修改代码之前，应尽可能了解：

- 项目目录结构
- 主要技术栈
- 构建方式
- 测试方式
- 运行方式
- 当前 Branch
- Git Remote
- 当前工作区状态
- 当前版本号
- README / 项目文档
- CHANGELOG.md（如果存在）
- 依赖配置
- Agent / 项目其他规则文件

如果项目存在更高优先级或更具体的 Agent 配置，应同时遵循其规则。

如果某项检查与当前任务无关，可以跳过，但不得因此冒险执行可能产生严重后果的操作。

---

# 4. 先理解，再修改

Agent MUST 在修改代码前理解相关现有实现。

至少应根据任务复杂度检查：

1. 相关文件
2. 相关类 / 方法 / 组件
3. 调用关系
4. 数据流
5. 现有错误处理
6. 现有测试
7. 相关配置
8. 项目已有设计模式

对于 Bug：

```text
复现或确认问题
    ↓
定位原因
    ↓
理解相关代码
    ↓
设计最小安全修改
    ↓
修复
    ↓
回归验证
```

不得在尚未理解现有实现时进行大范围修改。

---

# 5. 任务规模与风险

Agent 必须从两个维度判断任务：

- **规模（Size）**：工作量与影响范围
- **风险（Risk）**：错误或变更造成的潜在影响

## 5.1 任务规模

分为：

### Small

局部、低影响、通常不改变整体结构的修改，例如：

- 修复一个 Bug
- 修改一个函数
- 调整一个组件
- 修改一个配置
- 增加简单校验
- 增加简单测试
- 文档修改
- 小范围性能优化

### Major

增加完整功能或明显扩展一个独立模块，但不改变整个项目技术方向，例如：

- 新增完整页面
- 增加 i18n
- 增加认证系统
- 增加数据库模块
- 增加新的业务模式
- 增加大型 UI 模块

### Massive

明显影响多个模块、系统架构、整体 UI、技术栈或项目方向，例如：

- 技术栈迁移
- 全面 UI 重构
- 大规模架构重构
- 核心系统重新设计
- 多个核心模块同时改造

## 5.2 风险等级

分为：

### LOW

错误容易发现、容易恢复、不会影响重要数据或项目核心能力。

### MEDIUM

可能影响部分功能，需要回归测试或较谨慎处理。

### HIGH

可能影响核心业务、兼容性、安全性、性能或重要数据。

### CRITICAL

可能造成：

- 数据丢失
- 安全事故
- 凭据泄露
- 不可逆破坏
- 远程仓库重大损坏
- 大规模生产故障

对于 HIGH / CRITICAL 风险任务，Agent MUST 提高验证和确认级别。

---

# 6. 需求确认原则

Agent 不以“提问数量”作为需求确认标准，而以**关键不确定性是否已经消除**作为标准。

Agent MUST 识别可能影响最终结果的重要未确定事项。

以下问题通常属于关键问题：

- 功能目标
- 范围边界
- 用户体验
- 架构
- 技术栈
- 数据结构
- API
- 安全
- 性能
- 兼容性
- 迁移方式
- 验收标准

如果缺少的信息不会改变技术方案、风险或最终结果，可以采用合理默认方案。

使用默认方案时，应明确说明：

```text
该项未由用户指定，Agent 使用项目现有规范作为默认方案。
```

Agent MUST NOT 将自己的猜测描述为用户需求。

---

# 7. 澄清问题原则

Agent SHOULD：

- 只询问真正影响结果的问题。
- 优先一次解决多个关键不确定性。
- 利用用户已经提供的信息，不重复询问。
- 优先使用项目现有规范作为默认值。
- 在风险较低且结果可逆时，尽量减少阻塞。

Agent MUST NOT：

- 为满足固定问题数量而重复提问。
- 对已经明确的信息再次询问。
- 因为非关键细节而阻塞整个任务。
- 用无意义的问题代替实际分析。

---

# 8. 变更前 Baseline

对于可能影响性能、行为、兼容性或用户体验的任务，Agent SHOULD 建立修改前基线。

适用时记录：

- 当前测试结果
- 构建状态
- 关键性能指标
- 关键功能行为
- 运行时间
- 内存占用
- API 行为
- UI 行为

基本流程：

```text
Baseline
    ↓
Change
    ↓
Verify
    ↓
Compare
    ↓
判断是否出现 Regression
```

不能仅因为新功能可以工作，就忽略旧功能是否发生退化。

---

# 9. Scope Control

Agent MUST 控制任务范围。

> **完成当前任务，不等于重构整个项目。**

Agent 应优先采用能够完整解决问题的最小安全修改。

原则：

```text
能改 1 个文件，不要无理由改 10 个文件。
能局部修复，不要无理由重构整个模块。
能复用现有依赖，不要无理由引入新依赖。
能保留现有结构，不要无理由改变架构。
```

如果发现与当前任务无关的问题：

1. 不应默默扩大修改范围。
2. 如果该问题不影响当前任务，可以记录并报告。
3. 如果必须修复才能完成当前任务，可以修复，但应明确说明原因。
4. 只有在用户明确要求或任务范围允许时，才进行额外改动。

---

# 10. 最小安全修改原则

Agent SHOULD 优先采用：

> **Smallest Safe Change That Fully Satisfies the Requirement**

也就是：

- 修改尽可能局部。
- 保持现有行为不变，除非需求要求改变。
- 保持现有接口不变，除非确有必要。
- 复用项目已有模式。
- 避免无关重构。
- 避免顺手升级依赖。
- 避免为了“代码更漂亮”改变无关部分。

但“最小修改”不意味着拒绝必要重构。

如果现有实现已经无法安全支持目标功能，应明确说明并进行必要范围内的结构调整。

---

# 11. 计划与拆解

复杂任务 SHOULD 拆解为可以独立验证的工作单元。

推荐模型：

```text
Major / Massive Task
        ↓
Logical Work Units
        ↓
Implementation
        ↓
Verification
```

拆解的目的不是制造更多任务，而是：

- 降低风险
- 缩小故障范围
- 方便测试
- 方便回滚
- 保持 Git 历史清晰

Agent MUST NOT 为了满足某个数量要求而机械拆分任务。

---

# 12. 高风险操作确认

以下操作通常需要更高等级的确认或至少明确告知用户：

- 删除重要数据
- 不可逆数据库迁移
- 大规模数据转换
- 修改生产配置
- 修改安全策略
- 修改认证机制
- 暴露或轮换凭据
- 修改公共 API 导致 Breaking Change
- 删除重要功能
- 修改 Git Remote
- Force Push
- 重写已 Push 的历史
- 删除远程 Branch

原则：

> **可逆操作优先；高风险操作必须可解释。**

---

# 13. Git 仓库检查

如果项目使用 Git，Agent SHOULD 在开始修改前检查：

```bash
 git status
 git branch --show-current
 git remote -v
```

如有需要，检查：

```bash
 git log --oneline -n 10
 git diff
```

如果项目没有 Git：

- 正式软件项目 SHOULD 使用 Git。
- 临时实验、代码片段或用户明确要求不使用 Git 的场景可以例外。

Agent MUST NOT 在已有 Git 仓库中重复执行 `git init`。

---

# 14. 保护用户已有修改

如果工作区存在修改，Agent MUST 先判断这些修改是否属于当前任务。

如果无法确定：

> 应暂停可能覆盖这些修改的操作，并向用户说明。

Agent MUST NOT 擅自执行：

```bash
 git reset --hard
 git clean -fd
 git checkout .
 git restore .
```

也不得：

- 删除用户修改
- 覆盖用户修改
- 擅自 Stash 用户修改
- 擅自 Reset 用户 Commit
- 擅自 Rebase 用户历史
- 擅自 Force Push

任何可能破坏已有工作的操作，都必须谨慎处理。

---

# 15. Git Remote

如果任务需要远程 Git 操作：

1. 检查当前 Remote。
2. 不得猜测 Repository 地址。
3. 不得将代码推送到未知 Repository。
4. 如果 Remote 不存在且确实需要 Push，应请求用户提供地址。
5. 如果已有 Remote 与用户提供的地址不一致，不得擅自覆盖。
6. 修改 Remote 前应明确告知用户。

如果任务只需要本地开发，则无需为了形式配置远程仓库。

---

# 16. Branch

优先遵循项目已有 Branch 工作流。

常见命名：

```text
feature/<name>
fix/<name>
refactor/<name>
docs/<name>
chore/<name>
perf/<name>
```

大规模或高风险任务 SHOULD 使用独立 Branch。

简单任务可以遵循项目现有流程直接使用当前 Branch。

Agent MUST NOT 未经允许删除远程 Branch。

---

# 17. Commit

Commit 应代表一个完整、可理解、具有逻辑意义的变更单元。

Commit Message 推荐：

```text
<type>(<scope>): <subject>
```

例如：

```text
feat(player): add movement system
fix(auth): handle expired token
refactor(ui): simplify button component
docs(readme): update installation guide
test(player): add collision tests
chore(deps): update dependencies
perf(render): optimize sprite rendering
```

常见类型：

- `feat`
- `fix`
- `docs`
- `style`
- `refactor`
- `test`
- `chore`
- `perf`

要求：

- MUST 清晰表达变更内容。
- SHOULD 保持一个 Commit 一个逻辑单元。
- 不得为了凑 Commit 数量制造无意义 Commit。
- 不得使用模糊的 `update`、`modify`、`change`、`stuff` 等作为主要描述。

---

# 18. Commit 前 Diff Review

Commit 前 MUST 检查：

```bash
 git status
 git diff
```

如果使用暂存区，还应检查：

```bash
 git diff --cached
```

确认：

- 修改属于当前任务。
- 没有意外文件。
- 没有误删代码。
- 没有意外修改用户工作。
- 没有 Debug 代码。
- 没有明显敏感信息。
- 测试结果与当前修改一致。
- Commit Message 与实际修改一致。

> `git status` 只能告诉你“哪些文件变化了”，`git diff` 才能确认“具体变化了什么”。

---

# 19. Push

Commit 与 Push 是两个不同的行为。

Commit 表示：

> 本地变更已经形成可追踪历史。

Push 表示：

> 该历史需要同步到远程仓库。

因此 Agent 不应强制每一个小更新都立即 Push。

是否 Push，应根据：

- 项目工作流
- 用户要求
- Branch 策略
- 协作需要
- CI 需要
- Release 流程

决定。

Push 前 MUST 确认：

- Remote 正确
- Branch 正确
- 无明显 Secrets
- Commit 内容正确
- 测试状态已知

Agent MUST NOT 未经允许使用：

```bash
 git push --force
 git push --force-with-lease
```

除非用户明确要求或项目已有明确自动化流程要求。

---

# 20. Secrets 与敏感信息

Agent MUST NOT 将真实敏感信息提交到 Git。

包括但不限于：

```text
API Key
Access Token
Password
Private Key
Secret
Certificate
Database Password
OAuth Secret
Cloud Credentials
.env
.env.*
```

除非项目明确要求，否则使用：

```text
.env.example
```

或项目规定的配置模板。

如果发现 Secret 已经进入 Git：

1. MUST 停止 Push。
2. 告知用户。
3. 移除敏感信息。
4. 如果已经进入历史，提醒用户可能已经泄露。
5. 必要时建议立即轮换 / 撤销 Secret。

不得为了完成任务忽略 Secrets 风险。

---

# 21. 依赖管理

增加、删除或升级依赖时 MUST：

1. 检查当前依赖。
2. 判断是否真的需要新依赖。
3. 优先使用项目已有依赖。
4. 检查兼容性。
5. 更新依赖配置。
6. 更新 Lockfile（适用时）。
7. 运行构建。
8. 运行相关测试。

同时：

- MUST NOT 为简单功能无意义地增加大型依赖。
- MUST NOT 顺手升级无关依赖。
- SHOULD 尽量保持变更范围局部。

---

# 22. 数据库与数据迁移

修改以下内容时：

- 数据库结构
- 数据模型
- Schema
- API 数据结构
- 持久化格式

Agent MUST 考虑：

- 旧数据兼容性
- 是否需要 Migration
- Migration 是否可逆
- 是否会造成数据丢失
- 是否需要备份
- 新旧版本能否共存

存在潜在数据破坏时：

> MUST 在执行前明确告知用户。

不得未经确认执行明显不可逆的数据破坏操作。

---

# 23. API 与兼容性

修改公共 API、接口、数据结构或外部调用方式时，Agent MUST 判断是否属于 Breaking Change。

如果存在 Breaking Change：

- 明确记录。
- 根据项目版本策略处理。
- 更新 CHANGELOG（如适用）。
- 更新文档（如适用）。
- 提供迁移方案（如需要）。

---

# 24. 测试策略

测试不是形式要求，而是证明变更正确性的主要手段之一。

## 24.1 Small

完成后 MUST 进行最小必要验证。

适用时包括：

- 编译
- 构建
- 单元测试
- 类型检查
- Lint
- 启动测试
- 手动验证

## 24.2 Major

完成后 SHOULD 进行：

- 完整 Build
- 自动化测试
- 回归测试
- 必要手动测试
- 关键路径验证

## 24.3 Massive

完成后 MUST 根据项目实际情况进行完整验证，包括适用的：

- 全量 Build
- 全量测试
- 全量回归
- 核心功能
- UI / UX
- 性能
- 兼容性
- 安全性

测试范围应与风险相匹配，而不是机械执行一份固定清单。

---

# 25. 测试失败处理

如果测试失败：

```text
测试失败
    ↓
定位
    ↓
判断：代码 / 测试 / 环境
    ↓
修复
    ↓
重新测试
```

Agent MUST NOT：

- 删除失败测试
- 降低测试标准
- 修改预期结果来强行通过
- 绕过测试
- 隐藏错误
- 声称测试通过

如果测试本身不再符合正确需求，可以修改测试，但必须确保新测试真实反映需求变化。

---

# 26. Bug 修复

Bug 修复 SHOULD 遵循：

```text
确认 Bug
    ↓
定位根因
    ↓
设计最小安全修复
    ↓
增加 / 更新回归测试
    ↓
修复
    ↓
重新测试
    ↓
检查回归
```

未验证修复成功前：

> MUST NOT 声称 Bug 已经修复。

---

# 27. UI / UX

涉及 UI 时，Agent 应根据项目适用范围考虑：

- 布局
- 可读性
- 一致性
- 交互反馈
- Loading
- Error
- Empty State
- Hover / Focus / Active
- 键盘操作
- 可访问性
- 响应式布局
- 深色 / 浅色模式（如果项目支持）

UI 变化不应只验证“能不能显示”，还应验证：

> **用户是否知道发生了什么、下一步可以做什么、失败后如何恢复。**

大型 UI 改造 SHOULD 先明确：

```text
Design System
    ↓
Layout
    ↓
Navigation
    ↓
Components
    ↓
Pages
    ↓
Responsive
    ↓
Migration
```

---

# 28. 性能

如果任务可能影响性能，Agent SHOULD：

1. 建立修改前基线。
2. 修改后重新测试。
3. 比较关键指标。
4. 判断是否出现明显 Regression。
5. 优先优化高影响问题。

对于实时应用、游戏、大数据处理、网络服务等项目：

> 性能应视为重要验收指标。

不得为了“看起来更快”而缺少实际验证。

---

# 29. 文档

如果功能改变了：

- 用户使用方式
- 安装方式
- API
- 配置方式
- 开发方式
- 数据迁移方式

Agent MUST 更新相关文档。

适用文档包括：

- README
- API 文档
- 使用文档
- 开发文档
- 配置示例
- Migration 文档

文档修改可以使用：

```text
 docs(...): ...
```

---

# 30. CHANGELOG

如果项目采用 CHANGELOG：

```text
CHANGELOG.md
```

推荐遵循 Keep a Changelog。

基本结构：

```markdown
# Changelog

## [Unreleased]

### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security
```

开发过程中，属于下一版本的变化 SHOULD 优先记录到 `Unreleased`。

不要求每个 Commit 都修改正式版本号。

---

# 31. Semantic Versioning

如果项目采用 Semantic Versioning：

```text
MAJOR.MINOR.PATCH
```

一般规则：

```text
MAJOR
不兼容变更

MINOR
向后兼容的新功能

PATCH
向后兼容的 Bug 修复
```

Agent MUST NOT 无理由修改版本号。

---

# 32. Pull Request

如果项目使用 Pull Request 工作流：

Major / Massive 任务 SHOULD 使用 PR。

PR 至少应说明：

- 修改目标
- 修改范围
- 技术方案
- 测试结果
- Breaking Changes
- Migration（适用时）
- 截图 / Demo（UI 项目适用）

PR 标题推荐遵循 Commit Message 风格。

---

# 33. CI

如果项目已经配置 CI，Agent MUST 尽可能满足 CI 要求。

常见检查：

```text
Build
Test
Lint
Type Check
Security Check
```

CI 失败时：

```text
CI Failure
    ↓
定位原因
    ↓
修复
    ↓
Commit
    ↓
Push
    ↓
重新检查
```

不得忽略已知 CI Failure 并声称任务已经完整完成。

---

# 34. Issue / Task 关联

如果项目使用 GitHub Issues / Projects：

Major / Massive 任务 SHOULD 与对应 Issue / Task 关联。

如果用户提供 Issue 编号，Agent 应在适当的 Commit / PR 中进行关联。

---

# 35. Definition of Done

每个任务完成前，Agent 应判断以下项目是否满足。

```text
[ ] 目标功能已实现
[ ] 任务范围没有被无理由扩大
[ ] 用户已有修改未被破坏
[ ] 必要测试已执行
[ ] 测试结果已知
[ ] Build 已验证（适用时）
[ ] 关键回归已检查
[ ] 性能已检查（适用时）
[ ] 安全性已检查（适用时）
[ ] 文档已更新（适用时）
[ ] CHANGELOG 已更新（项目使用时）
[ ] Diff 已检查
[ ] Commit 清晰
[ ] Remote / Branch 状态明确
```

注意：

> Definition of Done 是“适用项全部完成”，不是要求每个任务机械执行所有项目。

---

# 36. 失败恢复

如果 Agent 无法解决问题：

```text
停止扩大修改范围
        ↓
保留当前状态
        ↓
检查 Git 状态
        ↓
记录已尝试方案
        ↓
说明当前问题
        ↓
报告测试结果
        ↓
给出下一步建议
```

报告至少包括：

- 当前问题
- 已知原因
- 已尝试方案
- 当前项目状态
- 测试结果
- 尚未解决的问题
- 下一步建议

Agent MUST NOT：

- 隐藏问题
- 删除问题代码以假装完成
- 回滚用户已有修改
- 为了“看起来正常”而破坏功能

---

# 37. Git History

Git History 应保持：

- 清晰
- 可读
- 可追踪
- 与实际开发过程一致

避免：

- 无意义 Commit
- 大量模糊 `update`
- 无意义 Merge
- 隐藏实际变更
- 为了“好看”随意重写历史

已经 Push 到远程的历史 SHOULD NOT 随意重写。

---

# 38. Release

发布版本时，适用项目应完成：

```text
功能完成
    ↓
测试完成
    ↓
CHANGELOG 完整
    ↓
版本号确认
    ↓
Release Commit（如需要）
    ↓
Git Tag（如需要）
    ↓
Push
    ↓
CI / Release 验证
```

Tag 推荐：

```text
vMAJOR.MINOR.PATCH
```

例如：

```text
v1.0.0
v1.2.0
v2.0.0
```

---

# 39. Strictly Forbidden

Agent MUST NOT：

- 未测试就声称完成。
- 隐瞒测试失败。
- 隐瞒构建失败。
- 隐瞒已知 Bug。
- 为通过测试而删除测试。
- 为通过测试而绕过测试。
- 为通过测试而篡改错误预期。
- 覆盖用户已有修改。
- 删除用户已有修改。
- 擅自 Reset 用户工作。
- 擅自 Force Push。
- 擅自修改 Remote。
- 猜测 GitHub Repository 地址。
- 推送到未知 Repository。
- 提交 Secrets。
- 无理由修改版本号。
- 无理由升级无关依赖。
- 将自己的猜测描述为用户需求。
- 为了满足问题数量而重复提问。
- 无理由扩大任务范围。
- 未经确认执行明显不可逆的数据破坏操作。
- 未经允许执行高风险破坏性 Git 操作。
- 随意重写已经 Push 的 Git 历史。

---

# 40. Final Execution Model

Agent 最终应遵循：

```text
              Understand
                   ↓
                Inspect
                   ↓
              Scope + Risk
                   ↓
        ┌──────────┴──────────┐
        ↓                     ↓
有关键不确定性？          信息已充分
        ↓                     ↓
   Ask / Resolve            Plan
        └──────────┬──────────┘
                   ↓
                Implement
                   ↓
                 Test
                   ↓
              Review Diff
                   ↓
                Commit
                   ↓
            Push（需要时）
                   ↓
           Release（需要时）
```

核心原则：

> **先理解，再修改；先控制范围，再实施；先验证，再 Commit；先确认远程状态，再 Push；先完整验证，再 Release。**
