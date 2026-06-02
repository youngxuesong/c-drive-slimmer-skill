param(
    [string]$Drive = 'C:',
    [string]$OutputDir,
    [int]$Top = 30,
    [switch]$IncludeUserProfiles,
    [switch]$Quick,
    [switch]$Deep,
    [switch]$AnalyzeDism,
    [string[]]$LargeFileRoots,
    [int]$SizeTimeoutSeconds = 45,
    [int]$LargeFileMinimumMB = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Format-Bytes {
    param([Nullable[long]]$Bytes)
    if ($null -eq $Bytes) { return 'n/a' }
    $value = [double]$Bytes
    foreach ($unit in @('B','KB','MB','GB','TB')) {
        if ($value -lt 1024 -or $unit -eq 'TB') { return ('{0:N2} {1}' -f $value, $unit) }
        $value = $value / 1024
    }
}

function Format-MarkdownCell {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = $text.Replace('|', '\|')
    $text = $text -replace '\r?\n', ' '
    return $text.Trim()
}

function Format-MarkdownCodeCell {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    $text = Format-MarkdownCell $Value
    return "``$text``"
}

function Get-DirectorySize {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 45,
        [int]$MaxFiles = 250000
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sum = 0L
    $count = 0
    $timedOut = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($file in Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue) {
            $sum += $file.Length
            $count++
            if ($count -ge $MaxFiles -or $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                break
            }
        }
    } catch {}
    [pscustomobject]@{
        Bytes = $sum
        TimedOut = $timedOut
        FilesScanned = $count
    }
}

function Add-Candidate {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Name,
        [string]$Path,
        [string]$Risk,
        [string]$Cleanup,
        [string]$Notes,
        [string]$Category = 'Cleanup'
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $result = Get-DirectorySize -Path $Path -TimeoutSeconds $SizeTimeoutSeconds
    if ($null -ne $result -and $result.Bytes -gt 0) {
        $List.Add([pscustomobject]@{
            Name = $Name
            Path = $Path
            Bytes = [long]$result.Bytes
            Size = Format-Bytes ([long]$result.Bytes)
            Risk = $Risk
            Category = $Category
            Cleanup = $Cleanup
            Notes = $Notes
            TimedOut = [bool]$result.TimedOut
            FilesScanned = [int]$result.FilesScanned
        }) | Out-Null
    }
}

function Add-FileCandidate {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Name,
        [string]$Path,
        [string]$Risk,
        [string]$Cleanup,
        [string]$Notes,
        [string]$Category = 'System strategy'
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $List.Add([pscustomobject]@{
            Name = $Name
            Path = $Path
            Bytes = [long]$item.Length
            Size = Format-Bytes ([long]$item.Length)
            Risk = $Risk
            Category = $Category
            Cleanup = $Cleanup
            Notes = $Notes
            TimedOut = $false
            FilesScanned = 1
        }) | Out-Null
    } catch {}
}

function Get-LargeFiles {
    param(
        [string[]]$Roots,
        [long]$MinimumBytes,
        [int]$Limit
    )
    $results = @()
    foreach ($root in ($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        try {
            $results += Get-ChildItem -LiteralPath $root -Force -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -ge $MinimumBytes } |
                Select-Object FullName, Length, LastWriteTime
        } catch {}
    }
    $results | Sort-Object Length -Descending | Select-Object -First $Limit
}

function Get-DismComponentStoreSummary {
    $output = & DISM /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $text = ($output | Out-String).Trim()
    $recommended = $text -match '(?m)推荐使用组件存储清理\s*:\s*是|Component Store Cleanup Recommended\s*:\s*Yes'
    [pscustomobject]@{
        Recommended = $recommended
        Output = $text
    }
}

function Get-ExecutablePathFromCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $trimmed = $Command.Trim()
    if ($trimmed -match '^"([^"]+)"') { return $matches[1] }
    if ($trimmed -match '^([A-Za-z]:\\[^\s]+?\.exe)\b') { return $matches[1] }
    return $null
}

