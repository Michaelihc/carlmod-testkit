<#
.SYNOPSIS
  一键准备：检查环境 -> 导入服务端 -> 安装 Android SDK 并创建模拟器。可以重复运行，已完成的步骤会跳过。

.PARAMETER Second  同时创建第二个模拟器（双客户端测试用）。
#>
[CmdletBinding()]
param(
    [switch]$Second
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Step '第 1 步：检查环境'
& (Join-Path $PSScriptRoot 'Test-Prerequisites.ps1')
if ($LASTEXITCODE -ne 0) { Fail '环境检查未通过。' '按上面每个 [失败] 项的“下一步”处理，然后重新运行 setup.cmd。' }

Write-Step '第 2 步：导入服务端'
& (Join-Path $PSScriptRoot 'Import-Server.ps1')

Write-Step '第 3 步：安装 Android SDK 并创建模拟器'
& (Join-Path $PSScriptRoot 'Install-AndroidSdk.ps1')
if ($Second) { & (Join-Path $PSScriptRoot 'Install-AndroidSdk.ps1') -Second }

Write-Host ''
Write-Ok '准备完成。下一步：双击 start-all.cmd（或在菜单里选“一键开始测试”）。'
