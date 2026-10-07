<#
.SYNOPSIS
  检查运行环境：系统、虚拟化（WHPX）、Java、Python、内存、磁盘空间、输入文件（含服务端和客户端版本）、
  Android SDK、端口。

.DESCRIPTION
  每项显示 [通过] / [警告] / [失败] 和下一步该做什么。只读检查，不修改任何东西。
  有 [失败] 项时退出码为 1。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
$cfg = Get-KitConfig
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Item, [string]$Status, [string]$Detail, [string]$Next) {
    $results.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail; Next = $Next })
}

function Get-FreeGB([string]$Path) {
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        return [Math]::Round((New-Object IO.DriveInfo($root)).AvailableFreeSpace / 1GB, 1)
    } catch { return $null }
}

function Test-NonAscii([string]$Text) { return ($Text -match '[^\x00-\x7F]') }

# ---- 系统
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if (-not [Environment]::Is64BitOperatingSystem) {
    Add-Result '操作系统' 'FAIL' "$($os.Caption)（32 位）" '需要 64 位 Windows 10 或 Windows 11。'
} elseif ($build -lt 17134) {
    Add-Result '操作系统' 'FAIL' "$($os.Caption) build $build" '需要 Windows 10 1803（build 17134）或更新版本。'
} else {
    Add-Result '操作系统' 'OK' "$($os.Caption) build $build" ''
}
Add-Result 'PowerShell' 'OK' "$($PSVersionTable.PSVersion)" ''

# ---- 虚拟化 / WHPX
$sdk = Get-AndroidSdk
$emulatorExe = Join-Path $sdk 'emulator\emulator.exe'
if (Test-Path -LiteralPath $emulatorExe) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $accel = (& $emulatorExe -accel-check 2>&1 | ForEach-Object { "$_" }) -join ' ' } finally { $ErrorActionPreference = $prev }
    if ($accel -match 'WHPX.*usable') { Add-Result '模拟器加速 (WHPX)' 'OK' 'emulator -accel-check：WHPX 可用' '' }
    else { Add-Result '模拟器加速 (WHPX)' 'FAIL' "emulator -accel-check：$accel" '在“启用或关闭 Windows 功能”中勾选“Windows 虚拟机监控程序平台”，确认 BIOS 已开启虚拟化（VT-x/AMD-V），然后重启。' }
} else {
    $cs = Get-CimInstance Win32_ComputerSystem
    $whpxDll = Test-Path (Join-Path $env:SystemRoot 'System32\WinHvPlatform.dll')
    $fw = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
    if ($cs.HypervisorPresent -and $whpxDll) {
        Add-Result '模拟器加速 (WHPX)' 'OK' '虚拟机监控程序已运行，WHPX 组件存在（安装 SDK 后会再用 emulator -accel-check 确认）' ''
    } elseif (-not $cs.HypervisorPresent -and $fw -eq $false) {
        Add-Result '模拟器加速 (WHPX)' 'FAIL' 'BIOS/UEFI 中的 CPU 虚拟化未开启' '重启进入 BIOS/UEFI，开启 Intel VT-x 或 AMD-V（SVM），再启用“Windows 虚拟机监控程序平台”并重启。'
    } else {
        Add-Result '模拟器加速 (WHPX)' 'FAIL' '“Windows 虚拟机监控程序平台”未启用' '在“启用或关闭 Windows 功能”中勾选“Windows 虚拟机监控程序平台”（Windows Hypervisor Platform），然后重启。'
    }
}

# ---- Java（Android SDK 命令行工具需要）
$sdkReady = (Test-Path (Join-Path $sdk 'platform-tools\adb.exe')) -and (Test-Path $emulatorExe) -and
            (Test-Path (Join-Path $sdk 'system-images\android-36\google_apis\x86_64\system.img'))
