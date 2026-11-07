# NTX - Windows cleanup utility
# Read-only scan first; deletion only after explicit confirmation.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.

$script:Targets = New-Object 'System.Collections.Generic.List[object]'
$script:TargetKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:NTXReparseTargets = 0
$script:NTXProgressActive = $false
$script:NTXWidth = 80
$script:NTXInteractive = $false
$script:NTXUseColor = $true
$script:NTXOldErrorActionPreference = $ErrorActionPreference

$ErrorActionPreference = 'Continue'

function Initialize-NTXConsole {
    $script:NTXWidth = 80
    $script:NTXUseColor = $true
    try {
        $width = [int]$Host.UI.RawUI.WindowSize.Width
        if ($width -ge 30) { $script:NTXWidth = [Math]::Min($width, 100) }
    } catch {}

    $script:NTXInteractive = $true
    try {
        if ([Console]::IsOutputRedirected) {
            $script:NTXInteractive = $false
            $script:NTXUseColor = $false
        }
        if ($Host.Name -notmatch 'ConsoleHost') { $script:NTXInteractive = $false }
    } catch {
        $script:NTXInteractive = $false
        $script:NTXUseColor = $false
    }
    if ($env:NO_COLOR) { $script:NTXUseColor = $false }
}

function Get-NTXLineWidth {
    $width = [int]$script:NTXWidth
    if ($width -lt 42) { $width = 42 }
    return $width
}

function Get-NTXContentWidth {
    return ((Get-NTXLineWidth) - 2)
}

function Write-NTXColor {
    param(
        [AllowEmptyString()][string]$Text = '',
        [string]$Color = 'Gray',
        [switch]$NoNewline
    )
    if ($script:NTXUseColor) {
        try {
            if ($NoNewline) { Write-Host $Text -NoNewline -ForegroundColor $Color }
            else { Write-Host $Text -ForegroundColor $Color }
            return
        } catch {}
    }
    if ($NoNewline) { Write-Host $Text -NoNewline }
    else { Write-Host $Text }
}

function Write-NTXRule {
    param([string]$Color = 'DarkGray')
    Write-NTXColor ('  ' + ('-' * (Get-NTXContentWidth))) $Color
}

function Write-NTXSection {
    param([Parameter(Mandatory=$true)][string]$Title)
    Write-Host ''
    Write-NTXColor ('  ' + $Title.ToUpperInvariant()) 'Cyan'
    Write-NTXRule
}

function Write-NTXWrappedText {
    param(
        [string]$Text,
        [int]$Indent = 0,
        [string]$Color = 'Gray',
        [string]$FirstPrefix = ''
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    $padWidth = $Indent
    if ($FirstPrefix.Length -gt $padWidth) { $padWidth = $FirstPrefix.Length }
    $width = (Get-NTXLineWidth) - $padWidth
    if ($width -lt 12) { $width = 12 }

    $words = $Text.Trim() -split '\s+'
    $line = ''
    $first = $true
    foreach ($word in $words) {
        if ($line.Length -eq 0) {
            $line = $word
        } elseif (($line.Length + 1 + $word.Length) -le $width) {
            $line += ' ' + $word
        } else {
            $prefix = ' ' * $Indent
            if ($first -and $FirstPrefix) { $prefix = $FirstPrefix }
            Write-NTXColor ($prefix + $line) $Color
            $first = $false
            $line = $word
        }
    }
    if ($line.Length -gt 0) {
        $prefix = ' ' * $Indent
        if ($first -and $FirstPrefix) { $prefix = $FirstPrefix }
        Write-NTXColor ($prefix + $line) $Color
    }
}

function Write-NTXNote {
    param([string]$Message)
    Write-NTXWrappedText -Text $Message -Indent 5 -Color 'DarkGray' -FirstPrefix '  i  '
}

function Write-NTXWarning {
    param([string]$Message)
    Write-NTXWrappedText -Text $Message -Indent 5 -Color 'Yellow' -FirstPrefix '  !  '
}

function Write-NTXError {
    param([string]$Message)
    Write-NTXWrappedText -Text $Message -Indent 5 -Color 'Red' -FirstPrefix '  x  '
}

function Write-NTXSuccess {
    param([string]$Message)
    Write-NTXWrappedText -Text $Message -Indent 5 -Color 'Green' -FirstPrefix '  +  '
}

function Write-NTXProgress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Category,
        [string]$Detail
    )
    if (-not $script:NTXInteractive) { return }
    $script:NTXProgressActive = $true

    $lineWidth = Get-NTXLineWidth
    $pct = 0
    if ($Total -gt 0) { $pct = [int](($Current / [double]$Total) * 100) }
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }

    $barWidth = [int][Math]::Min(20, [Math]::Max(8, $lineWidth - 42))
    $filled = [int][Math]::Round(($barWidth * $pct) / 100.0)
    $barFilled = '=' * $filled
    $barEmpty = '-' * ($barWidth - $filled)

    $prefix = '  Scanning  ['
    $afterBar = ']  ' + ('{0,3}' -f $pct) + '%'
    $counter = ''
    if ($Total -gt 0) { $counter = '{0}/{1}' -f $Current, $Total }

    $fixed = $prefix.Length + $barWidth + $afterBar.Length + 2
    $space = $lineWidth - $fixed
    if ($space -lt 0) { $space = 0 }

    $counterWidth = $counter.Length
    $labelSpace = $space - $counterWidth - 2
    if ($labelSpace -lt 0) { $labelSpace = 0 }
    $label = [string]$Category
    if ($label.Length -gt $labelSpace) {
        if ($labelSpace -gt 3) { $label = $label.Substring(0, $labelSpace - 3) + '...' }
        else { $label = $label.Substring(0, $labelSpace) }
    }
    $padding = ' ' * [int][Math]::Max(0, $space - $label.Length - $counterWidth)

    Write-NTXColor ("`r" + $prefix) 'DarkGray' -NoNewline
    Write-NTXColor $barFilled 'Cyan' -NoNewline
    Write-NTXColor $barEmpty 'DarkGray' -NoNewline
    Write-NTXColor ($afterBar + '  ') 'DarkGray' -NoNewline
    Write-NTXColor $label 'White' -NoNewline
    Write-NTXColor ($padding + $counter) 'DarkGray' -NoNewline
}