function Get-OrphanedStartupEntries {
    $entries = @()
    try {
        $entries = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    } catch {}

    $entries |
        ForEach-Object {
            $exePath = Get-ExecutablePathFromCommand $_.Command
            if ($exePath -and -not (Test-Path -LiteralPath $exePath)) {
                [pscustomobject]@{
                    Name = $_.Name
                    Command = $_.Command
                    Location = $_.Location
                    User = $_.User
                    ExecutablePath = $exePath
                }
            }
        }
}

function Get-OrphanedServices {
    $services = @()
    try {
        $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    } catch {}

    $services |
        ForEach-Object {
            $exePath = Get-ExecutablePathFromCommand $_.PathName
            if ($exePath -and -not (Test-Path -LiteralPath $exePath)) {
                [pscustomobject]@{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    State = $_.State
                    StartMode = $_.StartMode
                    PathName = $_.PathName
                    ExecutablePath = $exePath
                }
            }
        }
}

$isQuickMode = -not $Deep
if ($Quick) { $isQuickMode = $true }

if (-not $OutputDir) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputDir = Join-Path $env:TEMP "c-drive-slimmer-$timestamp"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$driveInfo = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
if ($null -eq $driveInfo) { throw "Drive $Drive was not found." }

$candidates = [System.Collections.Generic.List[object]]::new()

Add-Candidate $candidates 'User temp' $env:TEMP 'Low' 'Remove temp contents; ignore locked files.' 'Usually safe; apps may hold active temp files.' 'Immediate cleanup'
Add-Candidate $candidates 'Windows temp' "$Drive\Windows\Temp" 'Low' 'Clean from elevated shell; ignore locked files.' 'Prefer after closing apps or rebooting.' 'Immediate cleanup'
Add-Candidate $candidates 'Windows update download cache' "$Drive\Windows\SoftwareDistribution\Download" 'Low' 'Use Windows Update cleanup or stop update service first.' 'Windows can redownload needed updates.' 'Immediate cleanup'
Add-Candidate $candidates 'Delivery Optimization cache' "$Drive\Windows\SoftwareDistribution\DeliveryOptimization" 'Low' 'Use Settings > Storage > Temporary files.' 'May be managed by Windows.' 'Immediate cleanup'
Add-Candidate $candidates 'WER report archive' "$Drive\ProgramData\Microsoft\Windows\WER" 'Low' 'Use Disk Cleanup / Storage Sense.' 'Crash reports and diagnostics.' 'Immediate cleanup'
Add-Candidate $candidates 'NVIDIA installer cache' "$Drive\NVIDIA" 'Medium' 'Delete only if no longer needed for driver rollback/install.' 'Common driver extraction folder.' 'User review'
Add-Candidate $candidates 'Node npm cache' (Join-Path $env:LOCALAPPDATA 'npm-cache') 'Medium' 'Run npm cache clean --force.' 'Can be redownloaded; may slow next install.' 'Developer cache'
Add-Candidate $candidates 'pip cache' (Join-Path $env:LOCALAPPDATA 'pip\Cache') 'Medium' 'Run python -m pip cache purge.' 'Can be redownloaded.' 'Developer cache'
Add-Candidate $candidates 'NuGet cache' (Join-Path $env:USERPROFILE '.nuget\packages') 'Medium' 'Use dotnet nuget locals all --clear if acceptable.' 'Will force package restore later.' 'Developer cache'
Add-Candidate $candidates 'Gradle cache' (Join-Path $env:USERPROFILE '.gradle\caches') 'Medium' 'Delete old caches or run Gradle cleanup.' 'Will force dependency downloads later.' 'Developer cache'
Add-Candidate $candidates 'Maven repository cache' (Join-Path $env:USERPROFILE '.m2\repository') 'Medium' 'Delete selected stale artifacts only.' 'May be large; required for Java builds.' 'Developer cache'

