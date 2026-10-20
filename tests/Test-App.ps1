# Loads the whole PC Hand-off app without showing its window, looks at this PC for real and checks every page with
# test data: a PC Move folder, a personal folder with a changed file, an Outlook file, two browser profiles,
# installed programs that need signing out, and the spec sheet. Nothing outside a temporary folder is changed.
# Usage: powershell -STA -File .\tests\Test-App.ps1 [-Language nl] [-Quick]   (exits 1 on failure; used by the GitHub build)
#   -Quick skips looking at the whole PC (the personal folders, licence and hardware) and only uses the test data.
param([string]$Language = 'en', [switch]$Quick, [int]$TimeoutSec = 400)
$app = Join-Path $PSScriptRoot '..\pc-handoff.ps1'
$src = [IO.File]::ReadAllText($app)
$harness = @'
$script:Fail = 0
trap { "FAIL  test stopped: $_ $($_.InvocationInfo.PositionMessage)"; $JobTimer.Stop(); exit 1 }
. ([scriptblock]::Create($Helpers))   # the background helpers in this scope too, to run the checks directly
function Check([bool]$Ok, [string]$What) { if ($Ok) { "ok    $What" } else { $script:Fail++; "FAIL  $What" } }
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') { "  [message] $($Text -replace "`r?`n", ' | ')" | Out-Host; if ($Buttons -eq 'YesNo') { 'Yes' } else { 'OK' } }
function Start-Process { param([Parameter(ValueFromRemainingArguments)]$Rest) "  [would open] $Rest" | Out-Host }
function Wait-Jobs([int]$Sec = __TIMEOUT__) { $d = (Get-Date).AddSeconds($Sec); do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 } while ($script:Jobs.Count -and (Get-Date) -lt $d); Check (-not $script:Jobs.Count) "background work finished within $Sec s" }
$errBefore = if (Test-Path $ErrorLogFile) { @(Get-Content $ErrorLogFile).Count } else { 0 }
$root = Join-Path $env:TEMP "pchandoff-test-$PID"
New-Item -ItemType Directory -Force $root | Out-Null
$StepsFile = Join-Path $root 'steps.json'   # ticks go here, not into this PC's own list

Check ([bool](Get-Command T)) 'app loaded'
Check ($script:CurrentPage -eq $pgStart) 'Start page shown'
Check (@($script:Pages).Count -eq 6) 'six pages'
Check (@(Get-PersonalFolders).Count -ge 5) 'personal folders found'

# --- 1. The real look at this PC (started when the app opened) ---
if (-not $QUICK) {
    Wait-Jobs
    Check ($script:CheckResult -ne $null) 'the check came back'
    "  check rows: $($lvCheck.Items.Count); sign-out steps: $($lvSign.Items.Count)"
    foreach ($it in $lvCheck.Items) { "    $($it.SubItems[0].Text) | $($it.SubItems[1].Text)" }
    Check ($script:CheckResult.Licence -ne $null) 'Windows licence read'
    Show-Page $pgBuyer; Wait-Jobs
    Check ($txtSpec.Text -match (T 'Processor') -and $txtSpec.Text -match (T 'Memory')) 'spec sheet has the processor and memory'
    $txtSpec.Text -split "`r?`n" | ForEach-Object { "    $_" }
} else { foreach ($j in @($script:Jobs)) { $j.State.Cancel = $true }; Wait-Jobs }

# --- 2. The checks, on test data: a PC Move folder, a folder with one changed file, mail, browsers ---
$usb = Join-Path $root 'usb'; $docs = Join-Path $root 'Documents'; $mail = Join-Path $root 'Outlook'; $chrome = Join-Path $root 'Chrome'
$bundle = Join-Path $usb 'PC Move - TEST - 2026-01-01'
New-Item -ItemType Directory -Force $bundle, $docs, $mail, $chrome | Out-Null
@{ Format = 'PC Move bundle'; Created = (Get-Date).AddHours(-2).ToString('s'); Complete = $true; From = @{ Pc = $env:COMPUTERNAME }
   Folders = @(@{ Key = 'Documents'; Complete = $true }) } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $bundle 'pc-move.json') -Encoding UTF8
