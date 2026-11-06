# Windows Disk Clean Master · V2.3

<p align="left">
  <b>English</b> | <a href="README.md">简体中文</a>
</p>

> 🛡️ **A project-aware Windows disk cleanup, dev cache migration, and read-only auditing tool for power users and modern developers. Built with safety, reversibility, and data protection as primary design principles.**

---

## 📖 Philosophy & V2.3 Architectural Evolution

Traditional disk cleaning utilities often prioritize aggressive, blind deletion. When dealing with modern, polyglot development environments, such tools frequently wipe critical package dependencies, corrupt local build states, or cause unrecoverable loss of uncommitted project artifacts.

**Windows Disk Clean Master V2.3 (Conservative File-Level TEMP & Project-Aware Edition)** builds on the safety foundations of V2.1/V2.2 with major architectural advances:
- **Menu 1 Revolutionary Upgrade: File-Level Precision TEMP Scanning (No Whole-Directory Deletions)**:
  - Traditional tools often abandon an entire folder if just one file is recent, or blindly wipe whole folders if their top-level directory timestamp appears old. V2.3 switches completely to **deep recursive file-by-file inspection**.
  - Strictly operates within the active user's `USERPROFILE\AppData\Local\Temp`; it never touches system paths (`Windows\Temp`), Windows Update caches, or the existing Recycle Bin contents.
  - Offers flexible retention thresholds: keep files active within the last **7 days (default), 14 days, or 30 days**.
  - **Zero whole-directory or empty-folder deletions**. Every candidate file undergoes **exclusive file-open access checks (detecting in-use processes)** and attribute verification before being sent to the Recycle Bin.
  - Extensively excludes critical file extensions (code, scripts, configs, lockfiles, archives, disk images, documents, databases) and nested project subtrees (`.git`, `node_modules`, `.gradle`, etc.).
- **Menu 2 Dev Build Quarantine Significantly Enhanced**:
  - **Active Build Process Detection**: Checks for running compilers and build tools (`cargo`, `rustc`, `flutter`, `dart`, `gradle`, `java`, `mvn`, `cmake`, etc.) and automatically blocks quarantine operations to prevent corrupting active builds.
  - **Project & Build Activity Telemetry**: Compares recent file modification times between source trees (`src`, `lib`, `test`) and build outputs to help users assess project activity.
  - **Volume-Based Logical Grouping**: Groups candidates by physical/logical drive (`C:`, `D:`, `E:`, etc.), summarizing item counts and volume sizes.
  - **Batch Selection Support**: Supports multi-index selection patterns like `1,3,5` or `1-10` (and mixed patterns like `1-3, 5, 8-10`), with per-item confirmation and process re-checks.
- **Global Dependency Stores Permanently Protected**: Gradle Wrapper/caches, Dart Pub Cache, and npm cache remain tagged as `[PROTECTED]` and are never purged.
- **Same-Volume Quarantine & 7-Day Cooldown**:
  - Build outputs are relocated to a dedicated `.wdcs-quarantine` directory on the same volume (instant move, zero cross-partition risk).
  - Items must undergo a **7-day cooldown period** before becoming eligible for permanent purge; final deletion requires typing `PURGE <ID>`.
  - Seamless, non-destructive restoration back to the original project path via Menu 8 (never overwrites existing files).
- **Verified Migration with Automatic Rollback**: Requires pre-flight free space headroom, runs 4-thread Robocopy, enforces full **SHA256 hash comparison**, preserves timestamped rollback backups, and creates NTFS Junctions.
- **Multi-Layer Shield**: Built-in system path exclusions + custom [`protected-paths.txt`](protected-paths.txt) whitelist + fail-closed protection against reparse points and symlinks.

---

## ✨ Key Feature Matrix