function Write-NTXActivity {
    param([string]$Label, [string]$Detail)
    if (-not $script:NTXInteractive) { return }
    $script:NTXProgressActive = $true

    $lineWidth = Get-NTXLineWidth
    $prefix = '  ' + $Label + '  '
    $available = $lineWidth - $prefix.Length
    if ($available -lt 0) { $available = 0 }

    $text = [string]$Detail
    if ($text.Length -gt $available) {
        if ($available -gt 3) { $text = $text.Substring(0, $available - 3) + '...' }
        else { $text = $text.Substring(0, $available) }
    }
    $padding = ' ' * [int][Math]::Max(0, $available - $text.Length)

    Write-NTXColor ("`r" + '  ') 'DarkGray' -NoNewline
    Write-NTXColor $Label 'Cyan' -NoNewline
    Write-NTXColor ('  ' + $text) 'White' -NoNewline
    Write-NTXColor $padding 'DarkGray' -NoNewline
}

function Clear-NTXProgress {
    if (-not $script:NTXProgressActive) { return }
    $script:NTXProgressActive = $false
    if (-not $script:NTXInteractive) { return }
    $width = Get-NTXLineWidth
    Write-NTXColor ("`r" + (' ' * $width) + "`r") 'DarkGray' -NoNewline
}

function Format-NTXBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Format-NTXCell {
    param([string]$Text, [int]$Width)
    if ($null -eq $Text) { $Text = '' }
    if ($Width -le 0) { return '' }
    if ($Text.Length -gt $Width) {
        if ($Width -gt 3) { return $Text.Substring(0, $Width - 3) + '...' }
        return $Text.Substring(0, $Width)
    }
    return $Text.PadRight($Width)
}

function Get-NTXFileLabel {
    param([long]$Count)
    if ($Count -eq 1) { return 'file' }
    return 'files'
}

function Write-NTXTableRow {
    param(
        [string]$Index,
        [string]$Category,
        [string]$Files,
        [string]$Size,
        [string]$Color = 'White',
        [string]$IndexColor = 'Cyan'
    )
    $catWidth = [int][Math]::Max(8, (Get-NTXContentWidth) - 30)
    $indexCell = [string]$Index
    if ($indexCell.Length -gt 3) { $indexCell = $indexCell.Substring(0, 3) }
    $indexCell = $indexCell.PadRight(3)
    $catCell = Format-NTXCell $Category $catWidth
    $filesCell = ([string]$Files).PadLeft(10)
    $sizeCell = ([string]$Size).PadLeft(11)

    Write-NTXColor ('  ' + $indexCell + '  ') $IndexColor -NoNewline
    Write-NTXColor ($catCell + '  ' + $filesCell + '  ' + $sizeCell) $Color
}

