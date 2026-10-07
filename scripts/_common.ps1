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

function Resolve-KitPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $script:KitRoot $Path)
}

# 默认值；testkit.config.psd1（可选，从 testkit.config.example.psd1 复制）中的同名键会覆盖它们。
function Get-KitConfig {
    if ($script:KitConfigCache) { return $script:KitConfigCache }
    $cfg = @{
        Port                 = 7777
        ServerVersion        = ''
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
    # ServerZip 可以是一个或多个路径。相对路径以本工具所在文件夹为起点。
    $cfg.ServerZip = @(@($cfg.ServerZip) | Where-Object { $_ } | ForEach-Object { Resolve-KitPath $_ })
    foreach ($k in 'ServerFolder', 'Apk', 'AndroidSdk') {
        if ($cfg[$k]) { $cfg[$k] = Resolve-KitPath $cfg[$k] }
    }
    $cfg.ServerVersion = "$($cfg.ServerVersion)".Trim()
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

function Find-ApkFile { Find-InputFile 'Apk' @('*.apk', '*.apk.*') '客户端 APK' }

# 服务端 ZIP 列表：配置的 ServerZip（一个或多个），否则 inputs 文件夹里的全部 *.zip（每个版本一个）。
function Find-ServerZips {
    $cfg = Get-KitConfig
    if ($cfg.ServerZip) {
        return @(foreach ($z in $cfg.ServerZip) {
            if (-not (Test-Path -LiteralPath $z -PathType Leaf)) {
                Fail "testkit.config.psd1 中 ServerZip 指向的服务端 ZIP 不存在：$z" '改正路径，或删掉这一项并把 ZIP 放进 inputs 文件夹。'
            }
            (Resolve-Path -LiteralPath $z).ProviderPath
        })
    }
    $inputs = Join-Path $script:KitRoot 'inputs'
    return @(Get-ChildItem -LiteralPath $inputs -Filter '*.zip' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ieq '.zip' } | Sort-Object Name | ForEach-Object FullName)
}

# ---------------------------------------------------------------- 服务端版本 / 客户端版本

if (-not $global:CarlModTestKitVersionCache) { $global:CarlModTestKitVersionCache = @{} }

# 按文件路径、大小和修改时间缓存计算结果（菜单里反复显示版本时不重复读取文件）。
function Get-CachedValue([IO.FileInfo]$CacheFile, [scriptblock]$Compute) {
    $key = '{0}|{1}|{2}' -f $CacheFile.FullName, $CacheFile.Length, $CacheFile.LastWriteTimeUtc.Ticks
    if (-not $global:CarlModTestKitVersionCache.ContainsKey($key)) { $global:CarlModTestKitVersionCache[$key] = & $Compute }
    return $global:CarlModTestKitVersionCache[$key]
}

function Open-ZipArchive([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    return [IO.Compression.ZipFile]::OpenRead($Path)
}

function Read-ZipEntryBytes($Entry) {
    $ms = New-Object IO.MemoryStream
    $s = $Entry.Open()
    try { $s.CopyTo($ms) } finally { $s.Dispose() }
    return ,$ms.ToArray()
}

# 从 Assembly-CSharp.dll 的内容识别服务端版本。版本取自 GameCore.Version 静态构造函数里赋给 VersionString 的字符串
# （只读取 IL，不运行游戏代码）；Assembly-CSharp 里有死斗模块的成员（PlayerStats.DmCleanup）时是 0.0.4 的死斗模块版。
# 返回 Version（如 0.0.5，读不到为 $null）、Deathmatch、Key（文件夹名和 ServerVersion 用，如 0.0.5、0.0.4-dm）、Label（显示用）。
function Get-ServerBuildInfo([byte[]]$AssemblyBytes) {
    $version = $null
    try {
        $type = [Reflection.Assembly]::Load($AssemblyBytes).GetType('GameCore.Version', $false)
        $field = if ($type) { $type.GetField('VersionString') }
        $il = if ($field -and $type.TypeInitializer) { $type.TypeInitializer.GetMethodBody().GetILAsByteArray() }
        for ($i = 0; $il -and $i -le $il.Length - 10; $i++) {
            # ldstr <字符串> 后面紧跟 stsfld VersionString
            if ($il[$i] -eq 0x72 -and $il[$i + 5] -eq 0x80 -and [BitConverter]::ToInt32($il, $i + 6) -eq $field.MetadataToken) {
                $version = $type.Module.ResolveString([BitConverter]::ToInt32($il, $i + 1))
                break
            }
        }
    } catch { $version = $null }
    if ($version -notmatch '^[\w.\-]+$') { $version = $null }
    $dm = $false
    if ($AssemblyBytes.Length -gt 0) { $dm = [Text.Encoding]::GetEncoding(28591).GetString($AssemblyBytes).Contains("`0DmCleanup`0") }
    $key = if (-not $version) { 'unknown' } elseif ($dm) { "$version-dm" } else { $version }
    $label = if (-not $version) { '未知版本' } elseif ($dm) { "$version 死斗模块版" } else { $version }
    return [pscustomobject]@{ Version = $version; Deathmatch = $dm; Key = $key; Label = $label }
}

# 服务端文件夹（含 Carl Mod.exe）的版本；不是服务端文件夹时返回 $null。
function Get-ServerDirBuild([string]$ServerDir) {
    $file = Get-Item -LiteralPath (Join-Path $ServerDir 'Carl Mod_Data\Managed\Assembly-CSharp.dll') -ErrorAction SilentlyContinue
    if (-not $file) { return $null }
    return (Get-CachedValue $file { Get-ServerBuildInfo ([IO.File]::ReadAllBytes($file.FullName)) })
}

# 服务端 ZIP 的版本（只读取 ZIP 里的 Assembly-CSharp.dll，不解压）；ZIP 里没有 Carl Mod.exe 时返回 $null。
# 条目名可能用反斜杠分隔，也可能有一层顶层文件夹（如 “Carl Mod Server - 0.0.5\”）。
function Get-ZipServerBuild([string]$Zip) {
    $file = Get-Item -LiteralPath $Zip
    return (Get-CachedValue $file {
        $archive = Open-ZipArchive $file.FullName
        try {
            $entries = @{}
            foreach ($e in $archive.Entries) { $entries[$e.FullName.Replace('\', '/')] = $e }
            $exe = @($entries.Keys | Where-Object { $_ -eq 'Carl Mod.exe' -or $_.EndsWith('/Carl Mod.exe') } | Sort-Object Length)
            if ($exe.Count -eq 0) { return $null }
            $root = $exe[0].Substring(0, $exe[0].Length - 'Carl Mod.exe'.Length)
            $dll = $entries["${root}Carl Mod_Data/Managed/Assembly-CSharp.dll"]
            if (-not $dll) { return (Get-ServerBuildInfo ([byte[]]@())) }
            return (Get-ServerBuildInfo (Read-ZipEntryBytes $dll))
        } finally { $archive.Dispose() }
    })
}

# 读取二进制 AndroidManifest.xml 中 manifest 元素的 android:versionName（字符串值）；读不到返回 $null。
function Read-ManifestVersionName([byte[]]$b) {
    $pool = 8
    if ($b.Length -lt 36 -or [BitConverter]::ToUInt16($b, $pool) -ne 1) { return $null }
    $poolHeader = [BitConverter]::ToUInt16($b, $pool + 2)
    $count = [BitConverter]::ToInt32($b, $pool + 8)
    $utf8 = ([BitConverter]::ToUInt32($b, $pool + 16) -band 0x100) -ne 0
    $stringsStart = $pool + [BitConverter]::ToInt32($b, $pool + 20)
    $getString = {
        param([int]$Index)
        if ($Index -lt 0 -or $Index -ge $count) { return $null }
        $p = $stringsStart + [BitConverter]::ToInt32($b, $pool + $poolHeader + 4 * $Index)
        if ($utf8) {
            $p += $(if ($b[$p] -band 0x80) { 2 } else { 1 })
            $n = [int]$b[$p]
            if ($n -band 0x80) { $n = (($n -band 0x7F) -shl 8) -bor $b[$p + 1]; $p += 2 } else { $p += 1 }
            return [Text.Encoding]::UTF8.GetString($b, $p, $n)
        }
        $n = [int][BitConverter]::ToUInt16($b, $p); $p += 2
        if ($n -band 0x8000) { $n = (($n -band 0x7FFF) -shl 16) -bor [BitConverter]::ToUInt16($b, $p); $p += 2 }
        return [Text.Encoding]::Unicode.GetString($b, $p, 2 * $n)
    }
    $pos = $pool + [BitConverter]::ToInt32($b, $pool + 4)
    while ($pos + 30 -le $b.Length) {
        $size = [BitConverter]::ToInt32($b, $pos + 4)
        if ($size -le 0) { return $null }
        if ([BitConverter]::ToUInt16($b, $pos) -eq 0x0102) {
            # 第一个元素就是 manifest：属性从 $pos + 16 + attributeStart 开始，每个 attributeSize 字节。
            $attrStart = [BitConverter]::ToUInt16($b, $pos + 24)
            $attrSize = [BitConverter]::ToUInt16($b, $pos + 26)
            $attrCount = [BitConverter]::ToUInt16($b, $pos + 28)
            for ($k = 0; $k -lt $attrCount; $k++) {
                $a = $pos + 16 + $attrStart + $k * $attrSize
                if ((& $getString ([BitConverter]::ToInt32($b, $a + 4))) -eq 'versionName') {
                    return (& $getString ([BitConverter]::ToInt32($b, $a + 8)))
                }
            }
            return $null
        }
        $pos += $size
    }
    return $null
}

# APK 的版本（AndroidManifest.xml 的 versionName，读不到时取文件名里的 x.y.z），都没有时返回 $null。
function Get-ApkVersion([string]$Apk) {
    $file = Get-Item -LiteralPath $Apk
    return (Get-CachedValue $file {
        $v = $null
        try {
            $archive = Open-ZipArchive $file.FullName
            try {
                $entry = $archive.GetEntry('AndroidManifest.xml')
                if ($entry) { $v = Read-ManifestVersionName (Read-ZipEntryBytes $entry) }
            } finally { $archive.Dispose() }
        } catch { $v = $null }
        if (-not $v -and $file.Name -match '(\d+\.\d+\.\d+)') { $v = $Matches[1] }
        $v
    })
}

# inputs 里（或配置的）APK 的路径和版本；找不到或出错时返回 $null，不抛错。
function Get-ApkInfo {
    try {
        $apk = Find-ApkFile
        if ($apk) { return [pscustomobject]@{ Path = $apk; Version = (Get-ApkVersion $apk) } }
    } catch { }
    return $null
}

# 模拟器里已安装的客户端版本（versionName），读不到返回 $null。
function Get-InstalledClientVersion([string]$Serial) {
    foreach ($line in (Invoke-Adb $Serial shell dumpsys package $script:ClientPackage)) {
        if ($line -match 'versionName=(\S+)') { return $Matches[1] }
    }
    return $null
}

$script:VersionMatchNote = '客户端和服务端的版本必须相同，否则服务器会以版本不符拒绝连接（例如 0.0.4 的客户端不能加入 0.0.5 的服务器）。'

# ---------------------------------------------------------------- 原始服务端（每个版本一个）

# 可用的原始服务端（只读，测试服务器从它们复制），按版本排序。来源依次为：配置的 ServerFolder、
# Import-Server.ps1 解压的 .runtime\server-original-<版本>、旧版本工具解压的 .runtime\server-original。
# 同一版本只取第一个。
function Get-PristineServers {
    $cfg = Get-KitConfig
    $dirs = New-Object System.Collections.Generic.List[string]
    if ($cfg.ServerFolder) { $dirs.Add([IO.Path]::GetFullPath($cfg.ServerFolder)) }
    $found = @(Get-ChildItem -LiteralPath $script:Runtime -Directory -Filter 'server-original*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^server-original(-.+)?$' } | Sort-Object { $_.Name -eq 'server-original' }, Name)
    foreach ($d in $found) { $dirs.Add($d.FullName) }
    $list = @()
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'Carl Mod.exe'))) { continue }
        $b = Get-ServerDirBuild $dir
        if (-not $b) { $b = Get-ServerBuildInfo ([byte[]]@()) }
        if ($list | Where-Object { $_.Key -eq $b.Key }) { continue }
        $list += [pscustomobject]@{
            Key = $b.Key; Label = $b.Label; Version = $b.Version; Deathmatch = $b.Deathmatch; Dir = $dir
            FromConfig = [bool]($cfg.ServerFolder -and $dir -eq [IO.Path]::GetFullPath($cfg.ServerFolder))
        }
    }
    return @($list | Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } }, Key)
}