$javaExe = if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { (Get-Command java -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
$javaMajor = $null; $javaText = ''
if ($javaExe) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $javaText = (& $javaExe -version 2>&1 | ForEach-Object { "$_" } | Select-Object -First 1) } finally { $ErrorActionPreference = $prev }
    if ($javaText -match 'version "1\.(\d+)') { $javaMajor = [int]$Matches[1] }
    elseif ($javaText -match 'version "(\d+)') { $javaMajor = [int]$Matches[1] }
}
$javaNext = '安装 Java 17 或更新版本（例如 https://adoptium.net 的 Temurin JDK），安装后重新打开窗口。'
if ($javaMajor -ge 17) { Add-Result 'Java 17+' 'OK' $javaText.Trim() '' }
elseif ($sdkReady) { Add-Result 'Java 17+' 'WARN' $(if ($javaExe) { "版本过低：$javaText" } else { '未找到' }) "Android SDK 已装好，日常使用不需要 Java；以后重新安装 SDK 组件时再$javaNext" }
else { Add-Result 'Java 17+' 'FAIL' $(if ($javaExe) { "版本过低：$javaText" } else { '未找到 java（PATH 和 JAVA_HOME 中都没有）' }) $javaNext }

# ---- 服务端与 Python
$servers = @(); $zips = @(); $zipError = $null
try { $servers = @(Get-PristineServers) } catch { }
try { $zips = @(Find-ServerZips) } catch { $zipError = $_.Exception.Message }
$pending = @()   # 还没有导入的 ZIP
foreach ($z in $zips) {
    $b = $null
    try { $b = Get-ZipServerBuild $z } catch { }
    if (-not $b) { Add-Result '服务端 ZIP' 'WARN' "$(Split-Path -Leaf $z) 不是 Carl Mod 的 Windows 服务端（里面没有 Carl Mod.exe）" '把它移出 inputs 文件夹。'; continue }
    if (-not ($servers | Where-Object { $_.Key -eq $b.Key })) { $pending += [pscustomobject]@{ Name = (Split-Path -Leaf $z); Build = $b } }
}
$pendingText = ($pending | ForEach-Object { "$($_.Name)（$($_.Build.Label)）" }) -join '、'
if ($servers.Count -gt 0) {
    Add-Result '服务端' 'OK' "已导入：$(($servers | ForEach-Object Label) -join '、')" ''
    if ($pending.Count -gt 0) { Add-Result '服务端 ZIP' 'INFO' "未导入：$pendingText" '运行 setup.cmd（或 scripts\Import-Server.ps1）解压。' }
} elseif ($cfg.ServerFolder) {
    Add-Result '服务端' 'FAIL' "ServerFolder 里没有 Carl Mod.exe：$($cfg.ServerFolder)" '把 ServerFolder 改成包含 Carl Mod.exe 的文件夹。'
} elseif ($zipError) {
    Add-Result '服务端' 'FAIL' $zipError ''
} elseif ($pending.Count -gt 0) {
    Add-Result '服务端' 'OK' "找到 ZIP：$pendingText（运行 setup.cmd 时解压）" ''
} else {
    Add-Result '服务端' 'FAIL' 'inputs 文件夹里没有服务端 ZIP' '从 Carl Mod 官方渠道获取 Windows 服务端 ZIP，放进 inputs 文件夹。'
}
$python = Get-PythonCommand
if ($python) { Add-Result 'Python 3.8+' 'OK' ($python -join ' ') '' }
elseif ($pending.Count -eq 0 -and ($servers.Count -gt 0 -or $cfg.ServerFolder)) { Add-Result 'Python 3.8+' 'WARN' '未找到（服务端已导入，暂时不需要）' '以后要导入新的服务端 ZIP 时，从 https://www.python.org 安装 Python 3。' }
else { Add-Result 'Python 3.8+' 'FAIL' '未找到（解压服务端 ZIP 需要它）' '从 https://www.python.org 安装 Python 3，安装时勾选 “Add python.exe to PATH”，然后重新打开窗口。' }

# ---- APK
$apkVersion = $null
try {
    $apk = Find-ApkFile
    if ($apk) {
        $apkVersion = Get-ApkVersion $apk
        $v = if ($apkVersion) { "版本 $apkVersion，" } else { '' }
        Add-Result '客户端 APK' 'OK' "$(Split-Path -Leaf $apk)（$v$([Math]::Round((Get-Item -LiteralPath $apk).Length / 1GB, 2)) GB）" ''
    }
    else { Add-Result '客户端 APK' 'FAIL' 'inputs 文件夹里没有 APK' '从 Carl Mod 官方渠道获取安卓客户端 APK，放进 inputs 文件夹。' }
} catch { Add-Result '客户端 APK' 'FAIL' $_.Exception.Message '' }

