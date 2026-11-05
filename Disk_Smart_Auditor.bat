<# :
@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::Default))"
pause
exit /b
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host

Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "     全盘卸载残留、孤岛目录与沉睡大文件智能审计工具 (GUI版)  " -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan

$driveLetter = Read-Host "请输入要深度扫描的盘符 (例如 D 或 E，不要带冒号)"
$rootPath = "${driveLetter}:\"
if (-not (Test-Path $rootPath)) {
    Write-Host "[!] 盘符路径 $rootPath 不存在！" -ForegroundColor Red
    exit
}

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
        # 提取软件名核心词
        $cleanName = ($app.DisplayName -split '[\s\-\(\)_v\d]+')[0]
        if ($cleanName.Length -ge 3) { $knownKeywords.Add($cleanName) | Out-Null }
    }
}

# 收集桌面和开始菜单所有快捷方式指向的真实路径
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

Write-Host "[2/4] 正在分析 $rootPath 下的软件目录与卸载残留..." -ForegroundColor Green
# 扫描根目录下的第一层文件夹，以及常见软件安装目录下的子文件夹
$scanDirs = Get-ChildItem -Path $rootPath -Directory -Force -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -notmatch '^\$RECYCLE\.BIN$|^System Volume Information$|^Recovery$|^Windows$' }

$targetFolders = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
foreach ($dir in $scanDirs) {
    if ($dir.Name -match '^(Program Files|Program Files \(x86\)|Software|Apps|Games|ProgramData)$') {
        Get-ChildItem -Path $dir.FullName -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $targetFolders.Add($_) }
    } else {
        $targetFolders.Add($dir)
    }
}

foreach ($folder in $targetFolders) {
    $files = Get-ChildItem -Path $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
    if (-not $files) {
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
    if ($sizeMB -lt 5) { continue } # 忽略小于 5MB 的微小型目录，聚焦空间大户

    $exeCount = ($files | Where-Object { $_.Extension -match '^\.(exe|bat|cmd)$' }).Count
    $latestFile = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $inactiveDays = [int]((Get-Date) - $latestFile.LastWriteTime).TotalDays

    # 匹配注册表与快捷方式
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
            Advice        = "高嫌疑：无 .exe 且不在注册表 (也可能是纯素材/数据目录，请核对路径)"
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

Write-Host "[3/4] 正在全盘检索遗忘的编译缓存 (node_modules / target / build) 与大体积安装包..." -ForegroundColor Green

# 扫描全盘超过 30 天未变动的巨型构建目录 (node_modules, Rust target, Gradle/Flutter build)
Get-ChildItem -Path $rootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^(node_modules|target|build|\.gradle|\.dart_tool)$' -and $_.FullName -notmatch 'node_modules\\.*\\node_modules' } |
    ForEach-Object {
        $days = [int]((Get-Date) - $_.LastWriteTime).TotalDays
        if ($days -gt 30) {
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

# 扫描全盘超过 100MB 的独立安装包/压缩包/镜像
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

if ($auditResults.Count -eq 0) {
    Write-Host "`n[√] 扫描完成！$rootPath 非常干净，未发现明显的卸载残留或大体积冗余项。" -ForegroundColor Cyan
    exit
}

Write-Host "[4/4] 扫描完成！正在打开可视化决策窗口（请在弹出的窗口中按住 Ctrl 多选要清理的项，点击右下角【确定】）..." -ForegroundColor Yellow

# 弹出 Windows 原生交互表格供用户筛选和勾选
$selectedItems = $auditResults | Sort-Object Category, @{Expression="SizeMB"; Descending=$true} | 
    Out-GridView -Title "【磁盘智能审计报告 - $rootPath】请勾选要清理的条目（按住 Ctrl 或 Shift 可多选），然后点击右下角 [确定]" -PassThru

if ($selectedItems) {
    Write-Host "`n您共勾选了 $($selectedItems.Count) 个条目，总计约 $([math]::Round(($selectedItems | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)) GB：" -ForegroundColor Yellow
    $selectedItems | ForEach-Object { Write-Host " - [$($_.SizeMB) MB] $($_.FullPath)" -ForegroundColor Gray }
    
    $delMode = Read-Host "`n请选择清理方式：[1] 安全移入回收站 (推荐，可反悔)  [2] 永久彻底删除  [Q] 取消操作"
    
    if ($delMode -eq '1') {
        Add-Type -AssemblyName Microsoft.VisualBasic
        foreach ($item in $selectedItems) {
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
        Write-Host "`n[√] 全部选中项已安全移入回收站！" -ForegroundColor Cyan
    } elseif ($delMode -eq '2') {
        foreach ($item in $selectedItems) {
            Write-Host "正在永久删除: $($item.FullPath) ..." -ForegroundColor Red
            Remove-Item -Path $item.FullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "`n[√] 全部选中项已彻底删除！" -ForegroundColor Cyan
    }
} else {
    Write-Host "`n[*] 未选择任何条目，已安全退出。" -ForegroundColor Gray
}