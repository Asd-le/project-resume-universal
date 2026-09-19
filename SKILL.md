---
name: project-resume-universal
description: Analyze any software project regardless of language, framework, or architecture (backend, frontend, mobile, data/AI, monorepo, microservices, serverless) and generate an evidence-graded knowledge base plus multi-role resume versions, interview questions, and a confirmation checklist. Auto-detects stack and architecture first, then mines source, Git history, build files, configs, SQL/schema, and deployment artifacts without inventing facts. Use when the user asks to turn a codebase into resume material, or runs /project-resume-universal.
whenToUse: The user wants resume/interview material mined from a repository of any stack (Java/Spring, Node/TS, Python, Go, PHP, .NET, Vue/React, Flutter/RN, data/AI, etc.) or any architecture (monolith, microservices, monorepo, serverless, front+back in one repo).
---

# Project Resume Universal（跨技术栈 / 跨架构的通用项目简历生成）

你现在运行在一个**真实软件项目**目录中，且**这个技能不预设语言、框架与架构**。

目标：把「**源码 + Git 历史 + 构建配置 + 配置/环境 + 数据库/Schema + 部署产物 + 用户回答**」整理成一条**可核验的证据链**，
再据此生成真实、可面试的简历材料。

> **代码证明「做了什么」，Git 证明「谁做的」，数据库/日志/线上数据证明「规模与效果」，AI 只负责整理；无法确认的必须追问。**

通用版与「某一语言专用版」的区别只有三点：
1. **先识别项目画像**（语言/框架/架构/角色），再决定分析哪些文件；
2. **采集器跨栈**（同一套流程支持 Maven/Gradle/npm/pip/go mod/composer/csproj/Flutter…）；
3. **输出按目标岗位分流**（前端/后端/全栈/移动/数据/AI/测试/运维），措辞与侧重点不同，但**事实不变**。

---

## 0. 铁律（违反即失败）

1. **禁止编造**：用户没提供、代码/Git/数据无法证明的事实，一律不写。
2. **禁止造数字**：性能指标（QPS、提升百分比、耗时、数据量）必须有来源；没有就写 `[USER_REQUIRED]`。
3. **禁止混淆归属**：「项目用了某技术」≠「用户负责该技术」；团队成果 ≠ 个人成果。
4. **每条结论必须带证据**：文件路径（可含行号）/ commit hash / 配置键 / SQL / 日志片段 / 用户原话。
5. **无法确认就追问**：职责、动机、效果、事故、数据量 → 进 `05-confirmation.md`。
6. **不夸大**：`[INFERRED]` 只能写「疑似/可能」；`[USER_REQUIRED]` 未确认前**禁止**写入简历正文。
7. **只读分析**：不得修改被分析项目的任何业务文件（仅可写输出目录），不得提交 Git，不得把代码上传网络。

### 证据等级

| 等级 | 含义 | 能否写进简历 |
|---|---|---|
| `[CONFIRMED]` | 源码/配置/SQL/Git/数据可直接证明，能指明出处 | ✅ 作为事实陈述 |
| `[USER_PROVIDED]` | 用户本轮明确确认 | ✅ 作为事实 |
| `[INFERRED]` | 由结构合理推断，无直接证据 | ⚠️ 只能写「疑似/可能」 |
| `[USER_REQUIRED]` | 必须用户回答 | ❌ 未确认前禁止写入 |

判定细则与反例见 `references/evidence-rules.md`。

---

## 1. 参数解析（全部可选）

| 参数 | 含义 | 默认 |
|---|---|---|
| `--role=<frontend\|backend\|fullstack\|mobile\|data\|ai\|test\|devops\|any>` | 目标岗位，决定简历侧重与技能排序 | `any`（自动按项目画像推荐） |
| `--mode=<resume\|knowledge\|interview>` | 只出简历 / 只出知识库 / 只出面试题 | `resume` |
| `--branch=<ref>` | 分析指定分支（如 `origin/main`），不切工作区 | 当前工作区 |
| `--author=<a,b,c>` | Git 贡献分析对象，**支持多署名合并** | 提交量第一的作者 |
| `--since=<date>` | Git 起始时间 | 不限 |
| `--out=<dir>` | 输出目录 | `<项目根>/.project-resume` |
| `--refresh` | 强制重采证据 | 复用已有证据 |

---

## 2. 执行流程（十阶段）

```
① 项目画像识别 → ② 分支/工作区新鲜度 → ③ 证据采集 → ④ 技术栈与架构
   → ⑤ 业务模块与领域模型 → ⑥ 归属与贡献 → ⑦ 亮点与量化 → ⑧ 用户确认
   → ⑨ 按岗位生成简历 → ⑩ 面试题与复盘
```

