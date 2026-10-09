[CmdletBinding()]
param(
    [string]$Distro = 'kali-linux',
    [switch]$Rebuilt
)
$ErrorActionPreference = 'Stop'
$release = '6.18.54.1-microsoft-standard-WSL2-CustomShahmKernal'
$payload = Join-Path $PSScriptRoot $(if ($Rebuilt) { 'rebuilt' } else { 'assets' })
$mode = $(if ($Rebuilt) { 'rebuilt' } else { 'original' })

function Invoke-Wsl {
    param([string[]]$Arguments)
    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed (exit $LASTEXITCODE)." }
}

function Expand-Gzip {
    param([string]$Source, [string]$Destination)
    $inputFile = [IO.File]::OpenRead($Source)
    try {
        $gzip = [IO.Compression.GZipStream]::new($inputFile, [IO.Compression.CompressionMode]::Decompress)
        try {
            $outputFile = [IO.File]::Create($Destination)
            try { $gzip.CopyTo($outputFile) } finally { $outputFile.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $inputFile.Dispose() }
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'Install WSL and Kali first: wsl --install -d kali-linux. Restart Windows and finish Kali first-run setup, then run this installer.'
}
$distros = (& wsl.exe --list --quiet) -replace "`0", ''
if ($LASTEXITCODE -ne 0 -or $Distro -notin @($distros | ForEach-Object { $_.Trim() })) {
    throw "Install and initialize '$Distro' first: wsl --install -d kali-linux"
}
Invoke-Wsl -Arguments @('--set-version', $Distro, '2')

Write-Host 'Checking bundled files before installation...'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
foreach ($item in $manifest.files) {
    $path = Join-Path $PSScriptRoot $item.path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) {
        throw "Bundled file changed or is incomplete: $($item.path)"
    }
}
if ($Rebuilt) {
    foreach ($line in Get-Content -LiteralPath (Join-Path $payload 'SHA256SUMS')) {
        if ($line -notmatch '^([a-f0-9]{64})  (kernel|modules\.vhdx\.gz|kernel-build-metadata\.tar\.gz)$') { throw 'Invalid rebuilt checksum file.' }
        if ((Get-FileHash -LiteralPath (Join-Path $payload $Matches[2])).Hash.ToLowerInvariant() -ne $Matches[1]) {
            throw 'Rebuilt artifact checksum mismatch.'
        }
    }
}

# wslpath handles both spaces and a different Windows account on future installs.
$linuxKit = (& wsl.exe -d $Distro -u root -- wslpath -a -u $PSScriptRoot).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxKit) { throw 'Could not resolve the kit directory inside Kali.' }
Invoke-Wsl -Arguments @('-d', $Distro, '-u', 'root', '--', 'bash', "$linuxKit/install-linux.sh", 'prepare', $mode)

$destination = Join-Path $env:USERPROFILE 'ShahmCustomKernel'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$kernelPath = Join-Path $destination $release
$modulesPath = Join-Path $destination "$release-modules.vhdx"
$stagedModules = "$modulesPath.new"
Copy-Item -LiteralPath (Join-Path $payload 'kernel') -Destination "$kernelPath.new" -Force
Expand-Gzip -Source (Join-Path $payload 'modules.vhdx.gz') -Destination $stagedModules

$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
$backup = "$wslConfig.before-shahm-kit"
$text = ''
if (Test-Path -LiteralPath $wslConfig) {
    $text = [IO.File]::ReadAllText($wslConfig)
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $wslConfig -Destination $backup }
}
$lines = [Collections.Generic.List[string]]::new()
$inside = $false
$found = $false
foreach ($line in ($text -split '\r?\n')) {
    if ($line -match '^\s*\[([^]]+)\]\s*$') {
        if ($inside) {
            $lines.Add("kernel=$($kernelPath.Replace('\','\\'))")
            $lines.Add("kernelModules=$($modulesPath.Replace('\','\\'))")
        }
        $inside = $Matches[1] -ieq 'wsl2'
        if ($inside) { $found = $true }
    }
    if ($inside -and $line -match '^\s*(kernel|kernelModules)\s*=') { continue }
    $lines.Add($line)
}
if (-not $found) { $lines.Add('[wsl2]'); $inside = $true }
if ($inside) {
    $lines.Add("kernel=$($kernelPath.Replace('\','\\'))")
    $lines.Add("kernelModules=$($modulesPath.Replace('\','\\'))")
}

Write-Host 'Restarting WSL to activate the kernel (all WSL distributions, including Docker, will stop).'
Invoke-Wsl -Arguments @('--shutdown')
Move-Item -LiteralPath "$kernelPath.new" -Destination $kernelPath -Force
Move-Item -LiteralPath $stagedModules -Destination $modulesPath -Force
[IO.File]::WriteAllText($wslConfig, (($lines -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
try {
    Invoke-Wsl -Arguments @('-d', $Distro, '-u', 'root', '--', 'bash', "$linuxKit/install-linux.sh", 'activate', $mode)
} catch {
    Write-Warning 'Activation failed. The previous .wslconfig is saved as .wslconfig.before-shahm-kit; restore it and run wsl --shutdown to return to your previous setup.'
    throw
}
Write-Host "Installed $release for $Distro. Open Kali normally to use it."
