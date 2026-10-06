<#
.SYNOPSIS
  .cmd 包装器使用的启动器：运行 scripts 里的脚本，出错时只显示中文错误信息（不显示 PowerShell 错误详情）。

.EXAMPLE
  powershell -File scripts\_run.ps1 Start-All.ps1 -Port 7778 -ForceStart
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Script,
    [Parameter(ValueFromRemainingArguments = $true)][object[]]$Rest
)

$path = Join-Path $PSScriptRoot $Script
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

try {
    $cmd = Get-Command -Name $path -CommandType ExternalScript -ErrorAction Stop
    # 从命令行传入的参数是字符串数组，“-Port 7778” 这样的名字不会自动绑定，这里按目标脚本的参数手动绑定。
    $named = @{}
    $positional = New-Object System.Collections.Generic.List[object]
    $tokens = @(if ($Rest) { $Rest })
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = "$($tokens[$i])"
        $meta = $null
        if ($t -match '^-([A-Za-z][\w]*)(?::(.*))?$') {
            $n = $Matches[1]; $inline = $Matches[2]
            $meta = $cmd.Parameters.Values | Where-Object { $_.Name -eq $n -or $_.Aliases -contains $n } | Select-Object -First 1
        }
        if (-not $meta) { $positional.Add($tokens[$i]); continue }
        if ($meta.SwitchParameter) {
            $named[$meta.Name] = if ($inline) { $inline -notmatch '^(\$?false|0)$' } else { $true }
        } elseif ($null -ne $inline -and $inline -ne '') {
            $named[$meta.Name] = $inline
        } elseif ($i + 1 -lt $tokens.Count) {
            $named[$meta.Name] = $tokens[++$i]
        } else {
            throw "参数 -$($meta.Name) 缺少值。"
        }
    }
    $posArgs = $positional.ToArray()
    & $path @named @posArgs
    if ($Script -eq 'Test-Prerequisites.ps1') { exit $LASTEXITCODE }
    exit 0
} catch {
    Write-Host ''
    Write-Host "[出错] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
