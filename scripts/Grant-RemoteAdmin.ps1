<#
.SYNOPSIS
  给模拟器里的客户端授予远程管理（RA）权限，使游戏内 控制台 里以 / 开头的 RA 命令生效。

.DESCRIPTION
  只修改测试服务器 .runtime\server-<端口>\AppData\config\<端口>\config_remoteadmin.txt 的 Members 列表。
  不指定 -UserId 时，从当前服务器日志里读取已连接客户端的设备 ID（形如 device_xxxx@device）。
  每个 AVD 的设备 ID 不同，第二个模拟器需要单独授权。修改后重启服务器才生效（加 -Restart 自动重启；
  客户端会自动重新连接）。

.PARAMETER Port     测试服务器端口，默认取配置 Port。
.PARAMETER UserId   要授权的 ID（device_xxxx@device）。可给多个。
.PARAMETER Group    权限组，默认 owner（最高权限）。
.PARAMETER Restart  修改后自动重启测试服务器。
#>
[CmdletBinding()]
param(
    [int]$Port,
    [string[]]$UserId,
    [string]$Group = 'owner',
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Port) { $Port = [int](Get-KitConfig).Port }

$serverDir = Get-ServerDir $Port
$file = Join-Path $serverDir "AppData\config\$Port\config_remoteadmin.txt"
if (-not (Test-Path -LiteralPath $file)) { Fail "找不到 $file。" "先启动一次端口 $Port 的测试服务器（start-all.cmd）。" }

if (-not $UserId) {
    $state = Get-RunningServer $Port
    if (-not $state) { Fail '没有指定 -UserId，且服务器没有在运行，无法从日志读取客户端 ID。' '先运行 start-all.cmd 让客户端连上服务器，再运行本脚本。' }
    $fs = [IO.File]::Open($state.LogPath, 'Open', 'Read', 'ReadWrite')
    try { $text = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Dispose() }
    $UserId = @([regex]::Matches($text, '(device_[0-9a-f]+@device)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($UserId.Count -eq 0) { Fail '服务器日志里还没有客户端的设备 ID。' '先让客户端连上服务器（start-all.cmd），再运行本脚本。' }
}

$utf8 = New-Object Text.UTF8Encoding($false)
$lines = New-Object 'Collections.Generic.List[string]'
$lines.AddRange([string[]][IO.File]::ReadAllLines($file, $utf8))
$idx = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^Members:') { $idx = $i; break } }
if ($idx -lt 0) { Fail "$file 里没有 Members: 行。" '检查该文件是否完整；删除它后重启服务器会重新生成。' }
if ($lines[$idx] -match '^Members:\s*\[\s*\]\s*$') { $lines[$idx] = 'Members:' }

$added = @()
foreach ($id in $UserId) {
    if ($id -notmatch '^\S+@\S+$') { Fail "ID 格式不对：$id" '格式为 device_xxxx@device。' }
    $exists = $false
    for ($j = $idx + 1; $j -lt $lines.Count -and $lines[$j] -match '^\s+-\s'; $j++) {
        if ($lines[$j] -match "^\s+-\s+$([regex]::Escape($id))\s*:") { $exists = $true }
    }
    if ($exists) { Write-Host "已有权限：$id"; continue }
    $lines.Insert($idx + 1, " - ${id}: $Group")
    $added += $id
}
if ($added.Count -gt 0) {
    Write-Utf8NoBom $file $lines.ToArray()
    foreach ($id in $added) { Write-Ok "已授予 $Group 权限：$id" }
}

if ($Restart) {
    if (Get-RunningServer $Port) {
        & (Join-Path $PSScriptRoot 'Stop-TestServer.ps1') -Port $Port
        & (Join-Path $PSScriptRoot 'Start-TestServer.ps1') -Port $Port
        Write-Note '客户端会自动重新连接；若没有，运行菜单里的“重新连接客户端”。'
    }
} elseif ($added.Count -gt 0) {
    Write-Note '重启测试服务器后生效（客户端会自动重新连接）。'
}
Write-Host '之后在游戏内点 控制台，输入以 / 开头的 RA 命令，例如 /forceclass 2 Scp173。'
