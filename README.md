# C Drive Slimmer Skill

Windows C: drive cleanup scanner for Codex. It helps diagnose low disk space, slow machines, cleanup candidates, and orphaned startup/service entries without deleting anything by default.

## What It Does

- Scans safe cleanup candidates such as temp folders, Recycle Bin, Windows update cache, WER reports, and common developer caches.
- Reports high-risk strategy items such as `hiberfil.sys`, `pagefile.sys`, `swapfile.sys`, and `Windows.old`.
- Finds large files in common user locations.
- Detects orphaned startup entries and Windows services whose executable path no longer exists.
- Generates a Markdown report, cleanup plan, and JSON report.
- Keeps cleanup actions separate from scanning. Nothing is deleted unless the user explicitly confirms the exact cleanup category.

## Install

Clone this repository into your Codex skills directory:

```powershell
cd $env:USERPROFILE\.codex\skills
git clone https://github.com/youngxuesong/c-drive-slimmer-skill.git c-drive-slimmer
```

Restart Codex after installation so the skill can be discovered.

If your skills directory does not exist yet:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex\skills"
```

## Use With Codex

Ask Codex for tasks like:

```text
Scan my C drive and tell me what can be safely cleaned.
```

```text
Check why this Windows machine is slow and whether disk cleanup is needed.
```

```text
Find orphaned startup items and services from uninstalled apps.
```

Codex will load the skill, run the scanner, read the generated reports, and summarize findings by risk level.

## Run The Scanner Directly

From PowerShell:

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1"
```

Save output to a known folder:

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1" -OutputDir C:\Temp\c-drive-report
```

Run a deeper scan:

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1" -Deep -Top 50
```

Analyze the Windows component store with DISM:

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1" -AnalyzeDism
```

Scan specific roots for large files:

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\c-drive-slimmer\scripts\Scan-CDriveCleanup.ps1" -LargeFileRoots C:\Users\Administrator\Downloads,C:\project
```

## Output Files

The scanner prints paths like:

```text
Markdown report: C:\Users\...\AppData\Local\Temp\c-drive-slimmer-YYYYMMDD-HHMMSS\c-drive-slimmer-report.md
Cleanup plan: C:\Users\...\AppData\Local\Temp\c-drive-slimmer-YYYYMMDD-HHMMSS\cleanup-plan.md
JSON report: C:\Users\...\AppData\Local\Temp\c-drive-slimmer-YYYYMMDD-HHMMSS\c-drive-slimmer-report.json
```

Use the Markdown report for human review and the JSON report for automation.

## Safety Model

- Default mode is scan-only.
- Do not manually delete `C:\Windows\WinSxS`, `C:\Windows\Installer`, Docker/WSL data, browser profiles, VM disks, databases, or user documents.
- Use Windows-supported cleanup tools before manual deletion.
- Remove startup entries or services only after confirming the app is uninstalled.
- HKLM registry and service cleanup require an elevated shell.
- Hibernation cleanup with `powercfg /h off` disables hibernation and Fast Startup.

## Requirements

- Windows.
- PowerShell 7+ (`pwsh`) is preferred.
- Windows PowerShell can run most checks, but PowerShell 7 is recommended for more consistent behavior.

## Repository Layout

```text
c-drive-slimmer/
├── SKILL.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── Scan-CDriveCleanup.ps1
```
