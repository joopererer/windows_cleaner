# Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Menu {
    Clear-Host
    $cDrive = Get-PSDrive C
    $freeGB = [math]::Round($cDrive.Free / 1GB, 2)
    $usedGB = [math]::Round($cDrive.Used / 1GB, 2)
    
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "       Windows C盘深度清理与缓存迁移工具 (Dev进度版) " -ForegroundColor Cyan
    Write-Host "       当前 C 盘状态: 可用 $freeGB GB / 已用 $usedGB GB" -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "1. [一键清理] 回收站 + 用户 %TEMP% + Windows 系统临时文件"
    Write-Host "2. [开发瘦身] 扫描并清理 Gradle / Dart / Pub / npm 构建缓存"
    Write-Host "3. [无感迁移] 将指定缓存目录迁移至 D 盘 (底层 NTFS 软链接)"
    Write-Host "4. [目录迁移] 修改系统默认 Program Files 安装注册表路径"
    Write-Host "5. [内存优化] 立即释放后台进程驻留工作集内存 (EmptyWorkingSet)"
    Write-Host "6. [实时监护] 开启 C 盘剩余空间后台监控预警 (低于 5GB 弹窗)"
    Write-Host "Q. 退出"
    Write-Host "====================================================="
}

# 通用辅助函数：带进度条高速删除大目录（按顶层子项分块推进，兼顾速度与实时反馈）
function Remove-DirectoryContentsWithProgress {
    param (
        [string]$TargetFolder,
        [string]$Title = "正在清理目录"
    )
    if (-Not (Test-Path $TargetFolder)) { return }

    Write-Progress -Id 2 -Activity $Title -Status "正在统计子目录结构..." -PercentComplete 0
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
        Write-Progress -Id 2 -Activity $Title -Status "[$pct%] ($current/$total) 正在清理: $($subItem.Name)" -PercentComplete $pct
        
        try {
            Remove-Item -Path $subItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Progress -Id 2 -Activity $Title -Completed
}

# 1. 基础垃圾清理（带分步总进度 + 文件级批次进度条）
function Invoke-BasicClean {
    $beforeFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)

    # 步骤 1/4
    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[1/4] 正在清空回收站..." -PercentComplete 10
    Write-Host "`n[1/4] 正在清空回收站..." -ForegroundColor Green
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # 步骤 2/4
    $HoursOld = 24
    $cutoffTime = (Get-Date).AddHours(-$HoursOld)
    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[2/4] 正在检索用户 %TEMP% 超时文件..." -PercentComplete 25
    Write-Host "[2/4] 正在安全清理用户临时目录 ($env:TEMP) [保护最近 $HoursOld 小时活跃文件]..." -ForegroundColor Green
    
    $tempFiles = @(Get-ChildItem -Path $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffTime })
    $totalFiles = $tempFiles.Count
    $freedBytes = 0

    if ($totalFiles -gt 0) {
        for ($i = 0; $i -lt $totalFiles; $i++) {
            # 每处理 40 个文件刷新一次进度条，避免拖慢 I/O
            if ($i % 40 -eq 0 -or $i -eq ($totalFiles - 1)) {
                $pct = [math]::Round((($i + 1) / $totalFiles) * 100, 1)
                $freedMBNow = [math]::Round($freedBytes / 1MB, 1)
                Write-Progress -Id 2 -ParentId 1 -Activity "清理用户 %TEMP%" -Status "进度: $pct% ($($i+1)/$totalFiles) | 已释放: $freedMBNow MB" -PercentComplete $pct
            }
            try {
                $size = $tempFiles[$i].Length
                Remove-Item $tempFiles[$i].FullName -Force -ErrorAction Stop
                $freedBytes += $size
            } catch {
                # 正在被 IDE / AI Agent / 编译器占用的文件自动跳过
            }
        }
        Write-Progress -Id 2 -ParentId 1 -Activity "清理用户 %TEMP%" -Completed
    }

    # 顺手清理空的临时子文件夹
    Get-ChildItem -Path $env:TEMP -Recurse -Directory -Force -ErrorAction SilentlyContinue | 
        Where-Object { (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } | 
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        
    $freedMB = [math]::Round($freedBytes / 1MB, 2)
    Write-Host "      -> 用户临时目录已释放 $freedMB MB" -ForegroundColor Yellow

    # 步骤 3/4
    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[3/4] 正在清理 Windows 系统临时目录..." -PercentComplete 65
    Write-Host "[3/4] 正在清理 Windows 系统临时目录 (C:\Windows\Temp)..." -ForegroundColor Green
    Remove-DirectoryContentsWithProgress -TargetFolder "C:\Windows\Temp" -Title "清理 C:\Windows\Temp"

    # 步骤 4/4
    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[4/4] 正在清理 Windows Update 缓存..." -PercentComplete 85
    Write-Host "[4/4] 正在清理 Windows Update 下载缓存..." -ForegroundColor Green
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Remove-DirectoryContentsWithProgress -TargetFolder "C:\Windows\SoftwareDistribution\Download" -Title "清理 Windows Update 缓存"
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    Write-Progress -Id 1 -Activity "基础垃圾清理" -Completed
    $afterFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $diffGB = [math]::Round($afterFree - $beforeFree, 2)
    Write-Host "`n[√] 基础清理完成！当前 C 盘可用: $afterFree GB (本次共腾出 $diffGB GB)" -ForegroundColor Cyan
}

