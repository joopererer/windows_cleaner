# Windows Disk Clean Master · V2.4.1

<p align="left">
  <b>English</b> | <a href="README.md">简体中文</a>
</p>

> 🛡️ **A project-aware Windows disk cleanup, dev cache migration, and read-only auditing tool for power users and modern developers. Built with safety, reversibility, and data protection as primary design principles.**

---

## 📖 Philosophy & V2.4.1 Architectural Evolution

Traditional disk cleaning utilities often prioritize aggressive, blind deletion. When dealing with modern, polyglot development environments, such tools frequently wipe critical package dependencies, corrupt local build states, or cause unrecoverable loss of uncommitted project artifacts.

**Windows Disk Clean Master V2.4.1 (Project Association Detection, fnm Compatibility & Progress Refined Edition)** introduces critical usability refinements while upholding strict safety invariants:

### 1. Granular Project-Associated Process Detection (No Global False Blockers)
- **Previous Limitation**: Early versions halted whenever any background process like `java.exe` or `dart.exe` was present, causing broad false positives and blocking all projects unnecessarily.
- **Intelligent Risk Stratification**:
  - **Directly Related (Hard Block)**: If a process command line explicitly references the project's absolute path, or the running binary itself resides inside the candidate build directory (e.g., an active test runner), **quarantine is strictly blocked**;
  - **Uncertain Affiliation (Soft Warning + Explicit Consent)**: Compilers or Java daemons with ambiguous command lines trigger a warning displaying PID and process name. In individual mode, users must explicitly acknowledge residual risk before typing `QUARANTINE`. In batch mode, users must supply an extra `ACCEPT-RISK` confirmation prior to `BATCH-QUARANTINE`;
  - **Distinct Project Processes (Safely Allowed)**: Processes clearly operating in unrelated directories do not block the active project;
  - **Fail-Closed Policy**: CIM/WMI query errors immediately halt quarantine; process states and directory integrity are re-verified right before execution.

### 2. fnm (Fast Node Manager) Native Compatibility & Environment Initialization
- **Problem**: `fnm` typically configures dynamic PATH entries inside interactive shell profiles. Running scripts under `-NoProfile` often caused `node.exe` to be unavailable, leading to false "npm not found" errors.
- **Clean Scoped Resolution**:
  - Automatically initializes `fnm` **scoped strictly to the current PowerShell process**, never polluting system or user permanent global PATHs;
  - Fixes argument compatibility with `fnm use` and detects the default Node alias;
  - Pairs directly with `npm.cmd` located in the resolved Node directory, avoiding outdated shims in `AppData\Roaming`.

### 3. Transparent, Real-Time Progress Telemetry (No Fictional Percentages)
- Real-time updates during project discovery: directories examined, candidate count, queue size, elapsed seconds, and truncated active path;
- Displays live counts of files and subdirectories while sizing large `build` or `target` folders;
- Employs an indeterminate progress model to avoid misleading percentages. Clear guidance clarifies that underlying Windows I/O pauses during large directory enumerations are normal and do not indicate a freeze.

### 4. Enduring Safety Architecture
- **Menu 1**: Conservative file-level `%TEMP%` scanning (7/14/30 day options, exclusion of scripts/configs/lockfiles/archives, exclusive file-open access checks, Recycle Bin only, zero empty/whole folder deletions);
- **Menu 2**: Global package caches permanently protected; read-only preflight step before quarantine with three flexible modes: Cancel, Batch Quarantine, or Individual Confirmation;
- **Same-Volume Quarantine & 7-Day Cooldown**: Relocates build outputs to `.wdcs-quarantine` on the same disk volume; eligible for permanent purge via `PURGE <ID>` only after 7 days;
- **Menu 8 Dedicated Restore**: Clean, 1-click restoration to original paths (refuses to overwrite existing folders);
- **Menu 3 Cross-Volume Migration**: Free space pre-flight check + 4-thread Robocopy + **full SHA256 tree hashing** + local backup + auto-rollback;
- **Read-Only Modules**: Menus 4 (Install Paths), 5 (Process RAM ranking), and 7 (Full-Disk Audit report without delete buttons);
- **Multi-Tier Defense**: Core system path locks + custom [`protected-paths.txt`](protected-paths.txt) whitelist + fail-closed protection against reparse points and symlinks.

---

## ✨ Key Feature Matrix

