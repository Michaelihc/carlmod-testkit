<#
.SYNOPSIS
  安装 Android SDK 组件并创建测试用的模拟器（AVD）。可以重复运行。

.DESCRIPTION
  - 从 dl.google.com 下载官方 command-line tools 到 <SDK>\cmdline-tools\latest（已存在则跳过）。
  - 安装 platform-tools、emulator 和 Google APIs x86_64 系统镜像（API 36 / Android 16）。已安装的组件
    不会重复下载；加 -Update 才会更新到最新版本。该 x86_64 镜像自带 ARM 转译，能运行 arm64-v8a 的游戏。
    必须用 API 36：API 34 镜像的 ARM 转译器不支持 libunity.so 加载时执行的 AArch64 SEVL 指令，
    客户端会因 SIGILL 崩溃。
  - 创建 AVD（Pixel 6 配置，横屏，6 GB 内存，8 核，主机 GPU，16 GB 数据分区）。已存在则不改动。
  - 最后运行 “emulator -accel-check” 检查 WHPX 加速。本脚本不会修改 Windows 功能。

.PARAMETER AvdName   AVD 名称，默认取配置 AvdName（carlmod_api36）。
.PARAMETER Second    创建第二个 AVD（配置 SecondAvdName，默认 carlmod_api36_b），用于双客户端测试。
.PARAMETER Recreate  删除并重新创建 AVD（AVD 里安装的游戏和数据会一起删除）。
.PARAMETER Update    更新已安装的 SDK 组件。不要在模拟器运行时更新。
#>
[CmdletBinding()]
param(
    [Alias('Avd')]
    [string]$AvdName,
    [switch]$Second,
    [switch]$Recreate,
    [switch]$Update,
    [string]$CmdlineToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip',
    [string]$SystemImage = 'system-images/android-36/google_apis/x86_64'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
if (-not $AvdName) { $AvdName = if ($Second) { $cfg.SecondAvdName } else { $cfg.AvdName } }

$sdk = Get-AndroidSdk
$env:ANDROID_SDK_ROOT = $sdk
$sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdmanager = Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat'
Write-Host "Android SDK 位置：$sdk"

if (-not (Get-Command java -ErrorAction SilentlyContinue) -and -not $env:JAVA_HOME) {
    Fail '找不到 Java。Android SDK 的命令行工具需要 Java 17 或更新版本。' '安装 Java 17+（例如 https://adoptium.net 的 Temurin），重新打开窗口后再运行。'
}

if (-not (Test-Path -LiteralPath $sdkmanager)) {
    Write-Step '下载 Android command-line tools（约 150 MB）'
    New-Item -ItemType Directory -Force $sdk | Out-Null
    $zip = Join-Path $env:TEMP 'carlmod-testkit-cmdline-tools.zip'
    $tmp = Join-Path $sdk 'cmdline-tools\_extract'
    try {
        Invoke-WebRequest -UseBasicParsing $CmdlineToolsUrl -OutFile $zip
    } catch {
        Fail "下载失败：$($_.Exception.Message)" '检查网络（需要能访问 dl.google.com，必要时使用代理）后重新运行。'
    }
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Expand-Archive $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force (Join-Path $sdk 'cmdline-tools') | Out-Null
    Move-Item (Join-Path $tmp 'cmdline-tools') (Join-Path $sdk 'cmdline-tools\latest')
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip -Force
}

$imageDir = Join-Path $sdk (($SystemImage -replace '/', '\'))
$need = @()
if ($Update -or -not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe')))     { $need += 'platform-tools' }
if ($Update -or -not (Test-Path (Join-Path $sdk 'emulator\emulator.exe')))      { $need += 'emulator' }
if ($Update -or -not (Test-Path (Join-Path $imageDir 'system.img')))            { $need += $SystemImage }

if ($need.Count -gt 0) {
    Write-Step "安装 SDK 组件：$($need -join ', ')（系统镜像约 1.5 GB 下载，首次需要几分钟）"
    # 首次使用需要接受许可协议。
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        (1..20 | ForEach-Object { 'y' }) | & $sdkmanager --sdk_root="$sdk" --licenses 2>&1 | Out-Null
        & $sdkmanager --sdk_root="$sdk" @need 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\s*(\.\.\.|Unzipping)?.*\[[#. =]*\]' -and $_.Trim() }
    } finally { $ErrorActionPreference = $prev }
    if (-not (Test-Path (Join-Path $imageDir 'system.img'))) {
        Fail "系统镜像没有装好：$imageDir" '检查上面的 sdkmanager 输出（网络或磁盘空间问题），然后重新运行本脚本。'
    }
} else {
    Write-Ok 'SDK 组件已安装（platform-tools、emulator、API 36 系统镜像）。'
}

$avdHome = Get-AvdHome
$avdDir = Join-Path $avdHome "$AvdName.avd"
if ($Recreate -and (Test-Path $avdDir)) {
    Write-Step "删除 AVD $AvdName"
    Remove-Item $avdDir -Recurse -Force
    Remove-Item (Join-Path $avdHome "$AvdName.ini") -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path (Join-Path $avdDir 'config.ini'))) {
    Write-Step "创建 AVD $AvdName"
    $imageId = $SystemImage -replace '/', ';'
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { 'no' | & $avdmanager create avd -n $AvdName -k $imageId -d pixel_6 --force 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
    $cfgIni = Join-Path $avdDir 'config.ini'
    if (-not (Test-Path $cfgIni)) { Fail "avdmanager 没有创建 $cfgIni。" '确认系统镜像已安装，并检查用户文件夹下 .android\avd 是否可写。' }
    $set = [ordered]@{
        'avd.id' = $AvdName; 'avd.name' = $AvdName
        'hw.ramSize' = '6144'; 'hw.cpu.ncore' = '8'; 'vm.heapSize' = '512M'
        'hw.gpu.enabled' = 'yes'; 'hw.gpu.mode' = 'host'
        'hw.initialOrientation' = 'landscape'; 'hw.keyboard' = 'yes'
        'disk.dataPartition.size' = '16G'; 'showDeviceFrame' = 'no'
    }
    $lines = foreach ($l in (Get-Content $cfgIni)) {
        $k = ($l -split '=', 2)[0]
        if ($k -eq 'disk.dataPartition.path') { continue }   # "<temp>" 会在每次启动时丢掉已安装的游戏
        if ($set.Contains($k)) { "$k=$($set[$k])"; $set.Remove($k) } else { $l }
    }
    $lines += $set.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    Set-Content $cfgIni $lines -Encoding ASCII
    Write-Ok "已创建 AVD $AvdName"
} else {
    Write-Ok "AVD $AvdName 已存在。"
}

Write-Step '检查模拟器加速（WHPX）'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try { $accel = & (Join-Path $sdk 'emulator\emulator.exe') -accel-check 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
$accel | ForEach-Object { Write-Host "  $_" }
if (($accel -join "`n") -notmatch 'WHPX.*usable') {
    Fail '模拟器无法使用 WHPX 加速。' '在“启用或关闭 Windows 功能”中勾选“Windows 虚拟机监控程序平台”，确认 BIOS 已开启虚拟化（VT-x/AMD-V），重启电脑后再试。'
}
Write-Ok 'Android 环境准备完成。'
