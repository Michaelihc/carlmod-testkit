<#
.SYNOPSIS
  交互式菜单（menu.cmd 打开的就是它）。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$s = $PSScriptRoot
try { $Host.UI.RawUI.WindowTitle = 'Carl Mod 本地测试工具' } catch { }

function Invoke-Action([scriptblock]$Action) {
    try {
        & $Action
    } catch {
        Write-Host ''
        Write-Host "[出错] $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ''
    $null = Read-Host '按回车返回菜单'
}

function Open-Folder([string]$Path) {
    New-Item -ItemType Directory -Force $Path | Out-Null
    Invoke-Item -LiteralPath $Path
}

while ($true) {
    $cfg = Get-KitConfig
    Clear-Host
    Write-Host '==============================================' -ForegroundColor Cyan
    Write-Host '   Carl Mod 本地测试工具（服务器 + 安卓模拟器）' -ForegroundColor Cyan
    Write-Host '==============================================' -ForegroundColor Cyan
    Write-Host "   端口 $($cfg.Port)    模拟器 $($cfg.Serial)（$($cfg.AvdName)）" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  准备'
    Write-Host '    1  检查环境'
    Write-Host '    2  一键准备（导入服务端、安装 Android SDK、创建模拟器）'
    Write-Host '  测试'
    Write-Host '    3  一键开始测试（服务器 + 模拟器 + 客户端 + 自动连接）'
    Write-Host '    4  开始回合（forcestart）'
    Write-Host '    5  回到大厅（roundrestart）'
    Write-Host '    6  发送控制台命令'
    Write-Host '    7  截图'
    Write-Host '    8  查看状态'
    Write-Host '    9  重新连接客户端（重启游戏并加入服务器）'
    Write-Host '  双客户端'
    Write-Host '   10  创建第二个模拟器（只需一次）'
    Write-Host '   11  启动第二个客户端并连接'
    Write-Host '  其它'
    Write-Host '   12  测量帧率（30 秒）'
    Write-Host '   13  安装 LabAPI-Mobile 到测试服务器（可选）'
    Write-Host '   14  安装测试辅助插件 TestKitHelper（可选）'
    Write-Host '   15  打开截图文件夹'
    Write-Host '   16  打开日志文件夹'
    Write-Host '   17  授予游戏内 RA 权限（客户端连上后运行，会重启服务器）'
    Write-Host ''
    Write-Host '    0  全部停止（模拟器 + 服务器）'
    Write-Host '    Q  退出菜单（不停止任何东西）'
    Write-Host ''
    $choice = (Read-Host '请输入编号').Trim()

    switch ($choice) {
        '1'  { Invoke-Action { & (Join-Path $s 'Test-Prerequisites.ps1') } }
        '2'  { Invoke-Action { & (Join-Path $s 'Setup.ps1') } }
        '3'  { Invoke-Action { & (Join-Path $s 'Start-All.ps1') } }
        '4'  { Invoke-Action { & (Join-Path $s 'Send-ServerCommand.ps1') -Command forcestart } }
        '5'  { Invoke-Action { & (Join-Path $s 'Send-ServerCommand.ps1') -Command roundrestart } }
        '6'  { Invoke-Action { & (Join-Path $s 'Send-ServerCommand.ps1') -Interactive } }
        '7'  { Invoke-Action {
                   $name = (Read-Host '截图标签（可留空）').Trim()
                   if (-not $name) { $name = 'shot' }
                   & (Join-Path $s 'Capture.ps1') -Name $name -Open
               } }
        '8'  { Invoke-Action { & (Join-Path $s 'Show-Status.ps1') } }
        '9'  { Invoke-Action {
                   & (Join-Path $s 'Start-Client.ps1') -Restart
                   & (Join-Path $s 'Connect-Client.ps1')
               } }
        '10' { Invoke-Action { & (Join-Path $s 'Install-AndroidSdk.ps1') -Second } }
        '11' { Invoke-Action { & (Join-Path $s 'Start-All.ps1') -SecondOnly } }
        '12' { Invoke-Action {
                   $name = (Read-Host '本次测量的标签（可留空）').Trim()
                   if (-not $name) { $name = 'run' }
                   & (Join-Path $s 'Measure-FrameTime.ps1') -Name $name -DurationSec 30
               } }
        '13' { Invoke-Action { & (Join-Path $s 'Install-LabApiMobile.ps1') } }
        '14' { Invoke-Action { & (Join-Path $s 'Install-HelperPlugin.ps1') } }
        '15' { Open-Folder (Join-Path $script:Runtime 'captures') }
        '16' { Open-Folder (Join-Path $script:Runtime 'logs') }
        '17' { Invoke-Action { & (Join-Path $s 'Grant-RemoteAdmin.ps1') -Restart } }
        '0'  { Invoke-Action { & (Join-Path $s 'Stop-All.ps1') } }
        { $_ -in 'q', 'Q' } { return }
        default { }
    }
}