| Category | V2.4.1 Implementation Details |
| :--- | :--- |
| **Launch Security** | Double-clicking `win-disk-clean-master.bat` launches in the current standard user context **without requesting UAC elevation**. |
| **File-Level TEMP Cleanup** | Scans individual files in user `%TEMP%`, displays top-level groups and largest candidates; checks locks/attributes; **sends to Recycle Bin only**. |
| **Project Fingerprinting** | Validates verified project structures: **Gradle** (`gradlew.bat` + `build.gradle`), **Maven** (`pom.xml`), **Cargo** (`Cargo.toml` + `Cargo.lock`), **Dart/Flutter** (`pubspec.yaml`). |
| **Project Association Detection** | Distinguishes between directly related processes (blocked), uncertain processes (prompted), and unrelated project processes. |
| **fnm Native Compatibility** | Dynamically initializes Node runtime for the current session without permanently altering global PATHs. |
| **Real Progress & Elapsed Time**| Displays live directories checked, candidates found, elapsed seconds, and active path without fictional percentages. |
| **Preflight & Multi-Mode Confirmation** | Menu 2 runs a read-only preflight check with options for Cancel, Batch Quarantine, or Individual Confirmation. |
| **Same-Volume Quarantine** | Build outputs move to `.wdcs-quarantine` on the same disk partition without cross-volume hazard; reversible via Menu 8. |
| **7-Day Cooldown Purge** | Quarantined items younger than 7 days are locked against deletion. Purging requires entering `PURGE <ID>`. |
| **Safe Cross-Volume Migration** | Destination capacity headroom check + 4-thread Robocopy + **SHA256 whole-tree hashing** + local backup + auto-rollback. |
| **Read-Only Full-Disk Audit** | Menu 7 outputs audit reports to `%LOCALAPPDATA%\WinDiskCleanSafe\logs` without deletion buttons. |
| **Smart Bilingual UI (i18n)** | Reads the authentic user locale from Windows Registry; press `L` to toggle dynamically between English and Chinese. |
| **Custom Path Whitelist** | Supports [`protected-paths.txt`](protected-paths.txt) in the root directory (one absolute path per line) to block scanning and migration. |

---

## 🛠️ Complete Feature Matrix (Menus 1 ~ 9)

| Menu | Module | Safety Policy & Technical Details |
| :---: | :--- | :--- |
| **1** | **[Quick Clean] User %TEMP% (Conservative File-Level Edition)** | • **Strict Scope**: Scans only the active user's `%USERPROFILE%\AppData\Local\Temp`; never touches system paths.<br>• **Retention Threshold**: Allows keeping files modified within the last **7 days (default), 14 days, or 30 days**.<br>• **File-Level Exclusions**: Automatically excludes scripts/binaries (`.exe/.dll/.bat/.ps1/.js/.py/.rs`), configs/lockfiles (`.json/.yaml/.toml/lock`), databases, archives, docs/media, and nested project subtrees (`.git/node_modules/.gradle`, etc.).<br>• **Grouping & Largest Files**: Summarizes candidates by top-level source directory and shows top largest files.<br>• **Recycle Bin Only**: Performs **exclusive file-open checks** to detect running process locks; typing `RECYCLE` safely moves files to the Windows Recycle Bin (reversible). **Never deletes whole or empty folders**. |
| **2** | **[Dev Slimming] Dependency Inspection & Project Quarantine** | • **Global Cache Protection**: Gradle Wrapper/caches, Dart Pub Cache, and npm cache are marked as `[PROTECTED]` (sizes displayed in read-only mode).<br>• **fnm Compatibility & npm Maintenance**: Scoped dynamic fnm initialization; optional `npm cache verify` index maintenance.<br>• **Project-Associated Process Checks**: Hard blocks for processes referencing the current project; explicit risk prompts for ambiguous processes.<br>• **Strict Project Scan**: Validates project markers before listing verified `build` or `target` folders; shows latest source and build timestamps.<br>• **Preflight & 3 Confirmation Modes**: Runs preflight, then offers [1] Cancel, [2] Batch Quarantine (`BATCH-QUARANTINE` / `ACCEPT-RISK`), or [3] Individual Confirmation (`QUARANTINE`). |
| **3** | **[Seamless Migrate] Cross-Volume Safe Relocation** | • **Pre-flight Capacity Check**: Requires at least `source size × 1.1 + 100MB` available on the destination volume.<br>• **4-Thread Robocopy**: Replicates files and directory structures with strict error controls.<br>• **Whole-Tree SHA256 Verification**: Verifies every single file hash post-copy.<br>• **Rollback Backup & Junction**: Renames source to `.wdcs-backup-yyyyMMdd-HHmmss` for rollback before creating an NTFS Junction (`mklink /J`). Automatically rolls back if any step fails. |
| **4** | **[Install Paths] Inspect Program Files Registry** | **Read-Only**. Safely checks and displays current `ProgramFilesDir` and `ProgramFilesDir (x86)` registry keys. No global registry writes; users are encouraged to specify custom paths in individual software installers. |
| **5** | **[Memory] Inspect Process RAM Usage** | **Read-Only**. Lists the top 15 processes by Working Set memory. Does not call `EmptyWorkingSet`, preventing process page thrashing or UI stutter. |
| **6** | **[Disk Guard] Free Space Monitor** | Runs a background check every 5 minutes. Pops up a native Windows notification if drive `C:` free space drops below **5.0 GB**, helping avoid sudden compiler crashes. |
| **7** | **[Full-Disk Audit] Leftovers & Stale Artifacts Report** | **Strictly Read-Only (No deletion actions)**.<br>• Scans any designated drive letter for candidate project directories (`node_modules`, `build`, `target`) and archives/installers (>100MB, >14 days old).<br>• Generates an audit log in `%LOCALAPPDATA%\WinDiskCleanSafe\logs` and displays findings via `Out-GridView`. Does not offer deletion buttons because file names and timestamps alone do not prove safety. |
| **8** | **[Restore] Restore Quarantined Build Outputs** | Inspects the quarantine manifest and restores `Quarantined` directories **directly back to their original paths**; strictly refuses to overwrite existing folders. |
| **9** | **[Quarantine Purge] Reclaim Quarantined Space** | The sole path for permanent disk space reclamation:<br>• **Eligible only after a 7-day cooldown**.<br>• Restricted to one item at a time.<br>• Requires typing `PURGE <ID>` (e.g. `PURGE 1a2b3c...`) as an unambiguous confirmation step before physical removal. |