function Write-NTXReviewRow {
    param(
        [string]$Marker,
        [string]$Category,
        [string]$Files,
        [string]$Size,
        [string]$Color = 'White',
        [string]$MarkerColor = 'Green'
    )
    $catWidth = [int][Math]::Max(8, (Get-NTXContentWidth) - 30)
    $markerCell = [string]$Marker
    if ($markerCell.Length -gt 3) { $markerCell = $markerCell.Substring(0, 3) }
    $markerCell = $markerCell.PadRight(3)
    $catCell = Format-NTXCell $Category $catWidth
    $filesCell = ([string]$Files).PadLeft(10)
    $sizeCell = ([string]$Size).PadLeft(11)

    Write-NTXColor ('  ' + $markerCell + '  ') $MarkerColor -NoNewline
    Write-NTXColor ($catCell + '  ' + $filesCell + '  ' + $sizeCell) $Color
}

function Write-NTXSummaryRow {
    param([string]$Label, [string]$Value, [string]$Color = 'White')
    $width = [int][Math]::Min((Get-NTXContentWidth), 54)
    $labelWidth = [int][Math]::Min(22, [Math]::Max(14, $width - 14))
    $valueWidth = $width - $labelWidth
    if ($valueWidth -lt 8) {
        $valueWidth = 8
        $labelWidth = $width - $valueWidth
    }
    $line = '  ' + $Label.PadRight($labelWidth) + $Value.PadLeft($valueWidth)
    Write-NTXColor $line $Color
}

function Test-NTXAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Join-NTXPath {
    param([string]$Base, [string]$Child)
    if ([string]::IsNullOrWhiteSpace($Base)) { return $null }
    try { return Join-Path $Base $Child } catch { return $null }
}

function Get-NTXRootPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $trimmed = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($trimmed -match '^[A-Za-z]:$') { return $trimmed + [IO.Path]::DirectorySeparatorChar }
    if ([string]::IsNullOrEmpty($trimmed)) { return [IO.Path]::DirectorySeparatorChar.ToString() }
    return $trimmed
}

function Get-NTXRootPrefix {
    param([Parameter(Mandatory=$true)][string]$Root)
    return ($Root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)
}

function Get-NTXTargetLabel {
    param([string]$Path)
    $leaf = Split-Path -Leaf $Path
    $parent = Split-Path -Leaf (Split-Path -Parent $Path)
    if ($parent -and $leaf) { return ($parent + '\' + $leaf) }
    if ($leaf) { return $leaf }
    return $Path
}

function Get-NTXProfiles {
    $profiles = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $skipNames = @('Public','Default','Default User','All Users','defaultuser0','WDAGUtilityAccount')

    try {
        $instances = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
        foreach ($instance in $instances) {
            if ([string]::IsNullOrWhiteSpace($instance.LocalPath)) { continue }
            if ($instance.Special) { continue }
            $path = $instance.LocalPath
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            $leaf = Split-Path -Leaf $path
            if ($skipNames -contains $leaf) { continue }
            if ($seen.Add($path)) { $profiles.Add($path) }
        }
    } catch {}

    if ($profiles.Count -eq 0) {
        $usersRoot = Join-NTXPath $env:SystemDrive 'Users'
        if ($usersRoot -and (Test-Path -LiteralPath $usersRoot -PathType Container)) {
            Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($skipNames -notcontains $_.Name) {
                    $appData = Join-Path $_.FullName 'AppData'
                    if (Test-Path -LiteralPath $appData -PathType Container) {
                        if ($seen.Add($_.FullName)) { $profiles.Add($_.FullName) }
                    }
                }
            }
        }
    }

    if ($env:USERPROFILE -and (Test-Path -LiteralPath $env:USERPROFILE -PathType Container)) {
        if ($seen.Add($env:USERPROFILE)) { $profiles.Add($env:USERPROFILE) }
    }

    return @($profiles)
}

function Add-NTXTarget {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()][string]$Path,
        [string]$Filter = '*',
        [int]$MinAgeDays = 0,
        [string]$Note = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) } catch { return }
    try { $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop } catch { return }
    if (-not $item.PSIsContainer) { return }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $script:NTXReparseTargets++
        return
    }

    $key = ($Category + '|' + $fullPath + '|' + $Filter + '|' + $MinAgeDays)
    if ($script:TargetKeys.Add($key)) {
        $script:Targets.Add([pscustomobject]@{
            Category = $Category
            Path = $fullPath
            Filter = $Filter
            MinAgeDays = $MinAgeDays
            Note = $Note
        }) | Out-Null
    }
}

