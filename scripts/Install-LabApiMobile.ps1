<#
.SYNOPSIS
  把 LabAPI-Mobile（Carl Mod 服务端的 LabAPI 插件框架）安装到测试服务器。可选功能。

.DESCRIPTION
  - 从 https://github.com/Michaelihc/labapimobile 的最新发布版下载框架压缩包（或用 -Zip 指定本地压缩包），
    解压到 .runtime\labapi\。
  - 对测试服务器 .runtime\server-<端口>-<版本> 运行 LabApiMobile.Installer.exe。原始服务端不会被修改。
    安装器会把原来的 Assembly-CSharp.dll 备份为 Assembly-CSharp.dll.labapi-original。
    每个服务端版本的测试服务器是分开的，换版本后要再安装一次。
    支持 Carl Mod 0.0.4（官方版和死斗模块版）和 0.0.5；0.0.5 需要 LabAPI-Mobile 1.1.7-mobile.5 或更新版本。
  - 创建插件文件夹 <服务器>\AppData\SCP Secret Laboratory\LabAPI-Mobile\plugins\global\，
    把插件 DLL 放进去，重启服务器即可加载。
  服务器必须先停止。

.PARAMETER Port           测试服务器端口，默认取配置 Port。
.PARAMETER ServerVersion  服务端版本（导入了多个版本时使用），默认取配置 ServerVersion。
.PARAMETER Zip            本地的 LabAPI-Mobile 发布压缩包（不联网时使用）。
.PARAMETER Version        LabAPI-Mobile 发布版标签（例如 v1.1.7-mobile.5），默认最新版。
#>
[CmdletBinding()]
param(
    [int]$Port,
    [string]$ServerVersion,
    [string]$Zip,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Port) { $Port = [int](Get-KitConfig).Port }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (Get-RunningServer $Port) {
    Fail "端口 $Port 的测试服务器正在运行。安装 LabAPI-Mobile 前必须先停止它。" "运行 scripts\Stop-TestServer.ps1 -Port $Port，安装完再启动。"
}
$build = Select-PristineServer $ServerVersion
$serverDir = Initialize-TestServerDir (Get-ServerDir $Port $build) $build

$labRoot = Join-Path $script:Runtime 'labapi'
New-Item -ItemType Directory -Force $labRoot | Out-Null

if (-not $Zip) {
    $api = if ($Version) { "https://api.github.com/repos/Michaelihc/labapimobile/releases/tags/$Version" } else { 'https://api.github.com/repos/Michaelihc/labapimobile/releases/latest' }
    Write-Step '查询 LabAPI-Mobile 发布版'
    try { $release = Invoke-RestMethod -UseBasicParsing -Uri $api -Headers @{ 'User-Agent' = 'carlmod-testkit' } }
    catch { Fail "无法访问 GitHub：$($_.Exception.Message)" '检查网络；或从 https://github.com/Michaelihc/labapimobile/releases 手动下载压缩包，再用 -Zip <路径> 安装。' }
    $asset = $release.assets | Where-Object { $_.name -like 'LabApiMobile-*.zip' } | Select-Object -First 1
    if (-not $asset) { Fail "发布版 $($release.tag_name) 里没有 LabApiMobile-*.zip。" '从发布页手动下载后用 -Zip 指定。' }
    $downloads = Join-Path $script:Runtime 'downloads'
    New-Item -ItemType Directory -Force $downloads | Out-Null
    $Zip = Join-Path $downloads $asset.name
    if (-not (Test-Path -LiteralPath $Zip) -or (Get-Item -LiteralPath $Zip).Length -ne $asset.size) {
        Write-Step "下载 $($asset.name)（$($release.tag_name)）"
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $Zip
    }
}
if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { Fail "压缩包不存在：$Zip" '检查路径。' }

$extract = Join-Path $labRoot ([IO.Path]::GetFileNameWithoutExtension($Zip))
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
Expand-Archive -LiteralPath $Zip -DestinationPath $extract -Force
$installer = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'LabApiMobile.Installer.exe' | Select-Object -First 1
if (-not $installer) { Fail '压缩包里没有 LabApiMobile.Installer.exe。' '确认下载的是 LabAPI-Mobile 的发布压缩包。' }

Write-Step "安装 LabAPI-Mobile 到 $serverDir（服务端 $($build.Label)）"
& $installer.FullName $serverDir
if ($LASTEXITCODE -ne 0) { Fail "安装器失败（退出码 $LASTEXITCODE）。" '查看上面的输出。安装器只支持它认识的 Carl Mod 服务端版本；Carl Mod 0.0.5 需要 LabAPI-Mobile 1.1.7-mobile.5 或更新版本（去掉 -Version / -Zip 即使用最新版）。' }

$plugins = Join-Path (Get-LabApiDataDir $serverDir) 'plugins\global'
New-Item -ItemType Directory -Force $plugins | Out-Null
Write-Ok 'LabAPI-Mobile 已安装到测试服务器。'
Write-Host "插件文件夹：$plugins"
Write-Host '把插件 DLL 放进这个文件夹，然后启动（或重启）服务器。'
Write-Host '可选：运行 scripts\Install-HelperPlugin.ps1 安装测试辅助插件 TestKitHelper。'
