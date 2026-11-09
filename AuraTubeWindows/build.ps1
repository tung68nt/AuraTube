# Builds the native Windows app: self-contained win-x64 publish with bundled yt-dlp,
# a portable zip and an Inno Setup installer in AuraTubeWindows/dist.
#   pwsh AuraTubeWindows/build.ps1 -Version 2.1.12
param(
    [string]$Version = "0.0.0",
    [switch]$SkipInstaller
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = Join-Path $root "dist"
$publish = Join-Path $dist "publish"
$bin = Join-Path $root "bin"

Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $bin, $dist | Out-Null

# Bundle yt-dlp.exe (the app copies it to %LOCALAPPDATA%\AuraTube\bin and self-updates it).
$ytdlp = Join-Path $bin "yt-dlp.exe"
if (-not (Test-Path $ytdlp)) {
    Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $ytdlp -UseBasicParsing
}
& $ytdlp --version

dotnet publish (Join-Path $root "src/AuraTube/AuraTube.csproj") -c Release -r win-x64 --self-contained true `
    -p:Version=$Version -p:PublishReadyToRun=true -p:DebugType=none -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
Get-ChildItem $publish -Filter *.xml | Remove-Item
if (-not (Test-Path (Join-Path $publish "bin/yt-dlp.exe"))) { throw "yt-dlp.exe was not bundled" }
if (-not (Test-Path (Join-Path $publish "libvlc/win-x64/libvlc.dll"))) { throw "libvlc was not bundled" }

$zip = Join-Path $dist "AuraTube-Windows-Portable-v$Version.zip"
Compress-Archive -Path (Join-Path $publish "*") -DestinationPath $zip
Write-Host "Portable: $zip"

if (-not $SkipInstaller) {
    $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) {
        choco install innosetup -y --no-progress | Out-Null
        $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    }
    & $iscc "/DAppVersion=$Version" "/DSourceDir=$publish" "/DOutputDir=$dist" (Join-Path $root "installer/AuraTube.iss")
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
}
Get-ChildItem $dist -File | Format-Table Name, Length