# 选出要使用的原始服务端：参数 -ServerVersion，否则配置 ServerVersion；都没有时，只有一个版本就用它，
# 有多个版本时用和客户端 APK 版本相同的那个。可以写版本号（0.0.5）或文件夹用的键（0.0.4-dm）。
function Select-PristineServer([string]$ServerVersion) {
    $cfg = Get-KitConfig
    $all = @(Get-PristineServers)
    if ($all.Count -eq 0) {
        if ($cfg.ServerFolder) { Fail "ServerFolder 指向的文件夹里没有 Carl Mod.exe：$($cfg.ServerFolder)" '把 ServerFolder 改成包含 Carl Mod.exe 的文件夹。' }
        Fail '还没有导入服务端。' '把 Carl Mod 服务端 ZIP 放进 inputs 文件夹，然后运行 setup.cmd（或 scripts\Import-Server.ps1）。'
    }
    $names = ($all | ForEach-Object Label) -join '、'
    $want = if ($ServerVersion) { $ServerVersion.Trim() } else { $cfg.ServerVersion }
    if ($want) {
        $hit = @($all | Where-Object { $_.Key -eq $want })
        if ($hit.Count -eq 0) { $hit = @($all | Where-Object { $_.Version -eq $want }) }
        if ($hit.Count -eq 1) { return $hit[0] }
        if ($hit.Count -gt 1) { Fail "有多个 $want 版本的服务端：$names。" "改用 $(($hit | ForEach-Object Key) -join ' 或 ') 指定。" }
        Fail "没有 $want 版本的服务端（已导入：$names）。" '把该版本的服务端 ZIP 放进 inputs 文件夹后运行 scripts\Import-Server.ps1，或把 ServerVersion 改成已导入的版本。'
    }
    if ($all.Count -eq 1) { return $all[0] }
    $apk = Get-ApkInfo
    if ($apk -and $apk.Version) {
        $hit = @($all | Where-Object { $_.Version -eq $apk.Version })
        if ($hit.Count -eq 1) { return $hit[0] }
    }
    $last = $all[$all.Count - 1].Key
    Fail "已导入多个版本的服务端（$names），没有指定使用哪一个。" "在 testkit.config.psd1 里设置 ServerVersion（例如 ServerVersion = '$last'），或运行脚本时加 -ServerVersion $last。"
}

