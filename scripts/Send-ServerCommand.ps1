<#
.SYNOPSIS
  向测试服务器发送控制台命令（文件控制台）。

.DESCRIPTION
  服务端的文件控制台监视 <服务器>\Carl Mod_Data\Dedicated\<会话名>\ 文件夹，读取新出现的 cs*.mapi 文件
  （内容就是一行命令），并为每条输出写一个 sl*.mapi 文件。本脚本把命令文件原子地移进去，等待片刻，
  再清理处理过的命令文件和输出文件。

  限制：文件控制台只写出输出条目的类型名（“ServerOutput.TextOutputEntry”），不写文字，所以命令的
  回显无法从这里读到。脚本会把发送命令后服务器日志里新增的行打印出来；安装辅助插件 TestKitHelper
  （见 README）后，控制台输出会以 “[console]” 开头写进日志，这里就能看到命令结果。
  每条命令服务端还会记一条无害的 “Error while sending message”，命令照样执行。

  控制台命令不加前缀（forcestart、roundrestart），远程管理（RA）命令加 “/”（/roundlock enable）。

.PARAMETER Command      要发送的命令。不给且不加 -Interactive 时只清理残留的输出文件。
.PARAMETER Interactive  进入交互模式：逐条输入命令，空行退出。
.PARAMETER Port         端口，默认取配置 Port。
.PARAMETER WaitSec      发送后等待的秒数（默认 1.5）。

.EXAMPLE
  .\scripts\Send-ServerCommand.ps1 forcestart
  .\scripts\Send-ServerCommand.ps1 -Command roundrestart -Port 7778
  .\scripts\Send-ServerCommand.ps1 -Interactive
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,
    [switch]$Interactive,
    [int]$Port,
    [double]$WaitSec = 1.5
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Port) { $Port = [int](Get-KitConfig).Port }

$state = Get-RunningServer $Port
if (-not $state) {
    Fail "端口 $Port 没有正在运行的测试服务器。" '先启动服务器：start-all.cmd，或 scripts\Start-TestServer.ps1。'
}
if (-not $state.Session) {
    Fail "端口 $Port 的服务器是用 -Stdout 启动的，不能接收命令。" '停止后不加 -Stdout 重新启动：scripts\Stop-TestServer.ps1，再 scripts\Start-TestServer.ps1。'
}
$serverDir = $state.ServerDir
$dir = Join-Path $serverDir "Carl Mod_Data\Dedicated\$($state.Session)"
if (-not (Test-Path -LiteralPath $dir)) { Fail "找不到文件控制台文件夹：$dir" '重启测试服务器。' }

function Get-LogLength {
    if (-not (Test-Path -LiteralPath $state.LogPath)) { return 0 }
    return (Get-Item -LiteralPath $state.LogPath).Length
}

function Read-LogFrom([long]$Offset) {
    if (-not (Test-Path -LiteralPath $state.LogPath)) { return @() }
    $fs = [IO.File]::Open($state.LogPath, 'Open', 'Read', 'ReadWrite')
    try {
        if ($Offset -gt $fs.Length) { $Offset = 0 }
        $null = $fs.Seek($Offset, 'Begin')
        $text = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd()
    } finally { $fs.Dispose() }
    return ($text -split "`r?`n")
}

# 服务器日志里与命令无关的固定噪声。
$noise = @(
    '^\s*$', '^\(Filename: ', '^UnityEngine\.', '^\s+at ', '^Rethrow as ', '^0x[0-9a-fA-F]+ \(',
    'Error in server console: Error while sending message', '^ServerOutput\.'
)

function Remove-ConsoleFiles {
    Get-ChildItem -LiteralPath $dir -Filter 'sl*.mapi' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $dir -Filter 'cs*.mapi' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Send-One([string]$Line) {
    $before = Get-LogLength
    $name = 'cs{0}.mapi' -f [DateTime]::UtcNow.Ticks
    $staging = Join-Path $serverDir $name
    [IO.File]::WriteAllText($staging, $Line, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $staging -Destination (Join-Path $dir $name)
    Write-Host "已发送：$Line" -ForegroundColor Cyan
    Start-Sleep -Milliseconds ([int]($WaitSec * 1000))
    $entries = @(Get-ChildItem -LiteralPath $dir -Filter 'sl*.mapi' -ErrorAction SilentlyContinue).Count
    Remove-ConsoleFiles

    $new = @(Read-LogFrom $before | Where-Object { $l = $_; -not ($noise | Where-Object { $l -match $_ }) })
    if ($new.Count -gt 0) {
        Write-Host '--- 服务器日志新增内容 ---' -ForegroundColor DarkGray
        $new | ForEach-Object { Write-Host ($_ -replace '^\[console\] ', '') }
        Write-Host '--------------------------' -ForegroundColor DarkGray
    }
    if (-not ($new | Where-Object { $_ -like '[[]console[]]*' })) {
        Write-Host "服务器产生了 $entries 条输出（文件控制台不提供文字；安装辅助插件 TestKitHelper 后可在这里看到命令结果）。" -ForegroundColor DarkGray
    }
}

if ($Command) { Send-One $Command }
if ($Interactive) {
    Write-Host "交互模式：端口 $Port。控制台命令直接输入（如 forcestart），RA 命令前加 /（如 /roundlock enable）。空行退出。"
    while ($true) {
        $line = Read-Host '命令'
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        Send-One $line.Trim()
    }
}
if (-not $Command -and -not $Interactive) {
    Remove-ConsoleFiles
    Write-Host '已清理残留的控制台文件。'
}
