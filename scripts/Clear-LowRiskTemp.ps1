[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$OutputDir,
    [switch]$IncludeWindowsTemp,
    [switch]$SkipRecycleBin,
    [int]$LimitItems = 0
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

function New-ReportOutputDir {
    param([string]$RequestedOutputDir)
    if ($RequestedOutputDir) {
        [System.IO.Directory]::CreateDirectory($RequestedOutputDir) | Out-Null
        return $RequestedOutputDir
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $env:TEMP "c-drive-slimmer-clean-low-risk-$timestamp"
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Clear-DirectoryContents {
    param(
        [string]$Path,
        [System.Collections.Generic.List[object]]$Actions
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $processed = 0
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($LimitItems -gt 0 -and $processed -ge $LimitItems) { return }
            try {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove temp item')) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $Actions.Add([pscustomobject]@{
                        Target = $_.FullName
                        Action = 'Remove temp item'
                        Status = 'Attempted'
                    }) | Out-Null
                }
                $processed++
            } catch {}
        }
}

$freedEstimate = 0L
$actions = [System.Collections.Generic.List[object]]::new()
$reportDir = New-ReportOutputDir $OutputDir

$userTemp = $env:TEMP
$freedEstimate += Get-DirectoryBytes $userTemp
Clear-DirectoryContents $userTemp $actions

if (-not $SkipRecycleBin) {
    try {
        if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear contents')) {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
            $actions.Add([pscustomobject]@{
                Target = 'Recycle Bin'
                Action = 'Clear contents'
                Status = 'Attempted'
            }) | Out-Null
        }
    } catch {}
}

if ($IncludeWindowsTemp) {
    $windowsTemp = Join-Path $env:SystemRoot 'Temp'
    $freedEstimate += Get-DirectoryBytes $windowsTemp
    Clear-DirectoryContents $windowsTemp $actions
}

$summary = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('s')
    Mode = if ($WhatIfPreference) { 'WhatIf' } else { 'Execute' }
    IncludeWindowsTemp = [bool]$IncludeWindowsTemp
    SkipRecycleBin = [bool]$SkipRecycleBin
    EstimatedAttemptedBytes = $freedEstimate
    EstimatedAttempted = Format-Bytes $freedEstimate
    Actions = $actions
}

$jsonPath = Join-Path $reportDir 'clear-low-risk-temp-report.json'
$mdPath = Join-Path $reportDir 'clear-low-risk-temp-report.md'
$jsonText = $summary | ConvertTo-Json -Depth 5
try {
    [System.IO.File]::WriteAllText($jsonPath, $jsonText, [System.Text.UTF8Encoding]::new($false))
} catch {
    Write-Warning "Failed to write JSON report: $($_.Exception.Message)"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Low Risk Temp Cleanup Report')
$lines.Add('')
$lines.Add("Generated: $($summary.GeneratedAt)")
$lines.Add("Mode: $($summary.Mode)")
$lines.Add("Estimated attempted cleanup: $($summary.EstimatedAttempted)")
$lines.Add('')
$lines.Add('| Action | Target | Status |')
$lines.Add('|---|---|---|')
foreach ($item in $summary.Actions) {
    $lines.Add("| $($item.Action) | ``$($item.Target)`` | $($item.Status) |")
}
$mdText = [string]::Join([Environment]::NewLine, $lines)
try {
    [System.IO.File]::WriteAllText($mdPath, $mdText, [System.Text.UTF8Encoding]::new($false))
} catch {
    Write-Warning "Failed to write Markdown report: $($_.Exception.Message)"
}

Write-Host "Low-risk temp cleanup completed."
Write-Host "Estimated attempted cleanup: $(Format-Bytes $freedEstimate)"
Write-Host "Markdown report: $mdPath"
Write-Host "JSON report: $jsonPath"
