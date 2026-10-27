[CmdletBinding()]
param(
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.lyric-poster\signing\release'),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$KeyAlias = 'lyric-poster-release',
    [switch]$GeneratePassword,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$SigningDirectory = [IO.Path]::GetFullPath($SigningDirectory)
$propertiesPath = Join-Path $SigningDirectory 'key.properties'
$keystorePath = Join-Path $SigningDirectory 'lyric-poster-release.jks'
$recoveryPath = Join-Path $SigningDirectory 'KEEP-PRIVATE.txt'
$keytool = (Get-Command keytool -ErrorAction Stop).Source

if ($GeneratePassword -and $CheckOnly) { throw 'Choose either -GeneratePassword or -CheckOnly.' }
if ($SigningDirectory.TrimEnd('\').Equals($projectRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) -or
    $SigningDirectory.StartsWith($projectRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing material must be stored outside the source repository.'
}

function Protect-PrivatePath([string]$Path) {
    $isDirectory = (Get-Item -LiteralPath $Path).PSIsContainer
    if ($isDirectory) { $acl = New-Object Security.AccessControl.DirectorySecurity }
    else { $acl = New-Object Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true, $false)
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($userSid)
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    if ($isDirectory) { $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' }
    foreach ($sid in @($userSid, [Security.Principal.SecurityIdentifier]'S-1-5-18', [Security.Principal.SecurityIdentifier]'S-1-5-32-544')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $sid, [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance, [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function ConvertTo-JavaProperty([string]$Value) {
    $result = New-Object Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        switch ($code) {
            9 { [void]$result.Append('\t') }
            10 { [void]$result.Append('\n') }
            12 { [void]$result.Append('\f') }
            13 { [void]$result.Append('\r') }
            32 { [void]$result.Append('\ ') }
            33 { [void]$result.Append('\!') }
            35 { [void]$result.Append('\#') }
            58 { [void]$result.Append('\:') }
            61 { [void]$result.Append('\=') }
            92 { [void]$result.Append('\\') }
            default {
                if ($code -lt 32 -or $code -gt 126) { [void]$result.Append(('\u{0:x4}' -f $code)) }
                else { [void]$result.Append($character) }
            }
        }
    }
    return $result.ToString()
}

function ConvertFrom-JavaProperty([string]$Value) {
    return [regex]::Replace($Value, '\\u([0-9a-fA-F]{4})|\\(.)', [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        if ($match.Groups[1].Success) { return [string][char][Convert]::ToInt32($match.Groups[1].Value, 16) }
        switch -CaseSensitive ($match.Groups[2].Value) {
            't' { return "`t" }
            'n' { return "`n" }
            'r' { return "`r" }
            'f' { return [string][char]12 }
            default { return $match.Groups[2].Value }
        }
    })
}

function Invoke-SigningKeytool([string[]]$Arguments) {
    # Windows PowerShell treats native stderr warnings as ErrorRecords. Capture
    # them without turning keytool's harmless JKS warning into a script error.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' @Arguments 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw ('keytool failed: ' + (($output | ForEach-Object { [string]$_ }) -join "`n")) }
        return (($output | ForEach-Object { [string]$_ }) -join "`n")
    } finally { $ErrorActionPreference = $previousPreference }
}

function Write-NewPrivateFile([string]$Path, [string]$Content) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::ASCII.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
        [Array]::Clear($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    Protect-PrivatePath $Path
}

$oldStorePassword = [Environment]::GetEnvironmentVariable('LYRIC_POSTER_SETUP_STOREPASS', 'Process')
$oldKeyPassword = [Environment]::GetEnvironmentVariable('LYRIC_POSTER_SETUP_KEYPASS', 'Process')
$plainPassword = $null
$confirmation = $null
$securePassword = $null
$secureConfirmation = $null
$signingValues = $null
$certificate = $null
try {
    if ($CheckOnly) {
        if (-not (Test-Path -LiteralPath $propertiesPath -PathType Leaf)) { throw 'The private key.properties file does not exist.' }
        $signingValues = @{}
        foreach ($line in [IO.File]::ReadAllLines($propertiesPath, [Text.Encoding]::ASCII)) {
            if ($line -match '^([^#!\s=]+)=(.*)$') { $signingValues[$matches[1]] = ConvertFrom-JavaProperty $matches[2] }
        }
        foreach ($required in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
            if (-not $signingValues[$required]) { throw "Signing properties are incomplete: $required is missing." }
        }
        if ($signingValues['signingMode'] -ne 'custom-release') { throw 'This is not a production signing configuration created by this script.' }
        $keystorePath = $signingValues['storeFile']
        $KeyAlias = $signingValues['keyAlias']
        [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_STOREPASS', $signingValues['storePassword'], 'Process')
        [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_KEYPASS', $signingValues['keyPassword'], 'Process')
    } else {
        foreach ($path in @($propertiesPath, $keystorePath, $recoveryPath)) {
            if (Test-Path -LiteralPath $path) { throw "Signing identity already exists; refusing to overwrite: $path. Reuse it with -CheckOnly." }
        }
        if (Test-Path -LiteralPath $SigningDirectory) {
            if (-not (Test-Path -LiteralPath $SigningDirectory -PathType Container)) { throw 'SigningDirectory is not a directory.' }
            if (Get-ChildItem -LiteralPath $SigningDirectory -Force | Select-Object -First 1) {
                throw 'Choose a new or empty private signing directory; existing unrelated files will not be changed.'
            }
        } else { New-Item -ItemType Directory -Path $SigningDirectory -Force | Out-Null }
        Protect-PrivatePath $SigningDirectory

        if ($GeneratePassword) {
            $randomBytes = New-Object byte[] 36
            $random = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $random.GetBytes($randomBytes); $plainPassword = [Convert]::ToBase64String($randomBytes) }
            finally { $random.Dispose(); [Array]::Clear($randomBytes, 0, $randomBytes.Length) }
        } else {
            $securePassword = Read-Host 'Choose a permanent signing password (at least 12 characters)' -AsSecureString
            $secureConfirmation = Read-Host 'Confirm the signing password' -AsSecureString
            $plainPassword = [Net.NetworkCredential]::new('', $securePassword).Password
            $confirmation = [Net.NetworkCredential]::new('', $secureConfirmation).Password
            if ($plainPassword.Length -lt 12) { throw 'Use a signing password containing at least 12 characters.' }
            if ($plainPassword -cne $confirmation) { throw 'Password confirmation does not match.' }
        }
        [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_STOREPASS', $plainPassword, 'Process')
        [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_KEYPASS', $plainPassword, 'Process')
        $null = Invoke-SigningKeytool @(
            '-genkeypair', '-keystore', $keystorePath, '-storetype', 'JKS',
            '-alias', $KeyAlias, '-keyalg', 'RSA', '-keysize', '4096',
            '-sigalg', 'SHA256withRSA', '-validity', '10000',
            '-dname', 'CN=Lyric Poster, OU=Release Signing',
            '-storepass:env', 'LYRIC_POSTER_SETUP_STOREPASS',
            '-keypass:env', 'LYRIC_POSTER_SETUP_KEYPASS', '-noprompt'
        )
        Protect-PrivatePath $keystorePath
        $lines = @(
            ('storeFile=' + (ConvertTo-JavaProperty $keystorePath.Replace('\', '/'))),
            ('storePassword=' + (ConvertTo-JavaProperty $plainPassword)),
            ('keyAlias=' + (ConvertTo-JavaProperty $KeyAlias)),
            ('keyPassword=' + (ConvertTo-JavaProperty $plainPassword)),
            'signingMode=custom-release'
        )
        Write-NewPrivateFile $propertiesPath (($lines -join "`r`n") + "`r`n")
        $lines = $null
        Write-NewPrivateFile $recoveryPath (@(
            'PRIVATE ANDROID APP SIGNING MATERIAL - DO NOT PUBLISH OR COMMIT',
            '',
            'Keep this entire directory in a private encrypted backup.',
            'lyric-poster-release.jks contains the irreplaceable private signing key.',
            'key.properties contains the store/key passwords and alias in plain text.',
            'Reuse this same key and alias for every future update of this app.',
            'Do not run setup again to replace a lost password or key.',
            'If restored to another location, update only storeFile in key.properties.',
            'A new key cannot update the old preview APK signed with Android Debug.',
            'Do not delete the preview app before exporting/backing up its user data.',
            'See docs/android-signing.md in the source repository for build commands.'
        ) -join "`r`n")
        Write-Host 'Created a permanent production signing key. The password is stored only in the private key.properties file.'
    }

    $entry = Invoke-SigningKeytool @('-list', '-v', '-keystore', $keystorePath, '-alias', $KeyAlias, '-storepass:env', 'LYRIC_POSTER_SETUP_STOREPASS')
    if ($entry -notmatch 'Entry type:\s*PrivateKeyEntry') { throw 'The alias must contain a private signing key.' }
    # A certificate request proves the private-key password works as well as the
    # store password. It stays in memory and is never submitted or saved.
    $null = Invoke-SigningKeytool @('-certreq', '-keystore', $keystorePath, '-alias', $KeyAlias, '-storepass:env', 'LYRIC_POSTER_SETUP_STOREPASS', '-keypass:env', 'LYRIC_POSTER_SETUP_KEYPASS')
    $pem = Invoke-SigningKeytool @('-exportcert', '-rfc', '-keystore', $keystorePath, '-alias', $KeyAlias, '-storepass:env', 'LYRIC_POSTER_SETUP_STOREPASS')
    if ($pem -notmatch '(?s)-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\r\n]+)\s*-----END CERTIFICATE-----') {
        throw 'Could not export the public signing certificate.'
    }
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($matches[1]))
    if ($certificate.Subject -match 'CN=Android Debug') { throw 'An Android Debug key is not a production signing key.' }
    if ($certificate.NotAfter -le (Get-Date)) { throw 'The signing certificate has expired.' }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha256.ComputeHash($certificate.RawData))).Replace('-', '').ToLowerInvariant() }
    finally { $sha256.Dispose() }
    Write-Host "Signing properties: $propertiesPath"
    Write-Host "Private keystore: $keystorePath"
    Write-Host "Alias: $KeyAlias"
    Write-Host "Certificate subject: $($certificate.Subject)"
    Write-Host "Certificate expiry: $($certificate.NotAfter.ToString('yyyy-MM-dd'))"
    Write-Host "Certificate SHA-256: $fingerprint"
    Write-Host 'Build using scripts/build-android.ps1 -SigningProperties <the private key.properties path above>.'
    Write-Host 'Back up the entire private signing directory securely. Never commit or share it.'
} finally {
    [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_STOREPASS', $oldStorePassword, 'Process')
    [Environment]::SetEnvironmentVariable('LYRIC_POSTER_SETUP_KEYPASS', $oldKeyPassword, 'Process')
    if ($securePassword) { $securePassword.Dispose() }
    if ($secureConfirmation) { $secureConfirmation.Dispose() }
    if ($certificate) { $certificate.Dispose() }
    $signingValues = $null
    $plainPassword = $null
    $confirmation = $null
    $lines = $null
}
