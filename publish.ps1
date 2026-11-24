<#
    一键发布脚本  ——  publish.ps1

    用法：
        双击同目录下的 publish.cmd（推荐）
        或在 PowerShell 里：  powershell -ExecutionPolicy Bypass -File .\publish.ps1

    它会依次做这些事：
        1. 检查当前是不是 main 分支、有没有改动
        2. 本地用 hugo 先构建一遍（构建不过就不推送，线上不受影响）
        3. git add -A 并自动写一条提交说明
        4. git commit + git push 到 GitHub
        5. 等 GitHub Actions 跑完，告诉你「已上线 / 构建失败」

    可选参数：
        -Message "提交说明"     自己指定提交说明
        -DryRun                 只检查不推送（看看会提交什么）
        -NoBuild                跳过本地构建检查
        -NoWait                 不等待 Actions 结果，推送完就结束
        -RepoPath <路径>        指定仓库目录（默认脚本所在目录）
#>

[CmdletBinding()]
param(
    [string]$Message = '',
    [string]$RepoPath = '',
    [switch]$DryRun,
    [switch]$NoBuild,
    [switch]$NoWait
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$MainBranch = 'main'

# 参数默认值里拿不到 $PSScriptRoot（PowerShell 的已知行为），在这里补上
if (-not $RepoPath) {
    if ($PSScriptRoot) { $RepoPath = $PSScriptRoot }
    elseif ($MyInvocation.MyCommand.Path) { $RepoPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
    else { $RepoPath = (Get-Location).Path }
}
if (Test-Path -LiteralPath $RepoPath) {
    $RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
} else {
    Write-Host "找不到目录：$RepoPath" -ForegroundColor Red
    exit 1
}

function Write-Head([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Write-Ok([string]$text) { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Tip([string]$text) { Write-Host "  [..] $text" -ForegroundColor Gray }
function Write-Warn2([string]$text) { Write-Host "  [!!] $text" -ForegroundColor Yellow }
function Write-Fail([string]$text) { Write-Host "  [XX] $text" -ForegroundColor Red }

function Stop-WithError([string]$text) {
    Write-Fail $text
    Write-Host ''
    Write-Host '发布已中止。改动仍然留在工作区里，没有丢。' -ForegroundColor Yellow
    exit 1
}

function Invoke-Git {
    param([string[]]$GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @GitArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $text = ($output | Out-String)
    } catch {
        $code = 127
        $text = $_.Exception.Message
    } finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{ Code = $code; Text = $text.Trim() }
}

function Find-Hugo {
    $candidates = @()
    $candidates += (Join-Path $RepoPath 'hugo.exe')
    $parent = Split-Path -Path $RepoPath -Parent
    if ($parent) { $candidates += (Join-Path $parent 'hugo.exe') }
    $onPath = Get-Command hugo -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    }
    return $null
}

function Get-SiteUrl {
    $toml = Join-Path $RepoPath 'hugo.toml'
    if (Test-Path -LiteralPath $toml) {
        $raw = Get-Content -LiteralPath $toml -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            $m = [regex]::Match($raw, "(?m)^\s*baseURL\s*=\s*['`"]([^'`"]+)['`"]")
            if ($m.Success) { return $m.Groups[1].Value }
        }
    }
    return ''
}

function Get-PostTitle([string]$relativePath) {
    $full = Join-Path $RepoPath ($relativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full)) { return '' }
    $lines = Get-Content -LiteralPath $full -TotalCount 25 -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^\s*title\s*[:=]\s*(.+?)\s*$')
        if ($m.Success) {
            $v = $m.Groups[1].Value.Trim().Trim([char]34, [char]39)
            if ($v) { return $v }
        }
    }
    return ''
}

function Format-Bucket([string]$label, [int]$count) {
    if ($count -le 0) { return '' }
    if ($count -eq 1) { return $label }
    return "$label×$count"
}

function New-CommitMessage($Entries) {
    $posts = @($Entries | Where-Object { $_.Path -like 'content/posts/*' })
    $pages = @($Entries | Where-Object { $_.Path -like 'content/*' -and $_.Path -notlike 'content/posts/*' })
    $config = @($Entries | Where-Object { $_.Path -eq 'hugo.toml' -or $_.Path -like 'config/*' -or $_.Path -like 'i18n/*' -or $_.Path -like 'data/*' })
    $look = @($Entries | Where-Object { $_.Path -like 'layouts/*' -or $_.Path -like 'assets/*' -or $_.Path -like 'themes/*' -or $_.Path -like 'static/*' })
    $scripts = @($Entries | Where-Object { $_.Path -like 'scripts/*' -or $_.Path -eq 'publish.ps1' -or $_.Path -eq 'publish.cmd' -or $_.Path -like '*.ps1' -or $_.Path -like '*.cmd' })
    $bucketCount = $posts.Count + $pages.Count + $config.Count + $look.Count + $scripts.Count
    $other = $Entries.Count - $bucketCount

    $newPosts = @($posts | Where-Object { $_.Status -eq 'A' -and $_.Path -like '*.md' })
    if ($newPosts.Count -eq 1 -and $Entries.Count -eq 1) {
        $title = Get-PostTitle $newPosts[0].Path
        if ($title) { return "post: $title" }
        return 'post: 新增一篇文章'
    }

    $parts = @()
    $parts += Format-Bucket '文章' $posts.Count
    $parts += Format-Bucket '页面' $pages.Count
    $parts += Format-Bucket '配置' $config.Count
    $parts += Format-Bucket '外观' $look.Count
    $parts += Format-Bucket '脚本' $scripts.Count
    $parts += Format-Bucket '其他' $other
    $parts = @($parts | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return 'update: 日常更新' }
    return 'update: ' + ($parts -join '、')
}

function Get-RemoteInfo {
    $remote = Invoke-Git @('remote', 'get-url', 'origin')
    if ($remote.Code -ne 0) { return $null }
    $url = $remote.Text
    $m = [regex]::Match($url, 'github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ Owner = $m.Groups[1].Value; Repo = $m.Groups[2].Value; Url = $url }
}

function Wait-Deploy([string]$Sha, [string]$Owner, [string]$RepoName, [int]$TimeoutSeconds) {
    $headers = @{ 'User-Agent' = 'blog-publish-script'; 'Accept' = 'application/vnd.github+json' }
    $listUri = "https://api.github.com/repos/$Owner/$RepoName/actions/runs?head_sha=$Sha&per_page=5"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    $run = $null
    $notStarted = 0
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-RestMethod -Uri $listUri -Headers $headers -TimeoutSec 25
        } catch {
            return [pscustomobject]@{ State = 'api-error'; Detail = $_.Exception.Message; Url = '' }
        }
        $found = @($resp.workflow_runs) | Where-Object { $_.head_sha -eq $Sha } | Select-Object -First 1
        if ($found) { $run = $found; break }
        $notStarted++
        if ($notStarted -ge 4) {
            return [pscustomobject]@{ State = 'not-started'; Detail = ''; Url = "https://github.com/$Owner/$RepoName/actions" }
        }
        Start-Sleep -Seconds 10
    }
    if (-not $run) {
        return [pscustomobject]@{ State = 'timeout'; Detail = ''; Url = "https://github.com/$Owner/$RepoName/actions" }
    }

    $lastStatus = ''
    while ((Get-Date) -lt $deadline) {
        if ($run.status -eq 'completed') { break }
        if ($run.status -ne $lastStatus) {
            Write-Tip "部署进行中（$($run.status)）：$($run.name)"
            $lastStatus = $run.status
        }
        Start-Sleep -Seconds 10
        try {
            $run = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$RepoName/actions/runs/$($run.id)" -Headers $headers -TimeoutSec 25
        } catch {
            return [pscustomobject]@{ State = 'api-error'; Detail = $_.Exception.Message; Url = $run.html_url }
        }
    }
    if ($run.status -ne 'completed') {
        return [pscustomobject]@{ State = 'timeout'; Detail = ''; Url = $run.html_url }
    }
    return [pscustomobject]@{ State = $run.conclusion; Detail = ''; Url = $run.html_url }
}

# ============================================================================
#  开始
# ============================================================================

Write-Head '博客一键发布'
Write-Tip "仓库目录：$RepoPath"

if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
    Stop-WithError "这里不是 git 仓库：$RepoPath"
}

Push-Location -LiteralPath $RepoPath
try {
    $inside = Invoke-Git @('rev-parse', '--is-inside-work-tree')
    if ($inside.Code -ne 0) { Stop-WithError 'git 无法识别这个目录，请检查 .git 是否完整' }

    $branch = (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')).Text
    if ($branch -ne $MainBranch) {
        Stop-WithError "当前分支是 '$branch'，不是 '$MainBranch'。先执行：git checkout $MainBranch"
    }
    Write-Ok "当前分支：$branch"

    # ---- 1. 收集改动 ----
    $addResult = Invoke-Git @('add', '-A')
    if ($addResult.Code -ne 0) { Stop-WithError "git add 失败：$($addResult.Text)" }

    $statusText = (Invoke-Git @('diff', '--cached', '--name-status')).Text
    $entries = @()
    foreach ($line in ($statusText -split "`r?`n")) {
        if ($line.Trim() -eq '') { continue }
        $cols = $line -split "`t"
        if ($cols.Count -ge 2) {
            $entries += [pscustomobject]@{ Status = $cols[0]; Path = ($cols[1] -replace '\\', '/') }
        }
    }

    if ($entries.Count -eq 0) {
        Write-Ok '没有需要发布的改动，工作区是干净的。'
        Write-Tip "线上版本：$(Get-SiteUrl)"
        Write-Host ''
        exit 0
    }

    Write-Ok "检测到 $($entries.Count) 个文件改动"
    $statText = (Invoke-Git @('diff', '--cached', '--stat')).Text
    foreach ($line in ($statText -split "`r?`n")) {
        if ($line.Trim() -ne '') { Write-Tip $line }
    }

    # ---- 2. 本地构建检查 ----
    if ($NoBuild) {
        Write-Warn2 '已跳过本地构建检查（-NoBuild）'
    } else {
        $hugo = Find-Hugo
        if (-not $hugo) {
            Write-Warn2 '没找到 hugo.exe，跳过本地构建检查（CI 上仍会构建）'
        } else {
            Write-Tip "本地构建检查中：$hugo"
            $tmpDir = Join-Path $env:TEMP ('blog-build-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $prev = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $buildOut = & $hugo --gc --minify -d $tmpDir 2>&1 | ForEach-Object { "$_" }
                $buildCode = $LASTEXITCODE
            } catch {
                $buildOut = @($_.Exception.Message)
                $buildCode = 1
            } finally {
                $ErrorActionPreference = $prev
            }
            if (Test-Path -LiteralPath $tmpDir) {
                Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($buildCode -ne 0) {
                Write-Fail '构建失败，已中止发布 —— 线上内容保持不变'
                foreach ($line in @(($buildOut | Out-String) -split "`r?`n" | Select-Object -Last 25)) {
                    if ($line.Trim() -ne '') { Write-Host "      $line" -ForegroundColor DarkGray }
                }
                Write-Host ''
                Write-Host '把上面报错的行数对一下，修好再点一次即可。' -ForegroundColor Yellow
                exit 1
            }
            Write-Ok '本地构建通过'
        }
    }

    # ---- 3. 提交 ----
    if ($Message) { $commitMessage = $Message } else { $commitMessage = New-CommitMessage $entries }
    Write-Head '提交'
    Write-Tip "提交说明：$commitMessage"

    if ($DryRun) {
        Write-Ok 'DryRun 模式：只检查，不提交、不推送'
        Write-Host ''
        exit 0
    }

    $commitResult = Invoke-Git @('commit', '-m', $commitMessage)
    if ($commitResult.Code -ne 0) { Stop-WithError "提交失败：$($commitResult.Text)" }
    $shortSha = (Invoke-Git @('rev-parse', '--short', 'HEAD')).Text
    Write-Ok "已提交 $shortSha"

    # ---- 4. 推送 ----
    Write-Head '推送到 GitHub'
    $pushResult = Invoke-Git @('push', 'origin', $MainBranch)
    if ($pushResult.Code -ne 0 -and $pushResult.Text -match 'non-fast-forward|fetch first|rejected') {
        Write-Warn2 '远端有新提交（比如在网页上改过），先同步再重试'
        $pullResult = Invoke-Git @('pull', '--rebase', '--autostash', 'origin', $MainBranch)
        if ($pullResult.Code -ne 0) {
            Stop-WithError "同步失败，可能有冲突，需要手动处理：`n$($pullResult.Text)"
        }
        $pushResult = Invoke-Git @('push', 'origin', $MainBranch)
    }
    if ($pushResult.Code -ne 0) {
        Stop-WithError "推送失败：`n$($pushResult.Text)`n检查网络，或在终端执行 git push 看是不是需要登录 GitHub"
    }
    Write-Ok '已推送，GitHub Actions 会自动构建并上线'

    # ---- 5. 等部署结果 ----
    $siteUrl = Get-SiteUrl
    $remote = Get-RemoteInfo
    $runUrl = ''

    Write-Head '等待部署'
    if ($NoWait) {
        Write-Tip '已跳过等待（-NoWait）'
    } elseif (-not $remote) {
        Write-Tip '远端不是 github.com 仓库，跳过状态查询'
    } else {
        $sha = (Invoke-Git @('rev-parse', 'HEAD')).Text
        $result = Wait-Deploy -Sha $sha -Owner $remote.Owner -RepoName $remote.Repo -TimeoutSeconds 420
        $runUrl = $result.Url
        switch ($result.State) {
            'success' { Write-Ok '部署成功，已经上线' }
            'not-started' { Write-Warn2 '暂时没查到这次的工作流（有时要等几十秒才开始），去 Actions 页面确认一下' }
            'timeout' { Write-Warn2 '等待超时，去 Actions 页面看进度' }
            'api-error' {
                Write-Warn2 "查不到状态：$($result.Detail)"
                Write-Tip '不影响发布，GitHub 侧仍会继续部署'
            }
            default { Write-Fail "部署失败（$($result.State)），去 Actions 页面看日志" }
        }
    }

    # ---- 6. 收尾 ----
    Write-Head '完成'
    Write-Ok "提交 $shortSha 已推送"
    if ($siteUrl) { Write-Tip "站点：$siteUrl" }
    if ($runUrl) { Write-Tip "运行记录：$runUrl" }
    Write-Host ''

    $failed = ($runUrl -ne '') -and ($result -and $result.State -ne 'success' -and $result.State -notin @('not-started', 'timeout', 'api-error'))
    if ($failed) { exit 1 }
    exit 0
} finally {
    Pop-Location
}
