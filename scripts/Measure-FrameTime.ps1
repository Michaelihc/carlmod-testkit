<#
.SYNOPSIS
  用 SurfaceFlinger TimeStats 测量模拟器上客户端的帧率和帧间隔。

.DESCRIPTION
  开启并清空 “dumpsys SurfaceFlinger --timestats”，等待 -DurationSec 秒，读取游戏 SurfaceView 图层的统计：
    - AvgFps（呈现帧数 / 实际秒数）和图层自己的 averageFPS
    - 由 present2present 直方图得到的帧间隔 P50/P95/P99
    - 帧间隔超过 -LongFrameMs 的比例
  结果打印出来，并保存为 .runtime\captures\frametime-<Name>-<时间>.json。

  客户端经过 ARM64 二进制转译运行，数值不等于手机上的数值，只能用来对比不同版本。对比时保持同一 AVD、
  分辨率和场景，玩家站着不动（例如 forcestart 后的 D 级人员出生房间）。屏幕刷新率 60 Hz，所以帧间隔
  集中在 16.7 ms 的倍数附近。

.PARAMETER Name         输出文件名里的标签。
.PARAMETER DurationSec  采样秒数（默认 20）。
.PARAMETER WarmupSec    采样前等待的秒数（默认 0）。
.PARAMETER Serial       adb 序列号，默认取配置 Serial。
.PARAMETER Second       使用第二个模拟器（配置 SecondSerial）。
#>
[CmdletBinding()]
param(
    [string]$Name = 'run',
    [int]$DurationSec = 20,
    [int]$WarmupSec = 0,
    [string]$Serial,
    [int]$ConsolePort,
    [switch]$Second,
    [double]$LongFrameMs = 33.4
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Serial -and -not $ConsolePort -and $Second) { $Serial = (Get-KitConfig).SecondSerial }
$serial = Resolve-EmulatorSerial $Serial $ConsolePort
Assert-EmulatorOnline $serial
$Package = $script:ClientPackage
if (-not (Test-ClientRunning $serial)) { Fail '客户端没有在运行。' '先启动客户端并进入游戏场景。' }

# 后台的模拟器窗口会被 Windows 节能限速；每次测量前确保已关闭（已关闭时无副作用）。
if (-not (Disable-EmulatorPowerThrottling (Get-EmulatorConsolePort $serial))) { Write-Warning "找不到 $serial 的 qemu 进程，未关闭节能限速。" }

if ($WarmupSec -gt 0) { Write-Host "预热 $WarmupSec 秒"; Start-Sleep -Seconds $WarmupSec }

Invoke-Adb $serial shell dumpsys SurfaceFlinger --timestats -enable | Out-Null
Invoke-Adb $serial shell dumpsys SurfaceFlinger --timestats -clear | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
Write-Step "采样 $DurationSec 秒 ..."
Start-Sleep -Seconds $DurationSec
$dump = @(Invoke-Adb $serial shell dumpsys SurfaceFlinger --timestats -dump -maxlayers 30)
$elapsed = $sw.Elapsed.TotalSeconds
Invoke-Adb $serial shell dumpsys SurfaceFlinger --timestats -disable | Out-Null

# 按图层拆分，取游戏的 SurfaceView 图层。
$text = $dump -join "`n"
$blocks = [regex]::Split($text, '(?m)^(?=layerName = )')
$block = $blocks | Where-Object { $_ -match "(?m)^layerName = .*SurfaceView\[$([regex]::Escape($Package))/" } | Select-Object -First 1
if (-not $block) {
    $seen = ([regex]::Matches($text, '(?m)^layerName = (.*)$') | ForEach-Object { $_.Groups[1].Value }) -join '; '
    Fail "TimeStats 里没有 $Package 的图层。游戏在渲染吗？看到的图层：$seen" '确认游戏在前台并已进入场景。'
}

function Get-Num([string]$Block, [string]$Key) {
    $m = [regex]::Match($Block, "(?m)^$Key = ([\d.]+)")
    if ($m.Success) { [double]$m.Groups[1].Value } else { $null }
}
$totalFrames = Get-Num $block 'totalFrames'
$layerAvgFps = Get-Num $block 'averageFPS'
$hm = [regex]::Match($block, '(?m)^present2present histogram is as below:\s*\n(.+)$')
if (-not $hm.Success) { Fail 'TimeStats 输出里没有 present2present 直方图。' '确认模拟器使用 API 36 镜像。' }
$buckets = [regex]::Matches($hm.Groups[1].Value, '(\d+)ms=(\d+)') | ForEach-Object {
    [pscustomobject]@{ Ms = [int]$_.Groups[1].Value; Count = [int]$_.Groups[2].Value }
}
$n = ($buckets | Measure-Object Count -Sum).Sum
if ($n -lt 20) { Fail "直方图里只有 $n 帧。" '游戏是否暂停或在后台？让游戏保持在前台再测。' }

function Get-HistPercentile($Buckets, [int]$Total, [double]$q) {
    $target = [Math]::Ceiling($q * $Total); $acc = 0
    foreach ($b in $Buckets) { $acc += $b.Count; if ($acc -ge $target) { return $b.Ms } }
    return ($Buckets | Select-Object -Last 1).Ms
}
$over = ($buckets | Where-Object { $_.Ms -ge [Math]::Ceiling($LongFrameMs) } | Measure-Object Count -Sum).Sum
$res = [ordered]@{
    Name           = $Name
    DurationSec    = [Math]::Round($elapsed, 1)
    Frames         = [int]$totalFrames
    AvgFps         = [Math]::Round($totalFrames / $elapsed, 1)
    LayerAvgFps    = $layerAvgFps
    AvgFrameMs     = [Math]::Round(1000 * $elapsed / $totalFrames, 2)
    P50Ms          = Get-HistPercentile $buckets $n 0.50
    P95Ms          = Get-HistPercentile $buckets $n 0.95
    P99Ms          = Get-HistPercentile $buckets $n 0.99
    FramesOverLong = [int]$over
    PctOverLong    = [Math]::Round(100.0 * $over / $n, 1)
    LongFrameMs    = $LongFrameMs
    Histogram      = ($buckets | Where-Object { $_.Count -gt 0 } | ForEach-Object { "$($_.Ms)ms=$($_.Count)" }) -join ' '
}
$capDir = Join-Path $script:Runtime 'captures'
New-Item -ItemType Directory -Force $capDir | Out-Null
$json = Join-Path $capDir ('frametime-{0}-{1:yyyyMMdd-HHmmss}.json' -f $Name, (Get-Date))
Write-Utf8NoBom $json @(([pscustomobject]$res | ConvertTo-Json))
[pscustomobject]$res | Format-List | Out-Host
Write-Ok "已保存 $json"
