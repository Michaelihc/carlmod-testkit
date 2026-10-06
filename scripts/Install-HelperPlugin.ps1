<#
.SYNOPSIS
  构建并安装测试辅助插件 TestKitHelper（需要先安装 LabAPI-Mobile）。可选功能。

.DESCRIPTION
  TestKitHelper 提供：
    - 把服务器控制台输出写进服务器日志（前缀 [console]），Send-ServerCommand.ps1 因此能显示命令结果；
    - testkit 命令：list（玩家列表）、dummy（生成假人）、remove（移除假人）、tp（传送）。
  有 .NET SDK（dotnet 命令）时从 plugin\TestKitHelper 源码构建；否则（或加 -Download）从本项目的
  GitHub 发布页下载预编译的 TestKitHelper.dll。然后复制到测试服务器的
  AppData\SCP Secret Laboratory\LabAPI-Mobile\plugins\global\。服务器在运行时需要重启才会加载。

.PARAMETER Port      测试服务器端口，默认取配置 Port。
.PARAMETER Download  不构建，直接下载预编译的 DLL。
.PARAMETER Dll       安装指定的 TestKitHelper.dll。
#>
[CmdletBinding()]
param(
    [int]$Port,
    [switch]$Download,
    [string]$Dll
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Port) { $Port = [int](Get-KitConfig).Port }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$serverDir = Get-ServerDir $Port
$labApiDll = Join-Path $serverDir 'Carl Mod_Data\Managed\LabApi.dll'
if (-not (Test-Path -LiteralPath $labApiDll)) {
    Fail "端口 $Port 的测试服务器还没有安装 LabAPI-Mobile。" "先运行 scripts\Install-LabApiMobile.ps1 -Port $Port。"
}

if (-not $Dll) {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    $hasSdk = $false
    if ($dotnet -and -not $Download) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $hasSdk = [bool](& $dotnet.Source --list-sdks 2>$null | Where-Object { $_ -match '^\d' }) } finally { $ErrorActionPreference = $prev }
    }
    $out = Join-Path $script:Runtime 'build\TestKitHelper'
    if ($hasSdk) {
        $managed = Join-Path (Assert-PristineServer) 'Carl Mod_Data\Managed'
        $proj = Join-Path $script:KitRoot 'plugin\TestKitHelper\TestKitHelper.csproj'
        Write-Step '构建 TestKitHelper'
        & $dotnet.Source build $proj -c Release -nologo -v:minimal "-p:CarlManaged=$managed" "-p:LabApiDll=$labApiDll" -o $out
        if ($LASTEXITCODE -ne 0) { Fail '构建失败。' '查看上面的编译错误；也可以加 -Download 使用预编译的 DLL。' }
        $Dll = Join-Path $out 'TestKitHelper.dll'
    } else {
        if (-not $Download) { Write-Note '没有找到 .NET SDK，改为下载预编译的 TestKitHelper.dll。' }
        New-Item -ItemType Directory -Force $out | Out-Null
        $Dll = Join-Path $out 'TestKitHelper.dll'
        Write-Step '下载 TestKitHelper.dll'
        try { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Michaelihc/carlmod-testkit/releases/latest/download/TestKitHelper.dll' -OutFile $Dll }
        catch { Fail "下载失败：$($_.Exception.Message)" '检查网络，或安装 .NET SDK（https://dotnet.microsoft.com/download）后从源码构建。' }
    }
}
if (-not (Test-Path -LiteralPath $Dll -PathType Leaf)) { Fail "找不到 $Dll。" '检查路径。' }

$plugins = Join-Path (Get-LabApiDataDir $serverDir) 'plugins\global'
New-Item -ItemType Directory -Force $plugins | Out-Null
Copy-Item -LiteralPath $Dll -Destination (Join-Path $plugins 'TestKitHelper.dll') -Force
Write-Ok "TestKitHelper 已安装到 $plugins"
if (Get-RunningServer $Port) { Write-Note '服务器正在运行：重启服务器后插件才会加载（菜单“全部停止”后再“一键开始测试”，或分别运行 Stop/Start-TestServer.ps1）。' }
Write-Host '用法（控制台）：testkit list | testkit dummy ClassD | testkit dummy Scp173 2 | testkit remove all | testkit tp 2 3'