Set-Content (Join-Path $docs 'old letter.txt') 'packed up'; (Get-Item (Join-Path $docs 'old letter.txt')).LastWriteTime = (Get-Date).AddDays(-3)
Set-Content (Join-Path $docs 'new letter.txt') 'changed after packing up'
Set-Content (Join-Path $mail 'archive.pst') ('x' * 2000)
'{"profile":{"info_cache":{"Default":{"name":"Person 1","user_name":"someone@example.com"},"Profile 1":{"name":"Work","user_name":""}}}}' | Set-Content (Join-Path $chrome 'Local State') -Encoding UTF8
$arg = @{ Roots = @($usb); Folders = @([pscustomobject]@{ Key = 'Documents'; Name = 'Documents'; Path = $docs; OneDrive = $false }
                                      [pscustomobject]@{ Key = 'Pictures'; Name = 'Pictures'; Path = (Join-Path $root 'none'); OneDrive = $true })
          SystemDrive = $env:SystemDrive; Profile = $env:USERPROFILE; KnownRx = $RootKnownRx; MailDirs = @($mail); Browsers = @(@{ Name = 'Chrome'; Dir = $chrome }) }
$Job = $null
$r = & $CheckWork $arg
Check ($r.Bundle -and $r.Bundle.Dir -eq $bundle) 'PC Move folder from this PC found'
$d = @($r.Folders | Where-Object Key -eq 'Documents')[0]
Check ($d.Files -eq 2 -and $d.InBundle -and $d.Newer -eq 1) "changed file found ($($d.Files) files, $($d.Newer) newer)"
Check (@($r.Pst).Count -eq 1) 'Outlook file found'
Check (@($r.Browsers).Count -eq 2 -and @($r.Browsers | Where-Object Account).Count -eq 1) 'browser profiles and who is signed in'
# Programs that need signing out, as if they were installed.
$r.Programs = @('Norton 360', 'iTunes', 'Steam', 'Microsoft 365 Apps for business - en-us', 'Some Game Tool'); $r.Appx = @('5319275A.WhatsAppDesktop')
$r.Own = @(); $r.Drives = @([pscustomobject]@{ Name = 'D:'; Label = 'Data'; Used = 5GB }); $r.Others = @('Anna')
$r.Licence = [pscustomobject]@{ Activated = $true; Channel = 'OEM:DM'; Firmware = $true }
$script:CheckResult = $r; $script:MsAccount = $true; $script:BitLocker = 'on'
$null = $lvCheck.Handle; $null = $lvSign.Handle   # the window is never shown: list events only fire once the lists exist
Show-Check; Update-Steps
foreach ($it in $lvCheck.Items) { "    $($it.SubItems[0].Text) | $($it.SubItems[1].Text) | $($it.SubItems[2].Text)" }
$row = { param($id) @($lvCheck.Items | Where-Object { $_.Tag.Id -eq $id })[0] }
Check ((& $row 'bundle').Tag.Ok) 'PC Move folder row is green'
Check (-not (& $row 'folder|Documents').Tag.Ok -and (& $row 'folder|Documents').Tag.Do.Type -eq 'PcMove') 'changed Documents row asks for PC Move'
Check ((& $row 'folder|Pictures').Tag.Ok) 'OneDrive folder is green'
Check ((& $row 'browser|Chrome|Person 1').Tag.Ok -and -not (& $row 'browser|Chrome|Work').Tag.Ok) 'signed-in browser green, the other not'
Check ((& $row 'licence').Tag.Ok -and -not (& $row 'bitlocker').Tag.Ok) 'licence green, BitLocker asks for the recovery key'
$left = Get-CheckLeft
(& $row 'drive|D:').Checked = $true
Check ((Get-CheckLeft) -eq $left - 1 -and (Get-Done) -contains 'check|drive|D:') 'ticking a row counts and is saved'
(& $row 'bundle').Checked = $false
Check ((& $row 'bundle').Checked) 'green rows stay ticked'
# --- 3. Sign out ---
$stepIds = @($lvSign.Items | ForEach-Object { $_.Tag.Id })
"    steps: $($stepIds -join ', ')"
Check ('av|Norton' -in $stepIds -and 'itunes' -in $stepIds -and 'steam' -in $stepIds -and 'ms365' -in $stepIds -and 'whatsapp' -in $stepIds) 'sign-out steps found from the programs'
Check ($stepIds[-1] -eq 'msaccount') 'Microsoft account step comes last'
$n = Get-StepsLeft
$lvSign.Items[0].Checked = $true
Check ((Get-StepsLeft) -eq $n - 1) 'ticking a step counts'
Check ($tileCheck.Text -match '\d' -and $tileSign.Text -match '\d') "start tiles show what is left"
# --- 4. For the buyer, on test data ---
$script:Spec = [pscustomobject]@{ Pc = 'Contoso Book 14'; Kind = 'Laptop'; Serial = 'ABC123'; Cpu = 'Intel Core i5-1135G7'; Cores = 4; Threads = 8; RamBytes = 16GB; RamType = 'DDR4'; RamSpeed = 3200; Slots = 2; SlotsUsed = 1
    Disks = @([pscustomobject]@{ Name = 'Samsung 980'; Size = 512e9; Media = 'SSD'; Bus = 'NVMe'; Health = 'Healthy'; Wear = 3; Hours = 1200 }); Gpu = @('Intel Iris Xe Graphics')
    ScreenInch = 14.0; Resolution = '1920 x 1080'; Battery = [pscustomobject]@{ Health = 87; Cycles = 210 }; Windows = 'Windows 11 Home 24H2'; Win11 = $true; Win11Ready = $null }
