# project-resume-universal

**把任意软件项目变成可面试的技术资产。** 不预设语言、框架、架构。

| 能力 | 说明 |
|---|---|
| 跨技术栈 | Java/Spring · Node/TS（React/Vue/Nest/Express…）· Python（Django/Flask/FastAPI）· Go · PHP · .NET · Ruby · Rust · Flutter/RN · 小程序 |
| 跨架构 | 单体 · 分层 · 微服务 · Monorepo · Serverless · 前后端分离 · 多模块 |
| 跨项目类型 | 后端服务 · Web 前端 · 移动端/小程序 · 数据/AI 应用 · CLI/SDK/库 · 基础设施 |
| 跨岗位输出 | 后端 / 前端 / 全栈 / 移动 / 数据 / AI / 测试 / 运维 |
| 证据驱动 | 每条结论可回指文件:行、commit、配置键、SQL、日志；四级证据分级 |

---

## 安装

**方式 A · 作为技能安装**（推荐，安装后可用 `/project-resume-universal` 直接调用）

```powershell
# 安装到当前项目的技能目录
git clone https://github.com/Asd-le/project-resume-universal.git .dsh\skills\project-resume-universal
```

**方式 B · clone 到任意位置**，脚本按路径直接调用，无需安装：

```powershell
git clone https://github.com/Asd-le/project-resume-universal.git
cd project-resume-universal
```

> **环境要求**：Windows PowerShell 5.1 或 PowerShell 7+、`git`（分析 Git 历史时需要）。
> 采集器**只读**被分析项目，不联网、不执行构建。

---

## 快速开始

```powershell
# 1) 采集证据（只读项目，仅写输出目录）
& .dsh\skills\project-resume-universal\scripts\collect-project-evidence.ps1 -Author "<你的git署名>"

# 2) 让 AI 基于证据产出材料
/project-resume-universal
```

输出目录默认 `<项目根>/.project-resume/`。

---

## 目录结构

```
project-resume-universal/
├── SKILL.md                              技能主定义：铁律 / 十阶段流程 / 输出规范 / 维护提示
├── scripts/
│   ├── collect-project-evidence.ps1       跨栈证据采集器（项目画像 + 10 份证据）
│   └── collect-git-evidence.ps1           独立 Git 证据采集（贡献 / 新鲜度 / 作者聚合）
└── references/
    ├── evidence-rules.md                  证据分级 / JSON 规范 / 跨栈反例（必读）
    ├── role-playbooks.md                  8 类岗位的打法、措辞分档、必答题库
    ├── universal-pitfalls.md              跨栈踩坑清单（编码/脚本/Git/配置/数据/表述/安全）
    └── cheat-sheet.md                     命令速查（含线上取证 SQL 与日志命令、安全红线）
```

---

## 它产出什么

```
<项目根>/.project-resume/
├── README.md                  导航与安全提醒
├── 00-overview.md             项目画像与规模
├── 01-tech-stack.md           逐项技术 + 版本 + 证据 + 使用强度 + 等级
├── 02-architecture.md         架构形态与难点
├── 03-business-modules.md     业务模块与领域模型
├── 04-contribution-analysis.md 归属与贡献（区分本人/团队）
├── 05-highlights.md           亮点（三档措辞）
├── 06-confirmation.md         需要用户确认的问题
├── 07-interview-questions.md  分层面试题 + 岗位专项 + 软技能
├── 08-evidence.json           机器可读证据库（claims + pendingQuestions）
├── resume/                    按岗位分版本（backend/frontend/fullstack/mobile/data/ai/…）
└── evidence/                  采集器原始证据（00~09）+ 线上取证（若有）
```

---

## 核心设计（为什么可信）

1. **先画像后采集**：先判断"这是什么项目、什么栈、什么架构"，再决定看哪些文件——避免用后端模板硬套前端项目。
2. **证据分级**：`CONFIRMED / USER_PROVIDED / INFERRED / USER_REQUIRED`，未确认的内容禁止写入简历。
3. **归属可核**：Git 只证明"代码贡献"，不证明"设计责任"；团队他人写的模块单独标注。
4. **不造数字**：所有量化必须能指向证据文件；没有来源就进确认清单。
5. **多岗位复用**：同一套事实，按岗位换侧重与排序（不重复分析项目）。
6. **踩坑已固化**：编码/BOM/脚本语义/profile 覆盖/估算值/凭据泄漏等坑全部写进 references 与维护提示。

---

## 已验证

在真实 Java SaaS 项目上实测（3,300+ Java 文件、20,310 次提交）：

- 自动识别技术栈：Spring Boot、MyBatis、MySQL、Redis、RabbitMQ、ShardingSphere、Redisson、Quartz、**LLM 集成**、Swagger
- 自动识别架构：多模块 Maven 工程；文件类型分布、目录结构、入口文件
- 产出 10 份证据（含 2,674 行接口清单、992 行数据层证据、835 行脱敏配置）

> 前端/移动/数据类项目走同一流程，差异体现在 `references/role-playbooks.md` 的岗位打法与 `cheat-sheet.md` 的额外采集项。

---

## 安全提醒

分析产物常含**生产凭据、内网地址、PII**，务必：

1. 把输出目录加入 `.gitignore`（`.project-resume/`、`.dsh/`）；
2. 外发前扫一遍 `password|secret|token|sk-…|PRIVATE KEY`；
3. 源码里发现硬编码密钥 → 提醒用户**轮换**（删代码不够，Git 历史仍可检出）；
4. 线上取证用的私钥用完即删，并撤销服务器授权。

---

## License

[MIT](LICENSE) © 2026 Asd-le
