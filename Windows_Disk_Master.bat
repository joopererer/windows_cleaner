<# :
@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8))"
pause
exit /b
#>

# Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Menu {
    Clear-Host
    $cDrive = Get-PSDrive C
    $freeGB = [math]::Round($cDrive.Free / 1GB, 2)
    $usedGB = [math]::Round($cDrive.Used / 1GB, 2)
    
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "       Windows 磁盘深度清理、缓存迁移与全盘审计大师 (All-in-One)" -ForegroundColor Cyan
    Write-Host "       当前 C 盘状态: 可用 $freeGB GB / 已用 $usedGB GB" -ForegroundColor Yellow
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "1. [一键清理] 回收站 + 用户 %TEMP% + Windows 系统临时文件 (带进度)"
    Write-Host "2. [开发瘦身] 扫描并清理 Gradle / Dart / Pub / npm 构建缓存 (带进度)"
    Write-Host "3. [无感迁移] 开发缓存一键搬家 (含环境变量) 或 自定义目录软链接迁移"
    Write-Host "4. [目录迁移] 修改系统默认 Program Files 安装注册表路径"
    Write-Host "5. [内存优化] 立即释放后台进程驻留工作集内存 (EmptyWorkingSet)"
    Write-Host "6. [实时监护] 开启 C 盘剩余空间后台监控预警 (低于 5GB 弹窗)"
    Write-Host "7. [全盘审计] 扫描任意盘卸载残留/孤岛目录/老旧编译产物 (GUI勾选清理)" -ForegroundColor Green
    Write-Host "Q. 退出"
    Write-Host "============================================================="
}

# 通用辅助函数：带进度条高速删除大目录
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

    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[1/4] 正在清空回收站..." -PercentComplete 10
    Write-Host "`n[1/4] 正在清空回收站..." -ForegroundColor Green
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    $HoursOld = 24
    $cutoffTime = (Get-Date).AddHours(-$HoursOld)
    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[2/4] 正在检索用户 %TEMP% 超时文件..." -PercentComplete 25
    Write-Host "[2/4] 正在安全清理用户临时目录 ($env:TEMP) [保护最近 $HoursOld 小时活跃文件]..." -ForegroundColor Green
    
    $tempFiles = @(Get-ChildItem -Path $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffTime })
    $totalFiles = $tempFiles.Count
    $freedBytes = 0

    if ($totalFiles -gt 0) {
        for ($i = 0; $i -lt $totalFiles; $i++) {
            if ($i % 40 -eq 0 -or $i -eq ($totalFiles - 1)) {
                $pct = [math]::Round((($i + 1) / $totalFiles) * 100, 1)
                $freedMBNow = [math]::Round($freedBytes / 1MB, 1)
                Write-Progress -Id 2 -ParentId 1 -Activity "清理用户 %TEMP%" -Status "进度: $pct% ($($i+1)/$totalFiles) | 已释放: $freedMBNow MB" -PercentComplete $pct
            }
            try {
                $size = $tempFiles[$i].Length
                Remove-Item $tempFiles[$i].FullName -Force -ErrorAction Stop
                $freedBytes += $size
            } catch {}
        }
        Write-Progress -Id 2 -ParentId 1 -Activity "清理用户 %TEMP%" -Completed
    }

    Get-ChildItem -Path $env:TEMP -Recurse -Directory -Force -ErrorAction SilentlyContinue | 
        Where-Object { (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } | 
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        
    $freedMB = [math]::Round($freedBytes / 1MB, 2)
    Write-Host "      -> 用户临时目录已释放 $freedMB MB" -ForegroundColor Yellow

    Write-Progress -Id 1 -Activity "基础垃圾清理" -Status "[3/4] 正在清理 Windows 系统临时目录..." -PercentComplete 65
    Write-Host "[3/4] 正在清理 Windows 系统临时目录 (C:\Windows\Temp)..." -ForegroundColor Green
    Remove-DirectoryContentsWithProgress -TargetFolder "C:\Windows\Temp" -Title "清理 C:\Windows\Temp"

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
    Write-Host "`n=============================================================" -ForegroundColor Cyan
    Write-Host "[√] 开发缓存瘦身完毕！C 盘最新可用空间: $afterFree GB (共释放 $diffGB GB)" -ForegroundColor Green
}

