<#
.SYNOPSIS
  停止由 Start-TestServer.ps1 启动的测试服务器。

.DESCRIPTION
  读取 .runtime\state\server-<端口>.json 里的 PID，确认该进程是 “Carl Mod.exe” 且命令行包含 -port<端口>，
  然后只停止这一个进程。从不按进程名批量结束进程，所以其它服务端不受影响。

.PARAMETER Port  端口，默认取配置 Port。
.PARAMETER All   停止本工具记录的所有测试服务器（.runtime\state 里的每个 server-*.json）。
#>
[CmdletBinding()]
param(
    [int]$Port,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Stop-One([int]$P) {
    $file = Get-ServerStateFile $P
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "端口 $P 没有本工具启动的服务器记录，无需停止。"; return }
    $state = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $procId = [int]$state.Pid
    $info = Get-CimInstance Win32_Process -Filter "ProcessId = $procId" -ErrorAction SilentlyContinue
    if (-not $info) {
        Write-Host "端口 $P 的服务器（PID $procId）已经不在运行。"
    } elseif (-not (Test-IsTestServerProcess $info $P)) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Write-Note "PID $procId 现在是另一个程序（$($info.Name)），不是端口 $P 的测试服务器；没有停止它，只删除了过期记录。"
        return
    } else {
        Stop-Process -Id $procId -Force
        Wait-Process -Id $procId -Timeout 15 -ErrorAction SilentlyContinue
        Write-Ok "已停止端口 $P 的测试服务器（PID $procId）。"
    }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
}

if ($All) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $script:Runtime 'state') -Filter 'server-*.json' -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { Write-Host '没有本工具启动的服务器记录。'; return }
    foreach ($f in $files) { if ($f.BaseName -match '^server-(\d+)$') { Stop-One ([int]$Matches[1]) } }
    return
}

if (-not $Port) { $Port = [int](Get-KitConfig).Port }
Stop-One $Port
