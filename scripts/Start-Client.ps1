<#
.SYNOPSIS
  在模拟器上启动（或强制重启）Carl Mod 客户端。

.PARAMETER Restart  先强制停止游戏，让它从主菜单重新开始（Connect-Client.ps1 需要主菜单）。
.PARAMETER Serial   adb 序列号，默认取配置 Serial。
.PARAMETER Second   使用第二个模拟器（配置 SecondSerial）。
#>
[CmdletBinding()]
param(
    [switch]$Restart,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = (Get-KitConfig).SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
Assert-EmulatorOnline $serial
if (-not (Test-ClientInstalled $serial)) { Fail "$serial 上还没有安装客户端。" '先运行 scripts\Install-Client.ps1（start-all.cmd 会自动安装）。' }

if ($Restart) {
    Invoke-Adb $serial shell am force-stop $script:ClientPackage | Out-Null
    Invoke-Adb $serial logcat -c | Out-Null
}
Invoke-Adb $serial shell input keyevent KEYCODE_WAKEUP | Out-Null
# 刚启动完的模拟器偶尔会丢掉第一次启动请求，所以最多尝试 3 次，每次等 10 秒。
$clientPid = ''
for ($attempt = 1; $attempt -le 3 -and -not $clientPid; $attempt++) {
    Invoke-Adb $serial shell monkey -p $script:ClientPackage -c android.intent.category.LAUNCHER 1 | Out-Null
    for ($i = 0; $i -lt 10 -and -not $clientPid; $i++) {
        Start-Sleep -Seconds 1
        $clientPid = "$(Invoke-Adb $serial shell pidof $script:ClientPackage | Select-Object -First 1)".Trim()
    }
}
if (-not $clientPid) { Fail '客户端没有启动。' "截图看看模拟器状态（scripts\Capture.ps1 -Serial $serial），或查看日志：adb -s $serial logcat -s Unity:V。" }
Write-Ok "已启动客户端（$serial，pid $clientPid）"
