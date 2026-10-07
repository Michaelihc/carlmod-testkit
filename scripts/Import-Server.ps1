<#
.SYNOPSIS
  把 Carl Mod 服务端 ZIP 解压到 .runtime\server-original-<版本>（原始服务端，只读使用）。

.DESCRIPTION
  默认导入 inputs 文件夹里的每个 *.zip（或配置里的 ServerZip，可以是一个或多个）。每个服务端版本解压到自己的
  文件夹，例如 .runtime\server-original-0.0.5。版本从 ZIP 里的 Assembly-CSharp.dll 读取（GameCore.Version）；
  带死斗模块的 0.0.4 记为 0.0.4-dm。已导入的版本会跳过。ZIP 本身不会被修改；mono.msi 和 *.bak 备份文件不解压。
  配置了 ServerFolder（已解压好的服务端文件夹）时，它也是一个可用的服务端，不需要解压。
  测试服务器（.runtime\server-<端口>-<版本>）从原始服务端复制，原始服务端从不运行、不修改。
  有多个版本时，用配置 ServerVersion 或各脚本的 -ServerVersion 参数选择使用哪一个（见 README）。

.PARAMETER Zip    只导入这一个服务端 ZIP。
.PARAMETER Force  删除已导入的同版本原始服务端并重新解压（同一版本的服务端 ZIP 更新后使用）。
#>
[CmdletBinding()]
param(
    [string]$Zip,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig

function Show-Servers {
    $all = @(Get-PristineServers)
    if ($all.Count -eq 0) { return }
    Write-Host '可用的服务端：'
    foreach ($s in $all) { Write-Host "  $($s.Label)：$($s.Dir)" }
    try {
        $sel = Select-PristineServer
        Write-Host "测试服务器使用：$($sel.Label)$(if ($all.Count -gt 1 -and -not $cfg.ServerVersion) { '（与客户端 APK 版本相同）' })"
    } catch { Write-Note $_.Exception.Message }
}

if ($Zip) {
    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { Fail "ZIP 不存在：$Zip" '检查路径。' }
    $zips = @((Resolve-Path -LiteralPath $Zip).ProviderPath)
} else {
    $zips = @(Find-ServerZips)
}

if ($zips.Count -eq 0) {
    if (@(Get-PristineServers).Count -gt 0) {
        if ($cfg.ServerFolder) { Write-Ok "使用配置的服务端文件夹：$([IO.Path]::GetFullPath($cfg.ServerFolder))（不需要解压）" }
        Show-Servers
        return
    }
    if ($cfg.ServerFolder) { $null = Select-PristineServer }
    Fail '找不到服务端 ZIP。' '把 Carl Mod 服务端 ZIP 放进 inputs 文件夹，或在 testkit.config.psd1 里设置 ServerZip / ServerFolder。'
}

# 先读出每个 ZIP 的版本（不解压）。
$plan = @(foreach ($z in $zips) {
    $build = Get-ZipServerBuild $z
    if (-not $build) { Fail "$(Split-Path -Leaf $z) 里没有 Carl Mod.exe，不是 Carl Mod 的 Windows 服务端。" '把它移出 inputs 文件夹（或改正 ServerZip）。' }
    if (-not $build.Version) { Write-Note "读不到 $(Split-Path -Leaf $z) 的游戏版本，按“未知版本”导入。" }
    [pscustomobject]@{ Zip = $z; Build = $build }
})
$dup = @($plan | Group-Object { $_.Build.Key } | Where-Object Count -gt 1 | Select-Object -First 1)
if ($dup.Count -gt 0) {
    Fail "有多个 $($dup[0].Group[0].Build.Label) 版本的服务端 ZIP：$(($dup[0].Group | ForEach-Object { Split-Path -Leaf $_.Zip }) -join '、')" '每个版本只保留一个，或用 -Zip 指定要导入的文件。'
}

$python = $null
$tmp = Join-Path $script:Runtime 'import-tmp'
foreach ($p in $plan) {
    $label = $p.Build.Label
    $dest = Join-Path $script:Runtime "server-original-$($p.Build.Key)"
    if ((Test-Path -LiteralPath (Join-Path $dest 'Carl Mod.exe')) -and -not $Force) {
        Write-Ok "服务端 $label 已导入：$dest（要重新导入请加 -Force）"
        continue
    }
    if (-not $python) {
        $python = @(Get-PythonCommand)
        if ($python.Count -eq 0) { Fail '找不到 Python 3.8 或更新版本（解压服务端需要它）。' '从 https://www.python.org 安装 Python 3（勾选 “Add python.exe to PATH”），重新打开窗口后再运行。' }
    }
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    Write-Step "解压 $(Split-Path -Leaf $p.Zip)（服务端 $label）到 $dest"
    $pyArgs = @($python | Select-Object -Skip 1) + @((Join-Path $PSScriptRoot 'extract-server.py'), '--zip', $p.Zip, $tmp)
    & $python[0] @pyArgs
    if ($LASTEXITCODE -ne 0) { Fail "解压失败（退出码 $LASTEXITCODE）。" '确认 ZIP 是完整的 Carl Mod 服务端压缩包，且磁盘空间足够（约 1 GB）。' }
    if (-not (Test-Path -LiteralPath (Join-Path $tmp 'Carl Mod.exe'))) { Fail '解压后没有找到 Carl Mod.exe。' '确认 ZIP 是 Carl Mod 的 Windows 服务端。' }
    if (Test-Path -LiteralPath $dest) {
        Write-Step "删除旧的 $dest"
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $tmp -Destination $dest
    Write-Ok "服务端 $label 已导入：$dest"

    $old = @(Get-ChildItem -LiteralPath $script:Runtime -Directory -Filter "server-*-$($p.Build.Key)" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^server-\d+-$([regex]::Escape($p.Build.Key))$" })
    if ($old.Count -gt 0) {
        Write-Note "已有的 $label 测试服务器（$(($old | ForEach-Object Name) -join '、')）仍是重新导入前的文件。要使用新文件，先停止服务器再删除这些文件夹，下次启动时会重新复制（其中的配置和插件也会一并删除）。"
    }
}

$legacy = @(Get-ChildItem -LiteralPath $script:Runtime -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^server-\d+$' })
if ($legacy.Count -gt 0) {
    Write-Note "测试服务器现在按版本分开存放（.runtime\server-<端口>-<版本>）。旧的 $(($legacy | ForEach-Object Name) -join '、') 不再使用，确认其中没有要保留的配置后可以删除。"
}
Show-Servers
