# Windows Disk Clean Master (Windows 磁盘清理大师) · V2.1 安全版

<p align="left">
  <b>简体中文</b> | <a href="README_en.md">English</a>
</p>

> 🛡️ **专为 Windows 用户与现代开发者量身定制的“项目感知型”磁盘清理、开发缓存安全迁移与只读全盘审计工具。以安全、可逆、防误删为第一设计原则。**

---

## 📖 核心理念与 V2.1 架构革新

传统的磁盘清理工具往往追求“一键暴力清空”，在面对现代复杂的多语言开发环境时，极易误删重要包依赖、破坏项目配置或造成未提交编译产物不可逆丢失。

**Windows Disk Clean Master V2.1（项目感知安全版）** 进行了彻底的架构重构：
- **安全第一，非破坏性**：全面摒弃直接永久物理删除，引入 **同卷安全隔离区（Quarantine）** 与 **7 天冷静期** 机制；
- **项目特征深度感知**：严格识别 Gradle、Maven、Rust Cargo、Flutter/Dart 项目特征，绝不单凭文件夹名（如 `build`/`target`）盲删任何目录；
- **全生命周期可逆恢复**：所有被隔离的项目构建产物均支持一键原路无损恢复；
- **迁移强校验与自动回滚**：跨卷缓存迁移强制执行全文件 **SHA256 哈希比对**，并保留重命名备份；
- **去特权化与只读审计**：启动不默认索取 Administrator 权限，全盘审计全面改为只读报告，不修改全局系统注册表，不强制结束外部进程。

> 💡 **版本归档提示**：旧版包含暴力提权清理逻辑的脚本已完整归档至 [`old/`](old/) 目录下。

---

## ✨ V2.1 核心特性

- **零配置安全启动**：双击 `win-disk-clean-master.bat` 即可启动，默认在当前用户权限下执行，不请求 UAC 提权，杜绝越权破坏系统文件的隐患。
- **项目特征严格比对**：
  - **Gradle**：必须包含 `gradlew.bat` 与 `build.gradle(.kts)`；
  - **Maven**：必须包含 `pom.xml`；
  - **Rust Cargo**：必须包含 `Cargo.toml` 与 `Cargo.lock`；
  - **Flutter/Dart**：必须包含 `pubspec.yaml`；
  - **JavaScript/Node.js**：仅做识别并将其依赖 `node_modules` 标记为**永久保护，绝不自动清理**。
- **安全隔离区（Quarantine）机制**：
  - 待清理的构建产物移入项目上级同分区的 `.wdcs-quarantine` 专用隔离目录；
  - 同卷移动不跨分区，瞬间完成且不增加数据损坏风险，状态记录于 `%LOCALAPPDATA%\WinDiskCleanSafe\quarantine-v21.csv`；
  - 需手动逐字输入 `QUARANTINE` 确认。
- **7 天冷静期与两阶段销毁**：
  - 隔离未满 7 天的项目受系统保护，**拒绝永久物理清除**；
  - 满 7 天后，每次仅允许选择 1 项，并需逐字输入 `PURGE <ID>` 进行二次强校验，确保开发人员充分验证项目离线构建能力后再彻底回收空间。
- **多层立体防护网与白名单**：
  - 内置保护系统根目录、Windows、ProgramData、用户核心文件夹（文档/桌面/下载/OneDrive 等）；
  - 支持根目录下的 [`protected-paths.txt`](protected-paths.txt) 逐行配置受保护绝对路径；
  - 遍历过程中全面防御 NTFS Junction / 符号链接穿透，遇到重解析点立即 Fail-closed 终止，坚决不跟入遍历。
- **智能中英双语 (i18n)**：自动读取底层注册表 `HKCU:\Control Panel\International\LocaleName` 锁定用户实际区域，运行中按 `L` 键可随时热切换语言。

---

## 🛠️ 功能模块全览 (1 ~ 9)

