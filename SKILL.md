---
name: c-drive-slimmer
description: "Safe Windows C: drive cleanup scanner and slimming assistant. Use when the user asks to scan C drive, find cleanup candidates, free disk space, slim C:, clean Windows junk, analyze large folders/files, or produce safe cleanup recommendations. Defaults to fast read-only scanning and report generation; deletion requires explicit user confirmation and should prefer Windows-supported cleanup paths."
---

# C Drive Slimmer

Use this skill to reclaim Windows C: drive space safely.

## Safety Rules

- Default to scan-only. Do not delete files unless the user explicitly confirms the exact cleanup category.
- Run quick scan first. Use deep scan only when quick scan is insufficient or the user asks for exhaustive analysis.
- Prefer Microsoft/Windows-supported cleanup mechanisms before manual deletion.
- Never remove user documents, source code, photos, videos, browser profiles, email stores, credential files, VM disks, or database files without explicit per-path confirmation.
- Treat `C:\Windows\WinSxS`, `C:\Windows\Installer`, `C:\ProgramData`, `C:\Users\*\AppData`, Docker/WSL data, and package-manager caches as sensitive. Report sizes and recommended commands; do not directly purge undocumented internals.
- If elevated shell is needed, ask for approval and explain why.
- Before destructive cleanup, create or recommend a restore point when feasible.
- When generating helper PowerShell scripts for elevated cleanup, keep script source ASCII-only unless non-ASCII is strictly required. If localized labels are needed, avoid putting them in regex/string delimiters that may be run by legacy Windows PowerShell with a different code page.
- Verify elevation before HKLM/service cleanup. `whoami /groups` should show a high integrity level and the Administrators group should not be `deny only`; otherwise instruct the user to launch an elevated shell before retrying.

## Workflow

1. Run `scripts/Scan-CDriveCleanup.ps1` with default quick scan.
2. Read `c-drive-slimmer-report.md`, `cleanup-plan.md`, and JSON if detailed analysis is needed.
3. Summarize findings by risk tier:
   - Low risk: temp folders, recycle bin, Windows Update cleanup via supported tools, log/archive caches.
   - Medium risk: package caches, old downloads, large installer archives, old build artifacts.
   - High risk: app data, VM/container images, hibernation/pagefile changes, Windows component store, unknown large files.
4. Recommend a staged cleanup plan: low-risk first, then user-reviewed medium/high-risk items.
5. Only execute cleanup after explicit confirmation for each category.
6. For approved low-risk cleanup, prefer bundled scripts over ad hoc shell commands.

## Scanner Usage

```powershell
# Default: fast, read-only scan
pwsh -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1
```

Common options:

```powershell
# Save report to a custom folder
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -OutputDir C:\Temp\c-drive-report

# Explicit quick scan
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -Quick

# Deep scan with bounded directory-size estimates
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -Deep -Top 50

# Add DISM component store analysis; still read-only but slower
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -AnalyzeDism

# Scan specific roots for large files instead of scanning all C:\
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -LargeFileRoots C:\Users\Administrator\Downloads,C:\project

# Include all user profiles in large-file scan
pwsh -ExecutionPolicy Bypass -File ...\Scan-CDriveCleanup.ps1 -IncludeUserProfiles
```

Cleanup helpers:

```powershell
# Low-risk temp cleanup for the current user
pwsh -ExecutionPolicy Bypass -File ...\Clear-LowRiskTemp.ps1

# Preview low-risk cleanup without deleting anything
pwsh -ExecutionPolicy Bypass -File ...\Clear-LowRiskTemp.ps1 -WhatIf

# Save low-risk cleanup report to a custom folder
pwsh -ExecutionPolicy Bypass -File ...\Clear-LowRiskTemp.ps1 -WhatIf -OutputDir C:\tmp\c-drive-low-risk-clean

# Include Windows temp as well; run elevated when needed
pwsh -ExecutionPolicy Bypass -File ...\Clear-LowRiskTemp.ps1 -IncludeWindowsTemp

# Clear pip and npm caches
pwsh -ExecutionPolicy Bypass -File ...\Clear-DevCaches.ps1

# Preview developer cache cleanup without deleting anything
pwsh -ExecutionPolicy Bypass -File ...\Clear-DevCaches.ps1 -WhatIf

# Save developer cache cleanup report to a custom folder
pwsh -ExecutionPolicy Bypass -File ...\Clear-DevCaches.ps1 -WhatIf -OutputDir C:\tmp\c-drive-dev-cache-clean

# Also clear NuGet and Gradle caches
pwsh -ExecutionPolicy Bypass -File ...\Clear-DevCaches.ps1 -IncludeNuGet -IncludeGradle
```

## Built-In Detection

The scanner reports:

- Low-risk cleanup candidates: temp folders, recycle bin, Windows update/download caches, WER reports.
- Developer caches: npm, pip, NuGet, Gradle, Maven.
- Windows strategy items: `hiberfil.sys`, `pagefile.sys`, `swapfile.sys`, `Windows.old`.
- Orphaned startup entries and services whose executable path no longer exists.
- Optional deep-scan items: Docker data, Docker user data, WSL package data, top root directories.
- Optional DISM result: whether component store cleanup is recommended.

## Cleanup Recommendation Patterns

Use these only after reviewing the report with the user:

- Recycle Bin: `Clear-RecycleBin -Force`
- User temp: remove contents of `$env:TEMP` with locked-file errors ignored.
- Windows temp: remove contents of `C:\Windows\Temp` from an elevated shell.
- Component store: `DISM /Online /Cleanup-Image /AnalyzeComponentStore`, then if recommended `DISM /Online /Cleanup-Image /StartComponentCleanup`
- Hibernation: `powercfg /h off` only if the user does not use hibernate/Fast Startup.
- Docker/WSL/VM data: report usage first; use native prune/export/compact workflows only with user consent.
- Package managers: use native cache commands (`npm cache clean --force`, `pip cache purge`, `dotnet nuget locals all --clear`, etc.) after confirming impact.
- Orphaned startup/service entries from uninstalled apps: report exact registry value and service name first; remove only after confirmation and only from an elevated shell.
- Bundled cleanup scripts: `scripts/Clear-LowRiskTemp.ps1` for low-risk temp cleanup, `scripts/Clear-DevCaches.ps1` for developer caches.

## Output Expectations

- Give total reclaimable estimate as a range, not a guarantee.
- Distinguish immediately reclaimable space from space requiring reboot/admin tools/app-specific cleanup.
- Include exact paths for `c-drive-slimmer-report.md`, `cleanup-plan.md`, and JSON.
- Treat timeout-marked directory sizes as partial estimates.
- End with a short confirmation question before any cleanup action.
