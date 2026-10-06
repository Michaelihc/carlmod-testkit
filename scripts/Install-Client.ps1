<#
.SYNOPSIS
  把 Carl Mod 安卓客户端（com.carlmod.game）安装到正在运行的模拟器。

.DESCRIPTION
  APK 默认取 inputs 文件夹里唯一的 *.apk / *.apk.* 文件（或配置里的 Apk）。脚本先把它复制到
  .runtime\apk\（adb 只接受 .apk 扩展名；原文件从不修改），再执行 “adb install -r -g”。
  游戏数据保存在 AVD 里，每个 AVD 只需安装一次；测试新版本时用 -Apk 指定新文件。

.PARAMETER Apk        要安装的 APK，默认见上。
.PARAMETER Reinstall  先卸载（会清除游戏数据）再安装。
.PARAMETER IfMissing  已安装时直接跳过。
.PARAMETER Serial     adb 序列号，默认取配置 Serial。
.PARAMETER Second     安装到第二个模拟器（配置 SecondSerial）。
#>
[CmdletBinding()]
param(
    [string]$Apk,
    [switch]$Reinstall,
    [switch]$IfMissing,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = (Get-KitConfig).SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
Assert-EmulatorOnline $serial

if ($IfMissing -and -not $Reinstall -and (Test-ClientInstalled $serial)) {
    Write-Ok "$serial 上已安装客户端，跳过安装。"
    return
}

if (-not $Apk) {
    $Apk = Find-ApkFile
    if (-not $Apk) { Fail '找不到客户端 APK。' '把 Carl Mod 安卓客户端 APK 放进 inputs 文件夹（或在 testkit.config.psd1 里设置 Apk）。' }
}
if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { Fail "APK 不存在：$Apk" '检查路径。' }
$Apk = (Resolve-Path -LiteralPath $Apk).ProviderPath

$src = Get-Item -LiteralPath $Apk
if ($src.Extension -ieq '.apk' -and $src.FullName -like "$(Join-Path $script:Runtime 'apk')\*") {
    $install = $src.FullName
} else {
    # 复制一份带 .apk 扩展名的副本；内容相同（大小和修改时间一致）时复用。
    $apkDir = Join-Path $script:Runtime 'apk'
    New-Item -ItemType Directory -Force $apkDir | Out-Null
    $base = ($src.Name -replace '(\.apk)?(\.\d+)?$', '') -replace '[^\w\.-]+', '_'
    $install = Join-Path $apkDir "$base.apk"
    $copy = Get-Item -LiteralPath $install -ErrorAction SilentlyContinue
    if (-not $copy -or $copy.Length -ne $src.Length -or $copy.LastWriteTimeUtc -ne $src.LastWriteTimeUtc) {
        Write-Step "复制 APK 到 $install（$([Math]::Round($src.Length / 1GB, 2)) GB）"
        Copy-Item -LiteralPath $src.FullName -Destination $install -Force
    }
}

if ($Reinstall) { Invoke-Adb $serial uninstall $script:ClientPackage | Out-Host }

Write-Step "安装客户端到 $serial（约 30 秒）"
$sw = [Diagnostics.Stopwatch]::StartNew()
$out = Invoke-Adb $serial install -r -g $install
$out | Out-Host
if (($out | Out-String) -notmatch 'Success') {
    Fail 'adb install 失败。' '查看上面的错误。INSUFFICIENT_STORAGE：用 Install-AndroidSdk.ps1 -Recreate 重建 AVD；NO_MATCHING_ABIS：AVD 必须使用 API 36 x86_64 镜像。'
}
Write-Ok ("已安装 {0}，用时 {1:N0} 秒" -f $script:ClientPackage, $sw.Elapsed.TotalSeconds)
Invoke-Adb $serial shell dumpsys package $script:ClientPackage | Select-String 'versionName|versionCode|primaryCpuAbi' | Select-Object -First 3 | Out-Host