# 3. 乾坤大挪移（预设开发缓存一键搬家 + 自定义目录迁移二合一）
function Move-DirectoryWithJunction {
    Write-Host "`n================ [无感迁移模式选择] ================" -ForegroundColor Cyan
    Write-Host "A. 【预设一键搬家】自动扫描 Gradle/Pub/Android/Cargo 等缓存并迁移 + 配环境变量" -ForegroundColor Green
    Write-Host "B. 【自定义目录迁移】手动输入任意 C 盘目录路径迁移至其他盘" -ForegroundColor Yellow
    $mode = Read-Host "请选择模式 (A/B，输入 Q 返回主菜单)"

    if ($mode -match '^[Aa]$') {
        $targetBase = Read-Host "请输入目标盘的缓存根目录 (直接回车默认为 D:\DevCache)"
        if ([string]::IsNullOrWhiteSpace($targetBase)) { $targetBase = "D:\DevCache" }

        $devItems = @(
            @{ Name = "Gradle 全局缓存 (.gradle)"; Source = "$env:USERPROFILE\.gradle"; Target = "$targetBase\.gradle"; EnvName = "GRADLE_USER_HOME"; EnvVal = "$targetBase\.gradle" },
            @{ Name = "Flutter / Dart Pub 缓存 (Pub\Cache)"; Source = "$env:LOCALAPPDATA\Pub\Cache"; Target = "$targetBase\PubCache"; EnvName = "PUB_CACHE"; EnvVal = "$targetBase\PubCache" },
            @{ Name = "Dart 分析服务缓存 (.dartServer)"; Source = "$env:LOCALAPPDATA\.dartServer"; Target = "$targetBase\.dartServer"; EnvName = $null; EnvVal = $null },
            @{ Name = "Android 模拟器镜像 (.android\avd)"; Source = "$env:USERPROFILE\.android\avd"; Target = "$targetBase\AndroidAVD"; EnvName = "ANDROID_AVD_HOME"; EnvVal = "$targetBase\AndroidAVD" },
            @{ Name = "Android SDK 默认目录 (Local\Android\Sdk)"; Source = "$env:LOCALAPPDATA\Android\Sdk"; Target = "$targetBase\AndroidSdk"; EnvName = "ANDROID_HOME"; EnvVal = "$targetBase\AndroidSdk" },
            @{ Name = "Rust Cargo 缓存 (.cargo)"; Source = "$env:USERPROFILE\.cargo"; Target = "$targetBase\.cargo"; EnvName = "CARGO_HOME"; EnvVal = "$targetBase\.cargo" },
            @{ Name = "NPM 全局缓存 (npm-cache)"; Source = "$env:APPDATA\npm-cache"; Target = "$targetBase\npm-cache"; EnvName = $null; EnvVal = $null }
        )

        Write-Host "`n正在扫描本机开发缓存状态...`n" -ForegroundColor Green
        $validList = @()
        $index = 1
        foreach ($item in $devItems) {
            $src = $item.Source
            if (Test-Path $src) {
                $dirInfo = Get-Item $src -Force
                $isLink = ($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                if ($isLink) {
                    Write-Host "[$index] $($item.Name) -> [已迁移/软链接就绪] ($src)" -ForegroundColor DarkGray
                } else {
                    Write-Progress -Id 1 -Activity "正在扫描缓存大小" -Status "正在统计: $($item.Name)..."
                    $sizeBytes = (Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $sizeGB = [math]::Round($sizeBytes / 1GB, 2)
                    Write-Host "[$index] $($item.Name) | 占用: $sizeGB GB" -ForegroundColor Yellow
                    Write-Host "    源路径: $src -> 目标: $($item.Target)" -ForegroundColor Gray
                    $item.Index = $index
                    $item.SizeGB = $sizeGB
                    $validList += $item
                }
                $index++
            }
        }
        Write-Progress -Id 1 -Activity "正在扫描缓存大小" -Completed

        if ($validList.Count -eq 0) {
            Write-Host "`n[√] 未发现需要迁移的开发缓存，或所有目录均已建立软链接！" -ForegroundColor Cyan
            return
        }

        $sel = Read-Host "`n请输入要搬家的编号 (多个用逗号如 1,2；输入 ALL 全部搬家；输入 Q 取消)"
        if ($sel -match '^[Qq]$') { return }

        Write-Host "`n[*] 正在停止后台可能锁定文件的守护进程 (java / dart / adb)..." -ForegroundColor Cyan
        Stop-Process -Name "java", "dart", "adb" -Force -ErrorAction SilentlyContinue

        $toProcess = if ($sel -match "^all$") { $validList } else {
            $ids = $sel -split ',' | ForEach-Object { $_.Trim() }
            $validList | Where-Object { $ids -contains [string]$_.Index }
        }

        foreach ($task in $toProcess) {
            $src = $task.Source
            $dst = $task.Target
            Write-Host "`n>>> 开始搬家: $($task.Name) ($($task.SizeGB) GB) <<<" -ForegroundColor Green
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

            $roboArgs = @("`"$src`"", "`"$dst`"", "/E", "/MOVE", "/MT:8", "/R:2", "/W:1", "/ETA")
            $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -Wait -NoNewWindow -PassThru

            if ($proc.ExitCode -lt 8) {
                if (Test-Path $src) { Remove-Item $src -Recurse -Force -ErrorAction SilentlyContinue }
                cmd /c mklink /J "`"$src`"" "`"$dst`"" | Out-Null
                if ($task.EnvName) {
                    [Environment]::SetEnvironmentVariable($task.EnvName, $task.EnvVal, "User")
                    Write-Host "    [环境变量已配置] $($task.EnvName) = $($task.EnvVal)" -ForegroundColor Gray
                }
                Write-Host "    [√] $($task.Name) 搬家圆满完成！" -ForegroundColor Cyan
            } else {
                Write-Host "    [!] 部分文件被占用 (ExitCode: $($proc.ExitCode))，请关闭 IDE 后重试！" -ForegroundColor Red
            }
        }
    } elseif ($mode -match '^[Bb]$') {
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
        if (-Not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        Write-Host "[*] 正在调用 Robocopy 8线程迁移数据..." -ForegroundColor Green
        $roboArgs = @("`"$sourceDir`"", "`"$targetDir`"", "/E", "/MOVE", "/MT:8", "/R:2", "/W:1", "/ETA")
        $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $roboArgs -Wait -NoNewWindow -PassThru

        if ($proc.ExitCode -lt 8) {
            if (Test-Path $sourceDir) { Remove-Item $sourceDir -Recurse -Force -ErrorAction SilentlyContinue }
            cmd /c mklink /J "`"$sourceDir`"" "`"$targetDir`""
            Write-Host "`n[√] 迁移成功！所有读写已无缝重定向至 $targetDir" -ForegroundColor Cyan
        } else {
            Write-Host "`n[!] 迁移未完全成功 (错误码: $($proc.ExitCode))，请关闭占用软件后重试。" -ForegroundColor Red
        }
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

# 5. 原生 API 内存整理
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

# 6. C盘实时监护
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
        Start-Sleep -Seconds 300
    }
}

# 7. 全盘卸载残留、孤岛目录与沉睡大文件智能审计 (带实时扫描进度条 + GUI 勾选弹窗)
function Invoke-DiskSmartAuditor {
    Write-Host "`n=============================================================" -ForegroundColor Cyan
    Write-Host "     全盘卸载残留、孤岛目录与沉睡大文件智能审计 (GUI勾选版)  " -ForegroundColor Cyan
    Write-Host "=============================================================" -ForegroundColor Cyan

    $driveLetter = (Read-Host "请输入要深度扫描的盘符 (例如 D 或 C，不要带冒号)").Trim(':')
    $rootPath = "${driveLetter}:\"
    if (-not (Test-Path $rootPath)) {
        Write-Host "[!] 盘符路径 $rootPath 不存在！" -ForegroundColor Red
        return
    }

    Write-Progress -Id 1 -Activity "全盘智能审计 ($rootPath)" -Status "[1/4] 正在建立注册表已安装软件与快捷方式索引库..." -PercentComplete 10
    Write-Host "`n[1/4] 正在读取系统注册表已安装软件库与快捷方式引用库..." -ForegroundColor Green
    
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

    Write-Progress -Id 1 -Activity "全盘智能审计 ($rootPath)" -Status "[2/4] 正在交叉比对目录与卸载残留..." -PercentComplete 30
    Write-Host "[2/4] 正在分析 $rootPath 下的软件目录与卸载残留..." -ForegroundColor Green
    
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
        Write-Progress -Id 2 -ParentId 1 -Activity "正在解剖目录结构 ($fIdx/$fCount)" -Status "正在检查: $($folder.FullName)" -PercentComplete $fPct

        $files = @(Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            $auditResults.Add([PSCustomObject]@{
                Category      = "【1-空壳残留】空文件夹"
                Name          = $folder.Name
                SizeMB        = 0
                LastActive    = $folder.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = [int]((Get-Date) - $folder.LastWriteTime).TotalDays
                Advice        = "内部无任何文件，可直接清理"
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
                Category      = "【2-疑似卸载残留】无主程序且未注册"
                Name          = $folder.Name
                SizeMB        = $sizeMB
                LastActive    = $latestFile.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = $inactiveDays
                Advice        = "无 .exe 且不在注册表 (若为纯个人素材/数据目录请勿勾选)"
                FullPath      = $folder.FullName
            })
        } elseif (-not $isRegistered -and $inactiveDays -gt 60) {
            $auditResults.Add([PSCustomObject]@{
                Category      = "【3-未注册孤岛目录】长期未变动"
                Name          = $folder.Name
                SizeMB        = $sizeMB
                LastActive    = $latestFile.LastWriteTime.ToString("yyyy-MM-dd")
                InactiveDays  = $inactiveDays
                Advice        = "含可执行文件但未在系统注册，已 $inactiveDays 天未变动"
                FullPath      = $folder.FullName
            })
        }
    }
    Write-Progress -Id 2 -ParentId 1 -Activity "正在解剖目录结构" -Completed

    Write-Progress -Id 1 -Activity "全盘智能审计 ($rootPath)" -Status "[3/4] 正在全盘搜寻陈旧编译缓存 (node_modules/target/build) 与大体积包..." -PercentComplete 70
    Write-Host "[3/4] 正在全盘检索遗忘的编译缓存 (node_modules / target / build) 与大体积安装包..." -ForegroundColor Green

    Get-ChildItem -Path $rootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^(node_modules|target|build|\.gradle|\.dart_tool)$' -and $_.FullName -notmatch 'node_modules\\.*\\node_modules' } |
        ForEach-Object {
            $days = [int]((Get-Date) - $_.LastWriteTime).TotalDays
            if ($days -gt 30) {
                Write-Progress -Id 2 -ParentId 1 -Activity "发现陈旧编译目录" -Status "正在计算体积: $($_.FullName)"
                $sBytes = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $sMB = [math]::Round($sBytes / 1MB, 1)
                if ($sMB -ge 100) {
                    $auditResults.Add([PSCustomObject]@{
                        Category      = "【4-陈旧项目编译产物】可随时重建"
                        Name          = $_.Name
                        SizeMB        = $sMB
                        LastActive    = $_.LastWriteTime.ToString("yyyy-MM-dd")
                        InactiveDays  = $days
                        Advice        = "老项目构建缓存 (>100MB)，删后可通过 npm/cargo/flutter 重新生成"
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
                    Category      = "【5-沉睡安装包/压缩包】大体积单文件"
                    Name          = $_.Name
                    SizeMB        = [math]::Round($_.Length / 1MB, 1)
                    LastActive    = $_.LastWriteTime.ToString("yyyy-MM-dd")
                    InactiveDays  = $days
                    Advice        = "下载或解压后遗留的大体积包 (>100MB)"
                    FullPath      = $_.FullName
                })
            }
        }

    Write-Progress -Id 2 -ParentId 1 -Activity "发现陈旧编译目录" -Completed
    Write-Progress -Id 1 -Activity "全盘智能审计 ($rootPath)" -Completed

    if ($auditResults.Count -eq 0) {
        Write-Host "`n[√] 扫描完成！$rootPath 非常干净，未发现明显的卸载残留或大体积冗余项。" -ForegroundColor Cyan
        return
    }

    Write-Host "[4/4] 扫描完成！正在弹出可视化表格窗口（按住 Ctrl 可多选要清理的项，点击右下角【确定】）..." -ForegroundColor Yellow

    $selectedItems = $auditResults | Sort-Object Category, @{Expression="SizeMB"; Descending=$true} | 
        Out-GridView -Title "【磁盘智能审计报告 - $rootPath】请按住 Ctrl 多选要清理的条目，然后点击右下角 [确定/OK]" -PassThru

    if ($selectedItems) {
        $totalSelectedGB = [math]::Round(($selectedItems | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)
        Write-Host "`n您共勾选了 $($selectedItems.Count) 个条目，总计约 $totalSelectedGB GB：" -ForegroundColor Yellow
        $selectedItems | ForEach-Object { Write-Host " - [$($_.SizeMB) MB] $($_.FullPath)" -ForegroundColor Gray }
        
        $delMode = Read-Host "`n请选择清理方式：[1] 安全移入回收站 (推荐，可还原)  [2] 永久彻底删除  [Q] 取消操作"
        
        if ($delMode -eq '1') {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $cIdx = 0
            foreach ($item in $selectedItems) {
                $cIdx++
                Write-Progress -Id 1 -Activity "正在移入回收站 ($cIdx/$($selectedItems.Count))" -Status $item.FullPath -PercentComplete (($cIdx / $selectedItems.Count) * 100)
                Write-Host "正在移入回收站: $($item.FullPath) ..." -ForegroundColor Green
                try {
                    if (Test-Path $item.FullPath -PathType Container) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($item.FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    } else {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.FullPath, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    }
                } catch {
                    Write-Host "[!] 无法移动 $($item.FullPath): $_" -ForegroundColor Red
                }
            }
            Write-Progress -Id 1 -Activity "正在移入回收站" -Completed
            Write-Host "`n[√] 全部选中项已安全移入回收站！" -ForegroundColor Cyan
        } elseif ($delMode -eq '2') {
            foreach ($item in $selectedItems) {
                Write-Host "正在永久删除: $($item.FullPath) ..." -ForegroundColor Red
                Remove-DirectoryContentsWithProgress -TargetFolder $item.FullPath -Title "正在删除 $($item.Name)"
                Remove-Item -Path $item.FullPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "`n[√] 全部选中项已彻底删除！" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`n[*] 未选择任何条目，已安全返回。" -ForegroundColor Gray
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
        '7' { Invoke-DiskSmartAuditor; Pause }
    }
} until ($choice -eq 'Q' -or $choice -eq 'q')