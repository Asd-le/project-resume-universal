# Git 证据采集（独立可测版本）——用数组承接命令输出，避免内联子表达式/管道解析问题
# 用法：. .\collect-git-evidence.ps1 -ProjectRoot <path> -Author "a,b" [-Branch ref] [-Since yyyy-MM-dd] -OutFile <md>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$Author,
    [string]$Branch,
    [string]$Since,
    [string]$OutFile
)

$ErrorActionPreference = 'Continue'

function Invoke-Git {
    param([string[]]$GitArgs)
    $out = @()
    try {
        $out = @(& git -C $script:Root @GitArgs 2>$null)
    } catch { Write-Debug ("git 失败: " + $_.Exception.Message); return @() }
    return ,$out
}
function First-Line {
    param($Values)
    $arr = @($Values)
    if ($arr.Count -gt 0 -and $arr[0] -ne $null) { return [string]$arr[0] }
    return ''
}
function GitFileList {
    param([string[]]$GitArgs)
    $raw = Invoke-Git $GitArgs
    $res = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($raw)) { if ($line -and ([string]$line).Trim() -ne '') { $res.Add([string]$line) } }
    return $res
}

$script:Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$ref = 'HEAD'
if ($Branch -and $Branch.Trim() -ne '') { $ref = $Branch }

$L = New-Object System.Collections.Generic.List[string]
function W { param([string]$s) $L.Add($s) }

