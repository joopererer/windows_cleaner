# Windows Disk Clean Master (Windows 磁盘清理大师)

<p align="left">
  <b>简体中文</b> | <a href="README_en.md">English</a>
</p>

> 🚀 **专为 Windows 用户与现代开发者量身定制的轻量级、免安装、双语（中/英）系统深度清理、开发缓存无感迁移与全盘智能审计工具。**

---

## 📖 项目简介

在 Windows 开发与日常使用中，C 盘经常面临各种“空间刺客”：
- Android SDK、Gradle、Flutter/Dart Pub、Rust Cargo、npm 等开发工具的缓存文件动辄几十 GB，默认无情霸占系统盘；
- 软件卸载后遗留在非系统盘的孤岛文件夹、空壳目录与陈旧安装包；
- 长期未维护的项目中残留的巨型 `node_modules`、`target`、`build` 编译缓存；
- 运行一段时间后 Windows 临时文件和后台进程驻留内存不断膨胀。

**Windows Disk Clean Master** 无需安装任何第三方依赖，采用 **Batch + PowerShell 混合无缝执行技术（Polyglot Script）**，只需双击即可自动申请管理员权限、绕过执行策略限制启动，提供高颜值交互式菜单与原生 GUI 审计界面。

---

## ✨ 核心特性

- **免配置即开即用**：双击即可自动调起 Windows UAC 提权并以 `-ExecutionPolicy Bypass` 运行，普通用户无需手动开启系统 PowerShell 运行权限。
- **智能中英双语 (i18n)**：自动读取底层真实注册表识别当前登录用户的系统语言环境（有效规避 UAC 提权至管理员账户时界面强制变成英文的 Windows 固有缺陷），支持运行时随时按 `L` 键热切换语言。
- **全流程带进度反馈**：彻底告别黑框“假死”焦虑，清理、扫描与迁移全过程集成系统级原生双层进度条（`Write-Progress`），实时显示百分比与吞吐量。
- **开发者“无感”搬家**：利用 8 线程 `robocopy /MT:8` 高速迁移大体积缓存，并自动建立 **NTFS Junction 目录软链接**与**用户环境变量适配**，IDE、编译器完全无感知。
- **全盘智能残留审计**：融合注册表已安装软件信息库 + 桌面/开始菜单快捷方式引用库，精准识别卸载残留、孤岛软件与陈旧项目编译产物，并调用 Windows 原生 `Out-GridView` 图形界面勾选清理，支持移入回收站（可反悔）。

---

## 🛠️ 功能详解

| 序号 | 功能模块 | 说明与实现细节 |
| :---: | :--- | :--- |
| **1** | **[一键清理] 基础垃圾清理** | • 清空回收站<br>• 安全清理 `%TEMP%`（**智能保护 24 小时内活跃文件**，避免破坏当前运行中的安装包或应用）<br>• 清理 `C:\Windows\Temp` 与 `SoftwareDistribution\Download`（自动停启更新服务 `wuauserv`） |
| **2** | **[开发瘦身] 开发者构建缓存扫描** | 扫描并清理 Android Gradle Wrapper、Gradle Caches、Dart Pub Cache、Dart Analysis Server、npm 缓存目录，清理前计算各目录体积并提供确认询问。 |
| **3** | **[无感迁移] 开发缓存一键搬家 / 软链接** | **模式 A（主流开发环境一键搬迁）**：<br>• 支持 `.gradle`、`Pub Cache`、`.dartServer`、`Android AVD`、`Android SDK`、`Rust Cargo`、`npm-cache`<br>• 自动终止可能占用文件锁的后台常驻进程（`java`, `dart`, `adb`）<br>• 8 线程 Robocopy 迁移后自动建立 NTFS Junction 软链接并更新对应的系统环境变量（如 `GRADLE_USER_HOME` 等）<br>**模式 B（自定义目录软链接迁移）**：输入任意源目录与目标盘路径，执行安全迁移与符号链接。 |
| **4** | **[目录迁移] 修改默认软件安装路径** | 一键修改注册表 `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion` 下的 `ProgramFilesDir` 和 `ProgramFilesDir (x86)` 为指定数据盘（如 `D:\Program Files`），使后续安装的 MSI/NSIS 软件默认装入大容量盘。 |
| **5** | **[内存优化] 释放工作集内存** | P/Invoke 动态加载 Windows 原生动态链接库 `psapi.dll`，调用 `EmptyWorkingSet` API，快速回收系统后台空闲进程占用的物理常驻内存。 |
| **6** | **[实时监护] C 盘剩余空间后台监控** | 启动轻量级后台轮询监控（默认每 5 分钟），当系统盘可用空间低于 **5.0 GB** 临界值时触发原生系统弹窗警报，防止 Gradle 编译或系统大版本更新突发爆盘。 |
| **7** | **[全盘审计] 卸载残留与大文件智能审计** | • 扫描指定盘符根目录与应用目录，自动对比注册表和快捷方式库<br>• 智能归纳 5 大类别：**空壳残留**、**疑似卸载残留**、**长期未变动孤岛目录**、**陈旧项目编译产物**（>30天未动且 >100MB 的 `node_modules`、`target`、`build`、`.gradle`）、**沉睡大体积安装包/压缩包**<br>• 原生 GUI 交互表格多选，支持 **安全移入回收站** 或 **彻底物理删除**。 |

---

## 🚀 快速上手

### 运行方式
- **方式一（推荐，双击启动）**：直接鼠标双击运行 `win-disk-clean-master.bat`。
- **方式二（单功能全盘审计）**：若只需对某个盘进行残留分析与可视化清理，直接双击运行 `win-disk-smart-auditor.bat`。
- **方式三（终端启动）**：在管理员命令行中执行：
  ```cmd
  # CMD
  win-disk-clean-master.bat

  # PowerShell
  .\win-disk-clean-master.ps1
  ```

---

## 📁 项目目录结构

```text
windows_cleaner/
├── README.md                      # 项目说明文档（中文版）
├── README_en.md                   # Project Documentation (English)
├── win-disk-clean-master.bat      # 【主入口】Windows 磁盘清理大师（双击直接运行）
├── win-disk-clean-master.ps1      # PowerShell 原生版本
└── win-disk-smart-auditor.bat     # 【独立组件】全盘智能审计独立版 (GUI)
```

---

## ⚠️ 免责声明与安全须知

1. **软链接操作**：在执行开发缓存迁移（NTFS Junction）前，程序会自动尝试结束 `java`、`dart`、`adb` 进程。建议在迁移前**主动保存并退出 Android Studio、VS Code、IntelliJ IDEA 等集成开发环境**。
2. **全盘审计清理**：审计工具识别出的“疑似卸载残留”主要是依据“无主可执行文件且未在系统注册表中找到”。若用户在对应目录下存放了纯个人素材、备份照片或自建数据文件，请在 GUI 窗口核对完整路径后再行勾选，建议优先选用【安全移入回收站】模式以便反悔恢复。
