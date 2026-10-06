# 公共函数，由 scripts\*.ps1 点引用（. _common.ps1）。兼容 Windows PowerShell 5.1 和 PowerShell 7。

$script:KitRoot = Split-Path -Parent $PSScriptRoot
$script:Runtime = Join-Path $script:KitRoot '.runtime'

try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

# ---------------------------------------------------------------- 错误与输出

# 抛出带“下一步”提示的中文错误。
function Fail([string]$Message, [string]$Next) {
    if ($Next) { throw "$Message`n下一步：$Next" }
    throw $Message
}

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "[完成] $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "[提示] $Text" -ForegroundColor Yellow }

# 写入不带 BOM 的 UTF-8 文本（服务端配置文件不能带 BOM）。
function Write-Utf8NoBom([string]$Path, [string[]]$Lines) {
    [IO.File]::WriteAllLines($Path, $Lines, (New-Object Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- 配置

# 默认值；testkit.config.psd1（可选，从 testkit.config.example.psd1 复制）中的同名键会覆盖它们。
function Get-KitConfig {
    if ($script:KitConfigCache) { return $script:KitConfigCache }
    $cfg = @{
        Port                 = 7777
        ServerZip            = ''
        ServerFolder         = ''
        Apk                  = ''
        AndroidSdk           = ''
        AvdName              = 'carlmod_api36'
        Serial               = 'emulator-5554'
        SecondAvdName        = 'carlmod_api36_b'
        SecondSerial         = 'emulator-5556'
        CommandSession       = 'testkit'
        ConfigOverrides      = @{ afk_time = '0' }
    }
    $file = Join-Path $script:KitRoot 'testkit.config.psd1'
    if (Test-Path -LiteralPath $file) {
        try {
            # 始终按 UTF-8 读取（记事本保存的无 BOM 文件在 Windows PowerShell 5.1 中也能正确读出中文路径）。
            $text = [IO.File]::ReadAllText($file, (New-Object Text.UTF8Encoding($false)))
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) { throw $errors[0].Message }
            $hash = $ast.Find({ param($n) $n -is [Management.Automation.Language.HashtableAst] }, $false)
            if (-not $hash) { throw '文件里没有 @{ ... }。' }
            $user = $hash.SafeGetValue()
        }
        catch { Fail "配置文件 testkit.config.psd1 格式有误：$($_.Exception.Message)" '对照 testkit.config.example.psd1 修改，或删除该文件以使用默认值。' }
        foreach ($k in $user.Keys) {
            if (-not $cfg.ContainsKey($k)) { Write-Note "testkit.config.psd1 中的未知配置项 '$k' 已忽略。" ; continue }
            $cfg[$k] = $user[$k]
        }
    }
    foreach ($k in 'ServerZip', 'ServerFolder', 'Apk', 'AndroidSdk') {
        if ($cfg[$k] -and -not [IO.Path]::IsPathRooted($cfg[$k])) { $cfg[$k] = Join-Path $script:KitRoot $cfg[$k] }
    }
    $script:KitConfigCache = $cfg
    return $cfg
}

# ---------------------------------------------------------------- 输入文件（服务端 ZIP / APK）

function Find-InputFile([string]$ConfigKey, [string[]]$Patterns, [string]$What) {
    $cfg = Get-KitConfig
    if ($cfg[$ConfigKey]) {
        if (-not (Test-Path -LiteralPath $cfg[$ConfigKey] -PathType Leaf)) {
            Fail "testkit.config.psd1 中 $ConfigKey 指向的$What不存在：$($cfg[$ConfigKey])" "改正路径，或删掉这一项并把文件放进 inputs 文件夹。"
        }
        return (Resolve-Path -LiteralPath $cfg[$ConfigKey]).ProviderPath
    }
    $inputs = Join-Path $script:KitRoot 'inputs'
    $found = @(foreach ($p in $Patterns) { Get-ChildItem -LiteralPath $inputs -Filter $p -File -ErrorAction SilentlyContinue })
    $found = @($found | Sort-Object FullName -Unique)
    if ($found.Count -eq 1) { return $found[0].FullName }
    if ($found.Count -gt 1) {
        Fail "inputs 文件夹里有多个$What：$(($found | ForEach-Object Name) -join '、')" "只保留一个，或在 testkit.config.psd1 中用 $ConfigKey 指定要用的文件。"
    }
    return $null
}

function Find-ServerZip { Find-InputFile 'ServerZip' @('*.zip') '服务端 ZIP' }
function Find-ApkFile   { Find-InputFile 'Apk' @('*.apk', '*.apk.*') '客户端 APK' }

# 原始服务端文件夹（只读，测试服务器从它复制）：配置的 ServerFolder，否则 .runtime\server-original。
function Get-PristineServerDir {
    $cfg = Get-KitConfig
    if ($cfg.ServerFolder) { return [IO.Path]::GetFullPath($cfg.ServerFolder) }
    return (Join-Path $script:Runtime 'server-original')
}

function Assert-PristineServer {
    $dir = Get-PristineServerDir
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'Carl Mod.exe'))) {
        if ((Get-KitConfig).ServerFolder) {
            Fail "ServerFolder 指向的文件夹里没有 Carl Mod.exe：$dir" '把 ServerFolder 改成包含 Carl Mod.exe 的文件夹。'
        }
        Fail '还没有导入服务端。' '把 Carl Mod 服务端 ZIP 放进 inputs 文件夹，然后运行 setup.cmd（或 scripts\Import-Server.ps1）。'
    }
    return $dir
}