function Add-NTXBrowserTargets {
    param([string]$Profile, [string]$UserDataRelativePath)
    $userData = Join-NTXPath $Profile $UserDataRelativePath
    if (-not $userData) { return }
    if (-not (Test-Path -LiteralPath $userData -PathType Container)) { return }

    $browserProfiles = Get-ChildItem -LiteralPath $userData -Directory -Force -ErrorAction SilentlyContinue
    foreach ($browserProfile in $browserProfiles) {
        foreach ($cacheName in @('Cache','Code Cache','GPUCache','DawnCache','GrShaderCache')) {
            Add-NTXTarget -Category 'Browser caches' -Path (Join-Path $browserProfile.FullName $cacheName) -Note 'Cache only; browser history, cookies and saved passwords are not targeted.'
        }
    }
}

function Build-NTXTargets {
    $profiles = Get-NTXProfiles
    $windowsTemp = Join-NTXPath $env:windir 'Temp'
    Add-NTXTarget -Category 'System temporary files' -Path $windowsTemp -MinAgeDays 1 -Note 'Files older than 24 hours; locked or protected files are skipped.'

    foreach ($profile in $profiles) {
        $local = Join-NTXPath $profile 'AppData\Local'
        $roaming = Join-NTXPath $profile 'AppData\Roaming'

        if ($local) {
            Add-NTXTarget -Category 'System temporary files' -Path (Join-Path $local 'Temp') -MinAgeDays 1 -Note 'Files older than 24 hours; locked files are skipped.'
        }

        Add-NTXBrowserTargets -Profile $profile -UserDataRelativePath 'AppData\Local\Google\Chrome\User Data'
        Add-NTXBrowserTargets -Profile $profile -UserDataRelativePath 'AppData\Local\Microsoft\Edge\User Data'
        Add-NTXBrowserTargets -Profile $profile -UserDataRelativePath 'AppData\Local\BraveSoftware\Brave-Browser\User Data'

        if ($local) {
            $firefoxProfiles = Join-Path $local 'Mozilla\Firefox\Profiles'
            if (Test-Path -LiteralPath $firefoxProfiles -PathType Container) {
                Get-ChildItem -LiteralPath $firefoxProfiles -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Add-NTXTarget -Category 'Browser caches' -Path (Join-Path $_.FullName 'cache2') -Note 'Firefox disk cache only.'
                    Add-NTXTarget -Category 'Browser caches' -Path (Join-Path $_.FullName 'startupCache') -Note 'Firefox startup cache only.'
                }
            }
        }

        if ($roaming) {
            Add-NTXTarget -Category 'Browser caches' -Path (Join-Path $roaming 'Opera Software\Opera Stable\Cache') -Note 'Opera cache only.'
        }
        if ($local) {
            Add-NTXTarget -Category 'Browser caches' -Path (Join-Path $local 'Opera Software\Opera Stable\Cache') -Note 'Opera cache only.'
        }

        if ($roaming) {
            foreach ($cacheName in @('Cache','Code Cache','GPUCache','DawnCache')) {
                Add-NTXTarget -Category 'Application caches' -Path (Join-Path $roaming ("discord\$cacheName")) -Note 'Discord cache only.'
            }
            foreach ($cacheName in @('Cache','CachedData','Code Cache','GPUCache')) {
                Add-NTXTarget -Category 'Application caches' -Path (Join-Path $roaming ("Code\$cacheName")) -Note 'Visual Studio Code cache only.'
            }
        }

        if ($local) {
            Add-NTXTarget -Category 'Application caches' -Path (Join-Path $local 'Microsoft\Windows\INetCache') -Note 'Windows internet cache; cookies and saved credentials are not targeted.'

            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $local 'npm-cache') -Note 'npm cache; packages can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $profile '.npm\_cacache') -Note 'npm content cache; packages can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $local 'pip\Cache') -Note 'pip download cache; packages can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $local 'Yarn\Cache') -Note 'Yarn cache; packages can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $local 'NuGet\v3-cache') -Note 'NuGet HTTP cache; packages can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $profile '.gradle\caches') -Note 'Gradle dependency/build cache; may require re-download or rebuild.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $profile '.cargo\registry\cache') -Note 'Cargo archive cache; crates can be downloaded again.'
            Add-NTXTarget -Category 'Developer caches' -Path (Join-Path $local 'go-build') -Note 'Go build cache; future builds may take longer.'

            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'D3DSCache') -Note 'Shader cache; may rebuild and cause temporary first-launch stutter.'
            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'NVIDIA\DXCache') -Note 'NVIDIA DirectX shader cache.'
            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'NVIDIA\GLCache') -Note 'NVIDIA OpenGL shader cache.'
            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'NVIDIA\NV_Cache') -Note 'NVIDIA shader cache.'
            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'AMD\DxCache') -Note 'AMD shader cache.'
            Add-NTXTarget -Category 'Graphics shader caches' -Path (Join-Path $local 'Intel\ShaderCache') -Note 'Intel shader cache.'

            Add-NTXTarget -Category 'Thumbnail cache' -Path (Join-Path $local 'Microsoft\Windows\Explorer') -Filter 'thumbcache*.db' -Note 'Thumbnail database only; thumbnails regenerate as needed.'
            Add-NTXTarget -Category 'Windows error reports' -Path (Join-Path $local 'Microsoft\Windows\WER\ReportArchive') -Note 'Optional diagnostic reports; remove only when you do not need them.'
            Add-NTXTarget -Category 'Windows error reports' -Path (Join-Path $local 'Microsoft\Windows\WER\ReportQueue') -Note 'Queued diagnostic reports; remove only when you do not need them.'
        }
    }

    if ($env:ProgramData) {
        Add-NTXTarget -Category 'Windows error reports' -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') -Note 'Optional system diagnostic reports.'
        Add-NTXTarget -Category 'Windows error reports' -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') -Note 'Optional queued system diagnostic reports.'
    }

    $steamRoots = @(
        (Join-NTXPath ${env:ProgramFiles(x86)} 'Steam\appcache\httpcache'),
        (Join-NTXPath $env:ProgramFiles 'Steam\appcache\httpcache'),
        (Join-NTXPath $env:LOCALAPPDATA 'Steam\htmlcache')
    )
    foreach ($steamRoot in $steamRoots) {
        Add-NTXTarget -Category 'Application caches' -Path $steamRoot -Note 'Steam web cache only; game files and downloads are not targeted.'
    }
}

