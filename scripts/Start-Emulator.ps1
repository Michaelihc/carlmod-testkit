<#
.SYNOPSIS
  用 WHPX 加速启动测试用模拟器（AVD），等 Android 启动完成后返回。

.DESCRIPTION
  默认冷启动（不加载快照），每次都从相同状态开始。模拟器日志写到 .runtime\logs\emulator-<控制台端口>.log。
  用 Stop-Emulator.ps1 关闭。

  模拟器的 qemu 进程会被排除在 Windows 节能限速之外；否则模拟器窗口不在前台时游戏会慢约四分之一。

  一个 AVD 同时只能运行一个实例，所以第二个模拟器用自己的 AVD 和控制台端口：
    Start-Emulator.ps1 -Second        （等同于 -AvdName carlmod_api36_b -Serial emulator-5556）

.PARAMETER AvdName      要启动的 AVD，默认取配置 AvdName。
.PARAMETER Serial       adb 序列号 emulator-<控制台端口>，默认取配置 Serial（emulator-5554）。
.PARAMETER Second       使用第二套 AVD 和序列号（配置 SecondAvdName / SecondSerial）。
.PARAMETER NoWindow     不显示模拟器窗口（仍使用主机 GPU 渲染）。
.PARAMETER Snapshot     允许加载/保存快照，而不是冷启动。
#>
[CmdletBinding()]
param(
    [Alias('Avd')]
    [string]$AvdName,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second,
    [switch]$NoWindow,
    [switch]$Snapshot,
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
if (-not $AvdName) { $AvdName = if ($Second) { $cfg.SecondAvdName } else { $cfg.AvdName } }
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = $cfg.SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
$ConsolePort = Get-EmulatorConsolePort $serial
if ($ConsolePort % 2 -ne 0 -or $ConsolePort -lt 5554 -or $ConsolePort -gt 5682) {
    Fail "控制台端口 $ConsolePort 无效。" '模拟器控制台端口必须是 5554 到 5682 之间的偶数，例如 emulator-5554、emulator-5556。'
}

$sdk = Get-AndroidSdk
$adb = Get-Adb
$env:ANDROID_SDK_ROOT = $sdk
$emulator = Join-Path $sdk 'emulator\emulator.exe'
if (-not (Test-Path -LiteralPath $emulator)) { Fail "找不到模拟器程序：$emulator" '先运行 setup.cmd（或 scripts\Install-AndroidSdk.ps1）。' }
if (-not (Test-Path (Join-Path (Get-AvdHome) "$AvdName.avd\config.ini"))) {
    $hint = if ($AvdName -eq $cfg.SecondAvdName) { 'scripts\Install-AndroidSdk.ps1 -Second' } else { "scripts\Install-AndroidSdk.ps1 -AvdName $AvdName" }
    Fail "AVD $AvdName 不存在。" "先创建它：$hint（或运行 setup.cmd）。"
}

# 测试用设置（可重复执行）：保持亮屏、关闭动画、预先确认“全屏查看”提示。
function Set-EmulatorTestSettings([string]$S) {
    # 保持亮屏；关闭动画，让输入时序更稳定。
    Invoke-Adb $S shell svc power stayon true | Out-Null
    Invoke-Adb $S shell settings put global window_animation_scale 0 | Out-Null
    Invoke-Adb $S shell settings put global transition_animation_scale 0 | Out-Null
    Invoke-Adb $S shell settings put global animator_duration_scale 0 | Out-Null
    # 新 AVD 首次全屏时会弹出“全屏查看”提示，挡住游戏并吞掉 Connect-Client.ps1 的点击。
    Invoke-Adb $S shell settings put secure immersive_mode_confirmations confirmed | Out-Null
    Invoke-Adb $S shell input keyevent KEYCODE_WAKEUP | Out-Null
    Invoke-Adb $S shell wm dismiss-keyguard | Out-Null
}

if (Get-AdbDevices | Where-Object { $_.Serial -eq $serial }) {
    $running = "$(Invoke-Adb $serial emu avd name | Select-Object -First 1)".Trim()
    if ($running -and $running -ne $AvdName) {
        Fail "$serial 上运行的是另一个 AVD（$running），不是 $AvdName。" '换一个序列号（例如 -Serial emulator-5558），或先关闭那个模拟器。'
    }
    Write-Ok "$serial（$AvdName）已在运行。"
    Set-EmulatorTestSettings $serial
    if (Disable-EmulatorPowerThrottling $ConsolePort) { Write-Host '已关闭它的 qemu 进程的节能限速。' }
    return
}

$other = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "-avd\s+$([regex]::Escape($AvdName))(\s|$)" } | Select-Object -First 1
if ($other) {
    $otherPort = if ($other.CommandLine -match '-port\s+(\d+)') { $Matches[1] } else { '?' }
    Fail "AVD $AvdName 已经在另一个模拟器实例中运行（控制台端口 $otherPort）。一个 AVD 同时只能运行一次。" "直接使用 -Serial emulator-$otherPort，或为第二个客户端使用第二个 AVD（-Second）。"
}