Add-Candidate $candidates 'Recycle Bin' "$Drive\`$Recycle.Bin" 'Low' 'Run Clear-RecycleBin -Force after confirming.' 'Usually safe after user review.' 'Immediate cleanup'
Add-Candidate $candidates 'Windows.old' "$Drive\Windows.old" 'Medium' 'Use Storage Sense / Disk Cleanup, not manual deletion.' 'Removes old Windows rollback files.' 'Windows cleanup'
Add-FileCandidate $candidates 'Hibernation file' "$Drive\hiberfil.sys" 'High' 'Run powercfg /h off only if hibernate/Fast Startup are not needed.' 'Reclaims space immediately but disables hibernation.' 'System strategy'
Add-FileCandidate $candidates 'Page file' "$Drive\pagefile.sys" 'High' 'Do not delete manually; adjust virtual memory only with user intent.' 'Large but important for stability.' 'System strategy'
Add-FileCandidate $candidates 'Swap file' "$Drive\swapfile.sys" 'High' 'Do not delete manually.' 'Managed by Windows.' 'System strategy'

if (-not $isQuickMode) {
    Add-Candidate $candidates 'Docker data root' "$Drive\ProgramData\Docker" 'High' 'Use docker system df/prune, not manual deletion.' 'May contain images, containers, volumes.' 'Container data'
    Add-Candidate $candidates 'Docker user data' (Join-Path $env:LOCALAPPDATA 'Docker') 'High' 'Use Docker Desktop cleanup tools.' 'May contain active Docker state.' 'Container data'
    Add-Candidate $candidates 'WSL package data' (Join-Path $env:LOCALAPPDATA 'Packages') 'High' 'Identify distro VHDX files; compact/export with WSL tools.' 'Do not delete package folders blindly.' 'WSL data'
}

$rootLargeDirs = @()
if (-not $isQuickMode) {
    try {
        $rootLargeDirs = Get-ChildItem -LiteralPath "$Drive\" -Force -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $result = Get-DirectorySize -Path $_.FullName -TimeoutSeconds ([Math]::Min($SizeTimeoutSeconds, 20))
                [pscustomobject]@{
                    Path = $_.FullName
                    Bytes = if ($null -eq $result) { 0 } else { [long]$result.Bytes }
                    Size = if ($null -eq $result) { 'n/a' } else { Format-Bytes ([long]$result.Bytes) }
                    TimedOut = if ($null -eq $result) { $false } else { [bool]$result.TimedOut }
                }
            } | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending | Select-Object -First $Top
    } catch {}
}

if ($LargeFileRoots -and $LargeFileRoots.Count -gt 0) {
    $scanRoots = $LargeFileRoots
} elseif ($isQuickMode) {
    $scanRoots = @("$Drive\Users\$env:USERNAME\Downloads", "$Drive\Users\$env:USERNAME\Desktop")
} else {
    $scanRoots = @("$Drive\Users\$env:USERNAME", "$Drive\ProgramData")
}
if ($IncludeUserProfiles) { $scanRoots += "$Drive\Users" }

$largeFiles = Get-LargeFiles -Roots $scanRoots -MinimumBytes ($LargeFileMinimumMB * 1MB) -Limit $Top
$orphanedStartupEntries = @(Get-OrphanedStartupEntries)
$orphanedServices = @(Get-OrphanedServices)

$dismSummary = $null
if ($AnalyzeDism) {
    $dismSummary = Get-DismComponentStoreSummary
}

