# Run by the "Slate re-sign reminder" scheduled task every 6 days. A free Apple ID signs
# Slate for 7 days; this asks to re-sign the day before, then opens iloader.
# Remove the task with: Unregister-ScheduledTask -TaskName "Slate re-sign reminder" -Confirm:$false
Add-Type -AssemblyName System.Windows.Forms

$ipa = Get-ChildItem (Join-Path $PSScriptRoot "..\out") -Recurse -Filter Slate.ipa -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName

$text = "Slate stops opening tomorrow unless it is re-signed.`n`n" +
        "1. Plug the iPad in with the cable and unlock it.`n" +
        "2. In iloader, choose Import IPA and pick:`n   $ipa`n`n" +
        "Your notebooks are kept. Open iloader now?"
$answer = [System.Windows.Forms.MessageBox]::Show($text, "Re-sign Slate", "YesNo", "Information")
if ($answer -eq "Yes") {
    Start-Process (Join-Path $env:LOCALAPPDATA "iloader\iloader.exe")
}