# ---------------------------------------------------------------- 测试服务器

# 测试服务器文件夹：每个端口、每个服务端版本一个（.runtime\server-<端口>-<版本>），切换版本时互不影响。
function Get-ServerDir([int]$Port, $Build) { Join-Path $script:Runtime "server-$Port-$($Build.Key)" }
function Get-ServerStateFile([int]$Port) { Join-Path $script:Runtime "state\server-$Port.json" }

# 读取状态文件（无 BOM 的 UTF-8；路径里可能有中文，Windows PowerShell 5.1 的 Get-Content 会读错）。
function Read-StateFile([string]$File) {
    return ([IO.File]::ReadAllText($File, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

# 返回本工具为该端口启动、且仍在运行的服务端进程信息；没有则返回 $null。
function Get-RunningServer([int]$Port) {
    $file = Get-ServerStateFile $Port
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $state = Read-StateFile $file
    $info = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$state.Pid)" -ErrorAction SilentlyContinue
    if (-not $info -or -not (Test-IsTestServerProcess $info $Port)) { return $null }
    return $state
}

function Test-IsTestServerProcess($Info, [int]$Port) {
    return ($Info.Name -eq 'Carl Mod.exe' -and $Info.CommandLine -match "-port$Port(\s|`"|$)")
}

# 确保测试服务器文件夹存在（从 $Build 的原始服务端复制）并含有 hoster_policy.txt（gamedir_for_configs: true）。
function Initialize-TestServerDir([string]$ServerDir, $Build) {
    $ServerDir = [IO.Path]::GetFullPath($ServerDir)
    if (-not (Test-Path -LiteralPath (Join-Path $ServerDir 'Carl Mod.exe'))) {
        $source = $Build.Dir
        if ([IO.Path]::GetFullPath($source).TrimEnd('\') -ieq $ServerDir.TrimEnd('\')) {
            Fail '测试服务器文件夹不能和原始服务端是同一个文件夹。' '去掉 -ServerDir，使用默认的 .runtime\server-<端口>-<版本>。'
        }
        Write-Step "复制原始服务端 $($Build.Label) 到 $ServerDir（约 0.7 GB，只需一次）"
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

# 脚本要操作的测试服务器：给了 -ServerVersion 时用该版本；否则该端口有运行中的测试服务器时用它；
# 再否则用选出的版本（见 Select-PristineServer）。返回 Build（版本信息）、ServerDir 和 Running。
function Resolve-TestServer([int]$Port, [string]$ServerVersion) {
    if (-not $ServerVersion) {
        $state = Get-RunningServer $Port
        if ($state) {
            $b = Get-ServerDirBuild $state.ServerDir
            if (-not $b) { $b = Get-ServerBuildInfo ([byte[]]@()) }
            return [pscustomobject]@{ Build = $b; ServerDir = $state.ServerDir; Running = $true }
        }
    }
    $build = Select-PristineServer $ServerVersion
    return [pscustomobject]@{ Build = $build; ServerDir = (Get-ServerDir $Port $build); Running = [bool](Get-RunningServer $Port) }
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
