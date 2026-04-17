[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Installation directory")]
    [string]$Prefix,
    
    [switch]$DesktopShortcut,
    [switch]$NoShortcuts,
    [switch]$SkipConnectivityCheck
)

$ErrorActionPreference = 'Stop'

# Configuration
$MiniforgeVersion = "24.11.2-1"
$MiniforgeInstaller = "Miniforge3-${MiniforgeVersion}-Windows-x86_64.exe"
$MiniforgeUrl = "https://github.com/conda-forge/miniforge/releases/download/${MiniforgeVersion}/${MiniforgeInstaller}"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedPrefix = [System.IO.Path]::GetFullPath($Prefix)

$CondaDir = Join-Path $ResolvedPrefix '.conda'
$CondaInstallerDir = Join-Path $ResolvedPrefix '.conda-installer'
$VenvDir = Join-Path $ResolvedPrefix '.venv'
$AppDir = Join-Path $ResolvedPrefix 'app'
$BinDir = Join-Path $ResolvedPrefix 'bin'
$DataDir = Join-Path $ResolvedPrefix 'data'
$ManifestPath = Join-Path $ResolvedPrefix 'install-manifest.txt'
$InstallerPath = Join-Path $CondaInstallerDir $MiniforgeInstaller

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "AVoc Portable Installer (with Bundled Python)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Install prefix: $ResolvedPrefix"
Write-Host ""

if ($DesktopShortcut -and $NoShortcuts) {
    throw 'Error: -DesktopShortcut and -NoShortcuts are mutually exclusive.'
}

# Create directory structure
New-Item -ItemType Directory -Force -Path $ResolvedPrefix, $BinDir, $DataDir, $CondaInstallerDir | Out-Null

# Download Miniforge if not present
if (Test-Path $InstallerPath) {
    Write-Host "Miniforge installer already present, skipping download."
} else {
    Write-Host "Downloading Miniforge $MiniforgeVersion..."
    Write-Host "  From: $MiniforgeUrl"
    
    try {
        Invoke-WebRequest -Uri $MiniforgeUrl -OutFile $InstallerPath -UseBasicParsing -TimeoutSec 300
        Write-Host "Downloaded: $InstallerPath" -ForegroundColor Green
    } catch {
        throw "Failed to download Miniforge: $_"
    }
}

# Verify installer exists and has reasonable size
$InstallerSize = (Get-Item $InstallerPath).Length
if ($InstallerSize -lt 50000000) {
    throw "Miniforge installer appears corrupted (size: $InstallerSize bytes)"
}

# Install Miniforge (silent mode, no registry, no PATH modification)
Write-Host ""
Write-Host "Installing Miniforge to $CondaDir..."
Write-Host "  - No registry entries"
Write-Host "  - No PATH modifications"
Write-Host ""

$InstallProcess = Start-Process -FilePath $InstallerPath -ArgumentList @(
    "/S",                           # Silent install
    "/D=$CondaDir"                  # Installation directory
) -Wait -PassThru

if ($InstallProcess.ExitCode -ne 0) {
    throw "Miniforge installation failed with exit code $($InstallProcess.ExitCode)"
}

# Force conda to keep package cache inside our tree
$env:CONDA_PKGS_DIRS = Join-Path $CondaDir 'pkgs'

# Create Python 3.12 environment
Write-Host ""
Write-Host "Creating Python 3.12 environment..."

$CondaExe = Join-Path $CondaDir 'Scripts\conda.exe'
if (-not (Test-Path $CondaExe)) {
    # Alternative location
    $CondaExe = Join-Path $CondaDir 'condabin\conda.bat'
}

& $CondaExe create -y -p $VenvDir python=3.12
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Python environment"
}

$PythonExe = Join-Path $VenvDir 'python.exe'
$PythonVersion = & $PythonExe -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"

Write-Host ""
Write-Host "Python $PythonVersion installed at: $PythonExe" -ForegroundColor Green

# Connectivity check
$ConnectivityStatus = "ok"
if (-not $SkipConnectivityCheck) {
    Write-Host "Checking connectivity to PyPI..."
    try {
        Invoke-WebRequest -Method Head -Uri 'https://pypi.org/simple/' -TimeoutSec 5 | Out-Null
    } catch {
        Write-Host "WARNING: Cannot reach pypi.org. Installation may fail if packages not cached." -ForegroundColor Yellow
        $ConnectivityStatus = "failed"
    }
}

# Install dependencies
Write-Host ""
Write-Host "Installing AVoc dependencies..."
& $PythonExe -m pip install --upgrade pip --quiet
$VenvPip = Join-Path $VenvDir 'Scripts\pip.exe'
& $VenvPip install -r (Join-Path $ScriptDir 'requirements-3.12.3.txt')

# Copy application files
Write-Host ""
Write-Host "Copying application files..."
if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir
}
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

Copy-Item -Recurse -Force (Join-Path $ScriptDir 'src') (Join-Path $AppDir 'src')
Copy-Item -Force (Join-Path $ScriptDir 'main.py') (Join-Path $AppDir 'main.py')
Copy-Item -Force (Join-Path $ScriptDir 'LICENSE') (Join-Path $AppDir 'LICENSE')
Copy-Item -Force (Join-Path $ScriptDir 'README.md') (Join-Path $AppDir 'README.md')

# Create launcher scripts
$PsLauncher = @'
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $env:AVOC_HOME) {
    $env:AVOC_HOME = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir '..'))
}
if (-not $env:AVOC_DATA_DIR) {
    $env:AVOC_DATA_DIR = Join-Path $env:AVOC_HOME 'data'
}

