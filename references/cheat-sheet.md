# 命令速查（Cheat Sheet）

复制即可用。所有脚本**只读**项目，仅写输出目录。

---

## 一、一次性生成完整材料

```powershell
# 在项目根目录执行：自动识别技术栈与架构，产出证据 + 简历 + 面试题
& .dsh\skills\project-resume-universal\scripts\collect-project-evidence.ps1 -Author "<你的git署名>"
```

然后（对 AI 说）：

```
/project-resume-universal
```

或在对话里说：**"按 project-resume-universal 流程，基于 evidence/ 生成 00~08 + resume/ 各岗位版本"**。

---

## 二、常用参数组合

```powershell
# 多署名合并（同一人多套 user.name）
... -Author "zhangsan,ZhangSan,zs"

# 分析指定分支（不动工作区）
... -Branch origin/main -Author "zhangsan"

# 限定时间范围（只看近两年贡献）
... -Author "zhangsan" -Since "2024-01-01"

# 输出到自定义目录
... -OutDir D:\resume\myproject

# 无 Git 仓库的项目（如交付源码包）
... -Author ""    # 跳过归属分析，只做技术栈/模块/亮点
```

---

## 三、换不同类型项目的额外动作

| 项目类型 | 采集器已覆盖 | 需要你额外提供/补充 |
|---|---|---|
| Java 后端 | 依赖、配置、接口、SQL、MQ、线程池 | 生产数据量、QPS、线上故障记录 |
| Node/TS 前端 | 依赖、路由、组件、构建配置 | **性能指标**（首屏/LCP/包体积）、页面数、用户量 |
| 移动端/小程序 | 页面栈、权限、渠道配置 | 崩溃率、启动耗时、装机量、渠道灰度记录 |
| Python 数据/AI | 依赖、Notebook、DAG、模型文件 | 数据量、模型效果指标、推理成本 |
| Go/PHP/.NET | 依赖、路由、结构 | 业务规模、线上问题 |
| Monorepo | 多包清单、工作区工具 | 你负责哪个 package |
| 微服务 | 服务清单、注册中心、MQ | 服务边界与你的职责范围 |
| Serverless | 函数配置、触发器 | 调用量、冷启动、成本 |

> **通用缺口**：任何类型的项目，**生产数据与线上问题是代码里没有的**——必须问用户，或用只读方式登录服务器/数据库取证（见下）。

---

## 四、线上取证（可选，但价值最高）

### 4.1 数据库（只读取数）

```bash
# 在能连数据库的机器上执行；只用 SELECT，别在库里跑写操作
mysql -h <host> -u<user> -p -D <db> -t < 取数.sql
```

取数模板（按需改表名）：

```sql
-- 规模
SELECT TABLE_SCHEMA, COUNT(*) AS tables, SUM(TABLE_ROWS) AS est_rows,
       ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1024/1024/1024,2) AS size_gb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys')
GROUP BY TABLE_SCHEMA ORDER BY est_rows DESC;

-- 核心表 Top 30（估算值；需要精确时另跑 COUNT(*)）
SELECT TABLE_NAME, TABLE_ROWS, ROUND((DATA_LENGTH+INDEX_LENGTH)/1024/1024,1) AS size_mb
FROM information_schema.TABLES WHERE TABLE_SCHEMA='<db>' ORDER BY TABLE_ROWS DESC LIMIT 30;

-- 关键业务量（示例：订单/退款/用户）
SELECT (SELECT COUNT(*) FROM t_order)  AS orders,
       (SELECT COUNT(*) FROM t_refund) AS refunds,
       (SELECT COUNT(*) FROM t_user)   AS users;
```

> 若数据库只在**内网可达**：用跳板机执行（`ssh <jump> 'bash -s' < 脚本`），或在服务器上执行后把结果拉回。
> **口径**：`TABLE_ROWS` 是估算值，与 `COUNT(*)` 可能差 20%+，文档里要标明。

### 4.2 Web 访问日志（QPS / 峰值 / 故障窗口）

