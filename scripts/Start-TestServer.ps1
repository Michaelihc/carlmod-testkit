<#
.SYNOPSIS
  启动本地 Carl Mod 测试服务器，等它开始监听后返回。

.DESCRIPTION
  - 测试服务器文件夹是 .runtime\server-<端口>-<版本>（例如 server-7777-0.0.5）。不存在时从该版本的原始服务端
    （.runtime\server-original-<版本>，或配置里的 ServerFolder）复制一份；原始服务端本身从不修改。
    导入了多个版本时，版本由 -ServerVersion 或配置 ServerVersion 决定（见 Import-Server.ps1）。
  - 写入 hoster_policy.txt（gamedir_for_configs: true），配置、封禁列表和日志都放在
    <服务器文件夹>\AppData，而不是真正的 %APPDATA%\SCP Secret Laboratory。唯一的例外是服务端的
    player-prefs 文件 %APPDATA%\SCP Secret Laboratory\registry.txt：服务端在读取该策略之前就确定了它的路径，
    每次回合重启会更新其中的 LastRoundrestartTime 和 SrvSp_* 键（-appdatapath 也改不了）。
  - 把 ConfigOverrides 写进 AppData\config\<端口>\config_gameplay.txt。默认 afk_time: 0，
    否则单个测试客户端在出生点站 90 秒会被踢。第一次启动时配置文件还不存在，脚本会先启动一次生成配置，
    停止、修改后再正式启动。
  - 端口已被占用时拒绝启动。同一端口已有本工具启动的服务器在运行时直接返回。
  - 默认用文件控制台（-key<会话名>）启动，之后用 Send-ServerCommand.ps1 发送命令。
    服务端不读取标准输入，所以 -stdout 模式下无法输入命令。参数顺序很重要：-stdout 必须在 -port<N> 之前。
  - 等日志出现 “Server started listening”（约 35 秒），把 PID 记录到 .runtime\state\server-<端口>.json，
    Stop-TestServer.ps1 只按这个 PID 停止。

.PARAMETER Port            游戏端口（UDP），默认取配置 Port（7777）。
.PARAMETER ServerVersion   服务端版本（如 0.0.5、0.0.4、0.0.4-dm），默认取配置 ServerVersion，见上。
.PARAMETER ServerDir       测试服务器文件夹，默认 .runtime\server-<端口>-<版本>。
.PARAMETER LogPath         Unity 日志路径，默认 .runtime\logs\server-<端口>-<时间>.log。
.PARAMETER TimeoutSec      等待启动的秒数（默认 180）。
.PARAMETER Stdout          用 -stdout 输出到 <日志>.stdout.txt，而不是文件控制台（之后不能发送命令）。
.PARAMETER ConfigOverrides 要写入 config_gameplay.txt 的键值，默认取配置（@{ afk_time = '0' }）。传 @{} 表示不修改。
.PARAMETER ExtraArgs       追加在 -port 之后的其它服务端参数。

.EXAMPLE
  .\scripts\Start-TestServer.ps1
  .\scripts\Start-TestServer.ps1 -ServerVersion 0.0.4
  .\scripts\Start-TestServer.ps1 -Port 7778 -ConfigOverrides @{ afk_time = '0'; friendly_fire = 'true' }
#>
[CmdletBinding()]
param(
    [int]$Port,
    [string]$ServerVersion,
    [string]$ServerDir,
    [string]$LogPath,
    [int]$TimeoutSec = 180,
    [switch]$Stdout,
    [hashtable]$ConfigOverrides,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
if (-not $Port) { $Port = [int]$cfg.Port }
if ($null -eq $ConfigOverrides) { $ConfigOverrides = $cfg.ConfigOverrides }
$session = $cfg.CommandSession

$running = Get-RunningServer $Port
if ($running) {
    Write-Ok "端口 $Port 的测试服务器已在运行（PID $($running.Pid)$(if ($running.Build) { "，服务端 $($running.Build)" })）。"
    Write-Host "日志：$($running.LogPath)"
    if ($ServerVersion -and $ServerVersion -notin @($running.Version, $running.Key)) { Write-Note "要换成 $ServerVersion 的服务端，先停止它：scripts\Stop-TestServer.ps1 -Port $Port。" }
    return
}

$build = $null
if ($ServerDir -and (Test-Path -LiteralPath (Join-Path $ServerDir 'Carl Mod.exe'))) { $build = Get-ServerDirBuild $ServerDir }
if (-not $build) { $build = Select-PristineServer $ServerVersion }
if (-not $ServerDir) { $ServerDir = Get-ServerDir $Port $build }
if (-not $LogPath)   { $LogPath = Join-Path $script:Runtime ('logs\server-{0}-{1:yyyyMMdd-HHmmss}.log' -f $Port, (Get-Date)) }
$ServerDir = [IO.Path]::GetFullPath($ServerDir)
$LogPath   = [IO.Path]::GetFullPath($LogPath)
$exe = Join-Path $ServerDir 'Carl Mod.exe'

if (Test-UdpPortInUse $Port) {
    Fail "UDP 端口 $Port 已被其它程序占用（可能是另一个服务端或其它游戏服务器）。" "关掉占用它的程序，或换一个端口：在 testkit.config.psd1 里改 Port，或运行时加 -Port 7778。"
}

$null = Initialize-TestServerDir $ServerDir $build

$stateDir = Join-Path $script:Runtime 'state'
New-Item -ItemType Directory -Force $stateDir | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $LogPath) | Out-Null
$stateFile = Get-ServerStateFile $Port
$configFile = Join-Path $ServerDir "AppData\config\$Port\config_gameplay.txt"

