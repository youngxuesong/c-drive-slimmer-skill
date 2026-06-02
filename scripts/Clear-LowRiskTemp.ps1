[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$IncludeWindowsTemp,
    [switch]$SkipRecycleBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Get-DirectoryBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0L }
    $sum = 0L
    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { $sum += $_.Length }
    } catch {}
    return $sum
}

function Format-Bytes {
    param([long]$Bytes)
    $value = [double]$Bytes
    foreach ($unit in @('B','KB','MB','GB','TB')) {
        if ($value -lt 1024 -or $unit -eq 'TB') { return ('{0:N2} {1}' -f $value, $unit) }
        $value = $value / 1024
    }
}

function Clear-DirectoryContents {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove temp item')) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                }
            } catch {}
        }
}

$freedEstimate = 0L

$userTemp = $env:TEMP
$freedEstimate += Get-DirectoryBytes $userTemp
Clear-DirectoryContents $userTemp

if (-not $SkipRecycleBin) {
    try {
        if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear contents')) {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}
}

if ($IncludeWindowsTemp) {
    $windowsTemp = Join-Path $env:SystemRoot 'Temp'
    $freedEstimate += Get-DirectoryBytes $windowsTemp
    Clear-DirectoryContents $windowsTemp
}

Write-Host "Low-risk temp cleanup completed."
Write-Host "Estimated attempted cleanup: $(Format-Bytes $freedEstimate)"
