# Pictures of PC Hand-off for the Microsoft Store, filled with made-up data (Anna's laptop), so nothing about this PC
# shows. The app loads hidden, like in Test-App.ps1; its own look at this PC is stopped. Nothing is changed.
# Usage: powershell -STA -File .\tests\Store-Screenshots.ps1 [-Language nl] [-Theme dark] [-Out folder]
#   Default folder: store\screenshots\<language>. The window is 1440 x 900, as the Store asks for at least 1366 x 768.
param([string]$Language = 'en', [string]$Theme = 'light', [string]$Out)
if (-not $Out) { $Out = Join-Path $PSScriptRoot "..\store\screenshots\$Language" }
New-Item -ItemType Directory -Force $Out | Out-Null
$src = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\pc-handoff.ps1'))
$harness = @'
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { if ($Buttons -eq 'YesNo') { 'No' } else { 'OK' } }
function Snap([string]$Name) {
    for ($i = 0; $i -lt 10; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save((Join-Path '__OUT__' "$Name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function Wait-Jobs { $d = (Get-Date).AddSeconds(60); do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while ($script:Jobs.Count -and (Get-Date) -lt $d) }
# Stop the real look at this PC; the pictures only show the made-up data below.
foreach ($j in @($script:Jobs)) { $j.State.Cancel = $true }; Wait-Jobs
$script:Loaded['For the buyer'] = $true   # no real spec sheet either
$form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-3000, 0)   # off screen
$form.MinimumSize = New-Object Drawing.Size(0, 0); $form.Size = New-Object Drawing.Size(1440, 900)
$form.Show()
$home_ = 'C:\Users\Anna'
$script:CheckResult = [pscustomobject]@{
    Bundle = [pscustomobject]@{ Dir = 'E:\PC Move - LAPTOP-ANNA - 2026-10-18'; When = [datetime]'2026-10-18' }
    Folders = @(
        [pscustomobject]@{ Key = 'Desktop'; Name = 'Desktop'; Path = "$home_\OneDrive\Desktop"; OneDrive = $true; Files = 24; Bytes = 85MB; InBundle = $false; Newer = 0 }
        [pscustomobject]@{ Key = 'Documents'; Name = 'Documents'; Path = "$home_\Documents"; OneDrive = $false; Files = 412; Bytes = 1.3GB; InBundle = $true; Newer = 3 }
        [pscustomobject]@{ Key = 'Pictures'; Name = 'Pictures'; Path = "$home_\Pictures"; OneDrive = $false; Files = 2318; Bytes = 8.4GB; InBundle = $true; Newer = 0 }
        [pscustomobject]@{ Key = 'Music'; Name = 'Music'; Path = "$home_\Music"; OneDrive = $false; Files = 640; Bytes = 3.1GB; InBundle = $true; Newer = 0 }
        [pscustomobject]@{ Key = 'Downloads'; Name = 'Downloads'; Path = "$home_\Downloads"; OneDrive = $false; Files = 57; Bytes = 1.2GB; InBundle = $false; Newer = 0 })
    Pst = @([pscustomobject]@{ Path = "$home_\Documents\Outlook Files\archive.pst"; Bytes = 2.1GB })
    Thunderbird = 0; Own = @()
    Drives = @([pscustomobject]@{ Name = 'D:'; Label = 'Data'; Used = 120GB })
    Others = @('Tom')
    Browsers = @([pscustomobject]@{ Browser = 'Chrome'; Profile = 'Anna'; Account = 'anna.jansen@example.com' }
                 [pscustomobject]@{ Browser = 'Edge'; Profile = 'Profile 1'; Account = $null })
    Licence = [pscustomobject]@{ Activated = $true; Channel = 'OEM:DM'; Firmware = $true }
    Programs = @('Microsoft 365 Apps for business - en-us', 'iTunes', 'Steam', 'Norton 360', 'Spotify', 'Dropbox')
    Appx = @('5319275A.WhatsAppDesktop')
}
$script:MsAccount = $true; $script:BitLocker = 'on'
$null = $lvCheck.Handle; $null = $lvSign.Handle
Show-Check; Update-Steps
$lvSign.Items[0].Checked = $true; $lvSign.Items[1].Checked = $true   # two steps already done
$lvSign.Tag = @(540, 560)   # design widths: room for the longest step in the picture (Resize-LastColumn uses them)
$script:Spec = [pscustomobject]@{ Pc = 'Contoso Book 14'; Kind = 'Laptop'; Serial = 'CB14-0042'; Cpu = 'Intel Core i5-1235U'; Cores = 10; Threads = 12; RamBytes = 16GB; RamType = 'DDR4'; RamSpeed = 3200; Slots = 2; SlotsUsed = 1
    Disks = @([pscustomobject]@{ Name = 'Samsung PM9A1'; Size = 512e9; Media = 'SSD'; Bus = 'NVMe'; Health = 'Healthy'; Wear = 4; Hours = 3100 }); Gpu = @('Intel Iris Xe Graphics')
    ScreenInch = 14.0; Resolution = '1920 x 1200'; Battery = [pscustomobject]@{ Health = 87; Cycles = 214 }; Windows = 'Windows 11 Home 25H2'; Win11 = $true; Win11Ready = $null }
Show-Specs; $btnSpecCopy.Enabled = $true; $btnSpecSave.Enabled = $true
Show-Page $pgStart; Snap 'start'
Show-Page $pgCheck; Snap 'check'
Show-Page $pgSign; Snap 'sign-out'
Show-Page $pgBuyer; Snap 'for-the-buyer'
Show-Page $pgWipe; Snap 'wipe'
$form.Close()
$JobTimer.Stop()
'@
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__OUT__', (Resolve-Path $Out).Path))
$src = $src.Replace("`$Settings = [ordered]@{ Language = 'auto'; Theme = 'system'", "`$Settings = [ordered]@{ Language = '$Language'; Theme = '$Theme'")
$src = $src.Replace("if (Test-Path `$SettingsFile) {", "if (`$false) {")   # not this PC's saved settings
$src = $src.Replace("`$StepsFile = Join-Path `$DataDir 'steps.json'", "`$StepsFile = Join-Path `$env:TEMP 'pchandoff-store-steps.json'")   # nor its ticks
$src = $src.Replace("`$form.Add_Shown({", "`$null = ({")   # no update check
$tmp = Join-Path $env:TEMP "pchandoff-store-shots-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
$env:PCHANDOFF_LANGDIR = Join-Path $PSScriptRoot '..\lang'
Remove-Item (Join-Path $env:TEMP 'pchandoff-store-steps.json') -ErrorAction SilentlyContinue
try { & $tmp } finally { Remove-Item $tmp, (Join-Path $env:TEMP 'pchandoff-store-steps.json') -ErrorAction SilentlyContinue }
"Saved to $Out"
