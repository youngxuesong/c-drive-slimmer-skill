[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$OutputDir,
    [switch]$IncludeNuGet,
    [switch]$IncludeGradle,
    [switch]$IncludeMaven
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function New-ReportOutputDir {
    param([string]$RequestedOutputDir)
    if ($RequestedOutputDir) {
        [System.IO.Directory]::CreateDirectory($RequestedOutputDir) | Out-Null
        return $RequestedOutputDir
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $env:TEMP "c-drive-slimmer-clean-dev-caches-$timestamp"
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Invoke-ToolIfPresent {
    param(
        [string]$Command,
        [string]$TargetLabel,
        [string[]]$Arguments,
        [System.Collections.Generic.List[object]]$Actions
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-Host "Skip: $Command not found."
        $Actions.Add([pscustomobject]@{
            Target = $TargetLabel
            Action = "$Command $($Arguments -join ' ')"
            Status = 'Skipped: command not found'
        }) | Out-Null
        return
    }

    Write-Host "Run: $Command $($Arguments -join ' ')"
    if ($PSCmdlet.ShouldProcess($TargetLabel, "$Command $($Arguments -join ' ')")) {
        & $cmd.Source @Arguments
        $Actions.Add([pscustomobject]@{
            Target = $TargetLabel
            Action = "$Command $($Arguments -join ' ')"
            Status = 'Attempted'
        }) | Out-Null
    }
}

$actions = [System.Collections.Generic.List[object]]::new()
$reportDir = New-ReportOutputDir $OutputDir

Invoke-ToolIfPresent 'python' 'pip cache' @('-m', 'pip', 'cache', 'purge') $actions
Invoke-ToolIfPresent 'npm' 'npm cache' @('cache', 'clean', '--force') $actions

if ($IncludeNuGet) {
    Invoke-ToolIfPresent 'dotnet' 'nuget cache' @('nuget', 'locals', 'all', '--clear') $actions
}

if ($IncludeGradle) {
    $gradleCache = Join-Path $env:USERPROFILE '.gradle\caches'
    if (Test-Path -LiteralPath $gradleCache) {
        Write-Host "Remove: $gradleCache"
        try {
            if ($PSCmdlet.ShouldProcess($gradleCache, 'Remove Gradle cache')) {
                Remove-Item -LiteralPath $gradleCache -Recurse -Force -ErrorAction Stop
                $actions.Add([pscustomobject]@{
                    Target = $gradleCache
                    Action = 'Remove Gradle cache'
                    Status = 'Attempted'
                }) | Out-Null
            }
        } catch {
            Write-Host "Skip: failed to remove Gradle cache."
            $actions.Add([pscustomobject]@{
                Target = $gradleCache
                Action = 'Remove Gradle cache'
                Status = 'Skipped: removal failed'
            }) | Out-Null
        }
    } else {
        Write-Host "Skip: Gradle cache not found."
        $actions.Add([pscustomobject]@{
            Target = $gradleCache
            Action = 'Remove Gradle cache'
            Status = 'Skipped: cache not found'
        }) | Out-Null
    }
}

if ($IncludeMaven) {
    $mavenRepo = Join-Path $env:USERPROFILE '.m2\repository'
    if (Test-Path -LiteralPath $mavenRepo) {
        Write-Host "Maven cache removal is intentionally not automatic."
        Write-Host "Review and delete stale artifacts manually: $mavenRepo"
        $actions.Add([pscustomobject]@{
            Target = $mavenRepo
            Action = 'Manual Maven cleanup review'
            Status = 'Reported only'
        }) | Out-Null
    } else {
        Write-Host "Skip: Maven repository not found."
        $actions.Add([pscustomobject]@{
            Target = $mavenRepo
            Action = 'Manual Maven cleanup review'
            Status = 'Skipped: repository not found'
        }) | Out-Null
    }
}

$summary = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('s')
    Mode = if ($WhatIfPreference) { 'WhatIf' } else { 'Execute' }
    IncludeNuGet = [bool]$IncludeNuGet
    IncludeGradle = [bool]$IncludeGradle
    IncludeMaven = [bool]$IncludeMaven
    Actions = $actions
}

$jsonPath = Join-Path $reportDir 'clear-dev-caches-report.json'
$mdPath = Join-Path $reportDir 'clear-dev-caches-report.md'
$jsonText = $summary | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($jsonPath, $jsonText, [System.Text.UTF8Encoding]::new($false))

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Developer Cache Cleanup Report')
$lines.Add('')
$lines.Add("Generated: $($summary.GeneratedAt)")
$lines.Add("Mode: $($summary.Mode)")
$lines.Add('')
$lines.Add('| Action | Target | Status |')
$lines.Add('|---|---|---|')
foreach ($item in $summary.Actions) {
    $lines.Add("| $($item.Action) | ``$($item.Target)`` | $($item.Status) |")
}
$mdText = [string]::Join([Environment]::NewLine, $lines)
[System.IO.File]::WriteAllText($mdPath, $mdText, [System.Text.UTF8Encoding]::new($false))

Write-Host "Developer cache cleanup completed."
Write-Host "Markdown report: $mdPath"
Write-Host "JSON report: $jsonPath"
