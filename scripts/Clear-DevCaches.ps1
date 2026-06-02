[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$IncludeNuGet,
    [switch]$IncludeGradle,
    [switch]$IncludeMaven
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Invoke-ToolIfPresent {
    param(
        [string]$Command,
        [string]$TargetLabel,
        [string[]]$Arguments
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-Host "Skip: $Command not found."
        return
    }

    Write-Host "Run: $Command $($Arguments -join ' ')"
    if ($PSCmdlet.ShouldProcess($TargetLabel, "$Command $($Arguments -join ' ')")) {
        & $cmd.Source @Arguments
    }
}

Invoke-ToolIfPresent 'python' 'pip cache' @('-m', 'pip', 'cache', 'purge')
Invoke-ToolIfPresent 'npm' 'npm cache' @('cache', 'clean', '--force')

if ($IncludeNuGet) {
    Invoke-ToolIfPresent 'dotnet' 'nuget cache' @('nuget', 'locals', 'all', '--clear')
}

if ($IncludeGradle) {
    $gradleCache = Join-Path $env:USERPROFILE '.gradle\caches'
    if (Test-Path -LiteralPath $gradleCache) {
        Write-Host "Remove: $gradleCache"
        try {
            if ($PSCmdlet.ShouldProcess($gradleCache, 'Remove Gradle cache')) {
                Remove-Item -LiteralPath $gradleCache -Recurse -Force -ErrorAction Stop
            }
        } catch {
            Write-Host "Skip: failed to remove Gradle cache."
        }
    } else {
        Write-Host "Skip: Gradle cache not found."
    }
}

if ($IncludeMaven) {
    $mavenRepo = Join-Path $env:USERPROFILE '.m2\repository'
    if (Test-Path -LiteralPath $mavenRepo) {
        Write-Host "Maven cache removal is intentionally not automatic."
        Write-Host "Review and delete stale artifacts manually: $mavenRepo"
    } else {
        Write-Host "Skip: Maven repository not found."
    }
}

Write-Host "Developer cache cleanup completed."
