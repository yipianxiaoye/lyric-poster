[CmdletBinding()]
param(
    [switch]$AcceptLicense,
    [switch]$EnableDeveloperMode,
    [string]$InstallPath = 'D:\App\VisualStudio\2022\BuildTools',
    [string]$CachePath = 'D:\App\VisualStudio\InstallerCache'
)

$ErrorActionPreference = 'Stop'
if (-not $AcceptLicense) {
    throw 'Installation requires explicit consent to the Microsoft Visual Studio Build Tools license. Supply -AcceptLicense after reviewing the license.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell session after approving the installation.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectRoot 'work\windows\vs_BuildTools.exe'
if (-not (Test-Path -LiteralPath $installer)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $installer) -Force | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -OutFile $installer
}
$signature = Get-AuthenticodeSignature -FilePath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation,') {
    throw 'The installer does not have a valid Microsoft Corporation signature.'
}

# Keep installer downloads off the system drive. These environment changes apply
# only to this script and its child processes, not future user sessions.
$installerTemp = Join-Path $CachePath 'Temp'
New-Item -ItemType Directory -Path $installerTemp -Force | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$env:TEMP = $installerTemp
$env:TMP = $installerTemp
try {
    $arguments = @(
        '--quiet', '--wait', '--norestart',
        '--installPath', ('"{0}"' -f $InstallPath),
        '--path', ('cache="{0}"' -f $CachePath),
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.26100'
    )
    Write-Host "Installing Microsoft Visual Studio 2022 Build Tools to $InstallPath"
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Visual Studio installer failed with exit code $($process.ExitCode). Inspect the installer logs in $installerTemp."
    }
    if ($process.ExitCode -eq 3010) {
        Write-Warning 'The installer requests a restart. This script will not restart Windows automatically.'
    }
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}

if ($EnableDeveloperMode) {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Host 'Windows Developer Mode has been enabled for Flutter plugin symbolic links.'
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'vswhere.exe was not installed.' }
$location = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Workload.VCTools Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $location) { throw 'Visual Studio is missing required C++ components.' }
Write-Host "Detected reusable global toolchain: $location"
Write-Host 'Next: run scripts\build-windows.ps1 from a normal PowerShell session.'
