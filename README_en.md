# Windows Disk Clean Master

<p align="left">
  <b>English</b> | <a href="README.md">简体中文</a>
</p>

> 🚀 **A lightweight, portable, bilingual (EN/ZH) Windows disk optimization toolkit for power users and modern developers. Features deep junk cleaning, seamless dev cache migration with NTFS junctions, and intelligent whole-disk leftover auditing.**

---

## 📖 Introduction

In modern software development and everyday Windows usage, drive `C:` frequently suffers from silent disk space exhaustion:
- Heavyweight cache directories from build tools like Android SDK, Gradle, Flutter/Dart Pub, Rust Cargo, and npm occupy tens of gigabytes by default on the system drive.
- Remnant folders, orphaned directories, and stale installers left behind after software uninstallation on non-system drives.
- Huge, forgotten `node_modules`, `target`, and `build` folders across inactive development projects.
- System temporary files, Windows Update download caches, and background process working sets steadily expanding over time.

**Windows Disk Clean Master** requires zero third-party installations. Using a **Batch + PowerShell Polyglot script architecture**, it can be launched directly with a double-click. It automatically requests administrative privileges via UAC, bypasses PowerShell execution policy restrictions, and provides a polished interactive console menu along with a native Windows GUI audit grid.

---

## ✨ Key Features

- **Double-Click & Run (Zero Setup)**: Automatically elevates to Administrator privileges via Windows UAC and executes under `-ExecutionPolicy Bypass`. No need to manually configure system PowerShell execution policies.
- **Smart Bilingual Support (i18n)**: Reads the authentic user locale from `HKCU:\Control Panel\International\LocaleName` to prevent Windows UAC elevation from forcing an English UI on localized systems. Supports live language switching at any time by pressing `L`.
- **Real-Time Visual Progress**: Say goodbye to frozen console windows. Features native dual-layer progress bars (`Write-Progress`) displaying real-time percentages, throughput, and item names across all cleanup, scanning, and migration tasks.
- **Seamless Dev Cache Relocation**: Uses 8-threaded `robocopy /MT:8` to safely migrate bulky caches to secondary drives, creating **NTFS Junction directory links** (`mklink /J`) and updating user environment variables automatically. IDEs and compilers continue working with zero friction.
- **Smart Whole-Disk Leftover Audit**: Cross-references the Windows Registry uninstallation database with Desktop and Start Menu shortcut (`.lnk`) targets to detect orphaned apps, empty folders, and stale build artifacts. Selected items can be reviewed via a native `Out-GridView` GUI and safely moved to the **Recycle Bin** (reversible) or permanently deleted.

---

## 🛠️ Feature Breakdown

| No. | Module | Description & Technical Details |
| :---: | :--- | :--- |
| **1** | **[Quick Clean] Basic Junk Cleanup** | • Empty Recycle Bin<br>• Safely clean user `%TEMP%` (**intelligently preserves files active within the last 24 hours** to prevent corrupting running installers)<br>• Clean `C:\Windows\Temp` and `SoftwareDistribution\Download` (automatically manages `wuauserv` service) |
| **2** | **[Dev Diet] Dev Build Cache Scanner** | Scans and cleans Gradle Wrapper distributions, Gradle Caches, Dart Pub Cache, Dart Analysis Server, and npm cache with folder size calculation and confirmation prompts. |
| **3** | **[Seamless Move] Cache Relocation / Symlinks** | **Mode A (Popular Dev Environments)**:<br>• Supports `.gradle`, `Pub Cache`, `.dartServer`, `Android AVD`, `Android SDK`, `Rust Cargo`, `npm-cache`<br>• Automatically terminates background daemons (`java`, `dart`, `adb`) to release file locks<br>• Migrates via 8-thread Robocopy, creates NTFS Junction links, and sets user environment variables (e.g., `GRADLE_USER_HOME`)<br>**Mode B (Custom Directory Relocation)**: Relocate any custom directory on `C:` to another drive with symlinks. |
| **4** | **[Path Shift] Change Default Install Drive** | Updates `ProgramFilesDir` and `ProgramFilesDir (x86)` under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion` to a preferred drive (e.g., `D:\Program Files`), making new MSI/NSIS software install to secondary drives by default. |
| **5** | **[RAM Booster] Trim Working Set Memory** | Uses P/Invoke to invoke `EmptyWorkingSet` from Windows native `psapi.dll`, immediately reclaiming idle physical memory held by background processes. |
| **6** | **[Live Guard] Real-Time C: Free Space Monitor** | Runs a background monitoring loop (checks every 5 minutes). Triggers a native Windows modal warning if free space on `C:` drops below **5.0 GB**, preventing sudden Gradle/Dart build failures. |
| **7** | **[Disk Audit] Leftovers & Large File Audit** | • Scans any selected drive letter and compares directories against the Registry and shortcut targets<br>• Identifies 5 major categories: **Empty Shell Folders**, **Likely Leftovers**, **Unregistered Orphan Directories** (inactive >60 days), **Stale Build Artifacts** (`node_modules`, `target`, `build` >100MB & inactive >30 days), and **Old Large Installers/Archives** (>100MB & >14 days)<br>• Native GUI selection dialog with options to **Send to Recycle Bin** (safe/reversible) or **Permanently Delete**. |

---

## 🚀 Quick Start

### How to Run
- **Method 1 (Recommended - Double-Click)**: Simply double-click `win-disk-clean-master.bat`.
- **Method 2 (Standalone Disk Auditor)**: To audit and clean a specific drive directly in GUI mode, double-click `win-disk-smart-auditor.bat`.
- **Method 3 (Terminal / CLI)**: Run from an elevated terminal:
  ```cmd
  # Command Prompt (CMD)
  win-disk-clean-master.bat

  # PowerShell
  .\win-disk-clean-master.ps1
  ```

---

## 📁 Repository Structure

```text
windows_cleaner/
├── README.md                      # Project Documentation (Chinese / 简体中文)
├── README_en.md                   # Project Documentation (English)
├── win-disk-clean-master.bat      # [Main Entry] Windows Disk Clean Master (Double-click runnable)
├── win-disk-clean-master.ps1      # Native PowerShell script version
└── win-disk-smart-auditor.bat     # [Standalone Tool] Smart Disk Leftover Auditor (GUI)
```

---

## ⚠️ Safety Guidelines & Disclaimer

1. **Symlink Operations**: Before relocating development caches, the script will attempt to stop `java`, `dart`, and `adb` background processes. It is highly recommended to **save your work and close Android Studio, VS Code, and IntelliJ IDEA** prior to migration.
2. **Whole-Disk Audit Cleanup**: Directories marked as "Likely Leftover" are flagged because they lack executable binaries and have no matching Windows Registry entry. If you store personal media, documents, or custom datasets in these directories, review their full paths in the GUI before deletion. Choosing the **Send to Recycle Bin** mode is strongly advised for safe recovery.