# Ensure data directories exist
New-Item -ItemType Directory -Force -Path `
    (Join-Path $env:AVOC_DATA_DIR 'settings'), `
    (Join-Path $env:AVOC_DATA_DIR 'cache'), `
    (Join-Path $env:AVOC_DATA_DIR 'logs'), `
    (Join-Path $env:AVOC_DATA_DIR 'models'), `
    (Join-Path $env:AVOC_DATA_DIR 'pretrain'), `
    (Join-Path $env:AVOC_DATA_DIR 'voice_cards') | Out-Null

# Redirect XDG paths
$env:XDG_DATA_HOME = $env:AVOC_DATA_DIR
$env:XDG_CONFIG_HOME = Join-Path $env:AVOC_DATA_DIR 'settings'
$env:XDG_CACHE_HOME = Join-Path $env:AVOC_DATA_DIR 'cache'
$env:XDG_STATE_HOME = Join-Path $env:AVOC_DATA_DIR 'logs'

$PythonPath = Join-Path $env:AVOC_HOME '.venv\python.exe'
$MainPath = Join-Path $env:AVOC_HOME 'app\main.py'

& $PythonPath $MainPath @args
'@

Set-Content -Path (Join-Path $BinDir 'avoc.ps1') -Value $PsLauncher

# CMD wrapper for double-click execution
$CmdWrapper = @'
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0avoc.ps1" %*
'@
Set-Content -Path (Join-Path $BinDir 'avoc.cmd') -Value $CmdWrapper

# Create uninstaller
$UninstallPs = @"
`$ErrorActionPreference = 'Stop'

`$RootDir = '$ResolvedPrefix'
`$Manifest = '$ManifestPath'

if (-not (Test-Path `$RootDir)) {
    Write-Host "Install root already removed: `$RootDir"
    exit 0
}

`$Yes = `$args -contains '--yes'

# Confirmation prompt
if (-not `$Yes) {
    Write-Host "This will uninstall AVoc by removing:"
    Write-Host "  `$RootDir"
    Write-Host ""
    
    if (Test-Path `$Manifest) {
        Write-Host "The following shortcuts will also be removed:"
        Get-Content `$Manifest | ForEach-Object { Write-Host "  `$_" }
        Write-Host ""
    }
    
    `$Confirm = Read-Host "Type 'yes' to continue"
    if (`$Confirm -ne 'yes') {
        Write-Host "Cancelled."
        exit 0
    }
}

# Remove shortcuts
if (Test-Path `$Manifest) {
    Get-Content `$Manifest | ForEach-Object {
        `$ShortcutPath = `$_.Trim()
        if ([string]::IsNullOrWhiteSpace(`$ShortcutPath)) { return }
        if (Test-Path `$ShortcutPath) {
            Remove-Item -Force `$ShortcutPath
            Write-Host "Removed: `$ShortcutPath"
        }
    }
    Remove-Item -Force `$Manifest
}

# Remove install root
Remove-Item -LiteralPath `$RootDir -Recurse -Force
Write-Host ""
Write-Host "AVoc has been completely uninstalled."
Write-Host "Removed: `$RootDir"
"@

Set-Content -Path (Join-Path $BinDir 'uninstall.ps1') -Value $UninstallPs

# CMD wrapper for uninstall
$UninstallCmd = @'
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
'@
Set-Content -Path (Join-Path $BinDir 'uninstall.cmd') -Value $UninstallCmd

# Create metadata
$Metadata = [ordered]@{
    installer = 'install.ps1'
    installed_at_utc = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    prefix = $ResolvedPrefix
    python_version = $PythonVersion
    python_source = 'bundled'
    miniforge_version = $MiniforgeVersion
    miniforge_installer = $MiniforgeInstaller
    miniforge_path = $InstallerPath
    conda_root = $CondaDir
    venv = '.venv'
    launcher = 'bin/avoc.ps1'
    launcher_cmd = 'bin/avoc.cmd'
    uninstaller = 'bin/uninstall.ps1'
    uninstaller_cmd = 'bin/uninstall.cmd'
    data_dir = 'data'
    requirements = 'requirements-3.12.3.txt'
} | ConvertTo-Json -Depth 3

Set-Content -Path (Join-Path $ResolvedPrefix 'install-metadata.json') -Value $Metadata

# Desktop shortcut
if ($DesktopShortcut) {
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $ShortcutPath = Join-Path $DesktopPath 'AVoc.lnk'
    
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = Join-Path $BinDir 'avoc.cmd'
    $Shortcut.WorkingDirectory = $ResolvedPrefix
    $IconPath = Join-Path $AppDir 'src\avoc\AVoc.svg'
    if (Test-Path $IconPath) {
        $Shortcut.IconLocation = $IconPath
    }
    $Shortcut.Save()
    
    Set-Content -Path $ManifestPath -Value $ShortcutPath
    Write-Host "Created desktop shortcut: $ShortcutPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Location:     $ResolvedPrefix"
Write-Host "Python:       $PythonVersion (bundled)"
Write-Host "Launcher:     $(Join-Path $BinDir 'avoc.ps1')"
Write-Host "              $(Join-Path $BinDir 'avoc.cmd')"
Write-Host ""
Write-Host "To run AVoc:"
Write-Host "  $(Join-Path $BinDir 'avoc.ps1')"
Write-Host "  # or double-click: $(Join-Path $BinDir 'avoc.cmd')"
Write-Host ""
Write-Host "To uninstall:"
Write-Host "  $(Join-Path $BinDir 'uninstall.ps1')"
Write-Host "  # or simply delete: $ResolvedPrefix"
Write-Host ""
Write-Host "Note: Miniforge installer kept at:"
Write-Host "  $InstallerPath"
Write-Host "==============================================" -ForegroundColor Cyan