# ---- 客户端和服务端版本
$verItem = '客户端与服务端版本'
if ($servers.Count -gt 0) {
    $sel = $null
    try { $sel = Select-PristineServer } catch {
        $msg = $_.Exception.Message -split "`n"
        Add-Result $verItem 'FAIL' $msg[0] ($msg[1] -replace '^下一步：', '')
    }
    if ($sel) {
        $how = if ($cfg.ServerVersion) { '（配置 ServerVersion）' } elseif ($servers.Count -gt 1) { '（与 APK 版本相同）' } else { '' }
        if (-not $apkVersion -or -not $sel.Version) {
            Add-Result $verItem 'INFO' "测试服务器使用 $($sel.Label)$how；读不到 APK 的版本" $script:VersionMatchNote
        } elseif ($apkVersion -eq $sel.Version) {
            Add-Result $verItem 'OK' "都是 $apkVersion（测试服务器使用 $($sel.Label)$how）" ''
        } else {
            Add-Result $verItem 'WARN' "客户端 APK 是 $apkVersion，测试服务器使用 $($sel.Label)$how" "$($script:VersionMatchNote)换用同版本的 APK，或导入并选择 $apkVersion 的服务端（配置 ServerVersion）。"
        }
    }
} elseif ($pending.Count -gt 0 -and $apkVersion) {
    if (-not ($pending | Where-Object { $_.Build.Version -eq $apkVersion })) {
        Add-Result $verItem 'WARN' "客户端 APK 是 $apkVersion，服务端 ZIP 是 $(($pending | ForEach-Object { $_.Build.Label }) -join '、')" "$script:VersionMatchNote"
    }
}

# ---- 硬件
$ramGB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
if ($ramGB -ge 16) { Add-Result '内存' 'OK' "$ramGB GB" '' }
else { Add-Result '内存' 'WARN' "$ramGB GB" '每个模拟器占用 6 GB，服务端约 1-2 GB。建议 16 GB 以上；双客户端测试建议 32 GB。' }
$cores = [Environment]::ProcessorCount
if ($cores -ge 8) { Add-Result 'CPU 线程数' 'OK' "$cores" '' }
else { Add-Result 'CPU 线程数' 'WARN' "$cores" '模拟器配置为 8 核，线程少于 8 时游戏会很卡。' }

# ---- 磁盘空间
$kitFree = Get-FreeGB $script:KitRoot
$kitNeed = 5
if ($null -eq $kitFree) { Add-Result '磁盘（本工具所在盘）' 'WARN' '无法读取剩余空间' '' }
elseif ($kitFree -ge $kitNeed) { Add-Result '磁盘（本工具所在盘）' 'OK' "剩余 $kitFree GB" '' }
else { Add-Result '磁盘（本工具所在盘）' 'FAIL' "剩余 $kitFree GB" "需要约 $kitNeed GB（每个版本的原始服务端 0.7 GB + 每个测试服务器 0.7 GB + APK 副本约 2 GB + 日志截图）。清理空间或把本工具移到别的盘。" }
$avdHome = Get-AvdHome
$avdExists = Test-Path (Join-Path $avdHome "$($cfg.AvdName).avd\config.ini")
$sdkNeed = 0
if (-not $sdkReady) { $sdkNeed += 7 }
if (-not $avdExists) { $sdkNeed += 12 }
$sdkFree = Get-FreeGB $sdk
$avdFree = Get-FreeGB $avdHome
$minFree = @($sdkFree, $avdFree | Where-Object { $null -ne $_ } | Sort-Object)[0]
$need = [Math]::Max($sdkNeed, 3)
if ($null -eq $minFree) { Add-Result '磁盘（SDK / 模拟器所在盘）' 'WARN' '无法读取剩余空间' '' }
elseif ($minFree -ge $need) { Add-Result '磁盘（SDK / 模拟器所在盘）' 'OK' "剩余 $minFree GB（SDK：$sdk；AVD：$avdHome）" '' }
else { Add-Result '磁盘（SDK / 模拟器所在盘）' 'FAIL' "剩余 $minFree GB，需要约 $need GB" 'Android SDK 约 6 GB，每个模拟器（安装游戏后）约 10 GB。清理空间，或在 testkit.config.psd1 设置 AndroidSdk、并设置环境变量 ANDROID_AVD_HOME 到空间充足的盘。' }

