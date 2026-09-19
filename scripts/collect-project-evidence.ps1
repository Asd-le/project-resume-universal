<#
.SYNOPSIS
    project-resume 通用证据采集器（跨技术栈、跨架构，只读）。

.DESCRIPTION
    不预设语言与架构，先做「项目画像识别」，再按识别结果采集证据。支持：
      · 后端：Java(Spring/Maven/Gradle)、Node/TS(Nest/Express/Koa/Fastify/Next)、
              Python(Django/Flask/FastAPI)、Go(Gin/Echo)、PHP(Laravel/ThinkPHP)、
              .NET、Ruby、Rust
      · 前端：React/Vue/Angular/Svelte/小程序(uni-app/Taro/原生)
      · 移动端：Flutter/RN/Android/iOS
      · 数据/AI：Python 数据栈、Notebook、LLM 相关依赖
      · 架构：单体 / 微服务 / Monorepo / Serverless / 前后端分离 / 多模块
      · 工程化：容器、K8s、CI/CD、IaC、Nginx、数据库迁移、测试与质量门禁
    只读项目源码，仅写入输出目录；不访问网络、不执行构建、不改业务文件。

.PARAMETER ProjectRoot
    项目根目录，默认当前工作目录。

.PARAMETER Author
    Git 贡献分析目标作者（可用逗号分隔多个署名，如 "zhangsan,ZhangSan,zs"）。缺省按提交量取第一作者。

.PARAMETER Branch
    指定分析分支（如 origin/main）。缺省分析当前工作区。

.PARAMETER OutDir
    输出目录，默认 <ProjectRoot>/.project-resume。

.PARAMETER Since
    Git 分析起始时间。

.EXAMPLE
    & .dsh\skills\project-resume-universal\scripts\collect-project-evidence.ps1 -Author "zhangsan,ZhangSan"
.EXAMPLE
    & ...\collect-project-evidence.ps1 -Branch origin/main -OutDir .project-resume
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$Author,
    [string]$Branch,
    [string]$OutDir,
    [string]$Since
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $OutDir) { $OutDir = Join-Path $root '.project-resume' }
$evDir = Join-Path $OutDir 'evidence'
New-Item -ItemType Directory -Force -Path $evDir | Out-Null

$script:warnings = New-Object System.Collections.Generic.List[string]

# ---------- 基础工具 ----------
function Read-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $t = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
        if ($null -eq $t) { return '' }
        return ,$t
    } catch { $script:warnings.Add('读取失败: ' + $Path); return '' }
}
function Write-Section {
    param([string]$Name, [System.Collections.Generic.List[string]]$Lines)
    $p = Join-Path $evDir $Name
    $Lines | Out-File -LiteralPath $p -Encoding UTF8
    Write-Host ("[ev] {0}  ({1} lines)" -f $Name, $Lines.Count)
}
function Rel {
    param([string]$Full)
    return ($Full.Substring($root.Length).TrimStart('\','/') -replace '\\','/')
}
# 项目文件清单（只看项目，不进入输出目录/依赖目录）
$SKIP_DIRS = @('node_modules','.git','target','build','dist','out','.next','.nuxt','vendor',
    '__pycache__','.venv','venv','env','.idea','.vscode','coverage','.gradle','bin','obj',
    'logs','tmp','.project-resume','.dsh','third_party','packages/*/node_modules')
function Get-ProjectFiles {
    param([int]$MaxDepth = 12)
    $all = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($root, 0))
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop(); $dir = $cur[0]; $depth = [int]$cur[1]
        if ($depth -gt $MaxDepth) { continue }
        $entries = @()
        try { $entries = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue } catch { continue }
        foreach ($e in $entries) {
            if ($e.PSIsContainer) {
                if ($SKIP_DIRS -contains $e.Name) { continue }
                $stack.Push(@($e.FullName, $depth + 1))
            } else { $all.Add($e) }
        }
    }
    return $all
}
function Find-First {
    param([System.Collections.Generic.List[object]]$Files, [string]$Name, [int]$Depth = 1)
    foreach ($f in $Files) {
        if ($f.Name -ieq $Name) {
            $rel = Rel $f.FullName
            if (($rel -split '/').Count -le ($Depth + 1)) { return $f }
        }
    }
    return $null
}
function Git {
    param([string[]]$GitArgs)
    try {
        $b = @('-C', $root)
        if ($Branch) { } # git log 的 branch 作为参数传入
        $r = & git @b @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($r)
    } catch { return @() }
}

$files = Get-ProjectFiles
$script:allFiles = $files
$hasGit = Test-Path -LiteralPath (Join-Path $root '.git')
$ref = if ([string]::IsNullOrWhiteSpace($Branch)) { 'HEAD' } else { $Branch }

# =====================================================================
# 0. 项目画像（先识别，再采集）
# =====================================================================
$prof = New-Object System.Collections.Generic.List[string]
function A0 { param([string]$s) $prof.Add($s) }

$extCount = @{}
foreach ($f in $files) { $e = $f.Extension.ToLower(); if ($e) { $extCount[$e] = 1 + ($extCount[$e] | ForEach-Object { $_ } | Select-Object -First 1) } }
# 重新精确统计
$extCount = @{}
foreach ($f in $files) { $e = $f.Extension.ToLower(); if (-not $e) { $e = '(none)' }; if ($extCount.ContainsKey($e)) { $extCount[$e]++ } else { $extCount[$e] = 1 } }

$manifestDefs = [ordered]@{
    'Node/npm'        = 'package.json'
    'pnpm workspace'  = 'pnpm-workspace.yaml'
    'Yarn workspace'  = 'yarn.lock'
    'Nx'              = 'nx.json'
    'Turborepo'       = 'turbo.json'
    'Lerna'           = 'lerna.json'
    'Java/Maven'      = 'pom.xml'
    'Java/Gradle'     = 'build.gradle'
    'Gradle KTS'      = 'build.gradle.kts'
    'Go module'       = 'go.mod'
    'Rust/Cargo'      = 'Cargo.toml'
    'Python/requirements' = 'requirements.txt'
    'Python/PyProject'= 'pyproject.toml'
    'Python/Pipenv'   = 'Pipfile'
    'Conda'           = 'environment.yml'
    'PHP/Composer'    = 'composer.json'
    'Ruby/Gemfile'    = 'Gemfile'
    'Dart/Flutter'    = 'pubspec.yaml'
    'CocoaPods'       = 'Podfile'
    'Carthage'        = 'Cartfile'
    'SwiftPM'         = 'Package.swift'
    'Gradle wrapper'  = 'gradlew'
    'Maven wrapper'   = 'mvnw'
}
$foundManifests = @()
foreach ($k in $manifestDefs.Keys) {
    $hit = @($files | Where-Object { $_.Name -ieq $manifestDefs[$k] })
    if ($hit.Count -gt 0) { $foundManifests += ($k + ' -> ' + (($hit | Select-Object -First 6 | ForEach-Object { Rel $_.FullName }) -join ', ') + $(if ($hit.Count -gt 6) { " (+$($hit.Count - 6) more)" } else { '' })) }
}