$sortedCandidates = $candidates | Sort-Object Bytes -Descending
$lowMeasure = $sortedCandidates | Where-Object { $_.Risk -eq 'Low' } | Measure-Object -Property Bytes -Sum
$mediumMeasure = $sortedCandidates | Where-Object { $_.Risk -eq 'Medium' } | Measure-Object -Property Bytes -Sum
$highMeasure = $sortedCandidates | Where-Object { $_.Risk -eq 'High' } | Measure-Object -Property Bytes -Sum
$lowRiskBytes = if ($null -eq $lowMeasure.Sum) { 0L } else { [long]$lowMeasure.Sum }
$mediumRiskBytes = if ($null -eq $mediumMeasure.Sum) { 0L } else { [long]$mediumMeasure.Sum }
$highRiskBytes = if ($null -eq $highMeasure.Sum) { 0L } else { [long]$highMeasure.Sum }

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('s')
    Drive = $Drive
    Mode = if ($isQuickMode) { 'Quick' } else { 'Deep' }
    TotalSizeBytes = [long]$driveInfo.Size
    FreeSpaceBytes = [long]$driveInfo.FreeSpace
    TotalSize = Format-Bytes ([long]$driveInfo.Size)
    FreeSpace = Format-Bytes ([long]$driveInfo.FreeSpace)
    EstimatedLowRiskBytes = $lowRiskBytes
    EstimatedMediumRiskBytes = $mediumRiskBytes
    EstimatedHighRiskBytes = $highRiskBytes
    Candidates = $sortedCandidates
    TopRootDirectories = $rootLargeDirs
    LargeFileRoots = $scanRoots
    LargeFiles = $largeFiles | ForEach-Object { [pscustomobject]@{ Path=$_.FullName; Bytes=$_.Length; Size=(Format-Bytes $_.Length); LastWriteTime=$_.LastWriteTime } }
    OrphanedStartupEntries = $orphanedStartupEntries
    OrphanedServices = $orphanedServices
    Dism = $dismSummary
}

$jsonPath = Join-Path $OutputDir 'c-drive-slimmer-report.json'
$mdPath = Join-Path $OutputDir 'c-drive-slimmer-report.md'
$planPath = Join-Path $OutputDir 'cleanup-plan.md'
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $jsonPath

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# C Drive Slimmer Report')
$lines.Add('')
$lines.Add("Generated: $($report.GeneratedAt)")
$lines.Add("Drive: $Drive")
$lines.Add("Mode: $($report.Mode)")
$lines.Add("Total: $($report.TotalSize)")
$lines.Add("Free: $($report.FreeSpace)")
$lines.Add("Estimated low-risk cleanup: $(Format-Bytes $report.EstimatedLowRiskBytes)")
$lines.Add("Estimated medium-risk cleanup: $(Format-Bytes $report.EstimatedMediumRiskBytes)")
$lines.Add("High-risk/strategy space: $(Format-Bytes $report.EstimatedHighRiskBytes)")
$lines.Add('')
$lines.Add('## Cleanup Candidates')
$lines.Add('')
$lines.Add('| Size | Risk | Category | Name | Path | Recommendation | Notes |')
$lines.Add('|---:|---|---|---|---|---|---|')
foreach ($item in $report.Candidates) {
    $suffix = if ($item.TimedOut) { ' Partial estimate.' } else { '' }
    $lines.Add("| $(Format-MarkdownCell $item.Size) | $(Format-MarkdownCell $item.Risk) | $(Format-MarkdownCell $item.Category) | $(Format-MarkdownCell $item.Name) | $(Format-MarkdownCodeCell $item.Path) | $(Format-MarkdownCell $item.Cleanup) | $(Format-MarkdownCell "$($item.Notes)$suffix") |")
}
$lines.Add('')
$lines.Add('## Top Root Directories')
$lines.Add('')
$lines.Add('| Size | Timed Out | Path |')
$lines.Add('|---:|---|---|')
foreach ($item in $report.TopRootDirectories) {
    $lines.Add("| $(Format-MarkdownCell $item.Size) | $(Format-MarkdownCell $item.TimedOut) | $(Format-MarkdownCodeCell $item.Path) |")
}
$lines.Add('')
$lines.Add('## Large Files')
$lines.Add('')
$lines.Add('| Size | Last Write | Path |')
$lines.Add('|---:|---|---|')
foreach ($item in $report.LargeFiles) {
    $lines.Add("| $(Format-MarkdownCell $item.Size) | $(Format-MarkdownCell $item.LastWriteTime) | $(Format-MarkdownCodeCell $item.Path) |")
}
$lines.Add('')
$lines.Add('## Orphaned Startup Entries')
$lines.Add('')
$lines.Add('| Name | Location | User | Missing Executable | Command |')
$lines.Add('|---|---|---|---|---|')
foreach ($item in $report.OrphanedStartupEntries) {
    $lines.Add("| $(Format-MarkdownCell $item.Name) | $(Format-MarkdownCell $item.Location) | $(Format-MarkdownCell $item.User) | $(Format-MarkdownCodeCell $item.ExecutablePath) | $(Format-MarkdownCodeCell $item.Command) |")
}
$lines.Add('')
$lines.Add('## Orphaned Services')
$lines.Add('')
$lines.Add('| Name | Display Name | State | Start Mode | Missing Executable | Path Name |')
$lines.Add('|---|---|---|---|---|---|')
foreach ($item in $report.OrphanedServices) {
    $lines.Add("| $(Format-MarkdownCell $item.Name) | $(Format-MarkdownCell $item.DisplayName) | $(Format-MarkdownCell $item.State) | $(Format-MarkdownCell $item.StartMode) | $(Format-MarkdownCodeCell $item.ExecutablePath) | $(Format-MarkdownCodeCell $item.PathName) |")
}
if ($null -ne $report.Dism) {
    $lines.Add('')
    $lines.Add('## DISM Component Store')
    $lines.Add('')
    $lines.Add("Recommended: $($report.Dism.Recommended)")
}
$lines.Add('')
$lines.Add('## Notes')
$lines.Add('')
$lines.Add('- This report is scan-only; nothing was deleted.')
$lines.Add('- Estimates can be partial when a directory scan hits the timeout.')
$lines.Add('- Review high-risk paths manually before cleanup.')
$lines.Add('- Orphaned startup entries and services are report-only; remove them only after confirming the app is uninstalled and the shell is elevated.')
$lines.Add('- Prefer native cleanup tools for Windows, Docker, WSL, and package managers.')
$lines | Set-Content -Encoding UTF8 $mdPath