Show-Specs
$sheet = $txtSpec.Text
Check ($sheet -match '16 GB DDR4' -and $sheet -match '512 GB NVMe SSD' -and $sheet -match '87\s?%' -and $sheet -notmatch 'ABC123') 'spec sheet from test data, without the serial number'
$chkSerial.Checked = $true
Check ($txtSpec.Text -match 'ABC123') 'serial number when asked'
# --- 5. Wipe ---
Show-Page $pgWipe
Check ($lblWipeOpen.Text -match '\d') "wipe page says what is still open"
foreach ($p in $script:Pages) { Show-Page $p }

Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
if ($script:TMiss) {
    # Shown texts with no translation. Names, paths, sizes and numbers are fine as they are.
    $out = New-Object Collections.Generic.HashSet[string]; foreach ($v in $script:TExact.Values) { [void]$out.Add($v) }
    $same = @($script:TExact.Keys | Where-Object { $script:TExact[$_] -ceq $_ })
    $miss = @($script:TMiss | Where-Object { -not $out.Contains($_) -and -not $out.Contains(($_ -split ': ')[0]) -and $_ -notin $same -and $_ -notmatch '^(.+)  \(\d+\)$|^Version \d' } |
        Where-Object { $_ -match '[a-z]{3}' -and $_ -notmatch '^[A-Z]:\\|\\|^\d|github\.com|^PC Hand-off( \d|$)|^(English|Nederlands|Deutsch|Français|Español|Italiano|Polski)$|^Version: |^Windows: |^Recent errors: |@|^Contoso|^Intel|^Samsung|^Windows 1\d|^(Chrome|Edge|Brave|Vivaldi|Firefox)\b|^Anna$' } | Sort-Object)
    foreach ($m in $miss) { "  not translated: $m" }
    Check (-not $miss) "every text shown is translated ($Lang)"
}
$errAfter = if (Test-Path $ErrorLogFile) { @(Get-Content $ErrorLogFile).Count } else { 0 }
if ($errAfter -gt $errBefore) { Get-Content $ErrorLogFile -Tail ($errAfter - $errBefore) | ForEach-Object { "  error log: $_" } }
Check ($errAfter -eq $errBefore) 'no errors inside the app'
$JobTimer.Stop()
"`n$(if ($script:Fail) { "$($script:Fail) check(s) FAILED" } else { 'All checks passed.' })"
exit [int]($script:Fail -gt 0)
'@
$src = $src.Replace('[void]$form.ShowDialog()', $harness.Replace('__TIMEOUT__', $TimeoutSec).Replace('$QUICK', $(if ($Quick) { '$true' } else { '$false' })))
$src = $src.Replace("`$Settings = [ordered]@{ Language = 'auto'", "`$Settings = [ordered]@{ Language = '$Language'")
$src = $src.Replace("if (Test-Path `$SettingsFile) {", "if (`$false) {")   # the test ignores this PC's saved settings
$src = $src.Replace("`$StepsFile = Join-Path `$DataDir 'steps.json'", "`$StepsFile = Join-Path `$env:TEMP 'pchandoff-test-steps.json'")
$tmp = Join-Path $env:TEMP "pchandoff-test-app-$PID.ps1"
[IO.File]::WriteAllText($tmp, $src, (New-Object Text.UTF8Encoding($true)))
$env:PCHANDOFF_LANGDIR = Join-Path $PSScriptRoot '..\lang'
$env:PCHANDOFF_TRACKT = $(if ($Language -ne 'en') { '1' } else { '' })
try { & $tmp; $code = $LASTEXITCODE } finally { Remove-Item $tmp, (Join-Path $env:TEMP 'pchandoff-test-steps.json') -ErrorAction SilentlyContinue }
exit $code