function Get-NTXFiles {
    param([Parameter(Mandatory=$true)]$Target)

    try { $rootAttributes = [IO.File]::GetAttributes($Target.Path) } catch { return }
    if (($rootAttributes -band [IO.FileAttributes]::Directory) -eq 0) { return }
    if (($rootAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }

    $cutoff = (Get-Date).AddDays(-1 * [int]$Target.MinAgeDays)
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Target.Path)

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            $entries = [IO.DirectoryInfo]::new($dir).GetFileSystemInfos()
        } catch { continue }

        foreach ($entry in $entries) {
            try {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($entry -is [IO.DirectoryInfo]) {
                    $stack.Push($entry.FullName)
                    continue
                }
                if ($Target.Filter -ne '*' -and $entry.Name -notlike $Target.Filter) { continue }
                if ($Target.MinAgeDays -gt 0 -and $entry.LastWriteTime -gt $cutoff) { continue }
                $entry
            } catch { continue }
        }
    }
}

function Remove-NTXEmptyDirectories {
    param([Parameter(Mandatory=$true)][string]$Root, $Candidates)

    if ($null -eq $Candidates -or $Candidates.Count -eq 0) { return }
    $root = Get-NTXRootPath $Root
    if ($root -match '^[A-Za-z]:[\\/]$') { return }

    $rootPrefix = Get-NTXRootPrefix $root
    $processed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($candidate in $Candidates) {
        $dir = $candidate
        while ($dir -and $dir.Length -gt $root.Length -and $dir.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            if (-not $processed.Add($dir)) { break }
            try {
                $item = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { break }
                $hasItems = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop | Select-Object -First 1
                if ($null -ne $hasItems) { break }
                Remove-Item -LiteralPath $dir -Force -ErrorAction Stop
            } catch { break }
            $dir = [IO.Path]::GetDirectoryName($dir)
        }
    }
}