# ---- 路径中的中文/特殊字符（Android 模拟器不支持）
foreach ($pair in @(@('Android SDK 路径', $sdk), @('AVD 路径', $avdHome))) {
    if (Test-NonAscii $pair[1]) {
        Add-Result $pair[0] 'WARN' "$($pair[1]) 含有非英文字符" 'Android 模拟器在含中文等非 ASCII 字符的路径下可能无法启动。可在 testkit.config.psd1 里把 AndroidSdk 设为英文路径（如 D:\Android\Sdk），并把环境变量 ANDROID_AVD_HOME 设为英文路径（如 D:\Android\avd）。'
    }
}

# ---- Android SDK / AVD
if ($sdkReady) { Add-Result 'Android SDK' 'OK' $sdk '' }
else { Add-Result 'Android SDK' 'WARN' "未安装完整：$sdk" '运行 setup.cmd 自动安装。' }
if ($avdExists) { Add-Result "模拟器 $($cfg.AvdName)" 'OK' (Join-Path $avdHome "$($cfg.AvdName).avd") '' }
else { Add-Result "模拟器 $($cfg.AvdName)" 'WARN' '尚未创建' '运行 setup.cmd 自动创建。' }

# ---- 端口
$port = [int]$cfg.Port
if (Get-RunningServer $port) { Add-Result "UDP 端口 $port" 'OK' '本工具的测试服务器正在使用' '' }
elseif (Test-UdpPortInUse $port) { Add-Result "UDP 端口 $port" 'WARN' '已被其它程序占用' "关闭占用它的程序，或在 testkit.config.psd1 里把 Port 改成别的端口（例如 7778）。" }
else { Add-Result "UDP 端口 $port" 'OK' '空闲' '' }

# ---- .NET SDK（可选，仅构建辅助插件）
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
$hasDotnetSdk = $false
if ($dotnet) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $hasDotnetSdk = [bool](& $dotnet.Source --list-sdks 2>$null | Where-Object { $_ -match '^\d' }) } finally { $ErrorActionPreference = $prev }
}
if ($hasDotnetSdk) { Add-Result '.NET SDK（可选）' 'OK' '可从源码构建辅助插件' '' }
else { Add-Result '.NET SDK（可选）' 'INFO' '未安装' '只有从源码构建辅助插件时需要；没有也可以下载预编译版本。' }

# ---- 输出
$label = @{ OK = '[通过]'; WARN = '[警告]'; FAIL = '[失败]'; INFO = '[信息]' }
$color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }
Write-Host ''
Write-Host 'Carl Mod 本地测试工具 - 环境检查' -ForegroundColor Cyan
Write-Host ''
foreach ($r in $results) {
    Write-Host ('{0} {1}：{2}' -f $label[$r.Status], $r.Item, $r.Detail) -ForegroundColor $color[$r.Status]
    if ($r.Next -and $r.Status -ne 'OK') { Write-Host "       下一步：$($r.Next)" }
}
$fails = @($results | Where-Object Status -eq 'FAIL').Count
$warns = @($results | Where-Object Status -eq 'WARN').Count
Write-Host ''
if ($fails -gt 0) {
    Write-Host ('有 {0} 项未通过，请按“下一步”处理后重新检查。' -f $fails) -ForegroundColor Red
    exit 1
}
if ($warns -gt 0) { Write-Host "检查通过（$warns 项警告）。" -ForegroundColor Yellow }
else { Write-Host '检查全部通过。' -ForegroundColor Green }
exit 0
