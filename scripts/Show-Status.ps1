<#
.SYNOPSIS
  显示当前状态：测试服务器、模拟器、客户端。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig

Write-Host '测试服务器：' -ForegroundColor Cyan
$files = @(Get-ChildItem -LiteralPath (Join-Path $script:Runtime 'state') -Filter 'server-*.json' -ErrorAction SilentlyContinue)
$any = $false
foreach ($f in $files) {
    if ($f.BaseName -notmatch '^server-(\d+)$') { continue }
    $p = [int]$Matches[1]
    $st = Get-RunningServer $p
    if ($st) {
        $any = $true
        $console = if ($st.Session) { '可发送命令' } else { '-stdout 模式，不能发送命令' }
        Write-Host "  端口 $p：运行中（PID $($st.Pid)，$console）"
        Write-Host "    日志：$($st.LogPath)"
        $plugins = Join-Path (Get-LabApiDataDir $st.ServerDir) 'plugins\global'
        if (Test-Path -LiteralPath (Join-Path $st.ServerDir 'Carl Mod_Data\Managed\LabApi.dll')) {
            $names = @(Get-ChildItem -LiteralPath $plugins -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object Name)
            Write-Host "    LabAPI-Mobile：已安装；插件：$(if ($names.Count) { $names -join ', ' } else { '无' })"
        }
    }
}
if (-not $any) { Write-Host '  没有运行中的测试服务器。' }

Write-Host '模拟器：' -ForegroundColor Cyan
$adbOk = $true
try { $null = Get-Adb } catch { $adbOk = $false; Write-Host '  Android SDK 未安装。' }
if ($adbOk) {
    $devices = @(Get-AdbDevices | Where-Object { $_.Serial -like 'emulator-*' })
    if ($devices.Count -eq 0) { Write-Host '  没有运行中的模拟器。' }
    foreach ($d in $devices) {
        if ($d.State -ne 'device') { Write-Host "  $($d.Serial)：$($d.State)"; continue }
        $avd = "$(Invoke-Adb $d.Serial emu avd name | Select-Object -First 1)".Trim()
        $mine = Test-Path -LiteralPath (Get-EmulatorStateFile (Get-EmulatorConsolePort $d.Serial))
        $client = if (Test-ClientRunning $d.Serial) { '客户端运行中' } elseif (Test-ClientInstalled $d.Serial) { '客户端已安装，未运行' } else { '未安装客户端' }
        Write-Host "  $($d.Serial)（$avd）：$client$(if ($mine) { '' } else { '（不是本工具启动的）' })"
    }
}
Write-Host "默认配置：端口 $($cfg.Port)，模拟器 $($cfg.Serial)（$($cfg.AvdName)），第二个 $($cfg.SecondSerial)（$($cfg.SecondAvdName)）" -ForegroundColor DarkGray
