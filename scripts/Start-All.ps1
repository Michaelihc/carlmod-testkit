<#
.SYNOPSIS
  一键开始测试：启动测试服务器 -> 启动模拟器 -> 安装（首次）并启动客户端 -> 自动连接服务器。

.DESCRIPTION
  已经在运行的服务器和模拟器会直接复用。客户端总是从主菜单重新启动后再连接。
  模拟器里已安装的客户端版本和服务端版本不同时会提示：版本不同的客户端无法加入服务器。

.PARAMETER Port           服务器端口，默认取配置 Port。
.PARAMETER ServerVersion  服务端版本（导入了多个版本时使用），默认取配置 ServerVersion。
.PARAMETER Second         同时启动第二个客户端（第二个 AVD，配置 SecondAvdName / SecondSerial）。
.PARAMETER SecondOnly     只启动并连接第二个客户端（服务器和第一个客户端已在运行时使用）。
.PARAMETER ForceStart     连接后发送 forcestart 开始回合。
.PARAMETER NoWindow       模拟器不显示窗口。
#>
[CmdletBinding()]
param(
    [int]$Port,
    [string]$ServerVersion,
    [switch]$Second,
    [switch]$SecondOnly,
    [switch]$ForceStart,
    [switch]$NoWindow
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
if (-not $Port) { $Port = [int]$cfg.Port }
$s = $PSScriptRoot

& (Join-Path $s 'Start-TestServer.ps1') -Port $Port -ServerVersion $ServerVersion
$runningVersion = (Get-RunningServer $Port).Version

function Start-OneClient([string]$Serial, [string]$Avd) {
    & (Join-Path $s 'Start-Emulator.ps1') -AvdName $Avd -Serial $Serial -NoWindow:$NoWindow
    & (Join-Path $s 'Install-Client.ps1') -Serial $Serial -IfMissing
    $clientVersion = Get-InstalledClientVersion $Serial
    if ($runningVersion -and $clientVersion -and $clientVersion -ne $runningVersion) {
        Write-Note "$Serial 里的客户端是 $clientVersion，服务端是 $runningVersion。$script:VersionMatchNote"
        Write-Note "安装同版本的客户端：scripts\Install-Client.ps1 -Serial $Serial -Apk <$runningVersion 的 APK>；或换用 $clientVersion 的服务端（-ServerVersion $clientVersion）。"
    }
    Write-Step "启动客户端（$Serial）"
    & (Join-Path $s 'Start-Client.ps1') -Serial $Serial -Restart
    & (Join-Path $s 'Connect-Client.ps1') -Serial $Serial -Port $Port
}

if (-not $SecondOnly) { Start-OneClient $cfg.Serial $cfg.AvdName }
if ($Second -or $SecondOnly) { Start-OneClient $cfg.SecondSerial $cfg.SecondAvdName }

if ($ForceStart) { & (Join-Path $s 'Send-ServerCommand.ps1') -Command forcestart -Port $Port }

Write-Host ''
Write-Ok '测试环境已就绪。'
Write-Host '常用操作：'
Write-Host '  开始回合      scripts\Send-ServerCommand.ps1 forcestart'
Write-Host '  回到大厅      scripts\Send-ServerCommand.ps1 roundrestart'
Write-Host '  截图          scripts\Capture.ps1 -Name <标签>'
Write-Host '  全部停止      stop-all.cmd'