function Get-NTXScan {
    $summary = @{}
    $totalFiles = 0L
    $totalBytes = 0L

    $categories = @($script:Targets | Select-Object -ExpandProperty Category -Unique | Sort-Object)
    $targetsByCategory = @{}
    $totalTargets = 0
    foreach ($category in $categories) {
        $targets = @($script:Targets | Where-Object { $_.Category -eq $category })
        $targetsByCategory[$category] = $targets
        $totalTargets += $targets.Count
    }

    $completedTargets = 0
    foreach ($category in $categories) {
        $count = 0L
        $bytes = 0L
        foreach ($target in $targetsByCategory[$category]) {
            $label = Get-NTXTargetLabel $target.Path
            Write-NTXProgress -Current $completedTargets -Total $totalTargets -Category $category -Detail $label
            Get-NTXFiles -Target $target | ForEach-Object {
                $count++
                $bytes += [long]$_.Length
            }
            $completedTargets++
            Write-NTXProgress -Current $completedTargets -Total $totalTargets -Category $category -Detail $label
        }
        $summary[$category] = [pscustomobject]@{ Files = $count; Bytes = $bytes }
        $totalFiles += $count
        $totalBytes += $bytes
    }

    Clear-NTXProgress
    $scanSummary = '{0:N0} {1}  |  {2} reclaimable' -f $totalFiles, (Get-NTXFileLabel $totalFiles), (Format-NTXBytes $totalBytes)
    if (('  +  Scan complete   ' + $scanSummary).Length -le (Get-NTXLineWidth)) {
        Write-NTXColor '  +  ' 'Green' -NoNewline
        Write-NTXColor 'Scan complete' 'Green' -NoNewline
        Write-NTXColor ('   {0:N0} {1}' -f $totalFiles, (Get-NTXFileLabel $totalFiles)) 'White' -NoNewline
        Write-NTXColor ('  |  ' + (Format-NTXBytes $totalBytes) + ' reclaimable') 'Green'
    } else {
        Write-NTXSuccess 'Scan complete'
        Write-NTXWrappedText -Text $scanSummary -Indent 5 -Color 'Green'
    }
    return [pscustomobject]@{ Categories = $summary; Files = $totalFiles; Bytes = $totalBytes }
}

function Show-NTXResults {
    param($Scan)

    Write-NTXSection 'Results'
    $rows = @($Scan.Categories.Keys | Where-Object { $Scan.Categories[$_].Files -gt 0 } | Sort-Object)
    if ($rows.Count -eq 0) {
        Write-NTXSuccess 'Nothing eligible for cleanup was found.'
        Write-Host ''
        return @()
    }

    Write-NTXTableRow -Index '#' -Category 'CATEGORY' -Files 'FILES' -Size 'RECLAIMABLE' -Color 'DarkGray' -IndexColor 'DarkGray'
    $index = 0
    foreach ($category in $rows) {
        $index++
        $item = $Scan.Categories[$category]
        Write-NTXTableRow -Index ([string]$index) -Category $category -Files ('{0:N0}' -f $item.Files) -Size (Format-NTXBytes $item.Bytes) -Color 'White' -IndexColor 'Cyan'
    }
    Write-NTXRule
    Write-NTXTableRow -Index '' -Category 'TOTAL' -Files ('{0:N0}' -f $Scan.Files) -Size (Format-NTXBytes $Scan.Bytes) -Color 'Green' -IndexColor 'Green'

    $empty = @($Scan.Categories.Keys | Where-Object { $Scan.Categories[$_].Files -eq 0 }).Count
    if ($empty -gt 0) {
        $label = 'categories'
        if ($empty -eq 1) { $label = 'category' }
        Write-Host ''
        Write-NTXNote ('{0} {1} had nothing to clean.' -f $empty, $label)
    }

    return $rows
}

function Get-NTXCategoryNotes {
    param([string]$Category)
    switch ($Category) {
        'Browser caches' { return 'Close browsers first. Cookies, history and saved passwords are not targeted.' }
        'Developer caches' { return 'Caches may need to be downloaded or rebuilt later.' }
        'Graphics shader caches' { return 'Caches regenerate; first launch may stutter.' }
        'Windows error reports' { return 'Reports may help troubleshoot crashes. Select only if unneeded.' }
        'Thumbnail cache' { return 'Windows regenerates thumbnails as folders open.' }
        'System temporary files' { return 'Only files older than 24 hours. Locked files are skipped.' }
        'Application caches' { return 'Only known cache folders. Personal files are not targeted.' }
        default { return '' }
    }
}

