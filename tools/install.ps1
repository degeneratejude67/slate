# Signs Slate.ipa with the Apple ID saved in plumesign and installs it on the iPad (USB or
# Wi-Fi sync). Running it again re-signs, which resets the free account's 7-day limit;
# notebooks stay because the bundle id and team do not change.
# usage: powershell -File tools\install.ps1 [-Ipa path]
param(
    [string]$Ipa,
    [string]$Udid = "00008030-0002342C2262202E",
    [int]$Tries = 3
)
$plume = "D:\ipad\signer\plumesign-2.7.1\plumesign.exe"

if (-not $Ipa) {
    $Ipa = Get-ChildItem (Join-Path $PSScriptRoot "..\out") -Recurse -Filter Slate.ipa -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Ipa) { throw "No Slate.ipa found. Run tools\fetch.ps1 first." }
"Installing $Ipa"

for ($i = 1; $i -le $Tries; $i++) {
    & $plume sign --package $Ipa --apple-id --register-and-install --udid $Udid
    if ($LASTEXITCODE -eq 0) { "Installed."; exit 0 }
    "Attempt $i failed (exit $LASTEXITCODE)."
    Start-Sleep -Seconds 5
}
exit 1
