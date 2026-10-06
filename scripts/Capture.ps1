<#
.SYNOPSIS
  保存模拟器截图（PNG）并输出文件路径。

.PARAMETER Name    文件名标签，截图保存为 .runtime\captures\<时间>-<Name>.png。
.PARAMETER Open    保存后用默认图片查看器打开。
.PARAMETER Serial  adb 序列号，默认取配置 Serial。
.PARAMETER Second  使用第二个模拟器（配置 SecondSerial）。

.EXAMPLE
  .\scripts\Capture.ps1 -Name main-menu
#>
[CmdletBinding()]
param(
    [string]$Name = 'shot',
    [string]$OutDir,
    [switch]$Open,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = (Get-KitConfig).SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
Assert-EmulatorOnline $serial
if (-not $OutDir) { $OutDir = Join-Path $script:Runtime 'captures' }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$safeName = $Name -replace '[\\/:*?"<>|\s]+', '_'
$file = Join-Path $OutDir ('{0:yyyyMMdd-HHmmss}-{1}.png' -f (Get-Date), $safeName)

$code = Save-AdbBinary -Serial $serial -OutFile $file -AdbArgs @('exec-out', 'screencap', '-p')
if ($code -ne 0 -or (Get-Item $file).Length -lt 1000) { Fail "截图失败（adb 退出码 $code）。" '确认模拟器已完全启动后重试。' }
Write-Ok "截图已保存：$file"
if ($Open) { Invoke-Item -LiteralPath $file }