function Read-NTXSelection {
    param([string[]]$CategoryList)

    $count = @($CategoryList).Count
    $range = '1'
    if ($count -gt 1) { $range = '1-' + $count }

    while ($true) {
        Write-NTXNote ('Enter numbers ({0}), ALL, or Q to quit.' -f $range)
        Write-NTXColor '  > ' 'Cyan' -NoNewline
        $answer = Read-Host

        if ([string]::IsNullOrWhiteSpace($answer)) { return @() }
        $answer = $answer.Trim()
        if ($answer.ToUpperInvariant() -eq 'Q') { return @() }
        if ($answer.ToUpperInvariant() -eq 'ALL') { return @($CategoryList) }

        $selected = New-Object 'System.Collections.Generic.List[string]'
        $valid = $true
        foreach ($part in ($answer -split ',')) {
            $number = 0
            if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $CategoryList.Count) {
                $valid = $false
                break
            }
            $category = $CategoryList[$number - 1]
            if (-not $selected.Contains($category)) { $selected.Add($category) }
        }

        if (-not $valid) {
            Write-NTXWarning ('Invalid selection. Use {0}, ALL, or Q.' -f $range)
            Write-Host ''
            continue
        }
        if ($selected.Count -eq 0) {
            Write-NTXWarning 'No categories selected.'
            Write-Host ''
            continue
        }

        return @($selected)
    }
}

function Show-NTXPreview {
    param($Scan, [string[]]$Selected)

    Write-NTXSection 'Review'
    $totalFiles = 0L
    $totalBytes = 0L

    Write-NTXReviewRow -Marker '' -Category 'CATEGORY' -Files 'FILES' -Size 'SIZE' -Color 'DarkGray' -MarkerColor 'DarkGray'
    foreach ($category in $Selected) {
        $item = $Scan.Categories[$category]
        $totalFiles += $item.Files
        $totalBytes += $item.Bytes
        Write-NTXReviewRow -Marker '[x]' -Category $category -Files ('{0:N0}' -f $item.Files) -Size (Format-NTXBytes $item.Bytes) -Color 'White' -MarkerColor 'Green'
        $note = Get-NTXCategoryNotes -Category $category
        if ($note) { Write-NTXWrappedText -Text $note -Indent 7 -Color 'DarkGray' }
    }

    Write-NTXRule
    Write-NTXReviewRow -Marker '' -Category 'SELECTED' -Files ('{0:N0}' -f $totalFiles) -Size (Format-NTXBytes $totalBytes) -Color 'Green' -MarkerColor 'Green'
    Write-Host ''
    Write-NTXNote 'Counts are from the initial scan. Cleanup re-checks every file.'
    Write-Host ''
    Write-NTXWrappedText -Text 'Permanent deletion. This cannot be undone.' -Indent 2 -Color 'Yellow'
}