# 2. 开发者专项缓存清理 (带扫描进度 + 删除百分比进度)
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

    Write-Host "`n[*] 正在扫描开发缓存目录（目录较大时统计体积需数秒，请稍候）..." -ForegroundColor Cyan

    foreach ($item in $devPaths.GetEnumerator()) {
        $idx++
        $scanPct = [math]::Round(($idx / $totalItems) * 100, 0)
        Write-Progress -Id 1 -Activity "扫描开发者构建缓存 ($idx/$totalItems)" -Status "正在统计体积: $($item.Key) ($($item.Value))..." -PercentComplete $scanPct

        if (Test-Path $item.Value) {
            # 先快速获取顶层子目录，按子块统计大小并刷新进度，避免大目录假死
            $subItems = @(Get-ChildItem $item.Value -Force -ErrorAction SilentlyContinue)
            $totalBytes = 0
            $subIdx = 0
            $subTotal = [math]::Max($subItems.Count, 1)

            foreach ($sub in $subItems) {
                $subIdx++
                $subPct = [math]::Round(($subIdx / $subTotal) * 100, 0)
                Write-Progress -Id 2 -ParentId 1 -Activity "正在计算 [$($item.Key)] 占用空间" -Status "扫描子项 ($subIdx/$subTotal): $($sub.Name)" -PercentComplete $subPct
                
                if ($sub.PSIsContainer) {
                    $s = (Get-ChildItem $sub.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    if ($s) { $totalBytes += $s }
                } else {
                    $totalBytes += $sub.Length
                }
            }
            Write-Progress -Id 2 -ParentId 1 -Activity "正在计算 [$($item.Key)] 占用空间" -Completed

            $sizeFormatted = [math]::Round($totalBytes / 1GB, 2)
            Write-Host "`n发现 [$($item.Key)] 占用: $sizeFormatted GB ($($item.Value))" -ForegroundColor Yellow
            
            if ($totalBytes -gt 0) {
                # 暂停顶部进度条遮挡，等待用户输入
                Write-Progress -Id 1 -Activity "扫描开发者构建缓存" -Completed
                $confirm = Read-Host "是否清理该目录？(y/n)"
                if ($confirm -eq 'y') {
                    Write-Host "[*] 正在清理 $($item.Key) ，请观察上方进度条..." -ForegroundColor Cyan
                    Remove-DirectoryContentsWithProgress -TargetFolder $item.Value -Title "正在清理 $($item.Key) ($sizeFormatted GB)"
                    Write-Host "[√] 已清理 $($item.Key)" -ForegroundColor Green
                }
            } else {
                Write-Host "    -> 目录已为空，自动跳过。" -ForegroundColor DarkGray
            }
        }
    }
    Write-Progress -Id 1 -Activity "扫描开发者构建缓存" -Completed
    $afterFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $diffGB = [math]::Round($afterFree - $beforeFree, 2)
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "[√] 开发缓存瘦身完毕！C 盘最新可用空间: $afterFree GB (共释放 $diffGB GB)" -ForegroundColor Green
}