---

## 🚀 Quick Start & Usage

### Requirements
- **OS**: Windows 10 / Windows 11 / Windows Server 2016+
- **Environment**: Windows PowerShell 5.1 or newer (built into Windows, no extra dependencies)
- **Recommended Terminal**: Windows Terminal with UTF-8 support (`chcp 65001`)

### How to Run

#### Option 1: Double-Click (Recommended)
Simply double-click **`win-disk-clean-master.bat`** in the repository root.
> This launches the PowerShell core in the current user context with UTF-8 encoding **without requesting UAC elevation** or altering execution policies permanently.

#### Option 2: Run via Terminal
Open any PowerShell prompt, navigate to the folder, and run:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-disk-clean-master.ps1"
```
Or execute directly in an existing session:
```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWD\win-disk-clean-master.ps1"
```

---

## 💡 Developer Setup Tip (fnm Environment)

If you manage Node.js versions with `fnm` (Fast Node Manager), add this to your PowerShell `$PROFILE`:

```powershell
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
```

To set a default Node version across sessions:
```powershell
fnm default 20.18.0  # or your preferred LTS version
```
> ⚠️ **Note**: Never permanently add temporary dynamic paths generated inside `fnm_multishells` to your system or user PATH.

---

## 📁 Repository Structure

```text
windows_cleaner/
├── README.md                      # Project Documentation (Chinese · V2.4.1)
├── README_en.md                   # Project Documentation (English · V2.4.1)
├── protected-paths.txt            # Custom protected directory whitelist (one path per line)
├── win-disk-clean-master.bat      # [Main Entry] Lightweight launcher (no auto-elevation)
├── win-disk-clean-master.ps1      # [Core Logic] V2.4.1 Safety-first PowerShell script
└── old/                           # [Archive] Early legacy scripts (contains aggressive deletion logic)
    ├── win-disk-clean-master.bat
    ├── win-disk-clean-master.ps1
    └── win-disk-smart-auditor.bat
```

---

## 🛡️ Protection Scope & `protected-paths.txt`

To prevent accidental data loss, V2.4.1 implements a robust multi-tier defense:

### 1. Built-in Protected Paths
The tool strictly rejects selecting or traversing:
- Drive roots (e.g., `C:\`, `D:\`)
- System core folders: `%windir%`, `C:\Program Files`, `C:\Program Files (x86)`, `C:\ProgramData`
- User core libraries: `Desktop`, `Documents`, `Pictures`, `Music`, `Videos`, `Downloads`, `OneDrive`
- Application logs and state store: `%LOCALAPPDATA%\WinDiskCleanSafe`

### 2. User-Defined Protected Whitelist (`protected-paths.txt`)
Add custom directories that must never be scanned, migrated, or quarantined to [`protected-paths.txt`](protected-paths.txt) (one absolute path per line; lines starting with `#` are ignored):
```text
# Absolute paths protected against traversal, migration, or quarantine
D:\Projects\ProductionApp
E:\ImportantBackups
```

---

## ⚠️ Notes & Disclaimer

1. **Timestamps Are Clues, Not Proof**: File modification timestamps provide safety signals but cannot definitively prove a file is useless. Temporary directories may house pending application sessions or unpack caches. Always inspect top groups and large files before recycling.
2. **Exclusive File Open Checks**: Testing for exclusive file access significantly mitigates the danger of deleting files actively held by applications, but cannot eliminate race conditions occurring between scan and deletion.
3. **Recycle Bin & Reclaiming Space**: Files sent to the Recycle Bin via Menu 1 continue to consume disk space. Space is reclaimed only after you manually review and empty the Windows Recycle Bin.
4. **Large Directory Enumeration Pauses**: During project discovery or build artifact sizing, enumerating directories containing hundreds of thousands of small files may cause brief UI update pauses. This is normal Windows file system behavior, not an application crash.
5. **Syntax Self-Check**:
   Verify script syntax integrity by running this snippet in PowerShell:
   ```powershell
   $tokens = $null; $errors = $null
   [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\win-disk-clean-master.ps1').Path,[ref]$tokens,[ref]$errors)
   $errors | Select-Object Message,@{N='Line';E={$_.Extent.StartLineNumber}}
   ```
   No output indicates syntax parsing completed with zero errors.
6. **General Disclaimer**: This tool is an open-source utility. Operations involving file manipulation inherently carry environmental variances. Always keep offsite backups of essential projects and codebases.