function Invoke-NTXCleanup {
    param([string[]]$SelectedCategories)

    Write-NTXSection 'Cleanup'
    $grandCount = 0L
    $grandBytes = 0L
    $grandSkipped = 0L
    $categoryIndex = 0
    $categoryTotal = @($SelectedCategories).Count

    foreach ($category in $SelectedCategories) {
        $categoryIndex++
        $categoryCount = 0L
        $categoryBytes = 0L
        $categorySkipped = 0L
        Write-NTXActivity -Label 'Cleaning' -Detail ('[{0}/{1}]  {2}' -f $categoryIndex, $categoryTotal, $category)

        foreach ($target in ($script:Targets | Where-Object { $_.Category -eq $category })) {
            $root = Get-NTXRootPath $target.Path
            $rootPrefix = Get-NTXRootPrefix $root
            $parents = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

            Get-NTXFiles -Target $target | ForEach-Object {
                $file = $_
                try {
                    $full = [IO.Path]::GetFullPath($file.FullName)
                    if (-not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { $categorySkipped++; return }
                    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $categorySkipped++; return }
                    $length = [long]$file.Length
                    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                    $categoryCount++
                    $categoryBytes += $length
                    $parents.Add([IO.Path]::GetDirectoryName($full)) | Out-Null
                } catch { $categorySkipped++ }
            }

            Remove-NTXEmptyDirectories -Root $root -Candidates $parents
        }

        Clear-NTXProgress

        $grandCount += $categoryCount
        $grandBytes += $categoryBytes
        $grandSkipped += $categorySkipped

        $resultText = '{0:N0} {1} removed  |  {2}' -f $categoryCount, (Get-NTXFileLabel $categoryCount), (Format-NTXBytes $categoryBytes)
        $skipText = '  |  {0:N0} skipped' -f $categorySkipped
        $catWidth = [int][Math]::Max(10, [Math]::Min(28, (Get-NTXContentWidth) - 52))
        if ((5 + $catWidth + 2 + $resultText.Length + $skipText.Length) -le (Get-NTXLineWidth)) {
            Write-NTXColor '  +  ' 'Green' -NoNewline
            Write-NTXColor ((Format-NTXCell $category $catWidth) + '  ') 'White' -NoNewline
            Write-NTXColor $resultText 'Green' -NoNewline
            if ($categorySkipped -gt 0) {
                Write-NTXColor $skipText 'Yellow'
            } else {
                Write-NTXColor $skipText 'DarkGray'
            }
        } else {
            Write-NTXColor '  +  ' 'Green' -NoNewline
            Write-NTXColor $category 'White'
            $detail = '{0:N0} {1} removed  |  {2}  |  {3:N0} skipped' -f $categoryCount, (Get-NTXFileLabel $categoryCount), (Format-NTXBytes $categoryBytes), $categorySkipped
            Write-NTXWrappedText -Text $detail -Indent 5 -Color 'Green'
        }
    }

    Write-NTXSection 'Summary'
    Write-NTXSuccess 'Cleanup complete.'
    Write-Host ''
    Write-NTXSummaryRow 'Files removed' ('{0:N0}' -f $grandCount) 'White'
    Write-NTXSummaryRow 'Space reclaimed' (Format-NTXBytes $grandBytes) 'Green'
    if ($grandSkipped -gt 0) {
        Write-NTXSummaryRow 'Skipped' ('{0:N0}' -f $grandSkipped) 'Yellow'
    }
    Write-Host ''
    Write-NTXNote 'Reported space is the sum of deleted file sizes; actual free space may differ.'
    Write-Host ''
}

function Start-NTX {
    if ($env:OS -ne 'Windows_NT') {
        Write-NTXError 'NTX only runs on Windows.'
        return
    }
    if ($PSVersionTable.PSVersion -lt [version]'5.1') {
        Write-NTXError 'NTX requires Windows PowerShell 5.1 or PowerShell 7+.'
        return
    }

    Initialize-NTXConsole
    if ($script:NTXInteractive) { Clear-Host }

    if (-not (Test-NTXAdmin)) {
        Write-NTXWarning 'Running without administrator privileges.'
        Write-NTXNote 'Some system and other-user locations may be skipped.'
        Write-Host ''
    }

    Write-NTXNote 'Close browsers and apps before cleaning their caches.'
    Write-NTXNote 'Personal files, browser sessions and restore points are excluded.'
    Write-Host ''

    Build-NTXTargets

    if ($script:NTXReparseTargets -gt 0) {
        Write-NTXNote ('Skipped {0} redirected cache location(s) for safety.' -f $script:NTXReparseTargets)
        Write-Host ''
    }

    if ($script:Targets.Count -eq 0) {
        Write-NTXWarning 'No supported cleanup locations were found.'
        return
    }

    $scan = Get-NTXScan
    $categoryList = @(Show-NTXResults -Scan $scan)
    if ($categoryList.Count -eq 0) { return }

    Write-NTXSection 'Select categories'
    $selected = @(Read-NTXSelection -CategoryList $categoryList)
    if ($selected.Count -eq 0) {
        Write-NTXWarning 'Cancelled. No files were changed.'
        return
    }

    Show-NTXPreview -Scan $scan -Selected $selected
    Write-Host ''
    Write-NTXNote 'Type CLEAN to continue, or press Enter to cancel.'
    Write-NTXColor '  > ' 'Cyan' -NoNewline
    $confirm = Read-Host

    if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm.Trim() -ine 'CLEAN') {
        Write-NTXWarning 'Cancelled. No files were changed.'
        return
    }

    Invoke-NTXCleanup -SelectedCategories $selected
}

Initialize-NTXConsole
try {
    Start-NTX
} catch {
    Write-Host ''
    Write-NTXError 'NTX stopped unexpectedly.'
    Write-NTXNote $_.Exception.Message
    Write-NTXNote 'Cleanup may be incomplete; review the output above.'
} finally {
    Clear-NTXProgress
    $ErrorActionPreference = $script:NTXOldErrorActionPreference
    if ($script:NTXInteractive) {
        Write-Host ''
        Write-NTXNote 'Press Enter to exit.'
        Read-Host | Out-Null
    }
}