```bash
# 每分钟请求量（找峰值与断流）
zcat access.log-<date>.gz | awk -F'[:[]' '{print $3":"$4}' | sort | uniq -c | sort -k2

# 峰值分钟的热点接口
grep '13/Sep/2026:09:59:' access.log | awk '{print $7}' | sort | uniq -c | sort -rn | head -20

# 状态码分布（499=客户端超时，5xx=服务端错误）
awk '{print $9}' access.log | sort | uniq -c | sort -rn | head

# 上游故障（连接被拒/超时/无可用后端）
zcat error.log-<date>.gz | grep -c 'connect() failed\|no live upstreams'
```

> **注意日志轮转偏移**：若 Nginx 配置为每天 03:00 轮转，则 `access.log-20260914.gz` 装的是 **09-13** 的日志。

### 4.3 应用日志（异常分类 / 重启 / GC）

```bash
# 异常分类（单遍聚合，别逐关键字重扫大文件）
zcat app-error.log.gz | awk '
  /OutOfMemoryError/ {oom++}
  /Connection is not available|CannotGetJdbcConnection/ {pool++}
  /Deadlock found|Lock wait timeout/ {deadlock++}
  /RejectedExecution/ {rejected++}
  /TimeoutException|Read timed out/ {timeout++}
  END {printf "OOM=%d 连接池=%d 死锁=%d 线程池拒绝=%d 超时=%d\n", oom, pool, deadlock, rejected, timeout}'

# 进程重启（启动横幅）
zgrep -E 'Started .* in [0-9.]+ seconds|Starting .*Application' app-info.log.gz

# 每分钟错误量（定位雪崩起点）
zcat app-error.log.gz | awk 'match($0,/^([0-9-]+ [0-9]{2}:[0-9]{2})/,t){c[t[1]]++} END{for(k in c) print k,c[k]}' | sort
```

### 4.4 服务器与 JVM

```bash
nproc; grep MemTotal /proc/meminfo; df -h
ps -eo pid,user,etime,rss,args | grep -v grep | grep -E 'java|node|python' | cut -c1-260   # 完整启动参数
ls /proc/<pid>/task | wc -l                       # 线程数
jstack <pid> > /tmp/jstack.log; head -50 /tmp/jstack.log   # 线程快照（抓 2-3 次看趋势）
jstat -gcutil <pid> 1000 10                       # GC 概况
top -Hp <pid> -b -n 1 | head -20                  # 哪个线程在占 CPU
```

**故障取证 SOP（30 秒固定现场）**：`jstack ×3`（间隔 10s）→ `top -Hp` → 连接池水位（Druid/Hikari 监控或 Arthas）→ `jstat -gcutil` → `ss -lntp`。

---

## 五、安全红线（每次都要检查）

```powershell
# 1. 输出目录必须被忽略
Add-Content .gitignore "`n.project-resume/`n.dsh/"
git check-ignore -v .project-resume .dsh

# 2. 扫产物里的凭据/PII（外发前必做）
Select-String -Path .project-resume\**\*.md,.project-resume\**\*.txt -Pattern `
  'password|passwd|secret|token|api[_-]?key|sk-[A-Za-z0-9]{10,}|BEGIN .*PRIVATE KEY|AKID|AccessKey'
```

**规则**：
1. 源码里发现硬编码密钥（尤其已进 Git 历史）→ 提醒用户**轮换**；
2. 线上取证私钥用完即删，并从服务器 `authorized_keys` 撤销；
3. 日志/证据里的真实姓名、手机号、订单号 → 外发前脱敏；
4. 不要把分析目录直接发给面试官。

---

## 六、增量维护（不用重头做）

| 场景 | 操作 |
|---|---|
| 补一份数据量 | 跑 4.1 的 SQL，把结果给 AI → 更新 `resume/*` 与 `08-evidence.json` |
| 代码有大更新 | 重跑采集器（长按 `--refresh` 语义）；人工修正写到 `_corrections.md` 以免被覆盖 |
| 加一个岗位版本 | 说"按 `--role=frontend` 出一个前端版本"，AI 从母版派生 |
| 换公司/换项目 | 到新项目目录重跑采集器 + `/project-resume-universal`，输出目录独立 |
| 面试前突击 | 只读 `resume/<岗位>.md` + `07-interview-questions.md`（含速记卡） |
