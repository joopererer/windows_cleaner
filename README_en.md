# Windows Disk Clean Master · V2.1 Safe Edition

<p align="left">
  <b>English</b> | <a href="README.md">简体中文</a>
</p>

> 🛡️ **A project-aware Windows disk cleanup, dev cache migration, and read-only auditing tool for power users and modern developers. Built with safety, reversibility, and data protection as primary design principles.**

---

## 📖 Philosophy & V2.1 Architectural Redesign

Traditional disk cleaning utilities often prioritize aggressive deletion. When dealing with modern, polyglot development environments, such tools frequently wipe critical package dependencies, corrupt local build states, or cause unrecoverable loss of uncommitted project artifacts.

**Windows Disk Clean Master V2.1 (Project-Aware Safe Edition)** has undergone a comprehensive architectural overhaul:
- **Safety First & Non-Destructive**: Replaces direct permanent physical deletion with a **Same-Volume Quarantine** system and a mandatory **7-day cooldown period**.
- **Deep Project Fingerprinting**: Validates strict project markers for Gradle, Maven, Rust Cargo, and Flutter/Dart before touching any folder. It never deletes directories based solely on generic names like `build` or `target`.
- **Full-Lifecycle Reversibility**: Any quarantined project build output can be restored cleanly to its original path at any time.
- **Strong Verification with Automatic Rollback**: Cross-volume migrations enforce whole-tree **SHA256 hash comparison** and keep an automatic local timestamped backup.
- **De-escalated Privileges & Read-Only Audit**: Runs without requiring administrative (UAC) elevation by default. Full-disk audits are strictly read-only, global registry keys are not modified, and background processes are never killed.

> 💡 **Legacy Archive Note**: Early versions featuring aggressive cleanup and automatic UAC elevation have been archived under the [`old/`](old/) directory.

---

## ✨ Key Features in V2.1

- **Zero-Elevation Safe Launch**: Simply double-click `win-disk-clean-master.bat`. It runs under the current standard user context without requesting UAC elevation, eliminating risks of unintended system modification.
- **Strict Project Fingerprinting**:
  - **Gradle**: Requires both `gradlew.bat` and `build.gradle(.kts)`.
  - **Maven**: Requires `pom.xml`.
  - **Rust Cargo**: Requires both `Cargo.toml` and `Cargo.lock`.
  - **Flutter/Dart**: Requires `pubspec.yaml`.
  - **JavaScript/Node.js**: Recognized and preserved; `node_modules` is marked as **permanently protected and never cleaned**.
- **Same-Volume Quarantine Mechanism**:
  - Build outputs selected for cleaning are moved to a dedicated `.wdcs-quarantine` directory on the project's parent partition.
  - Relocation stays within the same volume, completing instantly without cross-partition file-transfer risks.
  - Operations are logged in `%LOCALAPPDATA%\WinDiskCleanSafe\quarantine-v21.csv`.
  - Moving requires typing `QUARANTINE` as an explicit safety check.
- **7-Day Cooldown & Two-Phase Purge**:
  - Quarantined folders younger than 7 days are protected from permanent deletion.
  - After 7 days, users can select exactly one item at a time and must explicitly type `PURGE <ID>` to finalize permanent disk space reclamation.
- **Multi-Layer Defensive Shield**:
  - Built-in protection for drive roots, `%windir%`, `ProgramData`, and core user profile folders (Documents, Desktop, Downloads, OneDrive, etc.).
  - Supports custom absolute paths via [`protected-paths.txt`](protected-paths.txt).
  - Traversal strictly avoids following NTFS Junctions or Symlinks (fails closed on reparse points).
- **Intelligent Bilingual Support (i18n)**: Reads `HKCU:\Control Panel\International\LocaleName` to match the user's authentic Windows UI language. Switch between English and Chinese at any time with the `L` key.

---

## 🛠️ Complete Feature Matrix (Menus 1 ~ 9)

| Menu | Module | Safety Policy & Technical Details |
| :---: | :--- | :--- |
| **1** | **[Quick Clean] User %TEMP% Files** | • Previews only the active user's `%TEMP%` directory.<br>• **Preserves files active/modified within the last 7 days**.<br>• Requires typing `RECYCLE` to safely move candidates to the **Windows Recycle Bin** via native shell APIs (reversible); no direct permanent deletion.<br>• Does not manipulate Windows Update or system services. |
| **2** | **[Dev Slimming] Dependency Inspection & Project Quarantine** | • **Global Cache Protection**: Gradle Wrapper/caches, Dart Pub Cache, and npm cache are marked as `[PROTECTED]` (sizes displayed in read-only mode).<br>• **npm Diagnostics**: Detects the active `npm.cmd` and optionally runs `npm cache verify` to clean up internal cache indices.<br>• **Project Scan & Quarantine**: Enter a project parent folder (e.g. `D:\Projects`). Accurately scans for verified `build` or `target` directories.<br>• Enter an item number and type `QUARANTINE` to safely move it to `.wdcs-quarantine`. |
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
> This launches the PowerShell core in the current user context with UTF-8 encoding without requesting UAC elevation.

#### Option 2: Run via Terminal
Open any PowerShell prompt, navigate to the folder, and run:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-disk-clean-master.ps1"
```
Or directly execute in an existing session:
```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWD\win-disk-clean-master.ps1"
```

---

## 📁 Repository Structure

```text
windows_cleaner/
├── README.md                      # Project Documentation (Chinese · V2.1 Safe Edition)
├── README_en.md                   # Project Documentation (English · V2.1 Safe Edition)
├── protected-paths.txt            # Custom protected directory whitelist (one path per line)
├── win-disk-clean-master.bat      # [Main Entry] Lightweight launcher (no auto-elevation)
├── win-disk-clean-master.ps1      # [Core Logic] V2.1 Safety-first PowerShell script
└── old/                           # [Archive] Early legacy scripts (contains aggressive deletion logic)
    ├── win-disk-clean-master.bat
    ├── win-disk-clean-master.ps1
    └── win-disk-smart-auditor.bat
```

---

## 🛡️ Protection Scope & `protected-paths.txt`

To prevent accidental data loss, V2.1 implements a robust multi-tier defense:

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

1. **Build Artifacts & Rebuilding**: Quarantining a project's `build` or `target` folder removes existing compilation outputs. Subsequent runs will require rebuilding via Gradle, Maven, or Cargo.
2. **Offline Dependencies & Custom Outputs**: Avoid quarantining projects that rely on proprietary offline assets stored inside output folders. If an unintended quarantine occurs, use **Menu 8 [Restore]** to revert it immediately.
3. **Close Active IDEs**: Before performing quarantine (Menu 2) or migration (Menu 3), close Android Studio, VS Code, IntelliJ IDEA, and any terminal build processes to avoid Windows file locks.
4. **General Disclaimer**: This tool is an open-source automation utility. As with any file-system manipulation script, behavior may vary across custom environments. Always maintain offsite backups for critical repositories and data.