W '# 7 · Git 证据与分支新鲜度'
W ''
$hasGit = Test-Path -LiteralPath (Join-Path $script:Root '.git')
W ('- 项目根: ' + $script:Root)
W ('- 分析引用: ' + $ref)
W ('- 是否 Git 仓库: ' + $hasGit)
W ''
if (-not $hasGit) {
    W '- 非 Git 仓库，本章节结束（归属分析留空，改由用户确认职责）。'
} else {
    # ---- 工作区状态与新鲜度 ----
    $curBranch = First-Line (Invoke-Git @('rev-parse','--abbrev-ref','HEAD'))
    $curHead   = First-Line (Invoke-Git @('log','-1','--format=%h|%ad|%s','--date=short'))
    W '## 工作区状态'
    W ''
    W ('- 当前分支: ' + $curBranch)
    W ('- 当前 HEAD: ' + $curHead)
    $status = GitFileList @('status','--short')
    W ('- 未提交/未跟踪条目: ' + $status.Count)
    foreach ($s in ($status | Select-Object -First 20)) { W ('    - ' + $s) }
    W ''
    W '## 最新远端分支（判断是否在分析过期快照）'
    W ''
    $refsRaw = GitFileList @('for-each-ref','--sort=-committerdate','refs/remotes','--format=%(committerdate:short)|%(refname:short)|%(authorname)|%(subject)')
    if ($refsRaw.Count -eq 0) { W '- ⚠️ 无远端引用（可能未 fetch，或本地仓库）' }
    foreach ($r in ($refsRaw | Select-Object -First 12)) { W ('- ' + $r) }
    W ''
    if ($refsRaw.Count -gt 0) {
        $parts = ([string]$refsRaw[0]) -split '\|'
        if ($parts.Count -ge 2) {
            $newest = $parts[1]
            $behind = First-Line (Invoke-Git @('rev-list','--count',("HEAD.." + $newest)))
            if ($behind -match '^\d+$') {
                W ('- 工作区落后最新远端分支 ' + $newest + ' : **' + $behind + '** 个提交')
                if ([int]$behind -gt 0) {
                    W '- ⚠️ **工作区可能是过期快照**：规模/技术栈/贡献都可能失真，请用 -Branch 分析最新分支后再出结论。'
                }
            }
        }
    }
    W ''
    # ---- 总量与时间跨度 ----
    W '## 提交总量与时间跨度'
    W ''
    W ('- 提交总数: ' + (First-Line (Invoke-Git @('rev-list','--count',$ref))))
    W ('- 首个提交: ' + (First-Line (Invoke-Git @('log','--reverse','--format=%h|%ad|%an|%s','--date=short',$ref))))
    W ('- 最新提交: ' + (First-Line (Invoke-Git @('log','-1','--format=%h|%ad|%an|%s','--date=short',$ref))))
    W ''
    # ---- 作者聚合 ----
    W '## 全部作者与提交量（按邮箱聚合，便于发现同名多署名）'
    W ''
    W '| author | email | commits |'
    W '|---|---|---|'
    $authorLines = GitFileList @('log',$ref,'--format=%an|%ae')
    $authorGroups = @($authorLines | Group-Object | Sort-Object Count -Descending)
    foreach ($g in $authorGroups) {
        $p = ([string]$g.Name) -split '\|'
        $mail = ''
        if ($p.Count -gt 1) { $mail = $p[1] }
        W ('| ' + $p[0] + ' | ' + $mail + ' | ' + $g.Count + ' |')
    }
    W ''
    W '### 同邮箱多署名（必须合并统计）'
    W ''
    $mailGroups = @($authorLines | ForEach-Object {
            $p = ([string]$_) -split '\|'
            if ($p.Count -gt 1) { [pscustomobject]@{ mail = $p[1]; name = $p[0] } }
        } | Group-Object mail)
    $found = $false
    foreach ($mg in $mailGroups) {
        $uniqNames = @($mg.Group | Select-Object -ExpandProperty name -Unique)
        if ($uniqNames.Count -gt 1) {
            $found = $true
            W ('- **' + $mg.Name + '** → ' + ($uniqNames -join ' / ') + '（共 ' + $mg.Count + ' 次提交，必须合并）')
        }
    }
    if (-not $found) { W '- 未发现同邮箱多署名' }
    W ''
    # ---- 目标作者 ----
    $targetRaw = $Author
    if (-not $targetRaw -or $targetRaw.Trim() -eq '') {
        if ($authorGroups.Count -gt 0) {
            $targetRaw = (([string]$authorGroups[0].Name) -split '\|')[0]
            W ('- 未指定 -Author，自动选中提交量第一的作者: **' + $targetRaw + '**（需用户确认）')
        }
    }
    $authors = @($targetRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    W ('- 目标署名: ' + ($authors -join ', '))
    W ''
    foreach ($a in $authors) {
        $aArgs = @('--author=' + $a)
        if ($Since -and $Since.Trim() -ne '') { $aArgs += @('--since=' + $Since) }
        $logBase = @('log',$ref) + $aArgs
        $cnt = (GitFileList (@('log',$ref) + $aArgs + @('--oneline'))).Count
        W ('## 署名 ' + $a + ' : ' + $cnt + ' 次提交')
        W ''
        W ('- 首次: ' + (First-Line (Invoke-Git (@('log',$ref,'--reverse','--format=%h|%ad|%s','--date=short') + $aArgs))))
        W ('- 最近: ' + (First-Line (Invoke-Git (@('log',$ref,'-1','--format=%h|%ad|%s','--date=short') + $aArgs))))
        W '- 按年分布:'
        $years = GitFileList (@('log',$ref,'--format=%ad','--date=format:%Y') + $aArgs)
        foreach ($yg in @($years | Group-Object | Sort-Object Name)) { W ('    - ' + $yg.Name + ': ' + $yg.Count) }
        W ''
        # 改动量
        $numstat = GitFileList (@('log',$ref,'--numstat','--format=','--no-merges') + $aArgs)
        $adds = 0; $dels = 0
        $touched = New-Object System.Collections.Generic.HashSet[string]
        foreach ($nl in $numstat) {
            $p = ([string]$nl) -split "`t"
            if ($p.Count -lt 3) { continue }
            if ($p[0] -match '^\d+$') { $adds += [int]$p[0] }
            if ($p[1] -match '^\d+$') { $dels += [int]$p[1] }
            if ($p[2]) { [void]$touched.Add($p[2]) }
        }
        W ('- 新增行: ' + $adds + ' / 删除行: ' + $dels + ' / 触达文件（去重）: ' + $touched.Count)
        W ''
        W '### 该署名高频文件 Top 40（= 长期维护区域）'
        W ''
        $filesAll = GitFileList (@('log',$ref,'--name-only','--format=','--no-merges') + $aArgs)
        foreach ($fg in @($filesAll | Group-Object | Sort-Object Count -Descending | Select-Object -First 40)) {
            W ('- ' + $fg.Count + '  ' + $fg.Name)
        }
        W ''
        W '### 该署名新增文件 Top 40（= 从 0 到 1 的证据）'
        W ''
        $added = GitFileList (@('log',$ref,'--diff-filter=A','--name-only','--format=','--no-merges') + $aArgs)
        foreach ($x in @($added | Sort-Object -Unique | Select-Object -First 40)) { W ('- ' + $x) }
        W ''
        W '### 该署名删除/重命名文件（重构信号）'
        W ''
        $deleted = GitFileList (@('log',$ref,'--diff-filter=DR','--name-only','--format=','--no-merges') + $aArgs)
        W ('- 合计（去重）: ' + (@($deleted | Sort-Object -Unique)).Count)
        foreach ($x in @($deleted | Sort-Object -Unique | Select-Object -First 30)) { W ('    - ' + $x) }
        W ''
        W '### 该署名提交类型统计'
        W ''
        $subjects = GitFileList (@('log',$ref,'--format=%s') + $aArgs)
        $types = [ordered]@{
            '修复/问题' = '(?i)(fix|bug|hotfix|修复|问题|异常|报错|回滚|回退|紧急|线上|崩|卡|超时|挂了)'
            '性能/优化' = '(?i)(optimi|perf|性能|优化|慢|索引|index|缓存|cache|提速)'
            '新增功能'  = '(?i)(feat|feature|add|新增|支持|增加|实现)'
            '重构/调整' = '(?i)(refactor|重构|调整|迁移|改造|下沉|瘦身|抽离|清理)'
            '测试'      = '(?i)(test|测试|单测|用例)'
            '文档'      = '(?i)(doc|文档|readme|注释)'
            '依赖/构建' = '(?i)(deps|dependency|依赖|升级|bump|build|构建)'
            '部署/环境' = '(?i)(deploy|jenkins|nginx|发布|部署|环境|k8s|docker|ci)'
            'AI/大模型' = '(?i)(\bai\b|大模型|llm|rag|agent|prompt|embedding|百炼|智能)'
            '合并'      = '(?i)(merge)'
        }
        foreach ($t in $types.GetEnumerator()) {
            $c2 = 0
            foreach ($s in $subjects) { if (([string]$s) -match $t.Value) { $c2++ } }
            W ('- ' + $t.Key + ': ' + $c2)
        }
        W ''
        W '### 该署名提交主题抽样（最近 80 条）'
        W ''
        W '```'
        foreach ($s in @((GitFileList (@('log',$ref,'--format=%h|%ad|%s','--date=short') + $aArgs)) | Select-Object -First 80)) { W ([string]$s) }
        W '```'
        W ''
    }
    # ---- 事故线索与分支（全作者） ----
    W '## 线上问题/事故线索提交（含关键词，任意作者）'
    W ''
    $incident = GitFileList @('log',$ref,'--format=%h|%ad|%an|%s','--date=short')
    $pat = '(?i)(回滚|回退|崩|卡死|超时|积压|丢失|重复|资损|事故|紧急|线上|OOM|死锁|慢查询|越权|挂了|重启|泄漏|内存|降级|熔断|限流)'
    $n = 0
    foreach ($s in $incident) {
        if (([string]$s) -match $pat) { W ('- ' + $s); $n++; if ($n -ge 100) { break } }
    }
    W ''
    W '## 分支清单（feature/hotfix 名常直接暴露需求与线上问题）'
    W ''
    $branches = GitFileList @('branch','-a')
    foreach ($b in @($branches | Select-Object -First 80)) { W ('- ' + $b) }
    W ''
    W '## 最近提交（50 条，任意作者）'
    W ''
    W '```'
    foreach ($s in @((GitFileList @('log',$ref,'--format=%h|%ad|%an|%s','--date=short')) | Select-Object -First 50)) { W ([string]$s) }
    W '```'
}

if ($OutFile) {
    $L | Out-File -LiteralPath $OutFile -Encoding UTF8
    Write-Host ('[git] 写出 ' + $OutFile + ' (' + $L.Count + ' 行)')
} else {
    $L | ForEach-Object { Write-Output $_ }
}