| Category | V2.3 Implementation Details |
| :--- | :--- |
| **Launch Security** | Double-clicking `win-disk-clean-master.bat` launches in the current standard user context **without requesting UAC elevation**. |
| **File-Level TEMP Cleanup** | Scans individual files in user `%TEMP%`, displays top-level groups and largest candidates; checks locks/attributes; **sends to Recycle Bin only**. |
| **Project Fingerprinting** | Validates verified project structures: **Gradle** (`gradlew.bat` + `build.gradle`), **Maven** (`pom.xml`), **Cargo** (`Cargo.toml` + `Cargo.lock`), **Dart/Flutter** (`pubspec.yaml`). |
| **Build Process Guard** | Proactively halts quarantine if active build processes (`cargo`, `flutter`, `dart`, `java`, `mvn`, etc.) are running. |
| **Batch Selection & Telemetry** | Menu 2 accepts ranges like `1-3, 5, 8-10`, displaying recent activity timestamps for both source code and build outputs. |
| **Controlled Cache Inspection**| Global dependency caches are read-only; optionally runs `npm cache verify` to clean up npm internal indices. |
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
| **2** | **[Dev Slimming] Dependency Inspection & Project Quarantine** | • **Global Cache Protection**: Gradle Wrapper/caches, Dart Pub Cache, and npm cache are marked as `[PROTECTED]` (sizes displayed in read-only mode).<br>• **Build Process Guard**: Detects running compilers (`cargo`, `rustc`, `flutter`, `dart`, `java`, `mvn`, etc.) and halts quarantine to prevent corrupting active builds.<br>• **Strict Project Scan**: Enter a project parent folder (e.g. `D:\Projects`). Accurately scans for verified `build` or `target` directories.<br>• **Volume Grouping & Telemetry**: Groups findings by drive volume and displays latest modification times for both project sources and build samples.<br>• **Batch Selection & Quarantine**: Accepts ranges (e.g. `1-3, 5`); typing `QUARANTINE` moves selected items to `.wdcs-quarantine` on the same volume. |
| **3** | **[Seamless Migrate] Cross-Volume Safe Relocation** | • **Pre-flight Capacity Check**: Requires at least `source size × 1.1 + 100MB` available on the destination volume.<br>• **4-Thread Robocopy**: Replicates files and directory structures with strict error controls.<br>• **Whole-Tree SHA256 Verification**: Verifies every single file hash post-copy.<br>• **Rollback Backup & Junction**: Renames source to `.wdcs-backup-yyyyMMdd-HHmmss` for rollback before creating an NTFS Junction (`mklink /J`). Automatically rolls back if any step fails. |
| **4** | **[Install Paths] Inspect Program Files Registry** | **Read-Only**. Safely checks and displays current `ProgramFilesDir` and `ProgramFilesDir (x86)` registry keys. No global registry writes; users are encouraged to specify custom paths in individual software installers. |
| **5** | **[Memory] Inspect Process RAM Usage** | **Read-Only**. Lists the top 15 processes by Working Set memory. Does not call `EmptyWorkingSet`, preventing process page thrashing or UI stutter. |
| **6** | **[Disk Guard] Free Space Monitor** | Runs a background check every 5 minutes. Pops up a native Windows notification if drive `C:` free space drops below **5.0 GB**, helping avoid sudden compiler crashes. |
| **7** | **[Full-Disk Audit] Leftovers & Stale Artifacts Report** | **Strictly Read-Only (No deletion actions)**.<br>• Scans any designated drive letter for candidate project directories (`node_modules`, `build`, `target`) and archives/installers (>100MB, >14 days old).<br>• Generates an audit log in `%LOCALAPPDATA%\WinDiskCleanSafe\logs` and displays findings via `Out-GridView`. Does not offer deletion buttons because file names and timestamps alone do not prove safety. |
| **8** | **[Restore] Restore Quarantined Build Outputs** | Inspects the quarantine manifest and restores `Quarantined` directories **directly back to their original paths**; strictly refuses to overwrite existing folders. |
| **9** | **[Quarantine Purge] Reclaim Quarantined Space** | The sole path for permanent disk space reclamation:<br>• **Eligible only after a 7-day cooldown**.<br>• Restricted to one item at a time.<br>• Requires typing `PURGE <ID>` (e.g. `PURGE 1a2b3c...`) as an unambiguous confirmation step before physical removal. |

---

## 🚀 Quick Start

### Requirements
- **OS**: Windows 10 / Windows 11 / Windows Server 2016+
- **Environment**: Windows PowerShell 5.1 or newer (built into Windows, no extra dependencies)
- **Recommended Terminal**: Windows Terminal with UTF-8 support (`chcp 65001`)

### How to Run

#### Option 1: Double-Click (Recommended)
Simply double-click **`win-disk-clean-master.bat`** in the repository root.
> This launches the PowerShell core in the current user context with UTF-8 encoding **without requesting UAC elevation**.

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

## 📁 Repository Structure

```text
windows_cleaner/
├── README.md                      # Project Documentation (Chinese · V2.3 Safe Edition)
├── README_en.md                   # Project Documentation (English · V2.3 Safe Edition)
├── protected-paths.txt            # Custom protected directory whitelist (one path per line)
├── win-disk-clean-master.bat      # [Main Entry] Lightweight launcher (no auto-elevation)
├── win-disk-clean-master.ps1      # [Core Logic] V2.3 Safety-first PowerShell script
└── old/                           # [Archive] Early legacy scripts (contains aggressive deletion logic)
    ├── win-disk-clean-master.bat
    ├── win-disk-clean-master.ps1
    └── win-disk-smart-auditor.bat
```

---

## 🛡️ Protection Scope & `protected-paths.txt`

To prevent accidental data loss, V2.3 implements a robust multi-tier defense:

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
4. **Proprietary Outputs & Offline Builds**: Do not quarantine projects that rely on proprietary or manually placed assets within build output folders. If an inadvertent move occurs, use **Menu 8 [Restore]** immediately.
5. **User Profile Scope**: Running under a separate administrator account targets that account's `USERPROFILE` and `TEMP`. Always run the script within your regular user session without elevation.
6. **General Disclaimer**: This tool is an open-source utility. Operations involving file manipulation inherently carry environmental variances. Always keep offsite backups of essential projects and codebases.