# 前端/移动端/桌面特征
$stackProbes = [ordered]@{
    'React'          = '"react"'
    'Vue'            = '"vue"'
    'Angular'        = '"@angular/core"'
    'Svelte'         = '"svelte"'
    'Next.js'        = '"next"'
    'Nuxt'           = '"nuxt"'
    'Vite'           = '"vite"'
    'Webpack'        = '"webpack"'
    'TypeScript'     = '"typescript"'
    'ElementUI/Antd' = '"element-plus"|"element-ui"|"ant-design-vue"|"antd"'
    'uni-app'        = '"@dcloudio/uni-app"'
    'Taro'           = '"@tarojs/taro"'
    '微信小程序'      = 'app\.json|project\.config\.json'
    'Flutter'        = 'flutter:|sdk:\s*flutter'
    'React Native'   = '"react-native"'
    'Electron'       = '"electron"'
    'Express'        = '"express"'
    'NestJS'         = '"@nestjs/core"'
    'Koa'            = '"koa"'
    'Fastify'        = '"fastify"'
    'Spring Boot'    = 'spring-boot-starter'
    'Spring Cloud'   = 'spring-cloud'
    'MyBatis'        = 'mybatis'
    'JPA/Hibernate'  = 'spring-boot-starter-data-jpa|hibernate'
    'Django'         = 'Django==|django==|"django"'
    'Flask'          = 'Flask==|flask=='
    'FastAPI'        = 'fastapi'
    'Gin'            = 'gin-gonic/gin'
    'Echo'           = 'labstack/echo'
    'Laravel'        = 'laravel/framework'
    'ThinkPHP'       = 'topthink/framework'
    'ASP.NET'        = 'Microsoft\.AspNetCore|TargetFramework'
    'Actix/Axum'     = 'actix-web|axum'
    'MySQL'          = 'mysql-connector|mysqlclient|mysql2|PyMySQL|go-sql-driver/mysql'
    'PostgreSQL'     = 'postgresql|psycopg|pgx|lib/pq'
    'MongoDB'        = 'mongodb|mongoose|pymongo|mongo-driver'
    'Redis'          = 'redis|lettuce|jedis|ioredis'
    'Elasticsearch'  = 'elasticsearch|opensearch'
    'Kafka'          = 'kafka'
    'RabbitMQ'       = 'amqp|rabbitmq|pika|amqplib'
    'RocketMQ'       = 'rocketmq'
    'Nacos'          = 'nacos'
    'ShardingSphere' = 'shardingsphere|sharding-jdbc'
    'MyCat'          = 'mycat'
    'Redisson'       = 'redisson'
    'Quartz/XXL-Job' = 'quartz|xxl-job'
    'Docker'         = 'dockerfile'
    'Kubernetes'     = 'kind:\s*(Deployment|Service)|apiVersion:\s*apps/'
    'Helm'           = 'Chart\.yaml'
    'Terraform'      = '\.tf$'
    'Ansible'        = 'ansible'
    'Jenkins'        = 'Jenkinsfile'
    'GitHub Actions' = '\.github/workflows'
    'GitLab CI'      = '\.gitlab-ci\.yml'
    'ArgoCD'         = 'argoproj\.io'
    'Prometheus'     = 'prometheus'
    'Grafana'        = 'grafana'
    'SkyWalking/Zipkin' = 'skywalking|zipkin|jaeger'
    'Sentry'         = 'sentry'
    'ELK'            = 'logstash|filebeat|kibana'
    'OpenAI/LLM'     = 'openai|langchain|llama-index|dashscope|anthropic|qwen|ollama|zhipu|gemini'
    'RAG/向量库'     = 'milvus|pinecone|qdrant|weaviate|pgvector|chroma|faiss|redisvl'
    'Embedding'      = 'embedding|text-embedding|bge-|m3e'
    'Spring AI/LangChain4j' = 'spring-ai|langchain4j'
    'Jest/Vitest'    = '"jest"|"vitest"|"mocha"'
    'JUnit/TestNG'   = 'junit|testng'
    'Pytest'         = 'pytest'
    'Playwright/Cypress' = 'playwright|cypress'
    'ESLint/Prettier'= '"eslint"|"prettier"'
    'SonarQube'      = 'sonar'
    'Swagger/OpenAPI'= 'springfox|springdoc|swagger|openapi'
}
$manifestTexts = @{}
foreach ($k in $manifestDefs.Keys) {
    foreach ($f in @($files | Where-Object { $_.Name -ieq $manifestDefs[$k] })) {
        $manifestTexts[$k] = (($manifestTexts[$k] | ForEach-Object { $_ }) -join "`n") + (Read-Text $f.FullName)
    }
}
# 也把 docker/compose/k8s/nginx 等并入搜索文本
$infraNames = @('Dockerfile','docker-compose.yml','docker-compose.yaml','Jenkinsfile','.gitlab-ci.yml',
    'nginx.conf','Chart.yaml','Makefile','Procfile','serverless.yml','vercel.json','netlify.toml')
foreach ($n in $infraNames) {
    foreach ($f in @($files | Where-Object { $_.Name -ieq $n })) { $manifestTexts['infra:' + $n] = (Read-Text $f.FullName) }
}
$searchPool = ($manifestTexts.Values -join "`n")

$hitStacks = @()
foreach ($k in $stackProbes.Keys) {
    if ([bool]("$searchPool" -match $stackProbes[$k])) { $hitStacks += $k }
}
# 目录名也能作为信号（如 k8s/, helm/, terraform/）
$dirNames = @($files | ForEach-Object { ($_.DirectoryName.Substring([Math]::Min($root.Length, $_.DirectoryName.Length)) -replace '\\','/') } | Sort-Object -Unique)
foreach ($d in @('k8s','kubernetes','helm','charts','terraform','ansible','deploy','.github','.gitlab')) {
    if ($dirNames -match $d) { if ($hitStacks -notcontains $d) { $hitStacks += ('dir:' + $d) } }
}

# 架构形态判断
$arch = New-Object System.Collections.Generic.List[string]
if (@($files | Where-Object { $_.Name -ieq 'package.json' }).Count -ge 3) { $arch.Add('Monorepo（多个 package.json）') }
if (@($files | Where-Object { $_.Name -ieq 'pom.xml' }).Count -ge 2) { $arch.Add('多模块 Maven 工程') }
if ($hitStacks -contains 'Nx' -or $hitStacks -contains 'Turborepo' -or $hitStacks -contains 'Lerna') { $arch.Add('Monorepo 工具链（Nx/Turbo/Lerna）') }
if ($hitStacks -contains 'Kubernetes' -or $hitStacks -contains 'Helm') { $arch.Add('容器编排（K8s/Helm）') }
if ($hitStacks -contains 'Spring Cloud' -or $hitStacks -contains 'Nacos' -or $hitStacks -contains 'Kafka') { $arch.Add('微服务/分布式特征（Spring Cloud/Nacos/MQ）') }
if ($hitStacks -contains 'serverless.yml' -or (@($files | Where-Object { $_.Name -ieq 'serverless.yml' }).Count -gt 0)) { $arch.Add('Serverless') }
if ((Test-Path (Join-Path $root 'src/main')) -and (@($files | Where-Object { $_.Name -ieq 'package.json' }).Count -ge 1)) { $arch.Add('前后端同仓（src/main + package.json）') }
if ($hitStacks -contains 'React' -or $hitStacks -contains 'Vue' -or $hitStacks -contains 'Angular' -or $hitStacks -contains 'Svelte' -or $hitStacks -contains 'Next.js' -or $hitStacks -contains 'Nuxt') { $arch.Add('含前端应用') }
if ($hitStacks -contains 'Flutter' -or $hitStacks -contains 'React Native' -or $hitStacks -contains 'uni-app' -or $hitStacks -contains 'Taro' -or $hitStacks -contains '微信小程序') { $arch.Add('含移动端/小程序') }