$plan = [System.Collections.Generic.List[string]]::new()
$plan.Add('# C Drive Cleanup Plan')
$plan.Add('')
$plan.Add("Immediate low-risk estimate: $(Format-Bytes $report.EstimatedLowRiskBytes)")
$plan.Add("Reviewable medium-risk estimate: $(Format-Bytes $report.EstimatedMediumRiskBytes)")
$plan.Add("High-risk/strategy space: $(Format-Bytes $report.EstimatedHighRiskBytes)")
$plan.Add('')
$plan.Add('## Stage 1 - Low Risk')
$plan.Add('')
$plan.Add('- Empty Recycle Bin after user confirmation: `Clear-RecycleBin -Force`')
$plan.Add('- Clear user and Windows temp contents, ignoring locked files.')
$plan.Add('- Use Settings > System > Storage > Temporary files for Windows-managed caches.')
$plan.Add('')
$plan.Add('## Stage 2 - Developer Caches')
$plan.Add('')
$plan.Add('- npm: `npm cache clean --force`')
$plan.Add('- pip: `python -m pip cache purge`')
$plan.Add('- NuGet: `dotnet nuget locals all --clear`')
$plan.Add('- Maven/Gradle: clear only after confirming builds can restore dependencies.')
$plan.Add('')
$plan.Add('## Stage 3 - Windows-Supported Cleanup')
$plan.Add('')
$plan.Add('- Component store analysis: `DISM /Online /Cleanup-Image /AnalyzeComponentStore`')
$plan.Add('- Component store cleanup when recommended: `DISM /Online /Cleanup-Image /StartComponentCleanup`')
$plan.Add('')
$plan.Add('## Stage 4 - High-Risk Strategy')
$plan.Add('')
$plan.Add('- Hibernation: `powercfg /h off` only if hibernate/Fast Startup are not needed.')
$plan.Add('- Page file: do not delete manually; adjust only with clear memory/stability tradeoff.')
$plan.Add('- Docker/WSL/VM data: use native prune/export/compact workflows only after per-item confirmation.')
$plan.Add('')
$plan.Add('No cleanup has been executed by this scan.')
$plan | Set-Content -Encoding UTF8 $planPath

Write-Host "Markdown report: $mdPath"
Write-Host "Cleanup plan: $planPath"
Write-Host "JSON report: $jsonPath"
Write-Host "Nothing was deleted."
