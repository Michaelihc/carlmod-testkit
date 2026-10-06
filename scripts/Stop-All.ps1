<#
.SYNOPSIS
  全部停止：关闭本工具启动的所有模拟器和测试服务器。

.DESCRIPTION
  只处理 .runtime\state 里记录的、由本工具启动的模拟器和服务器；服务器停止前会核对进程命令行。
  其它模拟器和服务端不受影响。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Step '关闭模拟器'
$adbOk = $true
try { $null = Get-Adb } catch { $adbOk = $false; Write-Host '没有安装 Android SDK，跳过模拟器。' }
if ($adbOk) { & (Join-Path $PSScriptRoot 'Stop-Emulator.ps1') -All }

Write-Step '停止测试服务器'
& (Join-Path $PSScriptRoot 'Stop-TestServer.ps1') -All