### Phase 1 · 项目画像识别（**通用版新增，最关键**）

先回答四个问题，**后面的采集范围完全由它决定**：

1. **是什么类型**：后端服务 / Web 前端 / 移动端 / 小程序 / 桌面 / 数据管道 / AI 应用 / CLI 工具 / SDK·库 / 基础设施 / 全栈同仓？
2. **用什么语言与框架**：读构建清单（`package.json`/`pom.xml`/`build.gradle`/`go.mod`/`Cargo.toml`/`requirements.txt`/`pyproject.toml`/`composer.json`/`Gemfile`/`pubspec.yaml`/`*.csproj`）。
3. **什么架构**：单体 / 分层 / 微服务 / Monorepo / Serverless / 前后端分离 / 多模块 / 插件化？
4. **什么业务域**：从目录名 + 实体名 + 路由 + 表名 + README 归纳（电商、教育、金融、IM、SaaS、工具、数据平台…）。

**执行**：
```powershell
# ① 静态证据（项目画像 / 依赖 / 配置 / 接口 / 数据层 / 结构 / 业务模块）
& .dsh\skills\project-resume-universal\scripts\collect-project-evidence.ps1 `
    -Author "<作者>" [-Branch origin/main] [-OutDir .project-resume]

# ② Git 证据（独立脚本，产出的 07-git-evidence.md 覆盖第 ① 步的占位文件）
& .dsh\skills\project-resume-universal\scripts\collect-git-evidence.ps1 `
    -ProjectRoot . -Author "<作者>" [-Branch origin/main] [-Since yyyy-MM-dd] `
    -OutFile .project-resume\evidence\07-git-evidence.md
