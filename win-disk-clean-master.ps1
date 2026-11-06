#requires -Version 5.1
<#
Windows Disk Clean Master - Safe Edition V2.3
Safety policy: read-only audit, no permanent deletion, never remove package stores wholesale,
no global registry edits or process killing. Requires interactive Windows PowerShell 5.1+.
#>
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$script:LogRoot = Join-Path $env:LOCALAPPDATA 'WinDiskCleanSafe\logs'
$script:ProtectedExtra = Join-Path $PSScriptRoot 'protected-paths.txt'
$script:LogFile = $null
# Prefer the interactive user's Windows display locale, not only the PowerShell UI culture.
$script:DetectedLocale = $null
try { $script:DetectedLocale = (Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\International' -Name LocaleName -ErrorAction Stop).LocaleName } catch {}
if ([string]::IsNullOrWhiteSpace($script:DetectedLocale)) { $script:DetectedLocale = [System.Globalization.CultureInfo]::CurrentUICulture.Name }
$script:Culture = if ($script:DetectedLocale -match '^zh') { 'zh' } else { 'en' }
$script:QuarantineFile = Join-Path $env:LOCALAPPDATA 'WinDiskCleanSafe\quarantine-v21.csv'
$script:LastProjectScan = @()

function Say([string]$zh, [string]$en) { if ($script:Culture -eq 'zh') { $zh } else { $en } }
function Inform([string]$message, [string]$color = 'Gray') { Write-Host $message -ForegroundColor $color }
function Log([string]$action, [string]$path, [string]$result) {
    try {
        if (-not (Test-Path -LiteralPath $script:LogRoot)) { [void](New-Item -ItemType Directory -Path $script:LogRoot -Force) }
        if (-not $script:LogFile) { $script:LogFile = Join-Path $script:LogRoot ("session-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
        [pscustomobject]@{Time=(Get-Date).ToString('o');Action=$action;Path=$path;Result=$result} |
            Export-Csv -LiteralPath $script:LogFile -Encoding UTF8 -NoTypeInformation -Append
    } catch { Write-Warning "Logging failed: $($_.Exception.Message)" }
}
function AskExact([string]$question, [string]$word) {
    $answer = Read-Host "$question [$word]"
    return ($answer -ceq $word)
}
function Canonical([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Empty path' }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($path.Trim().Trim('"')))
    $root = [IO.Path]::GetPathRoot($full)
    if ($full -ieq $root) { return $root }
    return $full.TrimEnd('\')
}
function Under([string]$path, [string]$base) {
    if ([string]::IsNullOrWhiteSpace($base)) { return $false }
    $p = Canonical $path; $b = Canonical $base
    $prefix = if ($b.EndsWith('\')) { $b } else { $b + '\' }
    return ($p.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))
}
function IsRoot([string]$path) { return ([IO.Path]::GetPathRoot((Canonical $path)) -ieq (Canonical $path)) }
function IsLink([string]$path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}
function HasLinkAncestor([string]$path) {
    $p = Canonical $path
    while ($p -and (Test-Path -LiteralPath $p)) {
        if (IsLink $p) { return $true }
        $parent = Split-Path -Path $p -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $p) { break }
        $p = $parent
    }
    return $false
}
function BuiltInProtected {
    @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
        [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
        [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'),
        [Environment]::GetFolderPath('MyMusic'), (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'OneDrive'), $script:LogRoot) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
function ExtraProtected {
    if (Test-Path -LiteralPath $script:ProtectedExtra -PathType Leaf) {
        Get-Content -LiteralPath $script:ProtectedExtra -Encoding UTF8 |
            ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
    }
}
function AssertSafePath([string]$path, [string]$purpose) {
    $p = Canonical $path
    if (IsRoot $p) { throw "Refusing volume root: $p" }
    if (-not [IO.Path]::IsPathRooted($p)) { throw "Not absolute: $p" }
    if (HasLinkAncestor $p) { throw "Reparse point in path: $p" }
    foreach ($x in @(BuiltInProtected) + @(ExtraProtected)) {
        if (-not (Test-Path -LiteralPath $x)) { continue }
        if (Under $p $x) { throw "Protected ($purpose): $p (rule: $x)" }
        # Also block choosing a parent folder containing protected data.
        if (Under $x $p) { throw "Parent of protected path ($purpose): $p" }
    }
    return $p
}
function GetTree([string]$path) {
    # Fail closed on access errors, and refuse junctions/symlinks anywhere in the tree.
    $root = Canonical $path
    if (HasLinkAncestor $root) { throw "Linked directory: $root" }
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    $files = New-Object 'System.Collections.Generic.List[object]'
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
        foreach ($entry in $children) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked entry: $($entry.FullName)" }
            $relative = $entry.FullName.Substring($root.Length).TrimStart('\')
            if ($entry.PSIsContainer) { $dirs.Add($relative); $stack.Push($entry.FullName) }
            else { $files.Add([pscustomobject]@{Relative=$relative;Length=[long]$entry.Length;FullName=$entry.FullName}) }
        }
    }
    return [pscustomobject]@{ Files=$files.ToArray(); Directories=$dirs.ToArray() }
}
function BytesHuman([double]$n) { return ('{0:N2} GB' -f ($n / 1GB)) }
function GetTreeSize([string]$path) {
    $tree = GetTree $path
    $sum = [long]0
    foreach ($file in $tree.Files) { $sum += $file.Length }
    return $sum
}
function NativeCache([string]$cmd, [string[]]$arguments) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $c) { return $null }
    try {
        $value = (& $cmd @arguments 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -ne 0) { return $null }
        return ([string]$value).Trim()
    } catch { return $null }
}
function ShowIntro {
    Clear-Host
    $line = '==========================================================================='
    Inform $line 'Cyan'
    Inform (Say '       Windows 磁盘清理大师 V2.3 - 深度清理、缓存迁移与全盘审计' '       Windows Disk Clean Master V2.3 - Deep Clean, Cache Migration & Full-Disk Audit') 'Cyan'
    try {
        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $usedGB = [math]::Round($drive.Used / 1GB, 2)
        Inform (Say ("       当前 C 盘状态: 可用 {0:N2} GB / 已用 {1:N2} GB | 语言: 中文 (系统识别: {2})" -f $freeGB,$usedGB,$script:DetectedLocale) ("       C: Drive Status: Free {0:N2} GB / Used {1:N2} GB | Lang: English (System: {2})" -f $freeGB,$usedGB,$script:DetectedLocale)) 'Yellow'
    } catch {}
    Inform $line 'Cyan'
    Inform (Say '1. [一键清理] 逐文件扫描用户 %TEMP% 旧文件，确认后移入回收站' '1. [Quick Clean] Scan older %TEMP% files individually; preview and recycle')
    Inform (Say '2. [开发瘦身] 扫描 Gradle / Dart / Pub / npm 缓存与项目构建产物 (安全隔离)' '2. [Dev Slimming] Scan caches and project build outputs (safe quarantine)')
    Inform (Say '3. [无感迁移] 开发缓存与自定义目录安全迁移 (校验 + 备份)' '3. [Seamless Migrate] Safe migration with verification and backup')
    Inform (Say '4. [目录迁移] 查看默认 Program Files 安装注册表路径 (只读)' '4. [Install Paths] Inspect Program Files registry paths (read-only)')
    Inform (Say '5. [内存优化] 查看后台进程内存占用 (只读，不强制释放)' '5. [Memory] Inspect RAM usage (read-only; no forced trim)')
    Inform (Say '6. [实时监护] 开启 C 盘剩余空间后台监控预警 (低于 5GB 提醒)' '6. [Disk Guard] Monitor C: free space (alert below 5GB)')
    Inform (Say '7. [全盘审计] 扫描任意盘可疑目录与老旧编译产物 (只读报告)' '7. [Full-Disk Audit] Scan leftovers and old builds (read-only report)') 'Green'
    Inform (Say '8. [隔离恢复] 恢复已隔离的项目构建目录 (不覆盖原文件)' '8. [Restore] Restore quarantined builds (no overwrite)')
    Inform (Say '9. [隔离清理] 永久清理隔离超过 7 天的项目 (需明确确认)' '9. [Quarantine Purge] Permanently purge items held 7+ days (confirmation)')
    Inform '---------------------------------------------------------------------------' 'DarkGray'
    Inform (Say 'L. [Language] 切换语言为 English (Switch to English)' 'L. [语言切换] 切换语言为中文 (Switch to Chinese)') 'Magenta'
    Inform (Say 'Q. 退出 (Quit)' 'Q. Quit')
    Inform $line 'Cyan'
}

# Menu 1 in V2.3: conservative file-level scanning of the current user's TEMP.
# Do not treat an entire directory as garbage based on its age.
function Test-TempProtectedFile([string]$path) {
    $name = [IO.Path]::GetFileName($path)
    $extension = [IO.Path]::GetExtension($name).ToLowerInvariant()
    # Conservative exclusions: user-owned documents, executable/installable files,
    # source/config, archives and database/data stores are never auto-candidates.
    $excluded = @('.exe','.dll','.sys','.msi','.msp','.msix','.appx','.bat','.cmd','.ps1','.psm1','.vbs','.js','.ts','.py','.rs','.java','.kt','.dart','.cs','.cpp','.c','.h','.hpp',
        '.json','.yaml','.yml','.toml','.xml','.ini','.cfg','.config','.env','.lock','.db','.sqlite','.sqlite3','.mdb','.accdb','.bak',
        '.zip','.7z','.rar','.tar','.gz','.tgz','.iso','.vhd','.vhdx','.vmdk','.qcow2','.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx',
        '.txt','.md','.csv','.rtf','.jpg','.jpeg','.png','.gif','.webp','.svg','.mp3','.mp4','.mov','.avi','.wav','.flac')
    if ($excluded -contains $extension) { return $true }
    if ($name -match '^(?i:package-lock\.json|pnpm-lock\.yaml|yarn\.lock|pubspec\.lock|cargo\.lock|gradle\.properties|pom\.xml)$') { return $true }
    return $false
}
function Test-TempProtectedDirectory([string]$path) {
    # Ignore VCS, package stores, source or tool config subtrees even if nested in TEMP.
    $name = [IO.Path]::GetFileName($path.TrimEnd('\'))
    if ($name -match '^(?i:\.git|\.svn|\.hg|\.ssh|\.gnupg|node_modules|\.gradle|\.dart_tool|\.venv|venv|__pycache__|\.cargo|\.pub-cache|\.npm|\.pnpm-store|\.yarn|\.idea|\.vscode)$') { return $true }
    foreach ($extra in @(ExtraProtected)) {
        try {
            # Treat a user-protected directory and its ancestors as off-limits.
            if (Under $path $extra) { return $true }
        } catch { return $true }
    }
    return $false
}
function Invoke-TempPreview {
    $temp = Canonical $env:TEMP
    if (-not (Test-Path -LiteralPath $temp -PathType Container)) {
        Inform (Say '当前 TEMP 路径不存在。' 'Current TEMP directory does not exist.') 'Yellow'; return
    }
    if ((IsRoot $temp) -or (HasLinkAncestor $temp) -or (Test-TempProtectedDirectory $temp)) {
        Inform (Say 'TEMP 路径为根目录、链接或受保护位置，已停止。' 'TEMP is a root, link or protected path; aborted.') 'Yellow'; return
    }
    # Enforce explicit user scope: do not accidentally operate under Windows or shared system paths.
    $currentUser = Canonical $env:USERPROFILE
    if (-not (Under $temp $currentUser)) {
        Inform (Say ("TEMP 不在当前用户目录内，拒绝清理：{0}" -f $temp) ("TEMP is outside current user's profile, refusing: {0}" -f $temp)) 'Yellow'; return
    }
    $daysText = Read-Host (Say '保留最近多少天的文件？[默认 7，可输入 14 或 30]' 'Keep files modified in the last N days? [default 7, or 14/30]')
    $days = 7
    if (-not [string]::IsNullOrWhiteSpace($daysText)) {
        if ($daysText.Trim() -notin @('7','14','30')) {
            Inform (Say '仅支持 7、14、30 天；已取消。' 'Only 7, 14 or 30 days are supported; cancelled.') 'Yellow'; return
        }
        $days = [int]$daysText.Trim()
    }
    $cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$days)
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($temp)
    $scanDirs = 0; $scanFiles = 0; $recent = 0; $protected = 0; $links = 0; $errors = 0
    $candidateBytes = [long]0; $recentBytes = [long]0; $maxDirs = 150000; $maxFiles = 1500000
    Inform (Say ("正在按文件扫描：{0}（保留最近 {1} 天）" -f $temp,$days) ("Scanning individual files: {0} (retaining recent {1} days)" -f $temp,$days)) 'Cyan'
    while ($stack.Count -gt 0) {
        if ($scanDirs -ge $maxDirs -or $scanFiles -ge $maxFiles) { $errors++; break }
        $dir = $stack.Pop()
        if ((Test-TempProtectedDirectory $dir) -or (HasLinkAncestor $dir)) { $protected++; continue }
        $scanDirs++
        try { $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) }
        catch { $errors++; continue }
        foreach ($item in $children) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $links++; continue }
            if ($item.PSIsContainer) {
                if (Test-TempProtectedDirectory $item.FullName) { $protected++; continue }
                $stack.Push($item.FullName)
                continue
            }
            $scanFiles++
            if ($scanFiles -ge $maxFiles) { break }
            if (($item.Attributes -band [IO.FileAttributes]::System) -ne 0 -or
                ($item.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0 -or
                (Test-TempProtectedFile $item.FullName)) { $protected++; continue }
            if ($item.LastWriteTimeUtc -ge $cutoffUtc) { $recent++; $recentBytes += [long]$item.Length; continue }
            $relative = $item.FullName.Substring($temp.Length).TrimStart('\')
            $first = ($relative -split '\\')[0]
            $candidates.Add([pscustomobject]@{ Path=$item.FullName;Bytes=[long]$item.Length;ModifiedUtc=$item.LastWriteTimeUtc;Attributes=[int]$item.Attributes;Group=$first })
            $candidateBytes += [long]$item.Length
        }
        if (($scanDirs % 150) -eq 0) {
            Write-Progress -Activity (Say '扫描用户 TEMP（不修改文件）' 'Scanning user TEMP (read only)') -Status ("Dirs {0}, Files {1}, Candidates {2}" -f $scanDirs,$scanFiles,$candidates.Count) -PercentComplete -1
        }
    }
    Write-Progress -Activity (Say '扫描用户 TEMP（不修改文件）' 'Scanning user TEMP (read only)') -Completed
    Inform (Say ("扫描文件：{0}；扫描目录：{1}；最近 {2} 天保护：{3} 项；按类型保护/目录：{4} 项；链接跳过：{5}；读取错误或达上限：{6}" -f $scanFiles,$scanDirs,$days,$recent,$protected,$links,$errors) ("Files: {0}; directories: {1}; recent files: {3}; protected: {4}; links: {5}; scan errors/limits: {6}" -f $scanFiles,$scanDirs,$days,$recent,$protected,$links,$errors)) 'Gray'
    Inform (Say ("可选旧文件：{0} 项，约 {1}；这些文件尚未被删除。" -f $candidates.Count,(BytesHuman $candidateBytes)) ("Older-file candidates: {0}, about {1}; nothing has been deleted." -f $candidates.Count,(BytesHuman $candidateBytes))) 'Yellow'
    if ($candidates.Count -eq 0) {
        Inform (Say '没有满足当前保留与保护规则的文件；可尝试 14/30 天以提高保护程度，而不是降低保护范围。' 'No eligible files for these rules; 14/30 days makes selection more conservative.') 'DarkGray'
        return
    }
    Inform (Say '候选按 TEMP 顶层来源分组（仅展示前 12 组）：' 'Candidates grouped by top-level TEMP directory (top 12):') 'Cyan'
    $groups = @($candidates | Group-Object Group | ForEach-Object {
        $bytes = [long]0; foreach ($v in $_.Group) { $bytes += $v.Bytes }
        [pscustomobject]@{Directory=$_.Name;Files=$_.Count;GB=[math]::Round($bytes/1GB,3)}
    } | Sort-Object GB -Descending)
    $groups | Select-Object -First 12 | Format-Table -AutoSize
    Inform (Say '体积最大的候选文件（前 20 个）：' 'Largest individual candidates (top 20):') 'Cyan'
    $candidates | Sort-Object Bytes -Descending | Select-Object -First 20 |
        Select-Object @{N='MB';E={[math]::Round($_.Bytes/1MB,1)}},@{N='Modified';E={$_.ModifiedUtc.ToLocalTime().ToString('yyyy-MM-dd')}},Path |
        Format-Table -AutoSize -Wrap
    if ($errors -gt 0) {
        Inform (Say '注意：部分目录读取失败或达到限制；其内容不在候选列表中。' 'Some directories could not be read or limits were reached; their files are excluded.') 'Yellow'
    }
    Inform (Say '回收站并非备份；当前程序仅对当前用户 TEMP 中符合条件的普通文件逐个执行移入回收站。' 'Recycle Bin is not a backup. Only eligible ordinary files in this user TEMP will be recycled.') 'Yellow'
    if (-not (AskExact (Say ("确认将 {0} 个旧文件（约 {1}）移入回收站？" -f $candidates.Count,(BytesHuman $candidateBytes)) ("Recycle {0} old files (about {1})?" -f $candidates.Count,(BytesHuman $candidateBytes))) 'RECYCLE')) {
        Inform (Say '已取消，未修改文件。' 'Cancelled. Nothing changed.') 'Gray'; return
    }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0; $failed = 0; $changed = 0; $okBytes = [long]0
    foreach ($candidate in $candidates) {
        try {
            $path = Canonical $candidate.Path
            if ((-not (Under $path $temp)) -or (HasLinkAncestor $path) -or (Test-TempProtectedDirectory (Split-Path -Path $path -Parent)) -or (Test-TempProtectedFile $path)) {
                throw 'Path was changed or became protected'
            }
            $live = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($live.PSIsContainer -or (($live.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
                (($live.Attributes -band [IO.FileAttributes]::System) -ne 0) -or
                (($live.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) -or
                $live.LastWriteTimeUtc -ge $cutoffUtc -or
                $live.LastWriteTimeUtc -ne $candidate.ModifiedUtc -or
                [long]$live.Length -ne $candidate.Bytes -or
                [int]$live.Attributes -ne $candidate.Attributes) {
                $changed++; continue
            }
            # Reject files currently held open by other programs when exclusive access is unavailable.
            $stream = $null
            try {
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            } finally { if ($stream) { $stream.Dispose() } }
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $ok++; $okBytes += $candidate.Bytes
        } catch {
            $failed++
            Log 'RecycleTempFailed' $candidate.Path $_.Exception.Message
        }
        if ((($ok + $failed + $changed) % 100) -eq 0) {
            Write-Progress -Activity (Say '逐文件移入回收站' 'Recycling selected files') -Status ("Done {0}/{1}, failed {2}, changed {3}" -f ($ok+$failed+$changed),$candidates.Count,$failed,$changed) -PercentComplete ([math]::Min(100,[int](100*($ok+$failed+$changed)/$candidates.Count)))
        }
    }
    Write-Progress -Activity (Say '逐文件移入回收站' 'Recycling selected files') -Completed
    Inform (Say ("移入回收站成功 {0} 项（约 {1}）；状态变化跳过 {2}；失败/占用 {3}。" -f $ok,(BytesHuman $okBytes),$changed,$failed) ("Recycled {0} files (about {1}); changed/skipped {2}; failed/in use {3}." -f $ok,(BytesHuman $okBytes),$changed,$failed)) 'Cyan'
    Inform (Say '移入回收站后，磁盘可用空间通常不会立即增加；需要日后手动清空回收站才会真正释放。' 'Recycling normally does not immediately reclaim disk space; empty the Recycle Bin later only after review.') 'Yellow'
    Log 'TempFileScan' $temp ("days={0};candidates={1};recycled={2};changed={3};failed={4};bytes={5}" -f $days,$candidates.Count,$ok,$changed,$failed,$okBytes)
}
# Inspect a real npm executable, not only the first line of npm's output.
function Get-NpmExecutable {
    $cmds = @(Get-Command npm.cmd -All -ErrorAction SilentlyContinue) + @(Get-Command npm.exe -All -ErrorAction SilentlyContinue)
    foreach ($cmd in $cmds) { if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) { return $cmd.Source } }
    # npm is often in a version-manager's active Node directory; do not guess inactive versions.
    return $null
}
# Launch npm.cmd through cmd.exe (Windows batch files cannot be reliably started
# using .NET UseShellExecute=false directly). Capture stdout, stderr and exit code.
function Invoke-NpmConfigCache([string]$executable) {
    if (-not $executable) { return [pscustomobject]@{Path=$null;Error='npm not found'} }
    if ($executable -match '[&|<>"]') { return [pscustomobject]@{Path=$null;Error='unsafe executable path characters'} }
    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        # cmd.exe /d disables AutoRun; /s /c handles quoted executable paths.
        $psi.Arguments = '/d /s /c ""{0}" config get cache --loglevel=silent"' -f $executable
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        if (-not $process.Start()) { throw 'process did not start' }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch {}
            return [pscustomobject]@{Path=$null;Error='npm config timeout (15 seconds)'}
        }
        $stdout = $outTask.GetAwaiter().GetResult().Trim()
        $stderr = $errTask.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            $detail = if ($stderr) { $stderr } else { $stdout }
            if ($detail.Length -gt 400) { $detail = $detail.Substring(0,400) }
            return [pscustomobject]@{Path=$null;Error=("exit {0}: {1}" -f $process.ExitCode,$detail)}
        }
        $lines = @($stdout -split '[\r\n]+' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and $_ -notmatch '^npm (warn|notice|error)' })
        if ($lines.Count -ne 1 -or -not [IO.Path]::IsPathRooted($lines[0])) {
            return [pscustomobject]@{Path=$null;Error=("unexpected npm output: " + ($stdout.Substring(0,[Math]::Min(300,$stdout.Length))))}
        }
        return [pscustomobject]@{Path=(Canonical $lines[0]);Error=$null}
    } catch {
        return [pscustomobject]@{Path=$null;Error=$_.Exception.Message}
    } finally { if ($process) { $process.Dispose() } }
}
function Get-NpmCachePath([string]$executable) { return (Invoke-NpmConfigCache $executable).Path }

# These names are intentionally conservative: Win32_Process cannot reliably
# determine the working directory of a process started by an IDE or shell.
function Get-ActiveBuildProcesses {
    $names = @('cargo.exe','rustc.exe','rustup.exe','flutter.exe','dart.exe',
        'gradle.exe','gradle.bat','gradlew.exe','gradlew.bat','java.exe','javaw.exe',
        'mvn.exe','mvn.cmd','kotlinc.exe','cmake.exe','ninja.exe','msbuild.exe')
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object { $names -contains $_.Name.ToLowerInvariant() } |
        Select-Object ProcessId,Name,CommandLine)
    return $processes
}
function Assert-NoActiveBuild([string]$project) {
    # Stop if any potentially relevant build process exists, including a process
    # whose working directory cannot be determined. Safety beats convenience.
    $active = @(Get-ActiveBuildProcesses)
    if ($active.Count -eq 0) { return }
    $sample = @($active | Select-Object -First 6 | ForEach-Object { '{0}(PID {1})' -f $_.Name,$_.ProcessId }) -join ', '
    throw (Say ("发现正在运行的构建相关进程，无法可靠判断所属项目；已阻止隔离：$sample。请关闭相关构建进程后重试。") ("Build-related processes are running; project affiliation is uncertain. Quarantine blocked: $sample. Close build processes and retry."))
}
function Get-ProjectActivity([string]$project, [object]$buildTree) {
    # File modification is an activity *signal*, not access/last-used time.
    $latestProject = [datetime]::MinValue
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $project -File -Force -ErrorAction Stop)) {
            if ($file.LastWriteTime -gt $latestProject) { $latestProject = $file.LastWriteTime }
        }
        foreach ($name in @('src','lib','test','tests','android','ios','windows','web')) {
            $folder = Join-Path $project $name
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            $dir = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
            if ($dir.LastWriteTime -gt $latestProject) { $latestProject = $dir.LastWriteTime }
        }
    } catch { $latestProject = [datetime]::MinValue }
    $latestBuild = [datetime]::MinValue
    # GetTree returns full paths; prefer a limited sample for performance.
    foreach ($f in @($buildTree.Files | Select-Object -First 100)) {
        try {
            $t=(Get-Item -LiteralPath $f.FullName -ErrorAction Stop).LastWriteTime
            if ($t -gt $latestBuild) { $latestBuild=$t }
        } catch { $latestBuild=[datetime]::MinValue; break }
    }
    return [pscustomobject]@{Project=$latestProject;Build=$latestBuild}
}
function Format-Activity([datetime]$t) {
    if ($t -eq [datetime]::MinValue) { return (Say '未知' 'unknown') }
    return ('{0:yyyy-MM-dd}' -f $t)
}
function Parse-Selection([string]$value, [int]$max) {
    if ($value -notmatch '^\s*\d+(?:\s*-\s*\d+)?(?:\s*,\s*\d+(?:\s*-\s*\d+)?)*\s*$') { throw 'Selection must contain numbers, commas or ranges like 1-3' }
    $selected = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($token in ($value -split ',')) {
        $parts = $token.Trim() -split '\s*-\s*'
        $first = 0; $last = 0
        if (-not [int]::TryParse($parts[0],[ref]$first)) { throw 'Invalid number' }
        $last = $first
        if ($parts.Count -eq 2 -and -not [int]::TryParse($parts[1],[ref]$last)) { throw 'Invalid range' }
        if ($first -lt 1 -or $last -gt $max -or $last -lt $first) { throw 'Selection out of range' }
        if ($last - $first -gt 999) { throw 'Range too large' }
        for ($v=$first; $v -le $last; $v++) { [void]$selected.Add($v) }
    }
    return @($selected | Sort-Object)
}
function Get-ProjectKind([string]$dir) {
    # Anchored markers prevent arbitrary folders named build/target from becoming candidates.
    if (Test-Path -LiteralPath (Join-Path $dir 'gradlew.bat') -PathType Leaf) {
        if ((Test-Path -LiteralPath (Join-Path $dir 'build.gradle') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir 'build.gradle.kts') -PathType Leaf)) { return 'Gradle' }
    }
    if (Test-Path -LiteralPath (Join-Path $dir 'pom.xml') -PathType Leaf) { return 'Maven' }
    if ((Test-Path -LiteralPath (Join-Path $dir 'Cargo.toml') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $dir 'Cargo.lock') -PathType Leaf)) { return 'Cargo' }
    if (Test-Path -LiteralPath (Join-Path $dir 'pubspec.yaml') -PathType Leaf) { return 'Dart/Flutter' }
    if (Test-Path -LiteralPath (Join-Path $dir 'package.json') -PathType Leaf) { return 'JavaScript' }
    return $null
}
function Test-DevCandidate([string]$path, [string]$root, [string]$kind) {
    # Only narrowly-defined build products; never npm dependencies, pub, or Gradle global caches.
    if (AuditBlocked $path) { return $null }
    if (HasLinkAncestor $path) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $null }
    if (IsRoot $path) { return $null }
    $leaf = Split-Path -Path $path -Leaf
    $parent = Split-Path -Path $path -Parent
    if ($parent -ine (Canonical $root)) { return $null }
    $ok = (($kind -eq 'Gradle' -and $leaf -ceq 'build') -or
           ($kind -eq 'Maven' -and $leaf -ceq 'target') -or
           ($kind -eq 'Cargo' -and $leaf -ceq 'target') -or
           ($kind -eq 'Dart/Flutter' -and $leaf -ceq 'build'))
    if (-not $ok) { return $null }
    return '中：构建产物可能影响离线开发；隔离后可恢复'
}
function Get-DevProjects([string]$scanRoot) {
    $found = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($scanRoot)
    $checked = 0; $errors = 0; $limit = 15000
    $ignored = @('.git','.svn','node_modules','.gradle','.dart_tool','.idea','.vscode','.venv','venv','vendor','dist','build','target','.next','.nuxt','.wdcs-quarantine','WinDiskCleanSafe-Quarantine')
    while ($stack.Count -gt 0 -and $checked -lt $limit) {
        $dir = $stack.Pop(); $checked++
        if ($checked % 250 -eq 0) { Write-Progress -Activity (Say '识别开发项目' 'Detecting developer projects') -Status "$checked directories" }
        try {
            if (AuditBlocked $dir) { continue }
            $entries = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)
        } catch { $errors++; continue }
        $kind = Get-ProjectKind $dir
        if ($kind) {
            $outputs = switch ($kind) { 'Gradle' { @('build') } 'Maven' { @('target') } 'Cargo' { @('target') } 'Dart/Flutter' { @('build') } default { @() } }
            foreach ($output in $outputs) {
                $candidate = Join-Path $dir $output
                $risk = Test-DevCandidate $candidate $dir $kind
                if (-not $risk) { continue }
                try {
                    $tree = GetTree $candidate
                    $bytes = [long]0
                    foreach ($f in $tree.Files) { $bytes += $f.Length }
                    $activity = Get-ProjectActivity $dir $tree
                    $volume = [IO.Path]::GetPathRoot((Canonical $candidate)).TrimEnd('\')
                    $found.Add([pscustomobject]@{Project=$dir;Kind=$kind;Path=$candidate;Volume=$volume;Bytes=$bytes;Files=$tree.Files.Count;Risk=$risk;Modified=(Get-Item -LiteralPath $candidate).LastWriteTime;ProjectActivity=$activity.Project;BuildActivity=$activity.Build})
                } catch { $errors++; Inform (Say "无法完整检查，已跳过：$candidate" "Incomplete scan; skipped: $candidate") 'DarkYellow' }
            }
        }
        foreach ($e in $entries) {
            if (-not $e.PSIsContainer) { continue }
            if (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($ignored -contains $e.Name) { continue }
            if ($e.Name -match '^(\$RECYCLE\.BIN|System Volume Information|Windows|Program Files|Program Files \(x86\)|ProgramData|Recovery)$') { continue }
            if (AuditBlocked $e.FullName) { continue }
            $stack.Push($e.FullName)
        }
    }
    Write-Progress -Activity (Say '识别开发项目' 'Detecting developer projects') -Completed
    if ($stack.Count -gt 0) { Write-Warning (Say '扫描达到 15000 个目录上限，结果并不完整。' '15,000-directory scan cap reached; results are incomplete.') }
    Inform (Say "检查目录：$checked；读取异常：$errors；已识别构建候选：$($found.Count)" "Directories: $checked; errors: $errors; build candidates: $($found.Count)") 'Gray'
    return @($found.ToArray())
}
function Save-QuarantineRecord([object]$entry) {
    $parent = Split-Path $script:QuarantineFile -Parent
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop) }
    $entry | Export-Csv -LiteralPath $script:QuarantineFile -Append -Encoding UTF8 -NoTypeInformation -ErrorAction Stop
}
function Move-DevToQuarantine([object]$candidate) {
    # Recheck the source immediately before the move. Keep quarantine on the same volume.
    $path = Canonical $candidate.Path
    $kind = Get-ProjectKind $candidate.Project
    if ($kind -ne $candidate.Kind -or -not (Test-DevCandidate $path $candidate.Project $kind)) { throw 'Project or candidate classification changed' }
    [void](AssertSafePath $path 'build quarantine')
    Assert-NoActiveBuild $candidate.Project
    $newTree = GetTree $path
    $newBytes = [long]0; foreach ($f in $newTree.Files) { $newBytes += $f.Length }
    if ($newBytes -ne $candidate.Bytes -or $newTree.Files.Count -ne $candidate.Files) { throw 'Content changed since scan; skipped' }
    $projectParent = Split-Path (Canonical $candidate.Project) -Parent
    $qroot = Join-Path $projectParent '.wdcs-quarantine'
    if (HasLinkAncestor $projectParent) { throw 'Linked parent folder' }
    if (Test-Path -LiteralPath $qroot) {
        if (-not (Test-Path -LiteralPath $qroot -PathType Container) -or (IsLink $qroot)) { throw 'Unsafe quarantine folder' }
    } else { [void](New-Item -ItemType Directory -Path $qroot -ErrorAction Stop) }
    $id = [guid]::NewGuid().ToString('N')
    $target = Join-Path $qroot $id
    if (Test-Path -LiteralPath $target) { throw 'Quarantine collision' }
    Move-Item -LiteralPath $path -Destination $target -ErrorAction Stop
    try {
        Save-QuarantineRecord ([pscustomobject]@{Id=$id;Time=(Get-Date).ToString('o');Original=$path;Quarantine=$target;Project=$candidate.Project;Kind=$kind;Bytes=$newBytes;State='Quarantined'})
    } catch {
        try { Move-Item -LiteralPath $target -Destination $path -ErrorAction Stop } catch { Write-Warning "CRITICAL: manifest failed; folder at $target; original $path" }
        throw "Cannot save recovery record: $($_.Exception.Message)"
    }
    Log 'QuarantineBuild' $path "moved=$target; bytes=$newBytes"
    return $target
}
function Invoke-DevReport {
    $gradle = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
    $pub = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
    $npmExe = Get-NpmExecutable
    $npmResult = Invoke-NpmConfigCache $npmExe
    $npm = $npmResult.Path
    Inform (Say '依赖缓存保护（不删除）' 'Dependency caches are protected (no deletion)') 'Cyan'
    $rows = @(
        [pscustomobject]@{Name='Gradle wrapper';Path=(Join-Path $gradle 'wrapper\dists')},
        [pscustomobject]@{Name='Gradle cache';Path=(Join-Path $gradle 'caches')},
        [pscustomobject]@{Name='Pub cache';Path=$pub},
        [pscustomobject]@{Name='Dart analysis';Path=(Join-Path $env:LOCALAPPDATA '.dartServer')},
        [pscustomobject]@{Name='npm cache';Path=$npm}
    )
    foreach ($r in $rows) {
        if (-not $r.Path -or -not (Test-Path -LiteralPath $r.Path -PathType Container)) { continue }
        try { Inform ("{0,-18} {1,12} [PROTECTED]  {2}" -f $r.Name,(BytesHuman (GetTreeSize $r.Path)),$r.Path) 'Yellow' }
        catch { Write-Warning "Skipped unreadable cache: $($r.Path)" }
    }
    if (-not $npmExe) { Inform (Say 'npm：当前终端未找到 npm.cmd；检查 PATH、Node 版本管理器或重开终端。' 'npm.cmd not found in this session; check PATH/version manager.') 'Yellow' }
    elseif (-not $npm) { Inform (Say "发现 npm：$npmExe；查询失败：$($npmResult.Error)。不会操作 npm 缓存。" "Found npm: $npmExe; config query failed: $($npmResult.Error). Cache untouched.") 'Yellow' }
    else {
        Inform "npm executable: $npmExe" 'Gray'
        if (AskExact (Say '可选运行 npm cache verify（会修改 npm 自身缓存索引），输入 VERIFY' 'Optional npm cache verify (modifies its cache index). Type VERIFY') 'VERIFY') {
            & $npmExe cache verify
            $status = $LASTEXITCODE
            Log 'NpmVerify' $npm "exit=$status"
            Inform "npm exit code: $status"
        }
    }
    Inform (Say '输入开发项目的上级目录，例如 D:\\Projects；直接回车跳过。不会扫描整个 C 盘。' 'Enter a parent folder of projects, e.g. D:\\Projects; Enter to skip. No full C: scan.') 'Cyan'
    $inputPath = Read-Host (Say '项目扫描根目录' 'Project scan root')
    if ([string]::IsNullOrWhiteSpace($inputPath)) { return }
    try {
        $root = Canonical $inputPath
        if (-not (Test-Path -LiteralPath $root -PathType Container) -or (IsRoot $root) -or (HasLinkAncestor $root)) { throw 'Missing, volume root, or linked path' }
        if (AuditBlocked $root) { throw 'Scan root is protected; choose a non-protected project directory' }
        $projects = @(Get-DevProjects $root | Sort-Object Bytes -Descending)
    } catch { Write-Warning "Project scan rejected: $($_.Exception.Message)"; return }
    $script:LastProjectScan = $projects
    if ($projects.Count -eq 0) { Inform (Say '没有确认符合严格规则的构建目录；不会删除任何内容。' 'No qualifying build directories found; nothing changed.') 'Yellow'; return }
    Inform (Say '构建产物均为中风险，默认不选。最近活动日期仅是文件变动线索，不等于最近使用时间。' 'Build outputs are medium risk and unselected. Dates show modification signals, NOT actual last-used times.') 'Yellow'
    $groups = @($projects | Group-Object Volume | Sort-Object Name)
    foreach ($g in $groups) {
        $sum = [long]0; foreach ($item in $g.Group) { $sum += $item.Bytes }
        Inform (Say ("磁盘 {0}：{1} 个候选，约 {2}；隔离不会立即释放空间。" -f $g.Name,$g.Count,(BytesHuman $sum)) ("Volume {0}: {1} candidates, {2}; quarantine does NOT reclaim space." -f $g.Name,$g.Count,(BytesHuman $sum))) 'Cyan'
        for ($i=0; $i -lt $projects.Count; $i++) {
            $c=$projects[$i]
            if ($c.Volume -ne $g.Name) { continue }
            Inform ("[{0}] {1,-12} {2,10}  {3}" -f ($i+1),$c.Kind,(BytesHuman $c.Bytes),$c.Path) 'Yellow'
            Inform (Say ("     项目文件变动：{0} | 构建文件样本变动：{1}" -f (Format-Activity $c.ProjectActivity),(Format-Activity $c.BuildActivity)) ("     Project file changes: {0} | Build sample changes: {1}" -f (Format-Activity $c.ProjectActivity),(Format-Activity $c.BuildActivity))) 'DarkGray'
        }
    }
    Inform (Say '支持输入 1,3,5 或 1-10（也可混合）；回车取消。每项都会单独确认。隔离只移动文件，不释放空间。' 'Enter 1,3,5 or 1-10 (or mixed); Enter cancels. Each item requires confirmation. Quarantine does not free space.') 'Cyan'
    $choice = (Read-Host (Say '选择编号' 'Select numbers')).Trim()
    if (-not $choice) { return }
    try { $indices = @(Parse-Selection $choice $projects.Count) }
    catch { Write-Warning $_.Exception.Message; return }
    $moved=0; $skipped=0
    foreach ($index in $indices) {
        $candidate=$projects[$index-1]
        Inform (Say ("[{0}] 项目：{1}`n待隔离：{2}`n大小：{3}`n项目文件变动：{4}；构建样本变动：{5}`n请关闭 IDE 和构建任务。" -f $index,$candidate.Project,$candidate.Path,(BytesHuman $candidate.Bytes),(Format-Activity $candidate.ProjectActivity),(Format-Activity $candidate.BuildActivity)) ("[{0}] Project: {1}`nQuarantine: {2}`nSize: {3}`nProject changes: {4}; build sample: {5}`nClose IDEs/builds." -f $index,$candidate.Project,$candidate.Path,(BytesHuman $candidate.Bytes),(Format-Activity $candidate.ProjectActivity),(Format-Activity $candidate.BuildActivity))) 'Yellow'
        # Perform process check before asking, and recheck just before moving.
        try { Assert-NoActiveBuild $candidate.Project }
        catch { Write-Warning $_.Exception.Message; $skipped++; continue }
        if (-not (AskExact (Say ("第 {0} 项：输入 QUARANTINE 确认隔离，其他输入跳过" -f $index) ("Item {0}: type QUARANTINE to move; anything else skips" -f $index)) 'QUARANTINE')) { $skipped++; continue }
        try {
            $destination = Move-DevToQuarantine $candidate
            Inform (Say "已隔离：$destination；磁盘空间未释放。" "Quarantined: $destination; no disk space reclaimed.") 'Green'
            $moved++
        } catch { Write-Warning "Quarantine aborted: $($_.Exception.Message)"; $skipped++ }
    }
    Inform (Say ("操作结束：成功隔离 {0} 项，跳过/拒绝 {1} 项。通过菜单 8 恢复，菜单 9 在保留期后清理。" -f $moved,$skipped) ("Finished: {0} quarantined, {1} skipped/blocked. Restore via 8, purge after hold via 9." -f $moved,$skipped)) 'Cyan' 
}
function Invoke-RestoreBuild {
    if (-not (Test-Path -LiteralPath $script:QuarantineFile -PathType Leaf)) { Inform (Say '还没有隔离记录。' 'No quarantine records.') 'Yellow'; return }
    try { $records = @(Import-Csv -LiteralPath $script:QuarantineFile -Encoding UTF8 -ErrorAction Stop) }
    catch { Write-Warning "Cannot read manifest: $($_.Exception.Message)"; return }
    $pending = @($records | Where-Object { $_.State -eq 'Quarantined' -and (Test-Path -LiteralPath $_.Quarantine -PathType Container) })
    if ($pending.Count -eq 0) { Inform (Say '没有可恢复的隔离目录。' 'No restorable directories.') 'Yellow'; return }
    for ($i=0; $i -lt $pending.Count; $i++) { Inform ("[{0}] {1} => {2}" -f ($i+1),$pending[$i].Quarantine,$pending[$i].Original) 'Cyan' }
    $inputNum = Read-Host (Say '输入恢复编号（回车取消）' 'Restore number (Enter to cancel)')
    $n=0
    if (-not [int]::TryParse($inputNum,[ref]$n) -or $n -lt 1 -or $n -gt $pending.Count) { return }
    $item=$pending[$n-1]
    try {
        $target = Canonical $item.Original; $source = Canonical $item.Quarantine
        if (Test-Path -LiteralPath $target) { throw 'Original path already exists; never overwrite' }
        if (-not (Test-Path -LiteralPath (Split-Path $target -Parent) -PathType Container)) { throw 'Original parent missing' }
        if (HasLinkAncestor $source -or (HasLinkAncestor $target)) { throw 'Linked path' }
        if (AuditBlocked $target) { throw 'Original path protected' }
        if ((Split-Path $source -Parent) -ine (Join-Path (Split-Path $item.Project -Parent) '.wdcs-quarantine')) { throw 'Manifest/source relationship invalid' }
        [void](GetTree $source)
        if (-not (AskExact (Say "恢复到 $target？输入 RESTORE" "Restore to $target? Type RESTORE") 'RESTORE')) { return }
        Move-Item -LiteralPath $source -Destination $target -ErrorAction Stop
        $item.State = 'Restored'
        try { $records | Export-Csv -LiteralPath $script:QuarantineFile -Encoding UTF8 -NoTypeInformation -ErrorAction Stop }
        catch { Write-Warning 'Restore succeeded but manifest update failed; check record manually.' }
        Log 'RestoreBuild' $target "from=$source"
        Inform (Say "已恢复：$target" "Restored: $target") 'Green'
    } catch { Write-Warning "Restore failed safely: $($_.Exception.Message)" }
}
function Invoke-PurgeQuarantine {
    if (-not (Test-Path -LiteralPath $script:QuarantineFile -PathType Leaf)) { Inform (Say '暂无隔离记录。' 'No quarantine records.') 'Yellow'; return }
    try { $records = @(Import-Csv -LiteralPath $script:QuarantineFile -Encoding UTF8 -ErrorAction Stop) }
    catch { Write-Warning $_.Exception.Message; return }
    $eligible = New-Object 'System.Collections.Generic.List[object]'
    foreach ($record in $records) {
        if ($record.State -ne 'Quarantined') { continue }
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParse($record.Time, [ref]$date)) { continue }
        if ((Get-Date).ToUniversalTime() -lt $date.ToUniversalTime().AddDays(7)) { continue }
        if (-not (Test-Path -LiteralPath $record.Quarantine -PathType Container)) { continue }
        $eligible.Add($record)
    }
    if ($eligible.Count -eq 0) { Inform (Say '没有符合 7 天隔离期限的目录，不能永久删除。' 'No items past 7-day hold. Permanent deletion is unavailable.') 'Yellow'; return }
    for ($i=0; $i -lt $eligible.Count; $i++) {
        $item=$eligible[$i]
        Inform ("[{0}] {1} -> {2}" -f ($i+1), $item.Original, $item.Quarantine) 'Yellow'
    }
    $index = Read-Host (Say '输入要永久清除的一项编号（回车取消）' 'Enter ONE item number to permanently delete (Enter cancels)')
    $n=0
    if (-not [int]::TryParse($index,[ref]$n) -or $n -lt 1 -or $n -gt $eligible.Count) { return }
    $item=$eligible[$n-1]
    try {
        $source=Canonical $item.Quarantine
        $expectedParent=Canonical (Join-Path (Split-Path (Canonical $item.Project) -Parent) '.wdcs-quarantine')
        $expected=Canonical (Join-Path $expectedParent $item.Id)
        if ($source -ine $expected -or $item.Id -notmatch '^[0-9a-f]{32}$') { throw 'Quarantine manifest path mismatch' }
        if ((Split-Path $source -Parent) -ine $expectedParent) { throw 'Not a direct quarantine child' }
        if (HasLinkAncestor $source) { throw 'Linked quarantine item' }
        if (AuditBlocked $source) { throw 'Protected directory' }
        $tree=GetTree $source
        $bytes=[long]0; foreach ($f in $tree.Files) { $bytes += $f.Length }
        Inform (Say "永久删除：$source，约 $(BytesHuman $bytes)。无法通过程序恢复！" "PERMANENT deletion: $source, approx $(BytesHuman $bytes). Cannot restore through this tool!") 'Red'
        $approval = "PURGE $($item.Id)"
        if (-not (AskExact (Say "二次确认：逐字输入 $approval" "Second confirmation: type exactly $approval") $approval)) { return }
        # Fail closed: recheck after user confirmation; do not follow junctions or links.
        if (HasLinkAncestor $source) { throw 'Linked after confirmation' }
        [void](GetTree $source)
        Remove-Item -LiteralPath $source -Recurse -Force -ErrorAction Stop
        $item.State='Purged'
        try { $records | Export-Csv -LiteralPath $script:QuarantineFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Warning 'Deleted, but manifest could not be updated; manually inspect record.' }
        Log 'PurgeBuild' $source "bytes=$bytes"
        Inform (Say "已清理，估计释放 $(BytesHuman $bytes)（实际以文件系统为准）。" "Purged; approx $(BytesHuman $bytes) (actual recovery varies).") 'Green'
    } catch { Write-Warning "Purge failed or incomplete: $($_.Exception.Message)" }
}
function AssertMigrationPath([string]$source, [string]$dest) {
    $s = Canonical $source; $d = Canonical $dest
    if ($s -notmatch '^[A-Za-z]:\\' -or $d -notmatch '^[A-Za-z]:\\') { throw 'Local drive-letter paths only; UNC and relative paths are not supported' }
    if (-not (Test-Path -LiteralPath $s -PathType Container)) { throw "Missing source: $s" }
    [void](AssertSafePath $s 'migration source')
    [void](AssertSafePath $d 'migration target')
    if (Under $d $s -or Under $s $d) { throw 'Source/target overlap' }
    if ([IO.Path]::GetPathRoot($s) -ieq [IO.Path]::GetPathRoot($d)) { throw 'Destination must be a different volume' }
    if (Test-Path -LiteralPath $d) { throw 'Destination must not exist (avoid mixing data)' }
    if (-not (Test-Path -LiteralPath (Split-Path $d -Parent) -PathType Container)) { throw 'Destination parent must already exist' }
    if (HasLinkAncestor $d) { throw 'Linked destination ancestor' }
    # Require a fresh, exclusive backup name. Never overwrite any existing backup.
    $backup = $s + '.wdcs-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    if (Test-Path -LiteralPath $backup) { throw 'Backup name collision' }
    return [pscustomobject]@{Source=$s;Destination=$d;Backup=$backup}
}
function CompareTrees([string]$src, [string]$dst) {
    $a = GetTree $src; $b = GetTree $dst
    if ($a.Files.Count -ne $b.Files.Count -or $a.Directories.Count -ne $b.Directories.Count) { throw 'File or directory count differs' }
    $dstDirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in $b.Directories) { [void]$dstDirs.Add($directory) }
    foreach ($directory in $a.Directories) { if (-not $dstDirs.Contains($directory)) { throw "Missing directory: $directory" } }
    $destIndex = @{}
    foreach ($f in $b.Files) { $destIndex[$f.Relative] = $f }
    $count=0
    foreach ($f in $a.Files) {
        if (-not $destIndex.ContainsKey($f.Relative)) { throw "Missing file: $($f.Relative)" }
        $other = $destIndex[$f.Relative]
        if ($f.Length -ne $other.Length) { throw "Length differs: $($f.Relative)" }
        $ha = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $hb = (Get-FileHash -LiteralPath $other.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($ha -cne $hb) { throw "SHA256 differs: $($f.Relative)" }
        $count++
        if ($count % 100 -eq 0) { Inform "Verified $count / $($a.Files.Count) files..." }
    }
    return $true
}
function Invoke-SafeMigration {
    Inform (Say '迁移前请关闭相关 IDE、构建、终端进程。不会强制停止任何进程。' 'Close IDEs/builds/terminals first. No processes will be killed.') 'Yellow'
    $source = Read-Host (Say '源目录的完整路径' 'Full source directory path')
    $dest = Read-Host (Say '目标目录的完整路径（必须尚不存在，且在另一卷）' 'Full destination path (new path, different volume)')
    try { $plan = AssertMigrationPath $source $dest } catch { Write-Warning $_.Exception.Message; return }
    try {
        $sum = GetTreeSize $plan.Source
        Inform ("Source: $($plan.Source)`nTarget: $($plan.Destination)`nRollback backup: $($plan.Backup)`nApprox size: $(BytesHuman $sum)") 'Yellow'
        $driveLetter = [IO.Path]::GetPathRoot($plan.Destination).Substring(0,1)
        $free = (Get-PSDrive -Name $driveLetter -ErrorAction Stop).Free
        if ($free -lt ($sum * 1.10 + 100MB)) { throw 'Insufficient destination free space (10% + 100MB headroom required)' }
    } catch { Write-Warning $_.Exception.Message; return }
    if (-not (AskExact (Say '复制后 SHA256 校验，原目录改名备份并建立 Junction；输入 MIGRATE 确认' 'Copy, SHA256 verify, rename source to backup, create junction. Type MIGRATE') 'MIGRATE')) { return }
    $renamed = $false; $linked = $false
    try {
        [void](AssertMigrationPath $plan.Source $plan.Destination)
        [void](New-Item -ItemType Directory -Path $plan.Destination -ErrorAction Stop)
        & robocopy.exe $plan.Source $plan.Destination /E /XJ /COPY:DAT /DCOPY:DAT /R:1 /W:1 /MT:4 /NP
        $code = $LASTEXITCODE
        if ($code -ge 8) { throw "Robocopy failed with exit code $code; source unchanged, target left for inspection" }
        [void](CompareTrees $plan.Source $plan.Destination)
        # Revalidate source immediately before switching, and keep it as a rollback backup.
        [void](AssertSafePath $plan.Source 'migration switch')
        Rename-Item -LiteralPath $plan.Source -NewName (Split-Path $plan.Backup -Leaf) -ErrorAction Stop
        $renamed = $true
        $junction = New-Item -ItemType Junction -Path $plan.Source -Target $plan.Destination -ErrorAction Stop
        $linked = $true
        if (-not (IsLink $plan.Source)) { throw 'Junction verification failed' }
        $resolved = (Get-Item -LiteralPath $plan.Source -Force).Target
        if ($resolved -and -not (Under $plan.Destination ([string]($resolved | Select-Object -First 1)))) { throw 'Junction target mismatch' }
        Inform (Say ("迁移成功。源目录备份仍在：{0}。确认应用可正常运行后再手动处理备份。" -f $plan.Backup) ("Migration complete. Source backup retained at $($plan.Backup). Test apps before manually handling backup.")) 'Green'
        Log 'Migrate' $plan.Source ("Success; destination=$($plan.Destination); backup=$($plan.Backup)")
    } catch {
        $problem = $_.Exception.Message
        Write-Warning "Migration did not complete: $problem"
        if ($renamed) {
            try {
                if ($linked -and (Test-Path -LiteralPath $plan.Source)) {
                    # Remove only the reparse-point leaf (never recurse into target).
                    [IO.Directory]::Delete($plan.Source)
                }
                if (-not (Test-Path -LiteralPath $plan.Source)) { Rename-Item -LiteralPath $plan.Backup -NewName (Split-Path $plan.Source -Leaf) -ErrorAction Stop }
                Inform 'Rollback of original source completed.' 'Yellow'
            } catch { Write-Warning "Manual rollback required. Backup: $($plan.Backup) ; $($_.Exception.Message)" }
        }
        Log 'Migrate' $plan.Source ("FAILED: $problem; target=$($plan.Destination); backup=$($plan.Backup)")
        Inform (Say '注意：目标复制品不会自动删除，以避免意外数据损失。' 'Target copy is intentionally not automatically removed.') 'Yellow'
    }
}
function Show-InstallPath {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
    try {
        $reg = Get-ItemProperty -Path $key -ErrorAction Stop
        Inform ("ProgramFilesDir: {0}`nProgramFilesDir (x86): {1}" -f $reg.ProgramFilesDir,$reg.'ProgramFilesDir (x86)') 'Yellow'
        Inform (Say '只读检查，不修改注册表。请通过软件安装器自行选择安装位置。' 'Read only. Configure locations in each installer, not system registry.') 'Cyan'
    } catch { Write-Warning $_.Exception.Message }
}
function Show-Memory {
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 ProcessName,Id,@{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize
    Inform (Say '未执行工作集强制收缩。' 'No EmptyWorkingSet calls performed.') 'Cyan'
}
function Start-Guard {
    $lastAlert = [datetime]::MinValue
    Inform (Say '监控已启动。按 Ctrl+C 停止。' 'Monitoring started. Press Ctrl+C to stop.') 'Cyan'
    while ($true) {
        try {
            $f = (Get-PSDrive C).Free
            Inform ("{0}  C: free {1}" -f (Get-Date -Format 'HH:mm:ss'), (BytesHuman $f))
            if ($f -lt 5GB -and (Get-Date).Subtract($lastAlert).TotalMinutes -ge 30) {
                $lastAlert = Get-Date
                try { (New-Object -ComObject Wscript.Shell).Popup('C: free space is below 5 GB', 10, 'Disk Space Guard', 48) | Out-Null } catch { Write-Warning 'Low disk space' }
            }
        } catch { Write-Warning $_.Exception.Message }
        Start-Sleep -Seconds 300
    }
}
function AuditBlocked([string]$path) {
    $p = Canonical $path
    if (HasLinkAncestor $p) { return $true }
    foreach ($protected in @(BuiltInProtected) + @(ExtraProtected)) {
        if ($protected -and (Under $p $protected)) { return $true }
    }
    return $false
}
function Invoke-Audit {
    $drive = (Read-Host (Say '扫描盘符（例如 D）' 'Drive letter to scan (e.g. D)')).Trim().TrimEnd(':')
    if ($drive -notmatch '^[A-Za-z]$') { Write-Warning 'Invalid drive letter'; return }
    $root = "${drive}:\"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Write-Warning "Missing drive: $root"; return }
    Inform (Say '只读审计：文件/目录均不可通过此功能删除；扫描跳过系统保护路径、链接和权限异常项。' 'Read-only audit: nothing can be deleted here. Protected paths, links and errors are skipped.') 'Cyan'
    $report = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($root)
    $scanned=0; $skipped=0; $limit=30000
    $recognized = @{'node_modules'='Node dependency install (NOT junk)';'target'='Possible build output (NOT confirmed)';'build'='Possible build output (NOT confirmed)';'.gradle'='Gradle working cache (protected)';'.dart_tool'='Dart project state (protected)'}
    while ($stack.Count -gt 0 -and $scanned -lt $limit) {
        $current = $stack.Pop()
        $scanned++
        if ($scanned % 500 -eq 0) { Write-Progress -Activity 'Read-only audit' -Status "Examined $scanned directories; queued $($stack.Count)" }
        try { $entries = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop) }
        catch { $skipped++; continue }
        foreach ($entry in $entries) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++; continue }
            if (AuditBlocked $entry.FullName) { $skipped++; continue }
            if ($entry.PSIsContainer) {
                # Do not traverse system folders anywhere on a drive.
                if ($entry.Name -match '^(\$RECYCLE\.BIN|System Volume Information|Recovery|Windows|Program Files|Program Files \(x86\)|ProgramData)$') { $skipped++; continue }
                if ($recognized.ContainsKey($entry.Name)) {
                    # The *name* is not evidence of safe deletion. Report without size traversal.
                    $report.Add([pscustomobject]@{Type='Project directory (report only)';Path=$entry.FullName;MB='';Modified=$entry.LastWriteTime;Advice=$recognized[$entry.Name];Action='NEVER AUTO-DELETE'})
                    $skipped++; continue
                }
                $stack.Push($entry.FullName)
            } elseif ($entry.Length -ge 100MB -and $entry.Extension -match '^\.(zip|7z|rar|iso|msi|exe|tgz|tar|gz)$' -and $entry.LastWriteTime -lt (Get-Date).AddDays(-14)) {
                $report.Add([pscustomobject]@{Type='Large archive / installer';Path=$entry.FullName;MB=[math]::Round($entry.Length/1MB,1);Modified=$entry.LastWriteTime;Advice='May be a backup or required installer';Action='REVIEW ONLY'})
            }
        }
    }
    Write-Progress -Activity 'Read-only audit' -Completed
    if ($stack.Count -gt 0) { Write-Warning "Scan reached safety limit of $limit directories; report incomplete." }
    Inform (Say ("扫描目录 {0}，跳过/拒绝 {1}，信息条目 {2}。" -f $scanned,$skipped,$report.Count) ("Scanned $scanned directories; skipped $skipped; findings $($report.Count).")) 'Yellow'
    $out = Join-Path $script:LogRoot ("audit-{0}-{1}.csv" -f $drive.ToUpper(),(Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        [void](New-Item -ItemType Directory -Path $script:LogRoot -Force)
        if ($report.Count) { $report | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8 }
        else { 'No findings; no file deletion was performed' | Set-Content -LiteralPath $out -Encoding UTF8 }
        Inform "Report: $out" 'Green'
    } catch { Write-Warning "Could not save report: $($_.Exception.Message)" }
    if ($report.Count) {
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
            $report | Sort-Object Type,Path | Out-GridView -Title (Say '只读审计报告（不能从这里删除）' 'READ-ONLY audit report (no delete actions)')
        } else { $report | Select-Object -First 80 | Format-Table -AutoSize -Wrap }
    }
    Log 'Audit' $root ("read-only; scanned=$scanned; findings=$($report.Count)")
}

while ($true) {
    ShowIntro
    $choice = (Read-Host (Say '请选择操作' 'Choose action')).Trim().ToUpperInvariant()
    if ($choice -eq 'Q') { break }
    if ($choice -eq 'L') { $script:Culture = if ($script:Culture -eq 'zh') {'en'} else {'zh'}; continue }
    try {
        switch ($choice) {
            '1' { Invoke-TempPreview }
            '2' { Invoke-DevReport }
            '3' { Invoke-SafeMigration }
            '4' { Show-InstallPath }
            '5' { Show-Memory }
            '6' { Start-Guard }
            '7' { Invoke-Audit }
            '8' { Invoke-RestoreBuild }
            '9' { Invoke-PurgeQuarantine }
            default { Inform (Say '无效选项。' 'Unknown option.') 'Yellow' }
        }
    } catch { Write-Warning "Operation aborted safely: $($_.Exception.Message)"; Log 'Unhandled' $choice $_.Exception.Message }
    [void](Read-Host (Say '按回车返回菜单' 'Press Enter to return to menu'))
}
