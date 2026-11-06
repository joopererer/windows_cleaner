<# :
@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::Default))"
pause
exit /b
#>

# Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== 1. 修复：精准跟随真实用户系统语言（抗UAC提权英文干扰） ====================
$userLocale = $null
try {
    $userLocale = (Get-ItemProperty -Path "HKCU:\Control Panel\International" -Name "LocaleName" -ErrorAction Stop).LocaleName
} catch {
    $userLocale = [System.Globalization.CultureInfo]::CurrentUICulture.Name
}

$script:Lang = if ($userLocale -match '^zh') { 'ZH' } else { 'EN' }

$I18N = @{
    ZH = @{
        Title           = "Windows 磁盘清理大师 - 深度清理、缓存迁移与全盘审计"
        Status          = "当前 C 盘状态: 可用 {0} GB / 已用 {1} GB | 语言: 中文 (系统识别: $userLocale)"
        M1              = "1. [一键清理] 回收站 + 用户 %TEMP% + Windows 系统临时文件 (带进度)"
        M2              = "2. [开发瘦身] 扫描并清理 Gradle / Dart / Pub / npm 构建缓存 (带进度)"
        M3              = "3. [无感迁移] 开发缓存一键搬家 (含环境变量) 或 自定义目录软链接迁移"
        M4              = "4. [目录迁移] 修改系统默认 Program Files 安装注册表路径"
        M5              = "5. [内存优化] 立即释放后台进程驻留工作集内存 (EmptyWorkingSet)"
        M6              = "6. [实时监护] 开启 C 盘剩余空间后台监控预警 (低于 5GB 弹窗)"
        M7              = "7. [全盘审计] 扫描任意盘卸载残留/孤岛目录/老旧编译产物 (GUI勾选清理)"
        ML              = "L. [Language] 切换语言为 English (Switch to English)"
        MQ              = "Q. 退出 (Quit)"
        PromptChoice    = "请选择要执行的操作编号"
        CountingSub     = "正在统计子目录结构..."
        CleaningItem    = "[{0}%] ({1}/{2}) 正在清理: {3}"
        LangSwitched    = "[*] 语言已成功切换为: 中文 (Chinese)"
        
        CleanAct        = "基础垃圾清理"
        Step1Recycle    = "[1/4] 正在清空回收站..."
        Step2TempScan   = "[2/4] 正在安全清理用户临时目录 ({0}) [保护最近 {1} 小时活跃文件]..."
        TempProgress    = "进度: {0}% ({1}/{2}) | 已释放: {3} MB"
        TempFreed       = "      -> 用户临时目录已释放 {0} MB"
        Step3WinTemp    = "[3/4] 正在清理 Windows 系统临时目录 (C:\Windows\Temp)..."
        Step4WinUpd     = "[4/4] 正在清理 Windows Update 下载缓存..."
        BasicDone       = "[√] 基础清理完成！当前 C 盘可用: {0} GB (本次共腾出 {1} GB)"

        DevScanStart    = "[*] 正在扫描开发缓存目录（目录较大时统计体积需数秒，请稍候）..."
        DevScanAct      = "扫描开发者构建缓存 ({0}/{1})"
        DevCalcAct      = "正在计算 [{0}] 占用空间"
        DevScanSub      = "扫描子项 ({0}/{1}): {2}"
        DevFound        = "发现 [{0}] 占用: {1} GB ({2})"
        DevAskClean     = "是否清理该目录？(y/n)"
        DevCleaning     = "[*] 正在清理 {0} ，请观察上方进度条..."
        DevCleaned      = "[√] 已清理 {0}"
        DevEmptySkip    = "    -> 目录已为空，自动跳过。"
        DevAllDone      = "[√] 开发缓存瘦身完毕！C 盘最新可用空间: {0} GB (共释放 {1} GB)"

        MigTitle        = "================ [无感迁移模式选择] ================"
        MigModeA        = "A. 【预设一键搬家】自动扫描 Gradle/Pub/Android/Cargo 等缓存并迁移 + 配环境变量"
        MigModeB        = "B. 【自定义目录迁移】手动输入任意 C 盘目录路径迁移至其他盘"
        MigPromptMode   = "请选择模式 (A/B，输入 Q 返回主菜单)"
        MigTargetPrompt = "请输入目标盘的缓存根目录 (直接回车默认为 D:\DevCache)"
        MigScanning     = "正在扫描本机开发缓存状态..."
        MigAlreadyLink  = "[{0}] {1} -> [已迁移/软链接就绪] ({2})"
        MigItemInfo     = "[{0}] {1} | 占用: {2} GB"
        MigItemPath     = "    源路径: {0} -> 目标: {1}"
        MigNoneNeeded   = "[√] 未发现需要迁移的开发缓存，或所有目录均已建立软链接！"
        MigSelectPrompt = "请输入要搬家的编号 (多个用逗号如 1,2；输入 ALL 全部搬家；输入 Q 取消)"
        MigKillProc     = "[*] 正在停止后台可能锁定文件的守护进程 (java / dart / adb)..."
        MigStartItem    = ">>> 开始搬家: {0} ({1} GB) <<<"
        MigEnvSet       = "    [环境变量已配置] {0} = {1}"
        MigSuccess      = "    [√] {0} 搬家圆满完成！"
        MigFail         = "    [!] 部分文件被占用 (ExitCode: {0})，请关闭 IDE 后重试！"
        MigSrcPrompt    = "请输入要迁移的 C 盘源目录完整路径 (例如 C:\Users\univasity\.gradle)"
        MigDstPrompt    = "请输入目标盘路径 (例如 D:\DevCache\.gradle)"
        MigSrcNotExist  = "[!] 源目录不存在！"
        MigAlreadyJunc  = "[!] 该目录已经是软链接 (Junction)，无需重复迁移！"
        MigRobocopyRun  = "[*] 正在调用 Robocopy 8线程迁移数据..."

        RegDrivePrompt  = "请输入希望默认安装软件的盘符 (例如 D)"
        RegDone         = "[√] 注册表默认安装路径已修改为 {0} 盘！（注：对标准 MSI/NSIS 安装包立即生效）"

        MemStart        = "[*] 正在调用 psapi.dll 释放后台进程多余工作集内存..."
        MemAct          = "释放物理内存工作集"
        MemStatus       = "进度: {0}% ({1}/{2}) 正在整理进程: {3}"
        MemDone         = "[√] 内存整理完成！共整理 {0} 个进程，闲置物理内存已回收。"

        MonStart        = "[*] 已启动 C 盘空间实时监控 (按 Ctrl+C 停止)..."
        MonNormal       = "[{0}] 巡检正常 - 当前 C 盘剩余可用空间: {1} GB"
        MonWarnPopup    = "警告：C 盘剩余空间仅剩 {0} GB！`n这会导致 Gradle 构建和 Dart 编译失败，请立即运行清理！"
        MonWarnTitle    = "C盘空间监护中心"

        AudTitle        = "     全盘卸载残留、孤岛目录与沉睡大文件智能审计 (GUI勾选版)  "
        AudDrivePrompt  = "请输入要深度扫描的盘符 (例如 D 或 C，不要带冒号)"
        AudNotExist     = "[!] 盘符路径 {0} 不存在！"
        AudStep1        = "[1/4] 正在读取系统注册表已安装软件库与快捷方式引用库..."
        AudStep2        = "[2/4] 正在分析 {0} 下的软件目录与卸载残留..."
        AudStep3        = "[3/4] 正在全盘检索遗忘的编译缓存 (node_modules / target / build) 与大体积安装包..."
        AudStep4        = "[4/4] 扫描完成！正在弹出可视化表格窗口（按住 Ctrl 可多选要清理的项，点击右下角【确定】）..."
        AudCleanDisk    = "[√] 扫描完成！{0} 非常干净，未发现明显的卸载残留或大体积冗余项。"
        AudCat1         = "【1-空壳残留】空文件夹"
        AudAdv1         = "内部无任何文件，可直接清理"
        AudCat2         = "【2-疑似卸载残留】无主程序且未注册"
        AudAdv2         = "无 .exe 且不在注册表 (若为纯个人素材/数据目录请勿勾选)"
        AudCat3         = "【3-未注册孤岛目录】长期未变动"
        AudAdv3         = "含可执行文件但未在系统注册，已 {0} 天未变动"
        AudCat4         = "【4-陈旧项目编译产物】可随时重建"
        AudAdv4         = "老项目构建缓存 (>100MB)，删后可通过 npm/cargo/flutter 重新生成"
        AudCat5         = "【5-沉睡安装包/压缩包】大体积单文件"
        AudAdv5         = "下载或解压后遗留的大体积包 (>100MB)"
        AudGridTitle    = "[磁盘智能审计报告 - {0}] 请按住 Ctrl 多选要清理的条目，然后点击右下角 [确定/OK]"
        AudSelectedMsg  = "您共勾选了 {0} 个条目，总计约 {1} GB："
        AudDelPrompt    = "请选择清理方式：[1] 安全移入回收站 (推荐，可还原)  [2] 永久彻底删除  [Q] 取消操作"
        AudMovingRec    = "正在移入回收站: {0} ..."
        AudRecDone      = "[√] 全部选中项已安全移入回收站！"
        AudPermDeleting = "正在永久删除: {0} ..."
        AudPermDone     = "[√] 全部选中项已彻底删除！"
        AudCancel       = "[*] 未选择任何条目，已安全返回。"
    }
    EN = @{
        Title           = "Windows Disk Clean Master: Deep Clean, Cache Migration & Smart Audit"
        Status          = "C: Drive Status: Free {0} GB / Used {1} GB | Lang: English (System: $userLocale)"
        M1              = "1. [Quick Clean] Recycle Bin + %TEMP% + Windows Temp Files (with Progress)"
        M2              = "2. [Dev Slimming] Scan & Clean Gradle / Dart / Pub / npm Build Caches"
        M3              = "3. [Seamless Migrate] One-Click Dev Cache Migration (Symlink + Env Vars)"
        M4              = "4. [Default Install] Change Default 'Program Files' Install Drive in Registry"
        M5              = "5. [RAM Optimizer] Trim Background Process Working Set Memory (EmptyWorkingSet)"
        M6              = "6. [Disk Guard] Real-Time C: Free Space Monitor (Alert < 5GB)"
        M7              = "7. [Smart Auditor] Scan Any Drive for Leftovers/Orphans/Old Builds (GUI Select)"
        ML              = "L. [语言切换] 切换语言为中文 (Switch to Chinese)"
        MQ              = "Q. Quit"
        PromptChoice    = "Select an option"
        CountingSub     = "Counting subdirectories..."
        CleaningItem    = "[{0}%] ({1}/{2}) Cleaning: {3}"
        LangSwitched    = "[*] Language successfully switched to: English"

        CleanAct        = "Basic Disk Cleanup"
        Step1Recycle    = "[1/4] Emptying Recycle Bin..."
        Step2TempScan   = "[2/4] Safely cleaning user %TEMP% ({0}) [Protecting files active in last {1}h]..."
        TempProgress    = "Progress: {0}% ({1}/{2}) | Freed: {3} MB"
        TempFreed       = "      -> User %TEMP% freed {0} MB"
        Step3WinTemp    = "[3/4] Cleaning Windows Temp directory (C:\Windows\Temp)..."
        Step4WinUpd     = "[4/4] Cleaning Windows Update download cache..."
        BasicDone       = "[√] Basic cleanup completed! C: Free Space: {0} GB (Freed {1} GB)"

        DevScanStart    = "[*] Scanning developer cache directories (large folders may take a few seconds)..."
        DevScanAct      = "Scanning Dev Build Caches ({0}/{1})"
        DevCalcAct      = "Calculating size of [{0}]"
        DevScanSub      = "Scanning item ({0}/{1}): {2}"
        DevFound        = "Found [{0}] Size: {1} GB ({2})"
        DevAskClean     = "Clean this directory? (y/n)"
        DevCleaning     = "[*] Cleaning {0}, please check the progress bar above..."
        DevCleaned      = "[√] Cleaned {0}"
        DevEmptySkip    = "    -> Directory is already empty, skipping."
        DevAllDone      = "[√] Dev cache cleanup finished! C: Free Space: {0} GB (Freed {1} GB)"

        MigTitle        = "================ [Seamless Migration Mode] ================"
        MigModeA        = "A. [Preset Dev Migration] Auto-scan Gradle/Pub/Android/Cargo + Symlink + Set Env Vars"
        MigModeB        = "B. [Custom Directory] Manually migrate any C: folder to another drive via Junction"
        MigPromptMode   = "Select Mode (A/B, or Q to return)"
        MigTargetPrompt = "Enter target root path for caches (Press Enter for default D:\DevCache)"
        MigScanning     = "Scanning local developer caches..."
        MigAlreadyLink  = "[{0}] {1} -> [Already Migrated / Symlink Active] ({2})"
        MigItemInfo     = "[{0}] {1} | Size: {2} GB"
        MigItemPath     = "    Source: {0} -> Target: {1}"
        MigNoneNeeded   = "[√] No unmigrated dev caches found, or all directories are already linked!"
        MigSelectPrompt = "Enter item numbers to migrate (e.g. 1,2 or ALL, or Q to cancel)"
        MigKillProc     = "[*] Stopping background daemon processes (java / dart / adb) to release file locks..."
        MigStartItem    = ">>> Migrating: {0} ({1} GB) <<<"
        MigEnvSet       = "    [Env Var Configured] {0} = {1}"
        MigSuccess      = "    [√] {0} migrated successfully!"
        MigFail         = "    [!] Some files were locked (ExitCode: {0}), please close IDEs and retry!"
        MigSrcPrompt    = "Enter full source path on C: (e.g. C:\Users\univasity\.gradle)"
        MigDstPrompt    = "Enter target path on destination drive (e.g. D:\DevCache\.gradle)"
        MigSrcNotExist  = "[!] Source directory does not exist!"
        MigAlreadyJunc  = "[!] Directory is already a NTFS Junction symlink!"
        MigRobocopyRun  = "[*] Running 8-thread Robocopy migration..."

        RegDrivePrompt  = "Enter preferred default installation drive letter (e.g. D)"
        RegDone         = "[√] Default Program Files registry path set to {0}:\! (Effective immediately for MSI/NSIS)"

        MemStart        = "[*] Calling psapi.dll EmptyWorkingSet to trim background memory..."
        MemAct          = "Optimizing RAM Working Set"
        MemStatus       = "Progress: {0}% ({1}/{2}) Trimming process: {3}"
        MemDone         = "[√] Memory optimization complete! Trimmed {0} processes."

        MonStart        = "[*] Real-time C: space monitor started (Press Ctrl+C to stop)..."
        MonNormal       = "[{0}] Check OK - Current C: free space: {1} GB"
        MonWarnPopup    = "WARNING: C: drive free space is down to {0} GB!`nThis may break Gradle & Dart builds. Please clean up now!"
        MonWarnTitle    = "C: Drive Space Monitor"

        AudTitle        = "     Smart Disk Auditor: App Leftovers, Orphans & Old Builds (GUI)  "
        AudDrivePrompt  = "Enter drive letter to scan deeply (e.g. D or C, without colon)"
        AudNotExist     = "[!] Drive path {0} does not exist!"
        AudStep1        = "[1/4] Indexing installed software from Registry & Shortcut (.lnk) targets..."
        AudStep2        = "[2/4] Analyzing directories and uninstall leftovers on {0}..."
        AudStep3        = "[3/4] Searching for stale build artifacts (node_modules/target/build) & large archives..."
        AudStep4        = "[4/4] Scan complete! Opening GUI table (Hold Ctrl to multi-select items, then click [OK])..."
        AudCleanDisk    = "[√] Scan complete! {0} is clean, no obvious leftovers or large redundant items found."
        AudCat1         = "[1-Empty Folder] 0-Byte Directory"
        AudAdv1         = "Contains no files, safe to delete"
        AudCat2         = "[2-Likely Leftover] Unregistered & No .exe"
        AudAdv2         = "No executables & not in Registry (Do not delete if it's personal media/data)"
        AudCat3         = "[3-Unregistered Orphan] Inactive > 60 Days"
        AudAdv3         = "Has executables but not registered in Windows, inactive for {0} days"
        AudCat4         = "[4-Stale Build Cache] Rebuildable Anytime"
        AudAdv4         = "Old build cache (>100MB), can be regenerated via npm/cargo/flutter"
        AudCat5         = "[5-Old Archive/Installer] Large Single File"
        AudAdv5         = "Large installer or archive (>100MB) older than 14 days"
        AudGridTitle    = "[Smart Disk Audit Report - {0}] Hold Ctrl to select items to clean, then click [OK] at bottom-right"
        AudSelectedMsg  = "You selected {0} items, totaling ~{1} GB:"
        AudDelPrompt    = "Select cleanup mode: [1] Send to Recycle Bin (Safe/Reversible)  [2] Permanently Delete  [Q] Cancel"
        AudMovingRec    = "Moving to Recycle Bin: {0} ..."
        AudRecDone      = "[√] All selected items safely moved to Recycle Bin!"
        AudPermDeleting = "Permanently deleting: {0} ..."
        AudPermDone     = "[√] All selected items permanently deleted!"
        AudCancel       = "[*] No items selected, returning safely."
    }
}