# ---------------------------------------------------------------- 测试服务器

function Get-ServerDir([int]$Port) { Join-Path $script:Runtime "server-$Port" }
function Get-ServerStateFile([int]$Port) { Join-Path $script:Runtime "state\server-$Port.json" }

# 返回本工具为该端口启动、且仍在运行的服务端进程信息；没有则返回 $null。
function Get-RunningServer([int]$Port) {
    $file = Get-ServerStateFile $Port
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $state = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $info = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$state.Pid)" -ErrorAction SilentlyContinue
    if (-not $info -or -not (Test-IsTestServerProcess $info $Port)) { return $null }
    return $state
}

function Test-IsTestServerProcess($Info, [int]$Port) {
    return ($Info.Name -eq 'Carl Mod.exe' -and $Info.CommandLine -match "-port$Port(\s|`"|$)")
}

# 确保测试服务器文件夹存在（从原始服务端复制）并含有 hoster_policy.txt（gamedir_for_configs: true）。
function Initialize-TestServerDir([string]$ServerDir) {
    $ServerDir = [IO.Path]::GetFullPath($ServerDir)
    if (-not (Test-Path -LiteralPath (Join-Path $ServerDir 'Carl Mod.exe'))) {
        $source = Assert-PristineServer
        if ([IO.Path]::GetFullPath($source).TrimEnd('\') -ieq $ServerDir.TrimEnd('\')) {
            Fail '测试服务器文件夹不能和原始服务端是同一个文件夹。' '去掉 -ServerDir，使用默认的 .runtime\server-<端口>。'
        }
        Write-Step "复制原始服务端到 $ServerDir（约 0.7 GB，只需一次）"
        robocopy $source $ServerDir /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Fail "复制服务端失败（robocopy 退出码 $LASTEXITCODE）。" '检查磁盘空间和文件夹权限后重试。' }
        $global:LASTEXITCODE = 0
    }
    $policy = Join-Path $ServerDir 'hoster_policy.txt'
    if (-not (Test-Path -LiteralPath $policy)) {
        Write-Utf8NoBom $policy @('gamedir_for_configs: true')
        Write-Host "已写入 $policy"
    }
    if ((Get-Content -LiteralPath $policy -Raw) -notmatch 'gamedir_for_configs:\s*true') {
        Fail "$policy 里没有 'gamedir_for_configs: true'，拒绝继续（否则配置会写进真正的 %APPDATA%）。" '在该文件中加入一行 gamedir_for_configs: true。'
    }
    return $ServerDir
}

# LabAPI-Mobile 在测试服务器里的数据文件夹（插件放在其 plugins\global）。
function Get-LabApiDataDir([string]$ServerDir) {
    Join-Path $ServerDir 'AppData\SCP Secret Laboratory\LabAPI-Mobile'
}

function Test-UdpPortInUse([int]$Port) {
    return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- Python

# 返回可用的 Python 3.8+ 命令（数组：程序 + 参数），找不到返回 $null。
function Get-PythonCommand {
    foreach ($cand in @(@('py', '-3'), @('python'), @('python3'))) {
        $cmd = Get-Command $cand[0] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $args_ = @($cand | Select-Object -Skip 1)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $v = & $cmd.Source @args_ -c 'import sys; print(sys.version_info[0], sys.version_info[1])' 2>$null } finally { $ErrorActionPreference = $prev }
        if ($LASTEXITCODE -eq 0 -and "$v" -match '^(\d+) (\d+)') {
            if ([int]$Matches[1] -gt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -ge 8)) {
                return ,([string[]](@($cmd.Source) + $args_))
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------- Android SDK / 模拟器

function Get-AndroidSdk {
    $cfg = Get-KitConfig
    if ($cfg.AndroidSdk) { return $cfg.AndroidSdk }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) { return $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) { return $env:ANDROID_HOME }
    return (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
}

function Get-Adb {
    $adb = Join-Path (Get-AndroidSdk) 'platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adb)) { Fail "找不到 adb：$adb" '先运行 setup.cmd（或 scripts\Install-AndroidSdk.ps1）安装 Android SDK。' }
    return $adb
}

function Get-AvdHome {
    if ($env:ANDROID_AVD_HOME) { return $env:ANDROID_AVD_HOME }
    return (Join-Path $env:USERPROFILE '.android\avd')
}

# 解析目标模拟器的 adb 序列号：-Serial 优先，其次 -ConsolePort，最后用配置里的 Serial。
function Resolve-EmulatorSerial([string]$Serial, [int]$ConsolePort) {
    if ($Serial) { $null = Get-EmulatorConsolePort $Serial; return $Serial }
    if ($ConsolePort) { return "emulator-$ConsolePort" }
    return (Get-KitConfig).Serial
}

function Get-EmulatorConsolePort([string]$Serial) {
    if ($Serial -notmatch '^emulator-(\d+)$') { Fail "'$Serial' 不是模拟器序列号。" '序列号的格式是 emulator-<控制台端口>，例如 emulator-5554 或 emulator-5556。' }
    return [int]$Matches[1]
}

# 对指定模拟器执行 adb，返回输出行（合并 stderr）。不因非零退出码抛错。
# 用法：Invoke-Adb <serial> <adb 参数...>（无 param 块，-p 之类参数会原样传给 adb）。
function Invoke-Adb {
    $Serial = $args[0]
    $AdbArgs = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })
    $adb = Get-Adb
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $adb -s $Serial @AdbArgs 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $prev }
}

