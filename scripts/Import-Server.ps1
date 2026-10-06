<#
.SYNOPSIS
  把 Carl Mod 服务端 ZIP 解压到 .runtime\server-original（原始服务端，只读使用）。

.DESCRIPTION
  ZIP 默认取 inputs 文件夹里唯一的 *.zip（或配置里的 ServerZip）。ZIP 本身不会被修改。
  如果配置了 ServerFolder（已解压好的服务端文件夹），则不需要 ZIP，本脚本只检查该文件夹。
  测试服务器（.runtime\server-<端口>）都从原始服务端复制，原始服务端从不运行、不修改。

.PARAMETER Zip    服务端 ZIP 路径，默认见上。
.PARAMETER Force  删除已有的 .runtime\server-original 并重新解压（服务端更新后使用）。
#>
[CmdletBinding()]
param(
    [string]$Zip,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig

if ($cfg.ServerFolder -and -not $Zip) {
    $dir = Assert-PristineServer
    Write-Ok "使用配置的服务端文件夹：$dir（不需要解压）"
    return
}

$dest = Join-Path $script:Runtime 'server-original'
if ((Test-Path -LiteralPath (Join-Path $dest 'Carl Mod.exe')) -and -not $Force) {
    Write-Ok "服务端已导入：$dest（要重新导入请加 -Force）"
    return
}

if (-not $Zip) {
    $Zip = Find-ServerZip
    if (-not $Zip) { Fail '找不到服务端 ZIP。' '把 Carl Mod 服务端 ZIP 放进 inputs 文件夹，或在 testkit.config.psd1 里设置 ServerZip / ServerFolder。' }
}
if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { Fail "ZIP 不存在：$Zip" '检查路径。' }

$python = @(Get-PythonCommand)
if ($python.Count -eq 0) { Fail '找不到 Python 3.8 或更新版本（解压服务端需要它）。' '从 https://www.python.org 安装 Python 3（勾选 “Add python.exe to PATH”），重新打开窗口后再运行。' }

if (Test-Path -LiteralPath $dest) {
    Write-Step "删除旧的 $dest"
    Remove-Item -LiteralPath $dest -Recurse -Force
}
Write-Step "解压 $(Split-Path -Leaf $Zip) 到 $dest"
$exe = $python[0]
$pyArgs = @($python | Select-Object -Skip 1) + @((Join-Path $PSScriptRoot 'extract-server.py'), '--zip', $Zip, $dest)
& $exe @pyArgs
if ($LASTEXITCODE -ne 0) { Fail "解压失败（退出码 $LASTEXITCODE）。" '确认 ZIP 是完整的 Carl Mod 服务端压缩包，且磁盘空间足够（约 1 GB）。' }
if (-not (Test-Path -LiteralPath (Join-Path $dest 'Carl Mod.exe'))) { Fail '解压后没有找到 Carl Mod.exe。' '确认 ZIP 是 Carl Mod 的 Windows 服务端。' }
Write-Ok "服务端已导入：$dest"

$old = @(Get-ChildItem -LiteralPath $script:Runtime -Directory -Filter 'server-*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^server-\d+$' })
if ($old.Count -gt 0) {
    Write-Note "已有的测试服务器（$(($old | ForEach-Object Name) -join '、')）仍是旧版本。要使用新版本，先停止服务器再删除这些文件夹，下次启动时会重新复制（其中的配置和插件也会一并删除）。"
}
