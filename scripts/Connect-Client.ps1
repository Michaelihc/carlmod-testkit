<#
.SYNOPSIS
  自动点击 Carl Mod 主菜单，通过 IP 直连加入服务器，等到 Facility 场景加载完成。

.DESCRIPTION
  点击顺序：游戏 标签 -> IP直连 -> 地址输入框 -> 输入地址 -> 连接。点击位置按 2400x1080 横屏的比例计算，
  同宽高比的其它分辨率也适用。客户端必须停在主菜单（先运行 Start-Client.ps1 -Restart）。
  “已加入” 指 Unity 日志报告了 Facility 场景；回合是否开始由服务器决定（forcestart）。

  模拟器通过 10.0.2.2 访问本机，所以默认地址是 10.0.2.2:<配置端口>。

.PARAMETER Address  要加入的 主机:端口，默认 10.0.2.2:<配置 Port>。
.PARAMETER Port     只改端口时用，地址为 10.0.2.2:<Port>。
.PARAMETER Serial   adb 序列号，默认取配置 Serial。
.PARAMETER Second   使用第二个模拟器（配置 SecondSerial）。
#>
[CmdletBinding()]
param(
    [string]$Address,
    [int]$Port,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second,
    [int]$MenuTimeoutSec = 90,
    [int]$JoinTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
if (-not $Port) { $Port = [int]$cfg.Port }
if (-not $Address) { $Address = "10.0.2.2:$Port" }
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = $cfg.SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
Assert-EmulatorOnline $serial
if (-not (Test-ClientRunning $serial)) { Fail '客户端没有在运行。' "先运行 scripts\Start-Client.ps1 -Restart -Serial $serial。" }

# 横屏尺寸（wm size 按竖屏顺序报告物理尺寸）。
$size = (Invoke-Adb $serial shell wm size | Select-String 'Physical size: (\d+)x(\d+)' | Select-Object -First 1)
if (-not $size) { Fail '读取不到屏幕尺寸。' '确认模拟器已完全启动。' }
$a = [int]$size.Matches[0].Groups[1].Value; $b = [int]$size.Matches[0].Groups[2].Value
$W = [Math]::Max($a, $b); $H = [Math]::Min($a, $b)
function Tap([double]$fx, [double]$fy) { Invoke-Adb $serial shell input tap ([int]($fx * $W)) ([int]($fy * $H)) | Out-Null }

function Wait-UnityLog([string]$Pattern, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Invoke-Adb $serial logcat -d -s Unity:I | Select-String -Pattern $Pattern -Quiet)) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

Write-Step '等待主菜单'
if (-not (Wait-UnityLog "Loaded scene 'NewMainMenu'" $MenuTimeoutSec)) {
    Fail "$MenuTimeoutSec 秒内主菜单没有加载。" "重启客户端后再试：scripts\Start-Client.ps1 -Restart -Serial $serial。若一直卡住，截图查看（scripts\Capture.ps1）。"
}
Start-Sleep -Seconds 3
Invoke-Adb $serial logcat -c | Out-Null

Tap 0.1242 0.0463      # 游戏 标签
Start-Sleep -Seconds 1.5
Tap 0.1646 0.3222      # IP直连
Start-Sleep -Seconds 1.5
Tap 0.5000 0.4870      # 地址输入框
Start-Sleep -Seconds 1.5
Invoke-Adb $serial shell input text $Address | Out-Null
Start-Sleep -Seconds 1
Tap 0.4430 0.5490      # 连接
Write-Step "正在连接 $Address ..."

if (-not (Wait-UnityLog "Loaded scene 'Facility'" $JoinTimeoutSec)) {
    Fail "$JoinTimeoutSec 秒内没有进入 Facility 场景。" "确认服务器在运行（端口 $Port），再截图查看客户端状态：scripts\Capture.ps1 -Serial $serial。"
}
Write-Ok '已加入服务器（Facility 场景已加载）。用 forcestart 开始回合。'