| 菜单编号 | 功能模块 | 安全策略与实现细节 |
| :---: | :--- | :--- |
| **1** | **[一键清理] 用户临时文件** | • 仅预览当前登录用户的 `%TEMP%` 目录；<br>• **智能保护 7 天内活跃修改的文件**，跳过正在写入或近期产生的数据；<br>• 输入 `RECYCLE` 确认后，通过系统原生接口移入 **回收站**（可反悔还原），不直接物理删除；<br>• 不再触碰 Windows Update 服务与系统临时目录。 |
| **2** | **[开发瘦身] 构建缓存只读与项目产物隔离** | • **全局包依赖保护**：Gradle Wrapper/caches、Dart Pub Cache、npm cache 等标记为 `[PROTECTED]` 只读显示大小，绝不删除；<br>• **npm 诊断**：自动寻找当前生效的 `npm.cmd`，可选执行 `npm cache verify` 整理缓存索引；<br>• **项目扫描与隔离**：输入项目父目录（如 `D:\Projects`），严格验证项目特征后仅列出对应 `build` 或 `target`；<br>• 输入编号并确认 `QUARANTINE` 后，安全移动到同卷 `.wdcs-quarantine` 隔离区。 |
| **3** | **[无感迁移] 跨卷目录安全迁移** | • **前置空间预检**：目标卷必须剩余至少 `源体积 × 1.1 + 100MB` 冗余可用空间；<br>• **8线程 Robocopy 搬迁**：执行带错误限制的完整数据复制；<br>• **严格 SHA256 校验**：复制后对所有文件逐一进行 SHA256 强哈希校验；<br>• **回滚备份与安全软链**：校验通过后将源目录重命名为 `.wdcs-backup-yyyyMMdd-HHmmss` 保留本地备份，再建立 NTFS Junction（`mklink /J`）；如遇异常自动完整回滚，绝不破坏源数据。 |
| **4** | **[目录迁移] 查看软件安装路径** | **完全只读**。安全读取并展示注册表中的 `ProgramFilesDir` 和 `ProgramFilesDir (x86)` 当前指向，不再擅自篡改系统全局注册表配置，倡导在安装程序中自行选择路径。 |
| **5** | **[内存优化] 查看进程内存占用** | **完全只读**。按物理工作集从大到小列出占用内存最高的前 15 个后台进程，不再强制调用底层 `EmptyWorkingSet`，避免导致应用进程发生内存颠簸与卡顿。 |
| **6** | **[实时监护] C 盘剩余空间监控** | 启动轻量级后台轮询监控（每 5 分钟），当系统盘可用空间低于 **5.0 GB** 时弹出系统级桌面通知，预防编译器突然爆盘中断。 |
| **7** | **[全盘审计] 卸载残留与大文件报告** | **完全只读报告，移除任何删除能力**。<br>• 扫描指定盘符，识别可疑项目目录（`node_modules`、`build`、`target` 等）及 14 天前大于 100MB 的旧安装包/压缩包；<br>• 仅生成分析报告并保存至 `%LOCALAPPDATA%\WinDiskCleanSafe\logs`，可在 `Out-GridView` 表格中交互查阅，绝不提供批量删除按钮（因文件名和修改时间不能作为安全删除证据）。 |
| **8** | **[隔离恢复] 恢复已隔离的构建产物** | 读取隔离索引清单，将处于 `Quarantined` 状态的目录一键**原路无损恢复**回项目目录；若原路径已存在同名目录则严格拒绝覆盖。 |
| **9** | **[隔离清理] 永久回收隔离空间** | 真正回收磁盘空间的唯一入口：<br>• **必须隔离满 7 天** 才会出现在候选列表中；<br>• 每次仅限选中 1 项；<br>• 必须严格输入 `PURGE <ID>`（如 `PURGE 1a2b3c...`）进行防误触二次确认后才执行永久物理清除。 |

---

## 🚀 快速上手

### 运行环境要求
- **操作系统**：Windows 10 / Windows 11 / Windows Server 2016+
- **环境要求**：Windows PowerShell 5.1 或更高版本（系统自带，无需安装任何额外包）
- **终端推荐**：Windows Terminal，控制台默认支持 UTF-8（代码内自动调用 `chcp 65001`）

### 启动方式

#### 方式一：一键双击运行（推荐）
直接鼠标双击运行根目录下的 **`win-disk-clean-master.bat`** 即可。
> 该脚本会自动配置 UTF-8 编码，以当前用户身份拉起 PowerShell 核心，无需手动提权。

#### 方式二：在终端中直接执行 PowerShell
打开任意 PowerShell 终端窗口，进入当前项目目录并运行：
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\win-disk-clean-master.ps1"
```
或者在当前 PowerShell 会话中直接点运行：
```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PWD\win-disk-clean-master.ps1"
```

---

## 📁 仓库目录结构

```text
windows_cleaner/
├── README.md                      # 项目说明文档（中文版 · V2.1 安全版）
├── README_en.md                   # Project Documentation (English · V2.1 Safe Edition)
├── protected-paths.txt            # 自定义受保护路径白名单（每行一个绝对路径）
├── win-disk-clean-master.bat      # 【主入口】轻量级启动批处理（双击运行，无自动提权）
├── win-disk-clean-master.ps1      # 【核心实现】V2.1 安全优先版 PowerShell 脚本
└── old/                           # 【旧版归档】历史早期版本文件（含直接提权与强制清理逻辑）
    ├── win-disk-clean-master.bat
    ├── win-disk-clean-master.ps1
    └── win-disk-smart-auditor.bat
```

---

## 🛡️ 保护范围与 `protected-paths.txt` 说明

为了防止任何误操作风险，V2.1 构建了立体防护系统：

### 1. 内置受保护路径
系统自动锁死以下路径及其子目录，任何扫描与迁移操作均不可将其作为目标：
- 卷根目录（如 `C:\`, `D:\`）
- 系统核心目录：`%windir%`, `C:\Program Files`, `C:\Program Files (x86)`, `C:\ProgramData`
- 用户核心资料库：`Desktop`, `Documents`, `Pictures`, `Music`, `Videos`, `Downloads`, `OneDrive`
- 本工具日志与清单库：`%LOCALAPPDATA%\WinDiskCleanSafe`

### 2. 用户自定义保护清单 (`protected-paths.txt`)
您可以在根目录的 [`protected-paths.txt`](protected-paths.txt) 中追加自定义需要绝对保护的目录（每行一个完整绝对路径，支持 `#` 注释）：
```text
# 每行一个绝对路径，程序将完全保护其不被迁移、不被遍历、不被隔离
D:\Projects\ProductionApp
E:\ImportantBackups
```

---

## ⚠️ 限制与安全须知

1. **构建工具与依赖重建**：使用菜单 2 隔离项目的 `build` 或 `target` 目录后，项目构建产物将被移走，后续需要依赖 Gradle/Maven/Cargo 重新执行构建。
2. **离线依赖与专有输出**：若您的构建依赖特殊离线资源或包含手写放入输出目录的内容，请勿隔离。若出现误操作，可立刻通过 **菜单 8 [隔离恢复]** 原路召回。
3. **关闭相关 IDE 与任务**：在执行菜单 2（隔离）或菜单 3（迁移）前，请主动关闭 Android Studio、VS Code、IntelliJ IDEA 及运行中的编译进程，避免因 Windows 文件锁导致操作中断。
4. **非官方工具免责说明**：本工具为开源辅助运维脚本，运行任何具备文件操作能力的工具均存在客观环境差异风险，对核心项目操作前建议做好独立异地备份。
