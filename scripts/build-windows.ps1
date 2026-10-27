[CmdletBinding()]
param(
    [string]$StagingParent = 'D:\LyricPosterBuilds',
    [string]$ExistingBuildDirectory,
    [string]$OutputDirectory,
    [switch]$SkipTests,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
# A desktop session started before a user-level proxy repair will still have
# the old environment. Import saved values only when no process override exists.
foreach ($proxyName in @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY')) {
    if (-not [Environment]::GetEnvironmentVariable($proxyName, 'Process')) {
        $savedProxy = [Environment]::GetEnvironmentVariable($proxyName, 'User')
        if ($savedProxy) { [Environment]::SetEnvironmentVariable($proxyName, $savedProxy, 'Process') }
    }
}
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Visual Studio C++ Build Tools are missing. Complete scripts\setup-windows.ps1 first.'
}
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vsPath) { throw 'Visual Studio is missing MSVC or CMake.' }
$vsPath = @($vsPath)[0]
$cmake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $cmake)) { throw "CMake not found: $cmake" }
& $cmake --version
if ($LASTEXITCODE -ne 0) { throw 'CMake validation failed.' }

# An ASCII staging path avoids the Flutter analyzer/native-tool issues already
# observed with this project's Chinese directory name. Sources stay in place.
$StagingParent = [IO.Path]::GetFullPath($StagingParent)
if ($StagingParent -match '[^\x00-\x7F]') { throw 'StagingParent must be an ASCII path.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($ExistingBuildDirectory) {
    $staging = [IO.Path]::GetFullPath($ExistingBuildDirectory)
    $marker = Join-Path $staging '.lyric-poster-build'
    if (-not $staging.StartsWith($StagingParent.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $marker) -or
        (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim() -ne $projectRoot) {
        throw 'ExistingBuildDirectory must be a marked build for this project under StagingParent.'
    }
} else {
    $staging = Join-Path $StagingParent ("build-$stamp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
if ($staging -match '[^\x00-\x7F]') { throw 'The build directory must be an ASCII path.' }
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$projectRoot | Set-Content -LiteralPath (Join-Path $staging '.lyric-poster-build') -Encoding UTF8
$probeTarget = Join-Path $staging 'symlink-target'
$probeLink = Join-Path $staging ('symlink-link-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probeTarget -Force | Out-Null
# Windows PowerShell 5.1 cannot use Developer Mode's unprivileged symlinks.
# Probe with Dart, which uses the same link API as Flutter itself.
$probeScript = Join-Path $staging 'symlink_probe.dart'
"import 'dart:io'; Future<void> main(List<String> args) async { await Link(args[1]).create(args[0]); stdout.writeln('Symbolic link created without elevation.'); }" |
    Set-Content -LiteralPath $probeScript -Encoding ASCII
& $dart $probeScript $probeTarget $probeLink
if ($LASTEXITCODE -ne 0) {
    throw 'Plugin symbolic links are unavailable. Enable Windows Developer Mode and retry from a normal PowerShell session.'
}
Write-Host "Flutter: $flutter"
Write-Host "Visual Studio: $vsPath"
Write-Host "CMake: $cmake"
Write-Host "Build directory: $staging"
if ($CheckOnly) { Write-Host 'Windows build prerequisites passed.'; return }

foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $staging
}
foreach ($directory in @('lib', 'test', 'windows', 'assets')) {
    $source = Join-Path $projectRoot $directory
    if (Test-Path -LiteralPath $source) {
        & robocopy $source (Join-Path $staging $directory) /E /XD ephemeral .plugin_symlinks /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw "Could not copy $directory to the build directory." }
    }
}

$logDirectory = Join-Path $projectRoot 'work\windows'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory "build-$stamp.log"
Start-Transcript -Path $logPath | Out-Null
try {
    Push-Location $staging
    try {
        & $flutter --version
        if ($LASTEXITCODE -ne 0) { throw 'Flutter version check failed.' }
        & $flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
        if (-not $SkipTests) {
            & $flutter test --no-pub
            if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
        }
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    } finally { Pop-Location }

    $release = Join-Path $staging 'build\windows\x64\runner\Release'
    foreach ($required in @('lyric_poster.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $required))) { throw "Release output is incomplete: $required" }
    }
    $versionLine = Get-Content (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    $version = ($versionLine -replace '^version:\s*', '').Trim().Split('+')[0]
    $bundleName = "LyricPoster-$version-windows-x64-$stamp"
    $bundle = Join-Path $OutputDirectory $bundleName
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    Get-ChildItem -LiteralPath $release | Where-Object { $_.Extension -notin @('.pdb', '.lib', '.exp') } | Copy-Item -Destination $bundle -Recurse

    # App-local release CRT DLLs let the portable bundle run without asking the
    # recipient to install the C++ runtime separately.
    $redist = Join-Path $vsPath 'VC\Redist\MSVC'
    $crt = Get-ChildItem -LiteralPath $redist -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
        Sort-Object { [version]($_.Name) } -Descending |
        ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if (-not $crt) { throw 'The Visual C++ redistributable directory is missing; portable packaging is incomplete.' }
    Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' | Copy-Item -Destination $bundle
    foreach ($notice in @('LICENSE', 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $notice) -Destination (Join-Path $bundle $notice)
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\OFL.txt') -Destination (Join-Path $bundle 'FONT-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\ChillRoundF-OFL.txt') -Destination (Join-Path $bundle 'CHILLROUND-FONT-LICENSE.txt')

    @(
        'Lyric Poster / Windows x64 portable edition',
        "Version: $version",
        '',
        'Extract the entire ZIP, then open lyric_poster.exe.',
        'Keep the DLL files and the data folder next to the executable.',
        'Supports Windows 10/11 x64. Internet access is needed for NetEase playlist/lyrics requests.',
        'Includes Microsoft Visual C++ Runtime DLLs, Copyright Microsoft Corporation.'
    ) | Set-Content -LiteralPath (Join-Path $bundle 'README.txt') -Encoding UTF8
    $zip = Join-Path $OutputDirectory "$bundleName.zip"
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip -CompressionLevel Optimal
    Get-FileHash -Algorithm SHA256 -LiteralPath $zip | Format-List
    Write-Host "Portable application: $(Join-Path $bundle 'lyric_poster.exe')"
    Write-Host "Windows distribution: $zip"
    Write-Host "Build log: $logPath"
    Write-Host "Preserved build directory: $staging"
} finally { Stop-Transcript | Out-Null }
