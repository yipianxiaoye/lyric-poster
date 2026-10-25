[CmdletBinding()]
param(
    [string]$StagingParent = 'D:\LyricPosterBuilds',
    [string]$ExistingBuildDirectory,
    [string]$OutputDirectory,
    [string]$SigningProperties,
    [Security.SecureString]$LegacySigningPassword,
    [switch]$ImportLegacyDebugSigning,
    [switch]$SkipTests,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_USER_HOME', 'GRADLE_USER_HOME')) {
    if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
        $saved = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($saved) { [Environment]::SetEnvironmentVariable($name, $saved, 'Process') }
    }
}
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$null = Get-Command java -ErrorAction Stop
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk -or -not (Test-Path -LiteralPath $sdk)) {
    throw 'Android SDK not found. Configure the global ANDROID_HOME before building.'
}
$buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } |
    Select-Object -First 1
if (-not $buildTools) { throw 'Android SDK build-tools (including apksigner) are missing.' }
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
if (-not (Test-Path -LiteralPath $aapt)) { throw 'Android SDK aapt is missing.' }

function Protect-SigningPath([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    $directory = (Get-Item -LiteralPath $Path).PSIsContainer
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    if ($directory) { $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($sid in @($userSid, [Security.Principal.SecurityIdentifier]'S-1-5-18', [Security.Principal.SecurityIdentifier]'S-1-5-32-544')) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid, [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance, [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

if (-not $SigningProperties) { $SigningProperties = $env:LYRIC_POSTER_KEY_PROPERTIES }
if (-not $SigningProperties) { $SigningProperties = Join-Path $env:USERPROFILE '.lyric-poster\signing\key.properties' }
$SigningProperties = [IO.Path]::GetFullPath($SigningProperties)
if ($ImportLegacyDebugSigning) {
    # This opt-in exists only to preserve updates from the previously distributed
    # preview APK. It deliberately keeps its original Android debug certificate.
    # New publishers should supply their own permanent release key instead.
    if (Test-Path -LiteralPath $SigningProperties) {
        throw 'Signing properties already exist; refusing to overwrite the app signing identity.'
    }
    if (-not $LegacySigningPassword) {
        throw 'Import requires -LegacySigningPassword. Obtain it with Read-Host -AsSecureString; do not put a password in command arguments or source files.'
    }
    $legacyHome = $env:ANDROID_USER_HOME
    if (-not $legacyHome) { $legacyHome = Join-Path $env:USERPROFILE '.android' }
    $legacyKey = Join-Path $legacyHome 'debug.keystore'
    if (-not (Test-Path -LiteralPath $legacyKey)) { throw 'The previous preview signing key was not found.' }
    $signingDirectory = Split-Path -Parent $SigningProperties
    if ($signingDirectory.TrimEnd('\').Equals($projectRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) -or
        $signingDirectory.StartsWith($projectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Import signing material into a private directory outside the source tree.'
    }
    $newSigningDirectory = -not (Test-Path -LiteralPath $signingDirectory)
    New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
    # Do not change ACLs on a pre-existing parent directory chosen by the caller.
    if ($newSigningDirectory) { Protect-SigningPath $signingDirectory }
    $preservedKey = Join-Path $signingDirectory 'lyric-poster-preview-compatibility.jks'
    if (Test-Path -LiteralPath $preservedKey) { throw 'A preserved signing key already exists; refusing to replace it.' }
    Copy-Item -LiteralPath $legacyKey -Destination $preservedKey
    Protect-SigningPath $preservedKey
    $legacyPassword = [Net.NetworkCredential]::new('', $LegacySigningPassword).Password
    @(
        "storeFile=$($preservedKey.Replace('\', '/'))",
        "storePassword=$legacyPassword",
        'keyAlias=androiddebugkey',
        "keyPassword=$legacyPassword",
        'signingMode=legacy-preview-compatibility'
    ) | Set-Content -LiteralPath $SigningProperties -Encoding ASCII
    Protect-SigningPath $SigningProperties
    $legacyPassword = $null
    Write-Host 'Preserved the existing preview signing identity in the private user signing directory.'
}
if (-not (Test-Path -LiteralPath $SigningProperties)) {
    throw 'Signing properties are missing. Provide -SigningProperties or LYRIC_POSTER_KEY_PROPERTIES. Use -ImportLegacyDebugSigning only when intentionally preserving an existing preview certificate.'
}
$signingValues = @{}
foreach ($line in Get-Content -LiteralPath $SigningProperties) {
    if ($line -match '^\s*([^#!\s=]+)\s*=\s*(.*)$') { $signingValues[$matches[1]] = $matches[2] }
}
foreach ($required in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
    if (-not $signingValues[$required]) { throw "Signing properties are incomplete: $required is missing." }
}
$signingMode = $signingValues['signingMode']
$signingValues = $null
Write-Host "Flutter: $flutter"
Write-Host "Android SDK: $sdk"
Write-Host "Android build tools: $($buildTools.Name)"
if ($CheckOnly) { Write-Host 'Android build prerequisites and signing configuration passed.'; return }

# An ASCII staging path avoids native-tool problems with the source folder name.
$StagingParent = [IO.Path]::GetFullPath($StagingParent)
if ($StagingParent -match '[^\x00-\x7F]') { throw 'StagingParent must be an ASCII path.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($ExistingBuildDirectory) {
    $staging = [IO.Path]::GetFullPath($ExistingBuildDirectory)
    $marker = Join-Path $staging '.lyric-poster-android-build'
    if (-not $staging.StartsWith($StagingParent.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $marker) -or
        (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim() -ne $projectRoot) {
        throw 'ExistingBuildDirectory must be a marked Android build for this project under StagingParent.'
    }
} else {
    $staging = Join-Path $StagingParent ("android-$stamp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
if ($staging -match '[^\x00-\x7F]') { throw 'The build directory must be an ASCII path.' }
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$projectRoot | Set-Content -LiteralPath (Join-Path $staging '.lyric-poster-android-build') -Encoding UTF8
foreach ($file in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination $staging
}
foreach ($directory in @('lib', 'test', 'android', 'assets')) {
    $source = Join-Path $projectRoot $directory
    if (Test-Path -LiteralPath $source) {
        & robocopy $source (Join-Path $staging $directory) /E /XD .gradle .kotlin .cxx build /XF local.properties key.properties *.jks *.keystore *.p12 /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw "Could not copy $directory into the build directory." }
    }
}
$versionLine = Get-Content (Join-Path $staging 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if ($versionLine -notmatch '^version:\s*([^+\s]+)\+(\d+)') { throw 'pubspec.yaml must declare a version and build number.' }
$expectedVersion = $matches[1]
$expectedBuild = $matches[2]
$logDirectory = Join-Path $projectRoot 'work\android'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logPath = Join-Path $logDirectory "build-$stamp.log"
$previousSigningPath = $env:LYRIC_POSTER_KEY_PROPERTIES
$env:LYRIC_POSTER_KEY_PROPERTIES = $SigningProperties
Start-Transcript -Path $logPath | Out-Null
try {
    Push-Location $staging
    try {
        & $flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
        if (-not $SkipTests) {
            & $flutter test --no-pub
            if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
        }
        & $flutter build apk --release --no-pub --target-platform 'android-arm,android-arm64,android-x64'
        if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
    } finally { Pop-Location }

    $apk = Join-Path $staging 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'The signed release APK was not produced.' }
    $signature = & $apksigner verify --verbose --print-certs $apk 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $signatureText = $signature -join "`n"
    if ($signatureText -notmatch 'Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]{64})') { throw 'APK signing certificate fingerprint was not found.' }
    $certificateSha256 = $matches[1].ToLowerInvariant()
    if ($signingMode -eq 'legacy-preview-compatibility') {
        $legacyFingerprint = '7c974493abc02492443b9cb2ef91a7c7c3aebaf80df5d72e74b6d94899433e49'
        if ($certificateSha256 -ne $legacyFingerprint) { throw 'APK certificate changed: this would prevent updates from the existing preview app.' }
    }
    $badging = & $aapt dump badging $apk 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'APK manifest inspection failed.' }
    $badgingText = $badging -join "`n"
    if ($badgingText -notmatch "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") { throw 'APK package metadata was not found.' }
    $packageName = $matches[1]
    if ($packageName -ne 'com.lyricposter.lyric_poster' -or $matches[2] -ne $expectedBuild -or $matches[3] -ne $expectedVersion) {
        throw 'APK package identifier or version does not match the source.'
    }
    if ($badgingText -match 'application-debuggable') { throw 'Release APK unexpectedly has the debuggable flag.' }
    if ($badgingText -notmatch "uses-permission: name='android.permission.INTERNET'") { throw 'APK is missing the Internet permission required for lyrics.' }
    foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
        if ($badgingText -notmatch [regex]::Escape($abi)) { throw "Universal APK is missing architecture: $abi" }
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $destination = Join-Path $OutputDirectory "LyricPoster-$expectedVersion-android-universal.apk"
    Copy-Item -LiteralPath $apk -Destination $destination -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
    [ordered]@{
        packageName = $packageName
        versionName = $expectedVersion
        versionCode = [int]$expectedBuild
        architectures = @('armeabi-v7a', 'arm64-v8a', 'x86_64')
        debuggable = $false
        certificateSha256 = $certificateSha256
        signingMode = $(if ($signingMode) { $signingMode } else { 'custom-release' })
        sha256 = $hash
        bytes = (Get-Item -LiteralPath $destination).Length
    } | ConvertTo-Json | Set-Content -LiteralPath "$destination.json" -Encoding UTF8
    "$hash  $([IO.Path]::GetFileName($destination))" | Set-Content -LiteralPath "$destination.sha256" -Encoding ASCII
    Write-Host "Android APK: $destination"
    Write-Host "Version: $expectedVersion+$expectedBuild"
    Write-Host "Signing certificate SHA-256: $certificateSha256"
    Write-Host "APK SHA-256: $hash"
    Write-Host "Build log: $logPath"
    Write-Host "Preserved build directory: $staging"
} finally {
    $env:LYRIC_POSTER_KEY_PROPERTIES = $previousSigningPath
    Stop-Transcript | Out-Null
}