function Test-LogContains([string]$Path, [string]$Pattern) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        return $text.Contains($Pattern)
    } catch { return $false }
}

function Save-State([int]$ProcessId, [string]$Log, [bool]$FileConsole) {
    $state = [ordered]@{
        Pid = $ProcessId; Port = $Port; ServerDir = $ServerDir; LogPath = $Log
        Version = $build.Version; Key = $build.Key; Build = $build.Label
        Session = $(if ($FileConsole) { $session } else { '' }); Started = (Get-Date).ToString('s')
    }
    Write-Utf8NoBom $stateFile @(([pscustomobject]$state | ConvertTo-Json))
}

# 启动服务端并等待就绪，返回 Process。
function Start-ServerProcess([string]$Log, [bool]$UseFileConsole) {
    if (Test-Path -LiteralPath $Log) { Remove-Item -LiteralPath $Log -Force }
    if ($UseFileConsole) {
        # 文件控制台在构造时就监视这个文件夹，所以它必须先存在。
        $sessionDir = Join-Path $ServerDir "Carl Mod_Data\Dedicated\$session"
        if (Test-Path -LiteralPath $sessionDir) { Remove-Item -LiteralPath $sessionDir -Recurse -Force }
        New-Item -ItemType Directory -Force $sessionDir | Out-Null
    }
    $outputArg = if ($UseFileConsole) { "-key$session" } else { '-stdout' }
    $argList = @('-batchmode', '-nographics', $outputArg, "-port$Port", '-logFile', "`"$Log`"") + $ExtraArgs
    $startParams = @{
        FilePath = $exe; ArgumentList = $argList; WorkingDirectory = $ServerDir
        PassThru = $true; WindowStyle = 'Hidden'
    }
    if (-not $UseFileConsole) { $startParams.RedirectStandardOutput = "$Log.stdout.txt" }
    $p = Start-Process @startParams
    Save-State $p.Id $Log $UseFileConsole
    Write-Host "已启动 PID $($p.Id)：$($argList -join ' ')"

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($p.HasExited) { Fail "服务端提前退出（退出码 $($p.ExitCode)）。" "查看日志 $Log 末尾的报错。" }
        if (Test-LogContains $Log 'Server started listening') { return $p }
        Start-Sleep -Milliseconds 500
    }
    Fail ('等待 {0} 秒仍未出现 “Server started listening”（PID {1} 仍在运行）。' -f $TimeoutSec, $p.Id) "查看日志 $Log；需要放弃时运行 scripts\Stop-TestServer.ps1 -Port $Port。"
}

function Set-ConfigValues([string]$File, [hashtable]$Values) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.AddRange([string[]][IO.File]::ReadAllLines($File, $utf8))
    foreach ($key in $Values.Keys) {
        $new = "${key}: $($Values[$key])"
        $idx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^$([regex]::Escape($key)):") { $idx = $i; break } }
        if ($idx -ge 0) { $lines[$idx] = $new } else { $lines.Add($new) }
    }
    Write-Utf8NoBom $File $lines.ToArray()
    Write-Host "配置 $File：$(($Values.Keys | ForEach-Object { "$_=$($Values[$_])" }) -join ', ')"
}

if ($ConfigOverrides.Count -gt 0 -and -not (Test-Path -LiteralPath $configFile)) {
    Write-Step '第一次启动：先启动一次以生成配置文件（约 40 秒）'
    $boot = Start-ServerProcess "$LogPath.bootstrap.log" $false
    Stop-Process -Id $boot.Id -Force
    $boot.WaitForExit()
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $configFile)) { Fail "服务端没有生成 $configFile。" "查看日志 $LogPath.bootstrap.log。" }
}
if ($ConfigOverrides.Count -gt 0) { Set-ConfigValues $configFile $ConfigOverrides }

Write-Step "启动测试服务器（服务端 $($build.Label)，UDP 端口 $Port，约 35 秒）"
$proc = Start-ServerProcess $LogPath (-not $Stdout)
Write-Ok "测试服务器已就绪：服务端 $($build.Label)，UDP 端口 $Port，PID $($proc.Id)"
Write-Host "日志：     $LogPath"
Write-Host "AppData：  $(Join-Path $ServerDir 'AppData')"
Write-Host "模拟器里连接地址：10.0.2.2:$Port$(if ($build.Version) { "（客户端也必须是 $($build.Version) 版本）" })"
if ($Stdout) { Write-Note '-Stdout 模式不能发送控制台命令。' }