```
> 若第 ① 步的 `07-git-evidence.md` 显示"未采集成功，需补跑"，说明 Git 数据需单独跑第 ② 步（内联调用在某些执行环境下 git 输出会为空）。
采集器会先输出 `evidence/00-project-profile.md`：构建清单、技术栈信号、架构形态、文件类型分布、顶层结构、关键特征文件。

> 若画像识别失败（技术栈探针零命中），**不要硬猜**：读 README + 入口文件 + 测试文件，把结论标为 `[INFERRED]` 并列入 `05-confirmation.md`。

### Phase 2 · 新鲜度与归属前置校验（**血的教训，必做**）

| 检查 | 命令/依据 | 不做的后果 |
|---|---|---|
| **工作区是否落后主线** | `git rev-list --count HEAD..origin/<最新分支>`；采集器的 `07-git-evidence.md` 会直接给出「落后 N 个提交」告警 | 曾把落后 7,091 个提交的旧分支当最新，整份简历规模/技术栈全错 |
| **同邮箱多署名** | 采集器按邮箱聚合，输出「同邮箱多署名」清单 | 同一人改写 `user.name` 会被算成两个人，贡献腰斩 |
| **分支 vs 工作区差异** | `git worktree list`、`git status --short` | 工作区可能有未提交改动；**禁止**用 `checkout/reset` 去"修正"，改用 `git <ref>:<path>` 只读读取 |

### Phase 3 · 证据采集

采集器产出（**唯一原始证据来源**）：

```
<out>/evidence/
├── 00-project-profile.md          项目画像（类型/栈/架构/特征文件）
├── 01-build-and-deps.md           构建清单与全部依赖（跨栈）
├── 02-config-evidence.md          配置类文件（敏感值整行脱敏）
├── 03-api-inventory.md            接口/路由清单（多框架静态提取）
├── 04-tech-capability-evidence.md 跨栈技术能力探针（命中数 + 代表文件）
├── 05-database-evidence.md        SQL/Schema/迁移/ORM/表清单
├── 06-structure-and-frameworks.md 目录树、分层、入口文件
├── 07-git-evidence.md             Git 证据 + 分支新鲜度 + 作者聚合
├── 08-business-modules.md         业务目录聚类、实体名、页面/组件、数据脚本
└── 09-collector-selfcheck.md      自检与读取告警
```

**要求**：后续所有结论必须能回指上述文件某一行；采集器没覆盖的，用只读工具（read/grep/glob/git）补采并追加进对应文件。

**按栈补充采集**（不同项目类型要额外看的东西）：

| 项目类型 | 必须额外看 |
|---|---|
| 后端服务 | 接口清单、事务/锁/幂等、MQ 拓扑、连接池与线程池配置、SQL 与索引、线上日志（若有） |
| Web 前端 | 路由表与页面清单、状态管理、构建产物与体积、组件库、SSR/CSR、埋点、i18n |
| 移动端/小程序 | 页面栈与路由、原生能力调用、包体积、权限声明、渠道打包、灰度 |
| 数据/AI | 数据源与管道（DAG）、Notebook、特征/模型、评测指标、推理服务与成本 |
| 基础设施/平台 | IaC 资源清单、K8s 编排、CI/CD 阶段、监控告警规则 |

### Phase 4 · 技术栈与架构 → `01-tech-stack.md`、`02-architecture.md`

- 每项技术：`技术 | 版本 | 证据（文件:行） | 使用强度（命中数） | 等级`
- 架构：分层、模块边界、数据流、部署形态、**以及该架构带来的真实难点**
- 明确写出「**没有的能力**」（如无测试、无 CI、无容器化、无监控）——这既是诚实，也是面试的可讲点

### Phase 5 · 业务模块与领域模型 → `03-business-modules.md`

判定用「证据三角」：**目录/路由 + 实体·模型 + 表/集合 + 文案（注释、README、i18n）**。
每个模块输出：业务价值、关键实体、关键接口、关键流程（含异步/消息链路）、复杂度信号、证据、相关提交。

### Phase 6 · 归属与贡献 → `04-contribution-analysis.md`

- 提交量、时间跨度、改动行数、触达文件、高频文件（=长期维护区）、新增文件（=0→1）、删除重命名（=重构）
- 提交主题按类型统计（修复/优化/新增/重构/测试/文档/依赖/部署/AI）
- 分支名（feature/hotfix 直接暴露需求与线上问题）
- **必须写边界**：`Git 只能证明代码贡献，不能证明架构设计责任`；对团队他人写的模块，标注"团队成果"

### Phase 7 · 亮点与量化 → `05-highlights.md`

分五类找亮点：**性能 / 稳定性 / 架构 / 工程化 / 业务复杂度**，每条给出三档措辞（普通/中级/高级）。
量化只允许来自：**用户提供 > 项目文档 > Git > 配置/监控 > benchmark > 日志**。
找不到来源 → 写成 `[USER_REQUIRED]` 并进确认清单（**绝不自己填数字**）。

### Phase 8 · 用户确认 → `06-confirmation.md`

把 `[USER_REQUIRED]` 集中成**可回答**的清单，按主题分组，每组先给「代码已确认的事实」，再给问题。
必须覆盖：角色与职责边界、Git 作者假设是否正确、在职时间与团队规模、每个推断是否属实、真实数据（量级/并发/优化前后）、线上问题经历、脱敏范围、目标岗位与年限。

**生成简历前，关键问题必须提问；若用户要"先出草稿"，只输出 `[CONFIRMED]` 保守版并在顶部标注。**

### Phase 9 · 按岗位生成简历 → `resume/<岗位>.md`

同一套事实，按岗位换**侧重与排序**（措辞分档细则见 `references/role-playbooks.md`）：

| 岗位 | 放在最前 | 淡化 |
|---|---|---|
| 后端 | 并发/一致性/数据层/接口规模/稳定性 | 页面细节 |
| 前端 | 页面与组件规模/状态管理/构建优化/性能指标(必测) | 数据库内部 |
| 全栈 | 端到端链路、接口契约、交付速度 | 单侧深挖 |
| 移动端 | 页面栈/包体积/崩溃率/渠道发布 | 服务端细节 |
| 数据/AI | 数据规模、管道、模型与评测、成本 | CRUD |
| 测试/运维 | 质量门禁、CI/CD、监控告警、故障复盘 | 业务功能罗列 |

**每个岗位版本必须包含**：项目简介（业务+规模+你的角色）、技术栈、职责 3–6 条、亮点 3–5 条、难点 2–4 条、可量化表、待确认项。
**禁止**跨岗位复制后留下不匹配内容（如投前端却在技能首条写 ShardingSphere）。

### Phase 10 · 面试题与复盘 → `07-interview-questions.md`

每个亮点至少三层：**初级（概念）→ 中级（机制与取舍）→ 深挖（故障与边界）**；另加：
- **项目问题**：最复杂模块、你具体负责什么、为什么这样设计、线上出过什么问题
- **反套路**：这个方案有什么缺陷？如果重做怎么改？数据能证明吗？
- **岗位专项**：该岗位的高频基础题（见 `references/role-playbooks.md` 的题库清单）
- **软技能**：为什么离职、为什么选我们、职业规划、期望薪资结构、到岗时间

每题给**答题要点**并标注证据路径。

---

## 3. 输出产物

```
<项目根>/.project-resume/
├── README.md                  导航与使用说明（含安全提醒）
├── 00-overview.md
├── 01-tech-stack.md
├── 02-architecture.md
├── 03-business-modules.md
├── 04-contribution-analysis.md
├── 05-highlights.md
├── 06-confirmation.md
├── 07-interview-questions.md
├── 08-evidence.json           机器可读证据库
├── resume/                    按岗位分版本（frontend/backend/... ）
├── evidence/                  采集器原始证据 + 线上取证（若有）
├── sql/                       可复跑的取数脚本（若有数据库访问）
└── ssh/                       线上取证脚本（若需登录服务器）
```

`08-evidence.json` 结构：

```json
{
  "project": { "name": "", "type": "", "stack": [], "architecture": [], "scale": {} },
  "analysisMeta": { "ref": "", "targetAuthor": "", "authorAssumption": "", "role": "", "generatedAt": "" },
  "claims": [{
    "id": "C-001", "category": "tech-stack|architecture|business|contribution|highlight|metric|quality",
    "level": "CONFIRMED|USER_PROVIDED|INFERRED|USER_REQUIRED",
    "statement": "", "evidence": [{ "type": "file|config|sql|commit|log|user", "ref": "", "note": "" }],
    "usedInResume": true, "resumeWording": ""
  }],
  "pendingQuestions": [{ "id": "Q-001", "topic": "", "question": "", "why": "", "blocksResume": true, "status": "OPEN" }]
}
```

JSON 规范（**踩过的坑**）：
- `evidence.ref` 相对**仓库根**写完整路径（不要省略 `src/...` 前缀，否则不可机读校验）
- `type=commit` 必须是 commit hash；散文说明放 `note`
- `category` 只用枚举内取值，需要新值时先在此处登记
- 路径基准、枚举、`status` 字段定义见 `references/evidence-rules.md`

---

## 4. 完成后向用户汇报（必须）

1. 项目画像（类型/栈/架构一句话）
2. 规模与关键数字（带证据）
3. 已确认技术栈与**明确不存在的能力**
4. 归属结论（哪些是本人、哪些是团队，区分「参与」与「负责」）
5. 候选亮点（标等级）
6. **需要用户确认的问题**（标明哪些阻塞投递）
7. 生成的岗位版本清单 + 建议投递方向

---

## 5. 安全与合规（**每次都要提醒用户**）

分析产物常包含**生产凭据、内网地址、真实客户数据**，必须：

1. 输出目录**加入 `.gitignore`**（`.project-resume/`、`.dsh/`），避免误提交；
2. 采集器对配置类文件按**整行脱敏**（命中敏感词即丢弃值）；但 raw 证据文件仍可能含明文 →
   **外发/上传前必须人工检查**：`password|secret|token|ak|sk-|BEGIN .*PRIVATE KEY`;
3. 线上取证用的 SSH 私钥**用完即删**，并从服务器 `authorized_keys` 撤销；
4. 若在源码里发现硬编码密钥（已进 Git 历史），提醒用户**轮换**（删代码不够）；
5. 客户名/机构名/订单号等 PII，**先问用户是否需要脱敏**再写入简历。

---

## 6. 参考文档

- `references/evidence-rules.md`：证据等级判定、JSON 规范、反例清单（**必读**）
- `references/role-playbooks.md`：各岗位的侧重点、措辞分档、必答题库（前端/后端/全栈/移动/数据/AI/测试/运维）
- `references/universal-pitfalls.md`：跨栈踩坑清单（编码、BOM、脚本编码、路径基准、profile 覆盖、估算值 vs 精确值…）

## 7. 维护提示（改本技能前必读）

| 坑 | 表现 | 正确做法 |
|---|---|---|
| **SKILL.md 带 BOM** | frontmatter 首行不是 `---`，**技能从会话目录消失** | `SKILL.md` 必须 **UTF-8 无 BOM** |
| **.ps1 不带 BOM** | Windows PowerShell 5.1 按 ANSI 解码中文 → 大批 `ParserError` | `scripts/*.ps1` 用 **UTF-8 with BOM** |
| **PowerShell 保留变量** | `$args` 等不能当普通变量名 | 用 `$gitArgs`/`$authorArgs` |
| **正则里的引号** | 单双引号混用会让解析器错乱 | 复杂正则用 here-string `@'...'@` |
| **`$obj.Add (` 带空格** | 被解析成命令调用而非方法调用 | 方法调用与 `(` 之间不留空格 |
| **整数/估算值** | `information_schema.TABLE_ROWS` 是估算值，与精确 COUNT 可差 20%+ | 标注"估算"与"精确"，别混用 |
| **profile 覆盖** | 基础配置写了 A，profile 里写 B，实际生效是 B | 覆盖类配置必须核对 include/active 链 |
| **相对路径基准** | 证据里写 `src/...` 全路径，换项目才不会失效 | 统一以仓库根为基准 |