function T([string]$Key, [object[]]$ArgsList) {
    $tmpl = $I18N[$script:Lang][$Key]
    if (-not $tmpl) { return $Key }
    if ($ArgsList) { return [string]::Format($tmpl, $ArgsList) }
    return $tmpl
}

function Show-Menu {
    Clear-Host
    $cDrive = Get-PSDrive C
    $freeGB = [math]::Round($cDrive.Free / 1GB, 2)
    $usedGB = [math]::Round($cDrive.Used / 1GB, 2)
    
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "       $(T 'Title')" -ForegroundColor Cyan
    Write-Host "       $(T 'Status' @($freeGB, $usedGB))" -ForegroundColor Yellow
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host (T 'M1')
    Write-Host (T 'M2')
    Write-Host (T 'M3')
    Write-Host (T 'M4')
    Write-Host (T 'M5')
    Write-Host (T 'M6')
    Write-Host (T 'M7') -ForegroundColor Green
    Write-Host "-------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host (T 'ML') -ForegroundColor Magenta
    Write-Host (T 'MQ')
    Write-Host "===================================================================" -ForegroundColor Cyan
}

function Remove-DirectoryContentsWithProgress {
    param (
        [string]$TargetFolder,
        [string]$Title = "Cleaning..."
    )
    if (-Not (Test-Path $TargetFolder)) { return }

    Write-Progress -Id 2 -Activity $Title -Status (T 'CountingSub') -PercentComplete 0
    $topItems = @(Get-ChildItem -Path $TargetFolder -Force -ErrorAction SilentlyContinue)
    $total = $topItems.Count

    if ($total -eq 0) {
        Write-Progress -Id 2 -Activity $Title -Completed
        return
    }

    $current = 0
    foreach ($subItem in $topItems) {
        $current++
        $pct = [math]::Round(($current / $total) * 100, 1)
        Write-Progress -Id 2 -Activity $Title -Status (T 'CleaningItem' @($pct, $current, $total, $subItem.Name)) -PercentComplete $pct
        try {
            Remove-Item -Path $subItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Progress -Id 2 -Activity $Title -Completed
}

function Invoke-BasicClean {
    $beforeFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)

    Write-Progress -Id 1 -Activity (T 'CleanAct') -Status (T 'Step1Recycle') -PercentComplete 10
    Write-Host "`n$(T 'Step1Recycle')" -ForegroundColor Green
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    $HoursOld = 24
    $cutoffTime = (Get-Date).AddHours(-$HoursOld)
    Write-Progress -Id 1 -Activity (T 'CleanAct') -Status (T 'Step2TempScan' @($env:TEMP, $HoursOld)) -PercentComplete 25
    Write-Host (T 'Step2TempScan' @($env:TEMP, $HoursOld)) -ForegroundColor Green
    
    $tempFiles = @(Get-ChildItem -Path $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffTime })
    $totalFiles = $tempFiles.Count
    $freedBytes = 0

    if ($totalFiles -gt 0) {
        for ($i = 0; $i -lt $totalFiles; $i++) {
            if ($i % 40 -eq 0 -or $i -eq ($totalFiles - 1)) {
                $pct = [math]::Round((($i + 1) / $totalFiles) * 100, 1)
                $freedMBNow = [math]::Round($freedBytes / 1MB, 1)
                Write-Progress -Id 2 -ParentId 1 -Activity "%TEMP%" -Status (T 'TempProgress' @($pct, ($i+1), $totalFiles, $freedMBNow)) -PercentComplete $pct
            }
            try {
                $size = $tempFiles[$i].Length
                Remove-Item $tempFiles[$i].FullName -Force -ErrorAction Stop
                $freedBytes += $size
            } catch {}
        }
        Write-Progress -Id 2 -ParentId 1 -Activity "%TEMP%" -Completed
    }

    Get-ChildItem -Path $env:TEMP -Recurse -Directory -Force -ErrorAction SilentlyContinue | 
        Where-Object { (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } | 
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        
    $freedMB = [math]::Round($freedBytes / 1MB, 2)
    Write-Host (T 'TempFreed' @($freedMB)) -ForegroundColor Yellow

    Write-Progress -Id 1 -Activity (T 'CleanAct') -Status (T 'Step3WinTemp') -PercentComplete 65
    Write-Host (T 'Step3WinTemp') -ForegroundColor Green
    Remove-DirectoryContentsWithProgress -TargetFolder "C:\Windows\Temp" -Title "C:\Windows\Temp"

    Write-Progress -Id 1 -Activity (T 'CleanAct') -Status (T 'Step4WinUpd') -PercentComplete 85
    Write-Host (T 'Step4WinUpd') -ForegroundColor Green
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Remove-DirectoryContentsWithProgress -TargetFolder "C:\Windows\SoftwareDistribution\Download" -Title "Windows Update Cache"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    Write-Progress -Id 1 -Activity (T 'CleanAct') -Completed
    $afterFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $diffGB = [math]::Round($afterFree - $beforeFree, 2)
    Write-Host "`n$(T 'BasicDone' @($afterFree, $diffGB))" -ForegroundColor Cyan
}

function Invoke-DevCacheClean {
    $devPaths = [ordered]@{
        "Gradle Wrapper"       = "$env:USERPROFILE\.gradle\wrapper\dists"
        "Dart Pub Cache"       = "$env:LOCALAPPDATA\Pub\Cache"
        "Dart Analysis Server" = "$env:LOCALAPPDATA\.dartServer"
        "Gradle Caches"        = "$env:USERPROFILE\.gradle\caches"
        "NPM Cache"            = "$env:APPDATA\npm-cache"
    }

    $totalItems = $devPaths.Count
    $idx = 0
    $beforeFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)

    Write-Host "`n$(T 'DevScanStart')" -ForegroundColor Cyan

    foreach ($item in $devPaths.GetEnumerator()) {
        $idx++
        $scanPct = [math]::Round(($idx / $totalItems) * 100, 0)
        Write-Progress -Id 1 -Activity (T 'DevScanAct' @($idx, $totalItems)) -Status "$($item.Key) ($($item.Value))..." -PercentComplete $scanPct

        if (Test-Path $item.Value) {
            $subItems = @(Get-ChildItem $item.Value -Force -ErrorAction SilentlyContinue)
            $totalBytes = 0
            $subIdx = 0
            $subTotal = [math]::Max($subItems.Count, 1)

            foreach ($sub in $subItems) {
                $subIdx++
                $subPct = [math]::Round(($subIdx / $subTotal) * 100, 0)
                Write-Progress -Id 2 -ParentId 1 -Activity (T 'DevCalcAct' @($item.Key)) -Status (T 'DevScanSub' @($subIdx, $subTotal, $sub.Name)) -PercentComplete $subPct
                
                if ($sub.PSIsContainer) {
                    $s = (Get-ChildItem $sub.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    if ($s) { $totalBytes += $s }
                } else {
                    $totalBytes += $sub.Length
                }
            }
            Write-Progress -Id 2 -ParentId 1 -Activity (T 'DevCalcAct' @($item.Key)) -Completed

            $sizeFormatted = [math]::Round($totalBytes / 1GB, 2)
            Write-Host "`n$(T 'DevFound' @($item.Key, $sizeFormatted, $item.Value))" -ForegroundColor Yellow
            
            if ($totalBytes -gt 0) {
                Write-Progress -Id 1 -Activity (T 'DevScanAct' @($idx, $totalItems)) -Completed
                $confirm = Read-Host (T 'DevAskClean')
                if ($confirm -eq 'y') {
                    Write-Host (T 'DevCleaning' @($item.Key)) -ForegroundColor Cyan
                    Remove-DirectoryContentsWithProgress -TargetFolder $item.Value -Title "$($item.Key) ($sizeFormatted GB)"
                    Write-Host (T 'DevCleaned' @($item.Key)) -ForegroundColor Green
                }
            } else {
                Write-Host (T 'DevEmptySkip') -ForegroundColor DarkGray
            }
        }
    }
    Write-Progress -Id 1 -Activity "Scan" -Completed
    $afterFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $diffGB = [math]::Round($afterFree - $beforeFree, 2)
    Write-Host "`n===================================================================" -ForegroundColor Cyan
    Write-Host (T 'DevAllDone' @($afterFree, $diffGB)) -ForegroundColor Green
}

function Move-DirectoryWithJunction {
    Write-Host "`n$(T 'MigTitle')" -ForegroundColor Cyan
    Write-Host (T 'MigModeA') -ForegroundColor Green
    Write-Host (T 'MigModeB') -ForegroundColor Yellow
    $mode = Read-Host (T 'MigPromptMode')

    if ($mode -match '^[Aa]$') {
        $targetBase = Read-Host (T 'MigTargetPrompt')
        if ([string]::IsNullOrWhiteSpace($targetBase)) { $targetBase = "D:\DevCache" }

        $devItems = @(
            @{ Name = "Gradle (.gradle)"; Source = "$env:USERPROFILE\.gradle"; Target = "$targetBase\.gradle"; EnvName = "GRADLE_USER_HOME"; EnvVal = "$targetBase\.gradle" },
            @{ Name = "Flutter / Dart (Pub\Cache)"; Source = "$env:LOCALAPPDATA\Pub\Cache"; Target = "$targetBase\PubCache"; EnvName = "PUB_CACHE"; EnvVal = "$targetBase\PubCache" },
            @{ Name = "Dart (.dartServer)"; Source = "$env:LOCALAPPDATA\.dartServer"; Target = "$targetBase\.dartServer"; EnvName = $null; EnvVal = $null },
            @{ Name = "Android AVD (.android\avd)"; Source = "$env:USERPROFILE\.android\avd"; Target = "$targetBase\AndroidAVD"; EnvName = "ANDROID_AVD_HOME"; EnvVal = "$targetBase\AndroidAVD" },
            @{ Name = "Android SDK (Local\Android\Sdk)"; Source = "$env:LOCALAPPDATA\Android\Sdk"; Target = "$targetBase\AndroidSdk"; EnvName = "ANDROID_HOME"; EnvVal = "$targetBase\AndroidSdk" },
            @{ Name = "Rust Cargo (.cargo)"; Source = "$env:USERPROFILE\.cargo"; Target = "$targetBase\.cargo"; EnvName = "CARGO_HOME"; EnvVal = "$targetBase\.cargo" },
            @{ Name = "NPM (npm-cache)"; Source = "$env:APPDATA\npm-cache"; Target = "$targetBase\npm-cache"; EnvName = $null; EnvVal = $null }
        )

        Write-Host "`n$(T 'MigScanning')`n" -ForegroundColor Green
        $validList = @()
        $index = 1
        foreach ($item in $devItems) {
            $src = $item.Source
            if (Test-Path $src) {
                $dirInfo = Get-Item $src -Force
                $isLink = ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                if ($isLink) {
                    Write-Host (T 'MigAlreadyLink' @($index, $item.Name, $src)) -ForegroundColor DarkGray
                } else {
                    Write-Progress -Id 1 -Activity (T 'MigScanning') -Status "$($item.Name)..."
                    $sizeBytes = (Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $sizeGB = [math]::Round($sizeBytes / 1GB, 2)
                    Write-Host (T 'MigItemInfo' @($index, $item.Name, $sizeGB)) -ForegroundColor Yellow
                    Write-Host (T 'MigItemPath' @($src, $item.Target)) -ForegroundColor Gray
                    $item.Index = $index
                    $item.SizeGB = $sizeGB
                    $validList += $item
                }
                $index++
            }
        }
        Write-Progress -Id 1 -Activity (T 'MigScanning') -Completed

        if ($validList.Count -eq 0) {
            Write-Host "`n$(T 'MigNoneNeeded')" -ForegroundColor Cyan
            return
        }

        $sel = Read-Host "`n$(T 'MigSelectPrompt')"
        if ($sel -match '^[Qq]$') { return }

        Write-Host "`n$(T 'MigKillProc')" -ForegroundColor Cyan
        Stop-Process -Name "java", "dart", "adb" -Force -ErrorAction SilentlyContinue

        $toProcess = if ($sel -match "^all$") { $validList } else {
            $ids = $sel -split ',' | ForEach-Object { $_.Trim() }
            $validList | Where-Object { $ids -contains [string]$_.Index }
        }

        foreach ($task in $toProcess) {
            $src = $task.Source
            $dst = $task.Target
            Write-Host "`n$(T 'MigStartItem' @($task.Name, $task.SizeGB))" -ForegroundColor Green
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

            $roboArgs = @("`"$src`"", "`"$dst`"", "/E", "/MOVE", "/MT:8", "/R:2", "/W:1", "/ETA")
            $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -Wait -NoNewWindow -PassThru

            if ($proc.ExitCode -lt 8) {
                if (Test-Path $src) { Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue }
                cmd /c mklink /J "`"$src`"" "`"$dst`"" | Out-Null
                if ($task.EnvName) {
                    [Environment]::SetEnvironmentVariable($task.EnvName, $task.EnvVal, "User")
                    Write-Host (T 'MigEnvSet' @($task.EnvName, $task.EnvVal)) -ForegroundColor Gray
                }
                Write-Host (T 'MigSuccess' @($task.Name)) -ForegroundColor Cyan
            } else {
                Write-Host (T 'MigFail' @($proc.ExitCode)) -ForegroundColor Red
            }
        }
    } elseif ($mode -match '^[Bb]$') {
        $sourceDir = (Read-Host (T 'MigSrcPrompt')).Trim('"')
        $targetDir = (Read-Host (T 'MigDstPrompt')).Trim('"')

        if (-Not (Test-Path $sourceDir)) {
            Write-Host (T 'MigSrcNotExist') -ForegroundColor Red
            return
        }
        $dirInfo = Get-Item $sourceDir -Force
        if (($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Host (T 'MigAlreadyJunc') -ForegroundColor Yellow
            return
        }
        if (-Not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        Write-Host (T 'MigRobocopyRun') -ForegroundColor Green
        $roboArgs = @("`"$sourceDir`"", "`"$targetDir`"", "/E", "/MOVE", "/MT:8", "/R:2", "/W:1", "/ETA")
        $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -Wait -NoNewWindow -PassThru

        if ($proc.ExitCode -lt 8) {
            if (Test-Path $sourceDir) { Remove-Item $sourceDir -Recurse -Force -ErrorAction SilentlyContinue }
            cmd /c mklink /J "`"$sourceDir`"" "`"$targetDir`""
            Write-Host "`n$(T 'MigSuccess' @($sourceDir))" -ForegroundColor Cyan
        } else {
            Write-Host "`n$(T 'MigFail' @($proc.ExitCode))" -ForegroundColor Red
        }
    }
}

function Set-DefaultInstallDrive {
    $drive = (Read-Host (T 'RegDrivePrompt')).Trim(':')
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
    Set-ItemProperty -Path $regPath -Name "ProgramFilesDir" -Value "${drive}:\Program Files"
    Set-ItemProperty -Path $regPath -Name "ProgramFilesDir (x86)" -Value "${drive}:\Program Files (x86)"
    Write-Host (T 'RegDone' @($drive)) -ForegroundColor Cyan
}

function Optimize-Memory {
    Write-Host "`n$(T 'MemStart')" -ForegroundColor Green
    $signature = @"
    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
"@
    $type = Add-Type -MemberDefinition $signature -Name "MemUtil" -Namespace "Win32" -PassThru
    
    $procs = @(Get-Process)
    $total = $procs.Count
    for ($i = 0; $i -lt $total; $i++) {
        if ($i % 10 -eq 0 -or $i -eq ($total - 1)) {
            $pct = [math]::Round((($i + 1) / $total) * 100, 0)
            Write-Progress -Id 1 -Activity (T 'MemAct') -Status (T 'MemStatus' @($pct, ($i+1), $total, $procs[$i].ProcessName)) -PercentComplete $pct
        }
        try { $null = $type::EmptyWorkingSet($procs[$i].Handle) } catch {}
    }
    Write-Progress -Id 1 -Activity (T 'MemAct') -Completed
    Write-Host (T 'MemDone' @($total)) -ForegroundColor Cyan
}

function Start-DiskMonitor {
    Write-Host "`n$(T 'MonStart')" -ForegroundColor Green
    while ($true) {
        $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
        $timeStr = (Get-Date).ToString("HH:mm:ss")
        Write-Host (T 'MonNormal' @($timeStr, $freeGB)) -ForegroundColor Gray
        if ($freeGB -lt 5.0) {
            $wshell = New-Object -ComObject Wscript.Shell
            $wshell.Popup((T 'MonWarnPopup' @($freeGB)), 10, (T 'MonWarnTitle'), 48) | Out-Null
        }
        Start-Sleep -Seconds 300
    }
}

function Invoke-DiskSmartAuditor {
    Write-Host "`n===================================================================" -ForegroundColor Cyan
    Write-Host (T 'AudTitle') -ForegroundColor Cyan
    Write-Host "===================================================================" -ForegroundColor Cyan

    $driveLetter = (Read-Host (T 'AudDrivePrompt')).Trim(':')
    $rootPath = "${driveLetter}:\"
    if (-not (Test-Path $rootPath)) {
        Write-Host (T 'AudNotExist' @($rootPath)) -ForegroundColor Red
        return
    }

    Write-Progress -Id 1 -Activity "Audit ($rootPath)" -Status (T 'AudStep1') -PercentComplete 10
    Write-Host "`n$(T 'AudStep1')" -ForegroundColor Green
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $installedApps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    $knownKeywords = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($app in $installedApps) {
        if ($app.InstallLocation) { $knownKeywords.Add($app.InstallLocation.TrimEnd('\')) | Out-Null }
        if ($app.DisplayName) {
            $cleanName = ($app.DisplayName -split '[\s\-\(\)_v\d]+')[0]
            if ($cleanName.Length -ge 3) { $knownKeywords.Add($cleanName) | Out-Null }
        }
    }

    $shell = New-Object -ComObject WScript.Shell
    $lnkDirs = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("StartMenu"),
        [Environment]::GetFolderPath("CommonStartMenu")
    )
    foreach ($d in $lnkDirs) {
        Get-ChildItem -Path $d -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $target = $shell.CreateShortcut($_.FullName).TargetPath
                if ($target) { $knownKeywords.Add((Split-Path $target -Parent)) | Out-Null }
            } catch {}
        }
    }

    $auditResults = New-Object System.Collections.Generic.List[PSObject]

    Write-Progress -Id 1 -Activity "Audit ($rootPath)" -Status (T 'AudStep2' @($rootPath)) -PercentComplete 30
    Write-Host (T 'AudStep2' @($rootPath)) -ForegroundColor Green
    
    $scanDirs = Get-ChildItem -Path $rootPath -Directory -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notmatch '^\$RECYCLE\.BIN$|^System Volume Information$|^Recovery$|^Windows$|^Users$' }

    $targetFolders = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    foreach ($dir in $scanDirs) {
        if ($dir.Name -match '^(Program Files|Program Files \(x86\)|Software|Apps|Games|ProgramData)$') {
            Get-ChildItem -Path $dir.FullName -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $targetFolders.Add($_) }
        } else {
            $targetFolders.Add($dir)
        }
    }

    $fCount = [math]::Max($targetFolders.Count, 1)
    $fIdx = 0
    foreach ($folder in $targetFolders) {
        $fIdx++
        $fPct = [math]::Round(($fIdx / $fCount) * 100, 0)
        Write-Progress -Id 2 -ParentId 1 -Activity "Analyzing ($fIdx/$fCount)" -Status $folder.FullName -PercentComplete $fPct

        $files = @(Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            $auditResults.Add([PSCustomObject]@{
                Category      = (T 'AudCat1')
                Name          = $folder.Name
                SizeMB        = 0
                LastActive    = $folder.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = [int]((Get-Date) - $folder.LastWriteTime).TotalDays
                Advice        = (T 'AudAdv1')
                FullPath      = $folder.FullName
            })
            continue
        }

        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($totalBytes / 1MB, 1)
        if ($sizeMB -lt 5) { continue }

        $exeCount = @($files | Where-Object { $_.Extension -match '^\.(exe|bat|cmd)$' }).Count
        $latestFile = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $inactiveDays = [int]((Get-Date) - $latestFile.LastWriteTime).TotalDays

        $isRegistered = $false
        foreach ($kw in $knownKeywords) {
            if ($folder.FullName.StartsWith($kw, [System.StringComparison]::OrdinalIgnoreCase) -or 
                $folder.Name.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $isRegistered = $true
                break
            }
        }

        if (-not $isRegistered -and $exeCount -eq 0) {
            $auditResults.Add([PSCustomObject]@{
                Category      = (T 'AudCat2')
                Name          = $folder.Name
                SizeMB        = $sizeMB
                LastActive    = $latestFile.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = $inactiveDays
                Advice        = (T 'AudAdv2')
                FullPath      = $folder.FullName
            })
        } elseif (-not $isRegistered -and $inactiveDays -gt 60) {
            $auditResults.Add([PSCustomObject]@{
                Category      = (T 'AudCat3')
                Name          = $folder.Name
                SizeMB        = $sizeMB
                LastActive    = $latestFile.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = $inactiveDays
                Advice        = (T 'AudAdv3' @($inactiveDays))
                FullPath      = $folder.FullName
            })
        }
    }
    Write-Progress -Id 2 -ParentId 1 -Activity "Analyzing" -Completed

    Write-Progress -Id 1 -Activity "Audit ($rootPath)" -Status (T 'AudStep3') -PercentComplete 70
    Write-Host (T 'AudStep3') -ForegroundColor Green

    Get-ChildItem -Path $rootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^(node_modules|target|build|\.gradle|\.dart_tool)$' -and $_.FullName -notmatch 'node_modules\\.*\\node_modules' } |
        ForEach-Object {
            $days = [int]((Get-Date) - $_.LastWriteTime).TotalDays
            if ($days -gt 30) {
                Write-Progress -Id 2 -ParentId 1 -Activity "Build Cache" -Status $_.FullName
                $sBytes = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $sMB = [math]::Round($sBytes / 1MB, 1)
                if ($sMB -ge 100) {
                    $auditResults.Add([PSCustomObject]@{
                        Category      = (T 'AudCat4')
                        Name          = $_.Name
                        SizeMB        = $sMB
                        LastActive    = $_.LastWriteTime.ToString("yyyy-MM-dd")
                        InactiveDays  = $days
                        Advice        = (T 'AudAdv4')
                        FullPath      = $_.FullName
                    })
                }
            }
        }

    Get-ChildItem -Path $rootPath -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 100MB -and $_.Extension -match '^\.(iso|zip|7z|rar|exe|msi|apk|tgz|tar|gz)$' } |
        ForEach-Object {
            $days = [int]((Get-Date) - $_.LastWriteTime).TotalDays
            if ($days -gt 14) {
                $auditResults.Add([PSCustomObject]@{
                    Category      = (T 'AudCat5')
                    Name          = $_.Name
                    SizeMB        = [math]::Round($_.Length / 1MB, 1)
                    LastActive    = $_.LastWriteTime.ToString("yyyy-MM-dd")
                    InactiveDays  = $days
                    Advice        = (T 'AudAdv5')
                    FullPath      = $_.FullName
                })
            }
        }

    Write-Progress -Id 2 -ParentId 1 -Activity "Build Cache" -Completed
    Write-Progress -Id 1 -Activity "Audit ($rootPath)" -Completed

    if ($auditResults.Count -eq 0) {
        Write-Host "`n$(T 'AudCleanDisk' @($rootPath))" -ForegroundColor Cyan
        return
    }

    Write-Host (T 'AudStep4') -ForegroundColor Yellow

    $selectedItems = $auditResults | Sort-Object Category, @{Expression="SizeMB"; Descending=$true} | 
        Out-GridView -Title (T 'AudGridTitle' @($rootPath)) -PassThru

    if ($selectedItems) {
        $totalSelectedGB = [math]::Round(($selectedItems | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)
        Write-Host "`n$(T 'AudSelectedMsg' @($selectedItems.Count, $totalSelectedGB))" -ForegroundColor Yellow
        $selectedItems | ForEach-Object { Write-Host " - [$($_.SizeMB) MB] $($_.FullPath)" -ForegroundColor Gray }
        
        $delMode = Read-Host "`n$(T 'AudDelPrompt')"
        
        if ($delMode -eq '1') {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $cIdx = 0
            foreach ($item in $selectedItems) {
                $cIdx++
                Write-Progress -Id 1 -Activity "Recycle Bin ($cIdx/$($selectedItems.Count))" -Status $item.FullPath -PercentComplete (($cIdx / $selectedItems.Count) * 100)
                Write-Host (T 'AudMovingRec' @($item.FullPath)) -ForegroundColor Green
                try {
                    if (Test-Path $item.FullPath -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($item.FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    } else {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    }
                } catch {
                    Write-Host "[!] Error: $_" -ForegroundColor Red
                }
            }
            Write-Progress -Id 1 -Activity "Recycle Bin" -Completed
            Write-Host "`n$(T 'AudRecDone')" -ForegroundColor Cyan
        } elseif ($delMode -eq '2') {
            foreach ($item in $selectedItems) {
                Write-Host (T 'AudPermDeleting' @($item.FullPath)) -ForegroundColor Red
                Remove-DirectoryContentsWithProgress -TargetFolder $item.FullPath -Title $item.Name
                Remove-Item -Path $item.FullPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "`n$(T 'AudPermDone')" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`n$(T 'AudCancel')" -ForegroundColor Gray
    }
}

do {
    Show-Menu
    $choice = Read-Host (T 'PromptChoice')
    switch ($choice) {
        '1' { Invoke-BasicClean; Pause }
        '2' { Invoke-DevCacheClean; Pause }
        '3' { Move-DirectoryWithJunction; Pause }
        '4' { Set-DefaultInstallDrive; Pause }
        '5' { Optimize-Memory; Pause }
        '6' { Start-DiskMonitor }
        '7' { Invoke-DiskSmartAuditor; Pause }
        { $_ -in 'L', 'l' } { 
            $script:Lang = if ($script:Lang -eq 'ZH') { 'EN' } else { 'ZH' }
            Write-Host "`n$(T 'LangSwitched')" -ForegroundColor Magenta
            Start-Sleep -Seconds 1
        }
    }
} until ($choice -eq 'Q' -or $choice -eq 'q')