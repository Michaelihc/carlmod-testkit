<#
.SYNOPSIS
  正常关闭测试模拟器（adb emu kill），不影响其它模拟器。

.PARAMETER Serial  adb 序列号，默认取配置 Serial（emulator-5554）。
.PARAMETER Second  关闭第二个模拟器（配置 SecondSerial）。
.PARAMETER All     关闭本工具启动过的所有模拟器（.runtime\state 里的 emulator-*.json）。
#>
[CmdletBinding()]
param(
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

function Stop-One([string]$S) {
    $port = Get-EmulatorConsolePort $S
    if (-not (Get-AdbDevices | Where-Object { $_.Serial -eq $S })) {
        Write-Host "$S 没有运行。"
    } else {
        Invoke-Adb $S emu kill | Out-Null
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline -and (Get-AdbDevices | Where-Object { $_.Serial -eq $S })) { Start-Sleep -Milliseconds 500 }
        if (Get-AdbDevices | Where-Object { $_.Serial -eq $S }) { Fail "$S 在 60 秒内没有关闭。" '直接关闭模拟器窗口，或稍后再试。' }
        Write-Ok "已关闭 $S。"
    }
    Remove-Item -LiteralPath (Get-EmulatorStateFile $port) -Force -ErrorAction SilentlyContinue
}

if ($All) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $script:Runtime 'state') -Filter 'emulator-*.json' -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { Write-Host '没有本工具启动的模拟器记录。'; return }
    foreach ($f in $files) { if ($f.BaseName -match '^emulator-(\d+)$') { Stop-One "emulator-$($Matches[1])" } }
    return
}

if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = (Get-KitConfig).SecondSerial }
Stop-One (Resolve-EmulatorSerial $Serial $ConsolePort)