function Get-AdbDevices {
    $adb = Get-Adb
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $lines = & $adb devices 2>$null } finally { $ErrorActionPreference = $prev }
    foreach ($l in $lines) { if ("$l" -match '^(\S+)\s+(device|offline|unauthorized)\s*$') { [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] } } }
}

function Test-EmulatorOnline([string]$Serial) {
    return [bool](Get-AdbDevices | Where-Object { $_.Serial -eq $Serial -and $_.State -eq 'device' })
}

function Assert-EmulatorOnline([string]$Serial) {
    if (-not (Test-EmulatorOnline $Serial)) {
        Fail "模拟器 $Serial 没有运行。" '先启动模拟器：start-all.cmd，或 scripts\Start-Emulator.ps1。'
    }
}

# 把 adb exec-out 的原始输出写入文件（避免 PowerShell 改写二进制数据）。
function Save-AdbBinary {
    param([string]$Serial, [string]$OutFile, [string[]]$AdbArgs)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Get-Adb
    $psi.Arguments = (@('-s', $Serial) + $AdbArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($OutFile)
    try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
    $p.WaitForExit()
    return $p.ExitCode
}

function Get-EmulatorStateFile([int]$ConsolePort) { Join-Path $script:Runtime "state\emulator-$ConsolePort.json" }

# Windows 会对后台窗口的进程做节能限速（EcoQoS），模拟器窗口不在前台时 qemu 进程会明显变慢
# （同一场景从约 51 FPS 降到 39 FPS）。这里只对指定控制台端口的 qemu 进程关闭节能限速，返回其 PID；
# 找不到该进程时返回 $null。
function Disable-EmulatorPowerThrottling([int]$ConsolePort) {
    $qemu = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-port\s+$ConsolePort(\s|$)" } | Select-Object -First 1
    if (-not $qemu) { return $null }
    if (-not ('CarlModTestKit.PowerThrottling' -as [type])) {
        Add-Type -Namespace CarlModTestKit -Name PowerThrottling -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct State { public uint Version; public uint ControlMask; public uint StateMask; }
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr OpenProcess(uint access, bool inherit, int pid);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetProcessInformation(System.IntPtr process, int infoClass, ref State info, int size);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool CloseHandle(System.IntPtr handle);
'@
    }
    # PROCESS_SET_INFORMATION; ProcessPowerThrottling = 4; EXECUTION_SPEED (1) | IGNORE_TIMER_RESOLUTION (4)，状态为关闭。
    $handle = [CarlModTestKit.PowerThrottling]::OpenProcess(0x0200, $false, [int]$qemu.ProcessId)
    if ($handle -eq [IntPtr]::Zero) { Write-Warning "无法打开 qemu 进程 $($qemu.ProcessId)，未关闭节能限速。"; return $null }
    try {
        $state = New-Object CarlModTestKit.PowerThrottling+State
        $state.Version = 1; $state.ControlMask = 5; $state.StateMask = 0
        if (-not [CarlModTestKit.PowerThrottling]::SetProcessInformation($handle, 4, [ref]$state, 12)) {
            Write-Warning "关闭 qemu 进程 $($qemu.ProcessId) 的节能限速失败。"
            return $null
        }
    } finally { [void][CarlModTestKit.PowerThrottling]::CloseHandle($handle) }
    return [int]$qemu.ProcessId
}

$script:ClientPackage = 'com.carlmod.game'

function Test-ClientInstalled([string]$Serial) {
    return [bool](Invoke-Adb $Serial shell pm list packages $script:ClientPackage | Where-Object { $_ -match "^package:$([regex]::Escape($script:ClientPackage))$" })
}

function Test-ClientRunning([string]$Serial) {
    return [bool]("$(Invoke-Adb $Serial shell pidof $script:ClientPackage | Select-Object -First 1)".Trim())
}