A0 '# 0 · 项目画像（自动识别，供后续阶段分流）'
A0 ''
A0 ('- 项目根目录: ' + $root)
A0 ('- 采集时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
A0 ('- 分析引用: ' + $ref + $(if ($Branch) { '（分支模式）' } else { '（当前工作区）' }))
A0 ('- 项目文件数（排除依赖/构建产物）: ' + $files.Count)
A0 ''
A0 '## 构建清单文件（判断语言与包管理）'
A0 ''
if ($foundManifests.Count -eq 0) { A0 '- ⚠️ 未发现常见构建清单，可能是脚本型/文档型仓库或非常见技术栈' }
else { foreach ($m in $foundManifests) { A0 ('- ' + $m) } }
A0 ''
A0 '## 识别到的技术栈信号'
A0 ''
if ($hitStacks.Count -eq 0) { A0 '- ⚠️ 未命中任何预置技术探针（需人工确认技术栈）' }
else { foreach ($s in $hitStacks) { A0 ('- ' + $s) } }
A0 ''
A0 '## 推断的架构形态'
A0 ''
if ($arch.Count -eq 0) { A0 '- 未识别到明显特征（可能是单模块单体应用）' }
else { foreach ($a in $arch) { A0 ('- ' + $a) } }
A0 ''
A0 '## 文件类型分布（Top 25）'
A0 ''
A0 '| 扩展名 | 文件数 |'
A0 '|---|---|'
$extCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25 | ForEach-Object { A0 ('| ' + $_.Key + ' | ' + $_.Value + ' |') }
A0 ''
A0 '## 顶层结构（depth<=2，排除依赖目录）'
A0 ''
A0 '```'
$topDirs = @($dirNames | Where-Object { ($_ -split '/').Count -le 3 -and $_ -ne '' } | Sort-Object -Unique | Select-Object -First 60)
foreach ($d in $topDirs) { A0 ('  ' + $d) }
A0 '```'
A0 ''
A0 '## 快速特征文件（存在性）'
A0 ''
$quickNames = @('Dockerfile','docker-compose.yml','docker-compose.yaml','Jenkinsfile','.gitlab-ci.yml',
    'nginx.conf','Chart.yaml','Makefile','Procfile','serverless.yml','README.md','LICENSE','.editorconfig',
    'sonar-project.properties','.eslintrc','.eslintrc.js','.eslintrc.json','.prettierrc','tsconfig.json',
    'jest.config.js','vitest.config.ts','pytest.ini','.github')
foreach ($n in $quickNames) {
    $hit = @($files | Where-Object { $_.Name -ieq $n })
    if ($hit.Count -gt 0) { A0 ('- [存在] ' + $n + '  x' + $hit.Count + '  例: ' + (Rel $hit[0].FullName)) }
    elseif ($n -eq '.github' -and (Test-Path (Join-Path $root '.github'))) { A0 '- [存在] .github/（目录）' }
}
Write-Section '00-project-profile.md' $prof

# =====================================================================
# 1. 构建与依赖（跨栈）
# =====================================================================
$dep = New-Object System.Collections.Generic.List[string]
function A1 { param([string]$s) $dep.Add($s) }
A1 '# 1 · 构建与依赖证据（跨栈）'
A1 ''

# --- Node 系 ---
$pkgJson = Find-First $files 'package.json'
if ($pkgJson) {
    A1 '## Node 系（package.json）'
    A1 ''
    $allPkg = @($files | Where-Object { $_.Name -ieq 'package.json' })
    A1 ('- package.json 数量: ' + $allPkg.Count + '（>1 说明是 Monorepo 或多包）')
    A1 ''
    foreach ($pj in ($allPkg | Select-Object -First 8)) {
        $j = Read-Text $pj.FullName
        A1 ('### ' + (Rel $pj.FullName))
        A1 ''
        try {
        $o = $null
        try { $o = $j | ConvertFrom-Json } catch { }
            if ($o.name) { A1 ('- name: ' + $o.name + '  version: ' + $o.version) }
            if ($o.scripts) { A1 '- scripts:'; foreach ($p in $o.scripts.PSObject.Properties) { A1 ('    - ' + $p.Name + ': ' + $p.Value) } }
            if ($o.engines) { A1 ('- engines: ' + ($o.engines | ConvertTo-Json -Compress)) }
            $d = @()
            foreach ($sec in @('dependencies','devDependencies','peerDependencies','optionalDependencies')) {
                if ($o.$sec) { foreach ($p in $o.$sec.PSObject.Properties) { $d += ($sec.Substring(0, [Math]::Min(4, $sec.Length)) + ' ' + $p.Name + '@' + $p.Value) } }
            }
            A1 ('- 依赖共 ' + $d.Count + ' 条，全部列出：')
            foreach ($x in $d) { A1 ('    - ' + $x) }
        } catch { A1 '- ⚠️ package.json 解析失败，原文前 40 行：'; A1 '```json'; (($j -split "`n") | Select-Object -First 40) | ForEach-Object { A1 $_ }; A1 '```' }
        A1 ''
    }
    # 锁文件
    foreach ($lk in @('package-lock.json','yarn.lock','pnpm-lock.yaml')) {
        $f = Find-First $files $lk
        if ($f) { A1 ('- 锁文件: ' + (Rel $f.FullName) + ' (' + $f.Length + ' bytes)') }
    }
    A1 ''
}

# --- Java 系 ---
$pom = Find-First $files 'pom.xml'
if ($pom) {
    A1 '## Java 系（Maven）'
    A1 ''
    $pomText = Read-Text $pom.FullName
    $repaired = $pomText
    try {
        $repaired = [regex]::Replace($pomText, '(?s)<!--.*?-->', {
                param($m); $inner = $m.Value.Substring(4, $m.Value.Length - 7) -replace '--', '@@'
                return '<!--' + $inner + '-->' })
    } catch { }
    [xml]$x = $null
    try { [xml]$x = $repaired } catch { }
    if ($x) {
        A1 ('- groupId: ' + [string]$x.project.groupId + ' / artifactId: ' + [string]$x.project.artifactId + ' / version: ' + [string]$x.project.version + ' / packaging: ' + [string]$x.project.packaging)
        if ($x.project.parent) { A1 ('- parent: ' + [string]$x.project.parent.groupId + ':' + [string]$x.project.parent.artifactId + ':' + [string]$x.project.parent.version) }
        if ($x.project.properties) {
            A1 '- 版本属性:'
            foreach ($p in $x.project.properties.PSObject.Properties) {
                if ($p.Name -notmatch '^[A-Za-z_][A-Za-z0-9_\.\-]*$') { continue }
                A1 ('    - ' + $p.Name + ' = ' + [string]$p.Value)
            }
        }
        $deps = @($x.project.dependencies.dependency)
        A1 ('- 依赖共 ' + $deps.Count + ' 条，全部列出：')
        foreach ($d in $deps) {
            if (-not $d) { continue }
            $line = '    - ' + [string]$d.groupId + ':' + [string]$d.artifactId
            if ($d.version) { $line += ':' + [string]$d.version }
            if ($d.scope) { $line += ' [scope=' + [string]$d.scope + ']' }
            A1 $line
        }
        foreach ($pl in @($x.project.build.plugins.plugin)) {
            if ($pl) { A1 ('- plugin: ' + [string]$pl.groupId + ':' + [string]$pl.artifactId + $(if ($pl.version) { ':' + [string]$pl.version } else { '' })) }
        }
        $profileIds = @($x.project.profiles.profile | ForEach-Object { [string]$_.id } | Where-Object { $_ })
        if ($profileIds.Count -gt 0) { A1 ('- Maven profiles: ' + ($profileIds -join ', ')) }
    } else {
        A1 '- ⚠️ pom.xml 非常规 XML，降级正则提取依赖：'
        foreach ($m in [regex]::Matches($pomText, '(?s)<dependency\b[^>]*>([\s\S]*?)</dependency>')) {
            $b = $m.Groups[1].Value
            $g = [regex]::Match($b, '<groupId>([\s\S]*?)</groupId>').Groups[1].Value.Trim()
            $a = [regex]::Match($b, '<artifactId>([\s\S]*?)</artifactId>').Groups[1].Value.Trim()
            $v = [regex]::Match($b, '<version>([\s\S]*?)</version>').Groups[1].Value.Trim()
            A1 ('    - ' + $g + ':' + $a + $(if ($v) { ':' + $v } else { '' }))
        }
    }
    $allPoms = @($files | Where-Object { $_.Name -ieq 'pom.xml' })
    if ($allPoms.Count -gt 1) { A1 ('- 子模块 pom 共 ' + $allPoms.Count + ' 个: ' + (($allPoms | Select-Object -First 12 | ForEach-Object { Rel $_.FullName }) -join ', ')) }
    A1 ''
}
$gradle = Find-First $files 'build.gradle'; if (-not $gradle) { $gradle = Find-First $files 'build.gradle.kts' }
if ($gradle) {
    A1 '## Java 系（Gradle）'
    A1 ''
    A1 ('- ' + (Rel $gradle.FullName))
    A1 '```groovy'
    ((Read-Text $gradle.FullName) -split "`n" | Select-Object -First 120) | ForEach-Object { A1 $_ }
    A1 '```'
    A1 ''
}

# --- Python 系 ---
foreach ($pn in @('requirements.txt','pyproject.toml','Pipfile','environment.yml')) {
    $f = Find-First $files $pn
    if ($f) {
        A1 ('## Python 系（' + $pn + '）')
        A1 ''
        A1 ('- ' + (Rel $f.FullName))
        A1 '```'
        ((Read-Text $f.FullName) -split "`n" | Select-Object -First 100) | ForEach-Object { A1 $_ }
        A1 '```'
        A1 ''
    }
}

# --- Go / Rust / PHP / Ruby / Dart / .NET ---
$others = [ordered]@{ 'go.mod'='Go'; 'Cargo.toml'='Rust'; 'composer.json'='PHP'; 'Gemfile'='Ruby'; 'pubspec.yaml'='Dart/Flutter' }
foreach ($k in $others.Keys) {
    $f = Find-First $files $k
    if ($f) {
        A1 ('## ' + $others[$k] + '（' + $k + '）')
        A1 ''
        A1 ('- ' + (Rel $f.FullName))
        A1 '```'
        ((Read-Text $f.FullName) -split "`n" | Select-Object -First 80) | ForEach-Object { A1 $_ }
        A1 '```'
        A1 ''
    }
}
$csproj = @($files | Where-Object { $_.Extension -ieq '.csproj' -or $_.Extension -ieq '.sln' })
if ($csproj.Count -gt 0) {
    A1 '## .NET'
    A1 ''
    foreach ($f in ($csproj | Select-Object -First 8)) { A1 ('- ' + (Rel $f.FullName)) }
    $first = $csproj | Select-Object -First 1
    A1 '```xml'
    ((Read-Text $first.FullName) -split "`n" | Select-Object -First 60) | ForEach-Object { A1 $_ }
    A1 '```'
    A1 ''
}

# --- 容器/CI/IaC ---
A1 '## 容器 / CI / IaC / 部署（存在性与内容）'
A1 ''
foreach ($n in @('Dockerfile','docker-compose.yml','docker-compose.yaml','.dockerignore','Jenkinsfile',
        '.gitlab-ci.yml','Makefile','Procfile','serverless.yml','vercel.json','netlify.toml','Chart.yaml','nginx.conf')) {
    $hit = @($files | Where-Object { $_.Name -ieq $n })
    if ($hit.Count -eq 0) { continue }
    A1 ('### ' + $n + '  (' + $hit.Count + ' 个)')
    A1 '```'
    ((Read-Text $hit[0].FullName) -split "`n" | Select-Object -First 70) | ForEach-Object { A1 $_ }
    A1 '```'
    A1 ''
}
# workflows 目录
$wf = @($files | Where-Object { (Rel $_.FullName) -match '\.github/workflows/.+\.ya?ml$' })
if ($wf.Count -gt 0) {
    A1 ('### GitHub Actions workflows (' + $wf.Count + ')')
    foreach ($f in $wf) { A1 ('- ' + (Rel $f.FullName)) }
    A1 '```yaml'
    ((Read-Text $wf[0].FullName) -split "`n" | Select-Object -First 60) | ForEach-Object { A1 $_ }
    A1 '```'
    A1 ''
}
# k8s / helm / terraform
foreach ($pat in @('k8s','kubernetes','helm','charts','terraform','ansible','deploy')) {
    $hit = @($files | Where-Object { (Rel $_.FullName) -match ("(?i)(^|/)" + $pat + "/") })
    if ($hit.Count -gt 0) {
        A1 ('### ' + $pat + '/ 目录（' + $hit.Count + ' 个文件）')
        foreach ($f in ($hit | Select-Object -First 15)) { A1 ('- ' + (Rel $f.FullName)) }
        A1 ''
    }
}
Write-Section '01-build-and-deps.md' $dep

# =====================================================================
# 2. 配置证据（多格式，敏感值脱敏）
# =====================================================================
$cfg = New-Object System.Collections.Generic.List[string]
function A2 { param([string]$s) $cfg.Add($s) }
A2 '# 2 · 配置证据（多格式；敏感值已按键名整行脱敏）'
A2 ''
A2 '> 脱敏规则：整行命中敏感词（password/secret/token/key 等）时，只保留缩进+键名，值一律丢弃；'
A2 '> 注释行内嵌敏感键则整行丢弃。**不要把本文件外发。**'
A2 ''
$SENS = '(?i)(password|passwd|pwd|secret|accesskey|access-key|secretkey|secret-key|token|apikey|api-key|privatekey|private-key|appsecret|mchkey|encryptor|credential|dsn|connectionstring)'
$cfgPat = '\.(env|ini|conf|config|toml|properties|ya?ml|json)$'
$cfgCandidates = @($files | Where-Object {
        $n = $_.Name
        ($n -match '(?i)^(application|appsettings|config|settings|local|dev|prod|test|\.env)' -or
         $n -match '(?i)^\.env' -or $n -ieq 'config.php' -or $n -ieq 'database.php') -and
        $n -match $cfgPat -and
        $n -notmatch '(?i)(package-lock|yarn.lock|pnpm-lock|composer.lock|Gemfile.lock)'
    })
A2 ('- 命中配置类文件 ' + $cfgCandidates.Count + ' 个（仅列出，最多展示 12 个的脱敏内容）')
A2 ''
foreach ($f in ($cfgCandidates | Sort-Object Length -Descending | Select-Object -First 12)) {
    A2 ('## ' + (Rel $f.FullName) + '  (' + $f.Length + ' bytes)')
    A2 ''
    A2 '```'
    $lines = @((Read-Text $f.FullName) -split "`n")
    $shown = 0
    foreach ($ln in $lines) {
        if ($shown -ge 120) { A2 '... (截断)'; break }
        $trim = $ln.TrimStart()
        $indent = if ($trim.Length -lt $ln.Length) { $ln.Substring(0, $ln.Length - $trim.Length) } else { '' }
        $keyPart = ($ln -split '[:=]', 2)[0]
        if ($ln -match $SENS) {
            if ($trim.StartsWith('#') -or $trim.StartsWith('//')) { A2 ($indent + '# <REDACTED: 注释含敏感键，整行丢弃>') }
            elseif ($keyPart -match '\S') { A2 ($indent + $keyPart.Trim() + ': <REDACTED>') }
            else { A2 ($indent + '<REDACTED: 疑似密钥字面量，整行丢弃>') }
        } else {
            if ($ln.Length -gt 300) { A2 ($ln.Substring(0, 300) + '...') } else { A2 $ln }
        }
        $shown++
    }
    A2 '```'
    A2 ''
}
Write-Section '02-config-evidence.md' $cfg

# =====================================================================
# 3. 接口清单（多框架）
# =====================================================================
$api = New-Object System.Collections.Generic.List[string]
function A3 { param([string]$s) $api.Add($s) }
A3 '# 3 · 接口清单（按框架静态提取）'
A3 ''
A3 '> 全部为静态注解/路由提取，用于衡量接口规模与业务边界，不代表运行时准确数量。'
A3 ''

$codeExt = @('.java','.kt','.ts','.js','.tsx','.jsx','.py','.go','.php','.cs','.rb','.dart')
$codeFiles = @($files | Where-Object { $codeExt -contains $_.Extension.ToLower() })
A3 ('- 代码文件数: ' + $codeFiles.Count)
A3 ''

$totalRoutes = 0
$routeRows = 0
$MAXROWS = 6000
foreach ($f in $codeFiles) {
    if ($routeRows -ge $MAXROWS) { A3 '- ...（已达输出上限，截断）'; break }
    if ($f.Length -gt 1MB) { continue }
    $t = Read-Text $f.FullName
    if (-not $t) { continue }
    $rel = Rel $f.FullName
    $found = New-Object System.Collections.Generic.List[string]

    switch ($f.Extension.ToLower()) {
        { $_ -in '.java','.kt' } {
            $base = ''
            $bm = [regex]::Match($t, '(?s)@RequestMapping\s*\(\s*(?:value\s*=\s*)?[{"]([^"}]+)')
            if ($bm.Success) { $base = $bm.Groups[1].Value }
            foreach ($m in [regex]::Matches($t, '(?m)^\s*@(Get|Post|Put|Delete|Patch|Request)Mapping\s*(\([^)]*\))?')) {
                $path = ''; if ($m.Groups[2].Value) { $pm = [regex]::Match($m.Groups[2].Value, '[{"]([^"}]+)'); if ($pm.Success) { $path = $pm.Groups[1].Value } }
                $found.Add(('[' + $m.Groups[1].Value + '] ' + $base + $path))
            }
        }
        { $_ -in '.ts','.js','.tsx','.jsx' } {
            foreach ($m in [regex]::Matches($t, '(?m)@(Get|Post|Put|Delete|Patch|Head|Options|All)\s*\(\s*[`''"]([^`''"]+)')) { $found.Add(('[' + $m.Groups[1].Value + '] ' + $m.Groups[2].Value)) }
            foreach ($m in [regex]::Matches($t, '(?m)\b(?:app|router|route|server|fastify|api)\s*\.\s*(get|post|put|delete|patch|all|use)\s*\(\s*[`''"]([^`''"]+)')) { $found.Add(('[' + $m.Groups[1].Value.ToUpper() + '] ' + $m.Groups[2].Value)) }
            foreach ($m in [regex]::Matches($t, '(?m)@Controller\s*\(\s*[`''"]([^`''"]*)')) { $found.Add(('[Controller] ' + $m.Groups[1].Value)) }
        }
        '.py' {
            foreach ($m in [regex]::Matches($t, '(?m)@\w+\.(get|post|put|delete|patch|route)\s*\(\s*[''"]([^''"]+)')) { $found.Add(('[' + $m.Groups[1].Value.ToUpper() + '] ' + $m.Groups[2].Value)) }
            foreach ($m in [regex]::Matches($t, '(?m)^\s*(?:path|re_path|url)\s*\(\s*[''"]([^''"]+)')) { $found.Add(('[django-url] ' + $m.Groups[1].Value)) }
        }
        '.go' {
            foreach ($m in [regex]::Matches($t, '(?m)\.(GET|POST|PUT|DELETE|PATCH|Handle|HandleFunc)\s*\(\s*"([^"]+)"')) { $found.Add(('[' + $m.Groups[1].Value + '] ' + $m.Groups[2].Value)) }
        }
        '.php' {
            $phpPat = '(?m)Route::(get|post|put|delete|patch|any|resource)\s*\(\s*[''""]([^''""]+)'
            foreach ($m in [regex]::Matches($t, $phpPat)) { $found.Add(('[' + $m.Groups[1].Value.ToUpper() + '] ' + $m.Groups[2].Value)) }
        }
        '.cs' {
            foreach ($m in [regex]::Matches($t, '(?m)\[Http(Get|Post|Put|Delete|Patch)\s*(?:\(\s*"([^"]*)")?\]')) { $found.Add(('[' + $m.Groups[1].Value + '] ' + $m.Groups[2].Value)) }
        }
        '.rb' {
            $rbPat = @'
(?m)^\s*(get|post|put|delete|patch)\s+['"]([^'"]+)
'@
            foreach ($m in [regex]::Matches($t, $rbPat)) { $found.Add(('[' + $m.Groups[1].Value.ToUpper() + '] ' + $m.Groups[2].Value)) }
        }
        '.dart' {
            $dartPat = @'
(?m)'(/[A-Za-z0-9_/{}\.:\-]+)'
'@
            foreach ($m in [regex]::Matches($t, $dartPat)) { if ($m.Groups[1].Value.Length -gt 3) { $found.Add(('[dart-route] ' + $m.Groups[1].Value)) } }
        }
    }
    if ($found.Count -gt 0) {
        $uniq = @($found | Sort-Object -Unique)
        A3 ('### ' + $rel + '  (' + $uniq.Count + ')')
        foreach ($r in ($uniq | Select-Object -First 60)) { A3 ('  - ' + $r); $routeRows++ }
        if ($uniq.Count -gt 60) { A3 ('  - ...(该文件共 ' + $uniq.Count + ' 条，仅示 60)') }
        A3 ''
        $totalRoutes += $uniq.Count
    }
}
A3 ''
A3 ('**静态提取路由/接口总数: ' + $totalRoutes + '**')
A3 ''
A3 '## 接口按目录聚合（Top 30）'
A3 ''
$codeFiles | Where-Object {
    $t = Read-Text $_.FullName
    $t -match '(?m)@(Get|Post|Put|Delete|Patch)Mapping|@\w+\.(get|post|put|delete|patch)\(|\.(GET|POST|PUT|DELETE)\(|Route::(get|post)'
} | ForEach-Object { ($_.DirectoryName.Substring([Math]::Min($root.Length, $_.DirectoryName.Length)) -replace '\\','/') } |
    Group-Object | Sort-Object Count -Descending | Select-Object -First 30 | ForEach-Object { A3 ('- ' + $_.Name + ' : ' + $_.Count + ' 个文件含路由') }
Write-Section '03-api-inventory.md' $api

# =====================================================================
# 4. 技术能力证据（跨栈探针扫描）
# =====================================================================
$tech = New-Object System.Collections.Generic.List[string]
function A4 { param([string]$s) $tech.Add($s) }
A4 '# 4 · 技术能力证据（跨栈探针，命中数 + 代表文件）'
A4 ''
A4 '> 命中只证明"技术存在且被使用"，不证明"由谁设计"。命中数为 Java/TS/PY 等代码文件维度。'
A4 ''
$probes = [ordered]@{
    '事务'            = '@Transactional|\bBEGIN;|with transaction|\.atomic\(|transaction\.atomic'
    '异步/并发'       = '@Async|asyncio|Promise\.all|asyncio\.gather|CompletableFuture|goroutine|\bgo func|worker_threads|concurrent\.futures'
    '定时任务'        = '@Scheduled|cron|APScheduler|@Cron|Schedule\.|celery beat|node-cron|xxl-job|Quartz'
    '线程池/协程池'   = 'ThreadPoolExecutor|ExecutorService|ThreadPoolTaskExecutor|ProcessPoolExecutor|WorkerPool|asyncio\.Semaphore|GOMAXPROCS'
    '消息队列'        = '@RabbitListener|RabbitTemplate|KafkaTemplate|@KafkaListener|rocketmq|pika|amqp|amqplib|kafka-python|sarama|nsq'
    'MQ 可靠性'       = 'basicAck|basicNack|manual.*ack|ConfirmCallback|deadLetter|x-dead-letter|maxAttempts|idempoten|幂等|retry'
    '缓存'            = '@Cacheable|RedisTemplate|redisTemplate|StringRedisTemplate|ioredis|redis\.|cache\.|CacheManager|memcache'
    '分布式锁'        = 'Redisson|RLock|tryLock|SETNX|setIfAbsent|Lock\(|mutex\.Lock|ZooKeeper|etcd'
    '幂等/防重'       = 'idempoten|Idempotent|幂等|repeatSubmit|RepeatSubmit|nonce|unique.*request|dedup|@Idempotent'
    '多数据源'        = '@DS\b|dynamic-datasource|DynamicDataSource|MultiDataSource|readOnly.*datasource'
    '分库分表'        = 'shardingsphere|sharding-jdbc|ShardingAlgorithm|middleware.*shard|分片|shard'
    '多租户'          = 'tenant_id|tenantId|TenantContext|TenantLine|multi.?tenant|schema_name'
    '分页'            = 'PageHelper|startPage|PageInfo|IPage|LIMIT \?|limit\(|skip\(|offset|pageable'
    '批处理'          = 'batch|Batch|executeBatch|bulkCreate|bulkInsert|rewriteBatchedStatements|copy_from'
    'SQL/索引优化'    = 'ADD INDEX|create index|ADD KEY|explain|EXPLAIN|sql\s*优化|索引'
    '搜索引擎'        = 'elasticsearch|Elasticsearch|opensearch|lucene|solr|meilisearch|typesense'
    '缓存穿透/雪崩治理' = '布隆|bloom|空值缓存|null.*cache|random.*expire|mutex.*cache|singleflight'
    '限流/熔断/降级'  = 'RateLimiter|Sentinel|resilience4j|hystrix|circuit.?break|bulkhead|throttle|@SentinelResource|Guava.*RateLimiter'
    '重试'            = 'Retryable|retry|backoff|maxAttempts|tenacity|resilience4j.*retry'
    '链路追踪/可观测'  = 'MDC|traceId|TraceId|skywalking|zipkin|jaeger|opentelemetry|otel|prometheus|micrometer|actuator'
    '日志'            = 'logback|log4j|winston|pino|bunyan|loguru|logging\.|zap|slog'
    '鉴权/认证'       = 'JwtToken|@PreAuthorize|SecurityContext|Authorization|passport|jwt\.|@UseGuards|Spring Security|OAuth|oidc|SSO|sso'
    '权限模型'        = 'RBAC|role_permission|hasRole|hasPermission|@Permission|casbin|acl'
    '加密/国密/签名'  = 'SM2|SM3|SM4|BouncyCastle|AES|RSA|SignUtil|signature|hmac|jasypt|kms|vault'
    '文件/对象存储'   = 'Qiniu|qiniu|OSS|ossClient|s3|minio|cos\.|obs\.|multipart|UploadFile'
    'Excel/报表导入导出' = 'EasyExcel|POI|XSSFWorkbook|@Excel|openpyxl|pandas\.read_excel|exceljs|xlsx|sheetjs'
    '外部系统集成'    = 'RestTemplate|WebClient|OkHttp|HttpClient|axios|requests\.|httpx|feign|@FeignClient|grpc'
    '支付渠道'        = 'weixin.*pay|WxPay|alipay|allinpay|unionpay|ebusclient|stripe|paypal|银联|支付'
    '短信/邮件/推送'  = 'sms|Sms|SMS|dysmsapi|twilio|nodemailer|smtp|mail|push|极光|个推|firebase'
    '任务调度平台'    = 'xxl-job|elastic-job|airflow|dagster|prefect|temporal|dolphinscheduler|azkaban'
    'AI/LLM 集成'     = 'openai|OpenAI|langchain|llama.?index|dashscope|anthropic|qwen|ollama|zhipu|gemini|bedrock|spring-ai|langchain4j|ChatClient|ChatModel|prompt|Prompt'
    'RAG/向量检索'    = 'milvus|pinecone|qdrant|weaviate|pgvector|chroma|faiss|redisvl|VectorStore|vector_store|retriever|embedding|Embedding|bge-|m3e|rerank'
    'Agent/工具调用'  = 'ReAct|react_agent|tool_call|toolCall|function.?calling|FunctionTool|AgentExecutor|@Tool|mcp|MCP|plan.?and.?execute'
    '流式输出'        = 'SseEmitter|text/event-stream|Flux<|streamCall|incrementalOutput|StreamingResponse|EventSource|websocket|WebSocket'
    'AI 评测/可观测'  = 'eval|Eval|评测|golden|llm.?as.?judge|token.*usage|usage\.total_tokens|cost.*token'
    '状态机/工作流'   = 'StateMachine|状态流转|status.*transfer|workflow|Flowable|Activiti|temporal|BPMN'
    '测试'            = '@Test|@SpringBootTest|describe\(|it\(|test\(|pytest|func Test|RSpec|jest|vitest|MockMvc|Testcontainers'
    '类型安全/静态检查' = 'mypy|pyright|typescript|tsconfig|strict.*true|eslint|pylint|golangci|checkstyle|spotbugs'
    'API 文档'        = 'Swagger|springfox|springdoc|openapi|OpenAPI|@ApiOperation|swagger-ui|redoc|apidoc'
    '国际化'          = 'MessageSource|LocaleResolver|i18n|intl|react-intl|vue-i18n|gettext|babel'
    '前端状态管理'    = 'redux|zustand|mobx|pinia|vuex|recoil|jotai|rxjs|BehaviorSubject'
    '前端路由'        = 'react-router|vue-router|@angular/router|createBrowserRouter|createRouter'
    '前端构建优化'    = 'code.?split|lazy\(|dynamic import|tree.?shak|webpackChunkName|manualChunks|externals|bundle.*analy'
    'SSR/SSG'         = 'getServerSideProps|getStaticProps|nuxt|SSR|server.?side.*render|app router|RSC'
    '小程序特有'      = 'wx\.|uni\.|Taro\.|getApp\(\)|Page\(|Component\('
    '移动端原生能力'  = 'MethodChannel|PlatformException|PermissionsAndroid|Info\.plist|AndroidManifest|uses-permission'
    '数据管道/ETL'    = 'airflow|dbt|etl|ETL|spark|flink|pandas|polars|dataframe|datawarehouse|clickhouse'
    '容器化'          = 'FROM .*|docker-compose|dockerfile|image:'
    'CI/CD'           = 'Jenkinsfile|\.gitlab-ci|workflows/|\.travis|circleci|azure-pipelines|drone'
    'K8s/IaC'         = 'kind: Deployment|apiVersion: apps|resource "|helm|Chart\.yaml|terraform|ansible'
}
$poolFiles = $codeFiles
foreach ($probe in $probes.GetEnumerator()) {
    $hits = New-Object System.Collections.Generic.List[string]
    $count = 0
    foreach ($f in $poolFiles) {
        if ($f.Length -gt 1MB) { continue }
        $t = Read-Text $f.FullName
        if (-not $t) { continue }
        $ms = [regex]::Matches($t, $probe.Value)
        if ($ms.Count -gt 0) {
            $count += $ms.Count
            if ($hits.Count -lt 10) { $hits.Add((Rel $f.FullName) + ' (' + $ms.Count + ')') }
        }
    }
    A4 ('## ' + $probe.Key)
    A4 ''
    A4 ('- 命中总数: ' + $count)
    if ($hits.Count -gt 0) { A4 '- 代表文件:'; foreach ($h in $hits) { A4 ('    - ' + $h) } } else { A4 '- 代表文件: 无命中' }
    A4 ''
}
Write-Section '04-tech-capability-evidence.md' $tech

# =====================================================================
# 5. 数据库与数据层证据
# =====================================================================
$db = New-Object System.Collections.Generic.List[string]
function A5 { param([string]$s) $db.Add($s) }
A5 '# 5 · 数据库 / 数据层证据'
A5 ''
$sqlFiles = @($files | Where-Object { $_.Extension -ieq '.sql' })
A5 ('- SQL 文件数: ' + $sqlFiles.Count)
$migPatterns = @('migration','migrations','db/migrate','flyway','liquibase','alembic','prisma/migrations')
foreach ($p in $migPatterns) {
    $hit = @($files | Where-Object { (Rel $_.FullName) -match ("(?i)" + [regex]::Escape($p)) })
    if ($hit.Count -gt 0) { A5 ('- 迁移框架信号 [' + $p + ']: ' + $hit.Count + ' 个文件，例: ' + (Rel $hit[0].FullName)) }
}
A5 ''
if ($sqlFiles.Count -gt 0) {
    A5 '## SQL 文件清单（含体量与关键语句统计）'
    A5 ''
    A5 '| 文件 | bytes | CREATE TABLE | ALTER | INDEX | INSERT |'
    A5 '|---|---|---|---|---|---|'
    $tables = New-Object System.Collections.Generic.List[string]
    foreach ($s in ($sqlFiles | Sort-Object FullName)) {
        $t = Read-Text $s.FullName
        $ct = ([regex]::Matches($t, '(?i)CREATE\s+TABLE')).Count
        $at = ([regex]::Matches($t, '(?i)ALTER\s+TABLE')).Count
        $ix = ([regex]::Matches($t, '(?i)(ADD\s+(UNIQUE\s+)?(INDEX|KEY)|CREATE\s+(UNIQUE\s+)?INDEX)')).Count
        $ins = ([regex]::Matches($t, '(?i)INSERT\s+INTO')).Count
        A5 ('| ' + (Rel $s.FullName) + ' | ' + $s.Length + ' | ' + $ct + ' | ' + $at + ' | ' + $ix + ' | ' + $ins + ' |')
        foreach ($m in [regex]::Matches($t, '(?i)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"\[]?([A-Za-z0-9_]+)')) { $tables.Add($m.Groups[1].Value.ToLower()) }
    }
    $uniqTables = @($tables | Sort-Object -Unique)
    A5 ''
    A5 ('## 表名全集（去重，共 ' + $uniqTables.Count + ' 张）')
    A5 ''
    A5 '```'
    $uniqTables | ForEach-Object { A5 $_ }
    A5 '```'
    A5 ''
    # 索引与优化痕迹
    $idxFiles = @($sqlFiles | Where-Object { $_.Name -match '(?i)index|索引|optimi|性能|perf' })
    if ($idxFiles.Count -gt 0) {
        A5 '## 索引 / 性能相关脚本'
        A5 ''
        foreach ($s in $idxFiles) {
            A5 ('### ' + (Rel $s.FullName))
            A5 '```sql'
            ((Read-Text $s.FullName) -split "`n" | Select-Object -First 80) | ForEach-Object { A5 $_ }
            A5 '```'
            A5 ''
        }
    }
}
# ORM 模型/实体
$ormProbes = [ordered]@{
    'JPA/Hibernate 实体' = '@Entity|@Table'
    'MyBatis Mapper'     = '@Mapper|<mapper namespace|BaseMapper<'
    'Sequelize/TypeORM'  = '@Entity\(|Model\.init|sequelize|@Column\('
    'Prisma'             = 'model \w+ \{|@prisma/client'
    'Django 模型'        = 'models\.Model|class \w+\(models\.'
    'SQLAlchemy'         = 'declarative_base|Column\(|relationship\('
    'GORM'               = 'gorm\.Model|gorm:"'
    'Eloquent'           = 'extends Model|protected \$table'
}
A5 ''
A5 '## ORM / 实体层命中'
A5 ''
foreach ($k in $ormProbes.Keys) {
    $c = 0; $examples = @()
    foreach ($f in $codeFiles) {
        $t = Read-Text $f.FullName
        if ($t -and ([bool]("$t" -match $ormProbes[$k]))) { $c++; if ($examples.Count -lt 5) { $examples += (Rel $f.FullName) } }
    }
    A5 ('- ' + $k + ': ' + $c + ' 个文件' + $(if ($examples.Count -gt 0) { '，例: ' + ($examples -join ', ') } else { '' }))
}
Write-Section '05-database-evidence.md' $db

# =====================================================================
# 6. 框架与集成清单
# =====================================================================
$fw = New-Object System.Collections.Generic.List[string]
function A6 { param([string]$s) $fw.Add($s) }
A6 '# 6 · 目录结构与框架基础设施'
A6 ''
A6 '## 目录树（depth<=3，排除依赖目录，最多 400 行）'
A6 ''
A6 '```'
$printed = 0
$dirs = @($dirNames | Sort-Object -Unique)
foreach ($d in $dirs) {
    if ($printed -ge 400) { A6 '... (截断)'; break }
    if (($d -split '/').Count -le 4) { A6 ('  ' + $d); $printed++ }
}
A6 '```'
A6 ''
A6 '## 关键源码目录及文件数（Top 40）'
A6 ''
$codeFiles | ForEach-Object { ($_.DirectoryName.Substring([Math]::Min($root.Length, $_.DirectoryName.Length)) -replace '\\','/') } |
    Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 40 |
    ForEach-Object { A6 ('- ' + $_.Name + ' : ' + $_.Count + ' 个代码文件') }
A6 ''
A6 '## 入口 / 启动文件候选'
A6 ''
$entryPats = @('(?i)(Application|Main|Server|App|Index|Bootstrap|Startup)\.(java|kt|ts|js|py|go|cs|php|rb|dart)$',
    '(?i)(main|app|server|index)\.(ts|js|py|go|rb)$', '(?i)manage\.py$', '(?i)Program\.cs$')
foreach ($f in $codeFiles) {
    foreach ($p in $entryPats) { if ($f.Name -match $p) { A6 ('- ' + (Rel $f.FullName)); break } }
}
Write-Section '06-structure-and-frameworks.md' $fw

# =====================================================================
# 7. Git 证据 —— 由独立脚本 collect-git-evidence.ps1 产出
# ---------------------------------------------------------------------
# 说明：Git 证据采集在"被其他脚本内联调用"时可能受执行环境影响返回空输出，
#       因此这里做两件事：① 调用独立脚本；② 校验产出，若为空则给出明确的补跑指引。
$gitScript = Join-Path $PSScriptRoot 'collect-git-evidence.ps1'
$gitOut = Join-Path $evDir '07-git-evidence.md'
if (Test-Path -LiteralPath $gitScript) {
    $gitParams = @{ ProjectRoot = $root; OutFile = $gitOut }
    if ($Author) { $gitParams['Author'] = $Author }
    if ($Branch) { $gitParams['Branch'] = $Branch }
    if ($Since)  { $gitParams['Since'] = $Since }
    try { & $gitScript @gitParams 2>&1 | Out-Null } catch { $script:warnings.Add('Git 证据脚本调用失败: ' + $_.Exception.Message) }
}
# 校验产出是否有效（空则说明 Git 数据未采到）
$gitOk = $false
if (Test-Path -LiteralPath $gitOut) {
    $gi = Get-Content -LiteralPath $gitOut -Encoding UTF8 -ErrorAction SilentlyContinue
    $gitOk = (@($gi | Where-Object { $_ -match '^- 提交总数: \d' }).Count -gt 0)
}
if (-not $gitOk) {
    $msg = New-Object System.Collections.Generic.List[string]
    $msg.Add('# 7 · Git 证据（**未采集成功，需补跑**）')
    $msg.Add('')
    $msg.Add('采集器未能获取 Git 数据（在内联调用场景下 `git` 输出可能为空）。请**单独执行**下面的命令补跑：')
    $msg.Add('')
    $msg.Add('```powershell')
    $msg.Add('& .dsh\skills\project-resume-universal\scripts\collect-git-evidence.ps1 `')
    $msg.Add('    -ProjectRoot "' + $root + '" `')
    $msg.Add('    -Author "' + $Author + '" `')
    $msg.Add('    -OutFile "' + $gitOut + '"')
    $msg.Add('```')
    $msg.Add('')
    $msg.Add('补跑后该文件会包含：工作区新鲜度、提交总量、按邮箱聚合的作者表、**同邮箱多署名**、')
    $msg.Add('目标作者的改动量/高频文件/新增文件/提交类型统计、事故线索提交、分支清单。')
    Write-Section '07-git-evidence.md' $msg
    $script:warnings.Add('Git 证据未采集成功，已在 07-git-evidence.md 中给出补跑命令')
}
# =====================================================================
# 8. 业务模块证据（按目录/实体聚类）
# =====================================================================
$biz = New-Object System.Collections.Generic.List[string]
function A8 { param([string]$s) $biz.Add($s) }
A8 '# 8 · 业务模块与领域模型证据'
A8 ''
A8 '## 业务目录聚类（含 controller/service/domain 信号的目录）'
A8 ''
$bizDirs = @{}
foreach ($f in $codeFiles) {
    $rel = Rel $f.FullName
    $n = $f.Name
    if ($n -match '(?i)(Controller|Service|ServiceImpl|Resource|Handler|Router|View|ViewSet|Mapper|Repository|Entity|Model|Domain|DTO|VO|api)' -or $rel -match '(?i)/(controller|service|domain|model|entity|api|routes?|views?|handlers?)/') {
        $d = ($rel -split '/')[0..([Math]::Min(3, ($rel -split '/').Count - 2))] -join '/'
        if (-not $bizDirs.ContainsKey($d)) { $bizDirs[$d] = 0 }
        $bizDirs[$d]++
    }
}
$bizDirs.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 40 | ForEach-Object { A8 ('- ' + $_.Key + ' : ' + $_.Value + ' 个分层文件') }
A8 ''
A8 '## 领域实体/模型名（业务名词证据）'
A8 ''
$entityNames = New-Object System.Collections.Generic.List[string]
foreach ($f in $codeFiles) {
    if ($f.Name -match '(?i)(Entity|Model|Domain|Table)\.(java|kt|ts|js|py|go|cs|php|rb)$' -or
        ($f.Name -match '(?i)^(T|R|Kh|Yx)[A-Za-z0-9_]+\.(java|kt)$')) {
        $entityNames.Add($f.BaseName)
    }
}
$entityNames | Sort-Object -Unique | Select-Object -First 400 | ForEach-Object { A8 ('- ' + $_) }
A8 ''
A8 '## 前端/页面/组件（若适用）'
A8 ''
$viewFiles = @($codeFiles | Where-Object { $_.FullName -match '(?i)(pages?|views?|components?|screens?|layouts?)[\\/]' })
A8 ('- 页面/组件文件数: ' + $viewFiles.Count)
$viewFiles | Select-Object -First 60 | ForEach-Object { A8 ('- ' + (Rel $_.FullName)) }
A8 ''
A8 '## 数据/算法/脚本（若适用）'
A8 ''
$dataFiles = @($files | Where-Object { $_.Extension -in @('.ipynb','.parquet','.csv','.r','.R','.scala') -or $_.FullName -match '(?i)(notebooks?|scripts?|etl|pipelines?|dags?)[\\/]' })
A8 ('- 数据/脚本文件数: ' + $dataFiles.Count)
$dataFiles | Select-Object -First 40 | ForEach-Object { A8 ('- ' + (Rel $_.FullName)) }
Write-Section '08-business-modules.md' $biz

# =====================================================================
# 9. 自检
# =====================================================================
$chk = New-Object System.Collections.Generic.List[string]
$chk.Add('# 9 · 采集器自检')
$chk.Add('')
$chk.Add('- 本脚本对项目**只读**，仅写入输出目录。')
$chk.Add('- 未访问网络、未执行构建、未修改任何业务文件。')
$chk.Add('- 配置类文件中的敏感值已按键名整行脱敏；但**仍请勿外发本目录**。')
$chk.Add('- 推断性结论必须由分析方标注证据等级，脚本本身不下结论。')
$chk.Add('')
$chk.Add('## 输出文件')
$chk.Add('')
Get-ChildItem -LiteralPath $evDir -File | Sort-Object Name | ForEach-Object { $chk.Add('- ' + $_.Name + '  (' + $_.Length + ' bytes)') }
$chk.Add('')
$chk.Add('## 读取告警')
$chk.Add('')
if ($script:warnings.Count -eq 0) { $chk.Add('- 无。') } else { foreach ($w in ($script:warnings | Select-Object -Unique -First 40)) { $chk.Add('- ' + $w) } }
Write-Section '09-collector-selfcheck.md' $chk

Write-Host ''
Write-Host ('[ev] 完成。输出目录: ' + $evDir)
Write-Host ('[ev] 识别技术栈: ' + (($hitStacks | Select-Object -First 12) -join ', '))
Write-Host ('[ev] 架构形态: ' + (($arch) -join ' / '))
Write-Host ('[ev] 目标作者: ' + $Author)