$logDir = Join-Path $script:Runtime 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "emulator-$ConsolePort.log"

$emuArgs = @('-avd', $AvdName, '-port', $ConsolePort, '-accel', 'on', '-gpu', 'host',
             '-no-boot-anim', '-no-audio', '-netdelay', 'none', '-netspeed', 'full')
if (-not $Snapshot) { $emuArgs += '-no-snapshot' }
if ($NoWindow) { $emuArgs += '-no-window' }

Write-Step "启动模拟器 $AvdName（$serial，冷启动约 1 分钟）"
$proc = Start-Process -FilePath $emulator -ArgumentList $emuArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
Write-Host "模拟器启动器 PID $($proc.Id)（$($emuArgs -join ' ')）"
New-Item -ItemType Directory -Force (Join-Path $script:Runtime 'state') | Out-Null
Write-Utf8NoBom (Get-EmulatorStateFile $ConsolePort) @(([pscustomobject]@{ Serial = $serial; AvdName = $AvdName; LauncherPid = $proc.Id; Started = (Get-Date).ToString('s') } | ConvertTo-Json))

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$booted = $false
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited -and -not (Get-AdbDevices | Where-Object { $_.Serial -eq $serial })) {
        Remove-Item -LiteralPath (Get-EmulatorStateFile $ConsolePort) -Force -ErrorAction SilentlyContinue
        Fail "模拟器提前退出（退出码 $($proc.ExitCode)）。" "查看 $log 和 $log.err。常见原因：WHPX 未启用、磁盘空间不足、显卡驱动问题。"
    }
    if (Test-EmulatorOnline $serial) {
        $b = "$(Invoke-Adb $serial shell getprop sys.boot_completed | Select-Object -First 1)".Trim()
        if ($b -eq '1') { $booted = $true; break }
    }
    Start-Sleep -Seconds 2
}
if (-not $booted) { Fail "等待 $TimeoutSec 秒模拟器仍未启动完成。" "查看 $log；可以用 scripts\Stop-Emulator.ps1 -Serial $serial 关闭后重试。" }

Set-EmulatorTestSettings $serial

$qemuPid = Disable-EmulatorPowerThrottling $ConsolePort
if ($qemuPid) { Write-Host "已关闭 qemu 进程 $qemuPid 的节能限速。" }

$abis = "$(Invoke-Adb $serial shell getprop ro.product.cpu.abilist | Select-Object -First 1)".Trim()
$release = "$(Invoke-Adb $serial shell getprop ro.build.version.release | Select-Object -First 1)".Trim()
Write-Ok "$serial 已启动：Android $release，ABI：$abis"
if ($abis -notmatch 'arm64-v8a') { Write-Warning 'ABI 列表里没有 arm64-v8a，ARM64 的游戏 APK 无法运行。请使用 API 36 的 x86_64 系统镜像。' }