# 3. 乾坤大挪移（升级版：防重复链接 + Robocopy 实时进度显示）
function Move-DirectoryWithJunction {
    Write-Host "`n[提示] 该功能会将 C 盘目录高速迁移到目标盘，并在原位置建立 NTFS Junction 软链接。" -ForegroundColor Yellow
    $sourceDir = (Read-Host "请输入要迁移的 C 盘源目录完整路径 (例如 C:\Users\univasity\.gradle)").Trim('"')
    $targetDir = (Read-Host "请输入目标盘路径 (例如 D:\DevCache\.gradle)").Trim('"')

    if (-Not (Test-Path $sourceDir)) {
        Write-Host "[!] 源目录不存在！" -ForegroundColor Red
        return
    }

    $dirInfo = Get-Item $sourceDir -Force
    if (($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Host "[!] 该目录已经是软链接 (Junction)，无需重复迁移！" -ForegroundColor Yellow
        return
    }

    if (-Not (Test-Path $targetDir)) { 
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null 
    }

    Write-Host "[*] 正在调用 Robocopy 8线程迁移数据（下方将实时滚动显示迁移进度）..." -ForegroundColor Green
    # 移除了 /NFL /NDL，保留进度输出，使用 /ETA 显示预估时间
    $roboArgs = @("`"$sourceDir`"", "`"$targetDir`"", "/E", "/MOVE", "/MT:8", "/R:2", "/W:1", "/ETA")
    $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -Wait -NoNewWindow -PassThru

    if ($proc.ExitCode -lt 8) {
        if (Test-Path $sourceDir) { Remove-Item $sourceDir -Recurse -Force -ErrorAction SilentlyContinue }
        cmd /c mklink /J "`"$sourceDir`"" "`"$targetDir`""
        Write-Host "`n[√] 迁移成功！C 盘空间已释放，所有读写已无缝重定向至 $targetDir" -ForegroundColor Cyan
    } else {
        Write-Host "`n[!] 迁移未完全成功 (可能部分文件正被后台程序占用，错误码: $($proc.ExitCode))。" -ForegroundColor Red
        Write-Host "    请关闭占用该目录的软件（如 IDE / java.exe / dart.exe）后，再次运行本功能继续迁移剩余文件。" -ForegroundColor Yellow
    }
}

# 4. 修改默认软件安装盘
function Set-DefaultInstallDrive {
    $drive = Read-Host "请输入希望默认安装软件的盘符 (例如 D)"
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
    Set-ItemProperty -Path $regPath -Name "ProgramFilesDir" -Value "${drive}:\Program Files"
    Set-ItemProperty -Path $regPath -Name "ProgramFilesDir (x86)" -Value "${drive}:\Program Files (x86)"
    Write-Host "[√] 注册表默认安装路径已修改为 ${drive} 盘！（注：对标准 MSI/NSIS 安装包立即生效）" -ForegroundColor Cyan
}

# 5. 原生 API 内存整理 (带进程遍历百分比进度条)
function Optimize-Memory {
    Write-Host "`n[*] 正在调用 psapi.dll 释放后台进程多余工作集内存..." -ForegroundColor Green
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
            Write-Progress -Id 1 -Activity "释放物理内存工作集" -Status "进度: $pct% ($($i+1)/$total) 正在整理进程: $($procs[$i].ProcessName)" -PercentComplete $pct
        }
        try { $null = $type::EmptyWorkingSet($procs[$i].Handle) } catch {}
    }
    Write-Progress -Id 1 -Activity "释放物理内存工作集" -Completed
    Write-Host "[√] 内存整理完成！共整理 $total 个进程，闲置物理内存已回收。" -ForegroundColor Cyan
}

# 6. C盘实时监护 (低于阈值弹窗提醒)
function Start-DiskMonitor {
    Write-Host "`n[*] 已启动 C 盘空间实时监控 (按 Ctrl+C 停止)..." -ForegroundColor Green
    while ($true) {
        $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
        $timeStr = (Get-Date).ToString("HH:mm:ss")
        Write-Host "[$timeStr] 巡检正常 - 当前 C 盘剩余可用空间: $freeGB GB" -ForegroundColor Gray
        if ($freeGB -lt 5.0) {
            $wshell = New-Object -ComObject Wscript.Shell
            $wshell.Popup("⚠️ 警告：C 盘剩余空间仅剩 $freeGB GB！`n这会导致 Gradle 构建和 Dart 编译失败，请立即运行清理！", 10, "C盘空间监护中心", 48) | Out-Null
        }
        Start-Sleep -Seconds 300 # 每5分钟检查一次
    }
}

# 主循环
do {
    Show-Menu
    $choice = Read-Host "请选择要执行的操作编号"
    switch ($choice) {
        '1' { Invoke-BasicClean; Pause }
        '2' { Invoke-DevCacheClean; Pause }
        '3' { Move-DirectoryWithJunction; Pause }
        '4' { Set-DefaultInstallDrive; Pause }
        '5' { Optimize-Memory; Pause }
        '6' { Start-DiskMonitor }
    }
} until ($choice -eq 'Q' -or $choice -eq 'q')