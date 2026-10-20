#Requires -Version 5.1
# PC Hand-off: get your old Windows 10/11 PC ready to sell, give away or recycle.
#   Start         - the four steps and how far you are
#   Check         - before wiping: are your files somewhere else (OneDrive, a PC Move folder)? Mail files, folders
#                   outside your personal folders, other drives and accounts, browsers that aren't signed in,
#                   BitLocker and the Windows licence
#   Sign out      - licences and devices tied to this PC (Microsoft 365, iTunes, Adobe, antivirus, Steam, WhatsApp...),
#                   found from the installed programs, as a checklist
#   For the buyer - a sheet with the specs (processor, memory, drive, battery health, screen, Windows) to copy or save
#   Wipe          - Windows' own "Remove everything" reset, explained step by step
# PC Hand-off only reads from this PC; nothing changes until you start the reset yourself.
# Run PC-Handoff.exe (this script embedded; rebuild with build-exe.ps1 after editing) or PC-Handoff.cmd.
# Release a new version: bump $AppVersion, then .\publish-release.ps1 -Notes "...".

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# PC-Handoff.exe already contains these functions (no compiling at start-up); the plain script compiles them itself.
# Keep in step with the copy in build-exe.ps1.
if (-not ('PcHandoff.Native' -as [type])) { Add-Type -Namespace PcHandoff -Name Native -ErrorAction SilentlyContinue -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h, int attr, ref int value, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(System.IntPtr h, string app, string idList);
[DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr h, int msg, System.IntPtr w, System.IntPtr l);
'@ }
try { [void][PcHandoff.Native]::SetProcessDPIAware() } catch { }
[Windows.Forms.Application]::EnableVisualStyles()
$DpiScale = try { [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96 } catch { 1 }
function Px([double]$Pixels) { [int][Math]::Round($Pixels * $DpiScale) }   # for sizes WinForms doesn't scale itself

# Command line (PC-Handoff.exe /install /uninstall /?). The exe host passes $AppArgs.
$CliArgs = if ($AppArgs) { @($AppArgs) } else { @($args) }
$Cli = @{ Help = $false; Install = $false; Uninstall = $false }
foreach ($a in $CliArgs) {
    switch -Regex ("$a") {
        '^[/-](\?|h|help)$' { $Cli.Help = $true }
        '^[/-]install$' { $Cli.Install = $true }
        '^[/-]uninstall$' { $Cli.Uninstall = $true }
    }
}

$AppVersion = '1.0.0'                  # bump for every release; publish-release.ps1 tags it as v<version>
$UpdateRepo = 'michaelkloprogge-gif/pc-handoff'         # GitHub repo whose latest release the app updates from

$SelfExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$RunningAsExe = $SelfExe -notmatch '\\(powershell|pwsh)\.exe$'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$DataDir = Join-Path $env:LOCALAPPDATA 'PCHandoff'
New-Item -ItemType Directory -Force $DataDir | Out-Null
$LogFile = Join-Path $DataDir 'changes.log'
$StepsFile = Join-Path $DataDir 'steps.json'          # which rows on Check and Sign out are ticked off
$ErrorLogFile = Join-Path $DataDir 'errors.log'      # problems inside PC Hand-off itself; "Report a problem" includes recent ones
function Write-AppError([string]$Where, $Err) {
    try {
        $msg = if ($Err -is [Management.Automation.ErrorRecord]) {
            $at = if ($Err.InvocationInfo -and $Err.InvocationInfo.ScriptLineNumber) { " [line $($Err.InvocationInfo.ScriptLineNumber): $("$($Err.InvocationInfo.Line)".Trim())]" } else { '' }
            "$($Err.Exception.Message)$at"
        } else { "$Err" }
        Add-Content -Path $ErrorLogFile -Value ('{0:s}  v{1}  {2}: {3}' -f (Get-Date), $AppVersion, $Where, ($msg -replace '\s+', ' ')) -Encoding UTF8
        if ((Get-Item -LiteralPath $ErrorLogFile).Length -gt 256KB) { Set-Content -Path $ErrorLogFile -Value @(Get-Content $ErrorLogFile -Tail 500) -Encoding UTF8 }
    } catch { }
}
function Get-AppErrors([int]$Days = 14) {
    if (-not (Test-Path $ErrorLogFile)) { return }
    $since = (Get-Date).AddDays(-$Days).ToString('s')
    Get-Content $ErrorLogFile -Encoding UTF8 -Tail 300 | Where-Object { $_.Length -ge 19 -and $_.Substring(0, 19) -ge $since }
}
$SettingsFile = Join-Path $DataDir 'settings.json'
$Settings = [ordered]@{ Language = 'auto'; Theme = 'system'; CheckUpdates = $true }
if (Test-Path $SettingsFile) {
    try { (Get-Content $SettingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { if ($Settings.Contains($_.Name)) { $Settings[$_.Name] = $_.Value } } } catch { }
}
function Save-Settings { $Settings | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8 }

# ---------------------------------------------------------------------------
# Language. Code and data stay English; T() translates text on its way to the screen.
# Tables: lang\<code>.tsv, English <TAB> translation, one per line; {0}, {1}... stand for values filled in at run time.
# The exe carries them as resources.
# ---------------------------------------------------------------------------
$Languages = 'nl', 'de', 'fr', 'es', 'it', 'pl'
$Lang = if ($Settings.Language -in @('en') + $Languages) { $Settings.Language } else { $w = (Get-UICulture).TwoLetterISOLanguageName; if ($w -in $Languages) { $w } else { 'en' } }
# Case-sensitive lookups: "Edge" (a browser) and "edge" are different texts.
$script:TExact = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TCache = New-Object Collections.Hashtable([StringComparer]::Ordinal)
$script:TPatterns = @()
$UiCulture = if ($Lang -eq 'en') { [Globalization.CultureInfo]::CurrentCulture } else {
    [Globalization.CultureInfo]::GetCultureInfo(@{ nl = 'nl-NL'; de = 'de-DE'; fr = 'fr-FR'; es = 'es-ES'; it = 'it-IT'; pl = 'pl-PL' }[$Lang]) }
[Threading.Thread]::CurrentThread.CurrentCulture = $UiCulture
function Get-LangTable([string]$Code) {
    try {
        if ($RunningAsExe) {
            $st = [Reflection.Assembly]::GetEntryAssembly().GetManifestResourceStream("$Code.tsv")
            if ($st) { try { return (New-Object IO.StreamReader($st, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $st.Dispose() } }
        }
        $dir = if ($env:PCHANDOFF_LANGDIR) { $env:PCHANDOFF_LANGDIR } else { Join-Path (Split-Path -Parent $PSCommandPath) 'lang' }
        $file = Join-Path $dir "$Code.tsv"
        if (Test-Path $file) { return [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) }
    } catch { }
    ''
}
if ($Lang -ne 'en') {
    $pats = foreach ($line in (Get-LangTable $Lang) -split "`r?`n") {
        if (-not $line.Trim()) { continue }
        $en, $tr = $line -split "`t", 2
        if ($en -notmatch '\{\d+\}') { $script:TExact[$en] = $tr; continue }
        $rx = '^' + ([regex]::Escape($en) -replace '\\\{(\d+)}', '(?<p$1>.+?)') + '$'
        @{ Rx = [regex]::new($rx); Tr = $tr; N = ([regex]::Matches($en, '\{\d+\}')).Count; Lit = ($en -replace '\{\d+\}', '').Length }
    }
    $script:TPatterns = @($pats | Sort-Object { $_.Lit } -Descending)   # most specific first; "{0}: {1}" comes last
}
function T([string]$Text, [int]$Depth = 0) {
    if ($Lang -eq 'en' -or -not $Text -or $Depth -gt 3) { return $Text }
    if ($script:TCache.ContainsKey($Text)) { return $script:TCache[$Text] }
    $out = $Text
    if ($Text -match "`n") { $out = (($Text -split "`r?`n") | ForEach-Object { T $_ $Depth }) -join "`r`n" }
    elseif ($Text -match '^(\s*(?:(?:[-!]|\u2022)\s+)?)(.*?)(\s*)$' -and $Matches[2]) {
        $pre = $Matches[1]; $core = $Matches[2]; $post = $Matches[3]
        if ($script:TExact.ContainsKey($core)) { $out = $pre + $script:TExact[$core] + $post }
        else {
            foreach ($p in $script:TPatterns) {
                $m = $p.Rx.Match($core)
                if (-not $m.Success) { continue }
                $vals = @(for ($i = 0; $i -lt $p.N; $i++) { T $m.Groups["p$i"].Value ($Depth + 1) })
                $out = $pre + ($p.Tr -f $vals) + $post
                break
            }
        }
    }
    if ($script:TCache.Count -lt 20000) { $script:TCache[$Text] = $out }
    if ($script:TMiss -and $out -ceq $Text -and $Depth -eq 0) { [void]$script:TMiss.Add($Text) }   # tests: texts with no translation
    $out
}
$script:TMiss = if ($env:PCHANDOFF_TRACKT) { New-Object Collections.Generic.HashSet[string] } else { $null }
# Translate a window's controls now, and again whenever their text changes later.
function Enable-Translation($Control) {
    if ($Lang -eq 'en') { return }
    $translatable = $Control -is [Windows.Forms.Label] -or $Control -is [Windows.Forms.ButtonBase] -or
                    ($Control -is [Windows.Forms.TextBox] -and $Control.ReadOnly)
    if ($translatable) {
        $Control.Text = T $Control.Text
        $Control.Add_TextChanged({ if (-not $script:InT) { $script:InT = $true; $t = T $this.Text; if ($t -ne $this.Text) { $this.Text = $t }; $script:InT = $false } })
    }
    if ($Control -is [Windows.Forms.ListView]) { foreach ($c in $Control.Columns) { $c.Text = T $c.Text } }
    foreach ($child in $Control.Controls) { Enable-Translation $child }
}
# Installed copy: per user, no administrator needed.
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\PC Hand-off'
$InstalledExe = Join-Path $InstallDir 'PC-Handoff.exe'
$IsInstalled = $RunningAsExe -and ($SelfExe -eq $InstalledExe)
$FromWinget = $RunningAsExe -and $SelfExe -match '\\Microsoft\\WinGet\\(Packages|Links)\\'

function Write-Log([string]$Msg) {
    Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Msg) -Encoding UTF8
}
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}
function Show-Msg([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    [Windows.Forms.MessageBox]::Show((T $Text), 'PC Hand-off', $Buttons, $Icon)
}
function Get-RegValue([string]$Path, [string]$Name) {
    try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

# ---------------------------------------------------------------------------
# What to look at
# ---------------------------------------------------------------------------
# Personal folders, as Windows knows them (they may live in OneDrive or on another drive). The keys match PC Move's.
function Get-PersonalFolders {
    $dl = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    $dl = if ($dl) { [Environment]::ExpandEnvironmentVariables($dl) } else { Join-Path $env:USERPROFILE 'Downloads' }
    @(
        @{ Key = 'Desktop';   Name = 'Desktop';   Path = [Environment]::GetFolderPath('Desktop') }
        @{ Key = 'Documents'; Name = 'Documents'; Path = [Environment]::GetFolderPath('MyDocuments') }
        @{ Key = 'Pictures';  Name = 'Pictures';  Path = [Environment]::GetFolderPath('MyPictures') }
        @{ Key = 'Music';     Name = 'Music';     Path = [Environment]::GetFolderPath('MyMusic') }
        @{ Key = 'Videos';    Name = 'Videos';    Path = [Environment]::GetFolderPath('MyVideos') }
        @{ Key = 'Downloads'; Name = 'Downloads'; Path = $dl }
    ) | Where-Object { $_.Path } | ForEach-Object {
        $od = foreach ($o in $env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer) { if ($o -and $_.Path.StartsWith($o.TrimEnd('\') + '\', 'OrdinalIgnoreCase')) { $o } }
        $_.OneDrive = [bool]$od
        [pscustomobject]$_
    }
}
# Browsers built on Chromium keep their profiles, and who is signed in, in "Local State".
$ChromiumBrowsers = @(
    @{ Name = 'Chrome';  Dir = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
    @{ Name = 'Edge';    Dir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
    @{ Name = 'Brave';   Dir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
    @{ Name = 'Vivaldi'; Dir = "$env:LOCALAPPDATA\Vivaldi\User Data" }
)
$BrowserExe = @{
    Chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    Edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
    Brave = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe")
    Vivaldi = @("$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe", "$env:ProgramFiles\Vivaldi\Application\vivaldi.exe")
    Firefox = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe")
}
# The browser's own page with saved passwords (it has an export button).
$BrowserPasswords = @{ Chrome = 'chrome://password-manager/settings'; Edge = 'edge://settings/passwords'; Brave = 'brave://settings/passwords'; Firefox = 'about:logins' }
# Folders in the root of the Windows drive that come with Windows, programs or the PC's maker.
$RootKnownRx = '^(Windows|Windows\.old|Program Files|Program Files \(x86\)|ProgramData|Users|PerfLogs|Recovery|Boot|Documents and Settings|Intel|AMD|NVIDIA|Drivers|ESD|inetpub|OneDriveTemp|Config\.Msi|MSOCache|SWSetup|SWTOOLS|System\.sav|Dell|HP|Lenovo|ASUS|Acer|MSI|Apps|Logs|Temp|tmp|XboxGames|Python\d+|msys64|cygwin(64)?|tools|xampp|wamp(64)?|Strawberry|Ruby\d+.*|MinGW.*|vcpkg|android|flutter|Riot Games|Games)$'
# Programs that tie a licence, a device slot or a session to this PC: sign out before it goes.
# Match = installed program names (regex; a {0} in Text is filled with the name found), Appx = Store app names.
$ServiceCatalog = @(
    @{ Id = 'ms365'; Match = '^Microsoft (365|Office)\b'; Text = 'Sign out of Microsoft 365 (Office)'; Why = 'Microsoft 365 is signed in on a limited number of PCs. In Word: File > Account > Sign out, or remove this PC at your Microsoft account.'; Url = 'https://account.microsoft.com/services' }
    @{ Id = 'itunes'; Match = '^iTunes$'; Appx = '^AppleInc\.iTunes$'; Text = 'Deauthorise this computer in iTunes'; Why = 'Apple allows 5 authorised computers. In iTunes: Account > Authorisations > Deauthorise This Computer.' }
    @{ Id = 'icloud'; Match = '^iCloud\b'; Appx = '^AppleInc\.iCloud$'; Text = 'Sign out of iCloud'; Why = 'Open iCloud and click Sign out, so this PC leaves your Apple devices.' }
    @{ Id = 'adobe'; Match = '^Adobe (Creative Cloud|Acrobat(?! Reader)|Photoshop|Lightroom|Premiere|Illustrator|InDesign)'; Text = 'Sign out of Adobe'; Why = 'Adobe apps run on two computers at a time. In Creative Cloud or Acrobat: Help > Sign out frees this one.'; Url = 'https://account.adobe.com/' }
    @{ Id = 'steam'; Match = '^Steam$'; Text = 'Remove this PC from Steam'; Why = 'Steam Guard trusts this PC. Sign out of Steam, or use "Deauthorise all other devices" on the Steam website.'; Url = 'https://store.steampowered.com/twofactor/manage' }
    @{ Id = 'games'; Match = '^(Epic Games Launcher|EA app|Ubisoft Connect|Battle\.net|GOG GALAXY)'; Text = 'Sign out of {0}'; Why = 'Game launchers remember this PC. Sign out in the launcher.' }
    @{ Id = 'dropbox'; Match = '^Dropbox\b'; Text = 'Unlink this PC from Dropbox'; Why = 'Dropbox Basic allows 3 devices.'; Url = 'https://www.dropbox.com/account/security' }
    @{ Id = 'spotify'; Match = '^Spotify\b'; Appx = '^SpotifyAB\.SpotifyMusic$'; Text = 'Remove this PC from Spotify'; Why = 'Downloaded music counts against Spotify''s device limit. "Sign out everywhere" on your Spotify account page also works.'; Url = 'https://www.spotify.com/account/overview/' }
    @{ Id = 'netflix'; Appx = '^4DF9E0F8\.Netflix$'; Text = 'Sign out of Netflix'; Why = 'Downloaded films count against your Netflix download devices.'; Url = 'https://www.netflix.com/manageaccountaccess' }
    @{ Id = 'kindle'; Match = '^Kindle\b'; Text = 'Deregister Kindle on this PC'; Why = 'At Amazon: Content and devices > Devices > Deregister.' }
    @{ Id = 'whatsapp'; Match = '^WhatsApp\b'; Appx = '^5319275A\.WhatsAppDesktop$'; Text = 'Unlink WhatsApp from this PC'; Why = 'On your phone: WhatsApp > Settings > Linked devices, then log out this PC.' }
    @{ Id = 'telegram'; Match = '^Telegram Desktop'; Appx = '^TelegramMessengerLLP\.TelegramDesktop$'; Text = 'Log out of Telegram'; Why = 'On your phone: Telegram > Settings > Devices, then end this session.' }
    @{ Id = 'signal'; Match = '^Signal\b'; Text = 'Unlink Signal'; Why = 'On your phone: Signal > Settings > Linked devices.' }
    @{ Id = 'av'; Match = '^(Norton|McAfee|Kaspersky|Bitdefender|ESET|Avast Premium|AVG Internet|Trend Micro|F-Secure|Malwarebytes|Panda Dome|G DATA|Avira Prime)'; Text = 'Free your {0} licence'; Why = 'Remove this PC from your account on the maker''s website, so the licence can go to your new PC.' }
    @{ Id = 'pwm'; Match = '^(1Password|Bitwarden|LastPass|Dashlane|Keeper|NordPass)'; Text = 'Sign out of {0}'; Why = 'Your passwords stay in your account, but this PC should not stay signed in.' }
    @{ Id = 'music'; Match = '^(iLok License Manager|Native Access|Waves Central|Steinberg Download Assistant|Avid Link)'; Text = 'Deactivate licences in {0}'; Why = 'Music software licences are tied to this PC until you deactivate them.' }
)
$AccountUrls = @{ Norton = 'https://my.norton.com/'; McAfee = 'https://home.mcafee.com/myaccount'; Kaspersky = 'https://my.kaspersky.com/'; Bitdefender = 'https://central.bitdefender.com/'
                  ESET = 'https://home.eset.com/'; Malwarebytes = 'https://my.malwarebytes.com/'; 'Trend Micro' = 'https://account.trendmicro.com/'; 'F-Secure' = 'https://my.f-secure.com/'
                  'Avast Premium' = 'https://id.avast.com/'; 'AVG Internet' = 'https://myaccount.avg.com/' }
$PcMoveExe = Join-Path $env:LOCALAPPDATA 'Programs\PC Move\PC-Move.exe'
$PcMoveUrl = 'https://github.com/michaelkloprogge-gif/pc-move#readme'
# Windows' own reset ("Reset this PC"); it asks for administrator permission itself.
$ResetExe = Join-Path $env:windir 'System32\systemreset.exe'

# Drive encryption, from File Explorer's own property (works without administrator). 1, 3, 5, 6 = on; 2 = off.
function Get-BitLockerState([string]$Drive) {
    try {
        $sh = New-Object -ComObject Shell.Application
        $v = $sh.NameSpace("$Drive\").Self.ExtendedProperty('System.Volume.BitLockerProtection')
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        if ($v -in 1, 3, 5, 6) { 'on' } elseif ($v -eq 2) { 'off' } else { $null }
    } catch { $null }
}
# A Microsoft account signed in to Windows or the Store leaves its name here.
function Test-MicrosoftAccount { [bool](Get-ChildItem 'HKCU:\Software\Microsoft\IdentityCRL\StoredIdentities' -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------------------
# Background work: long jobs run in a separate runspace so the window stays responsive.
# A timer polls them and calls the Done block.
# ---------------------------------------------------------------------------
$Helpers = @'
function Get-FilesSafe([string]$Root) {
    if (-not [IO.Directory]::Exists($Root)) { return }
    $stack = New-Object System.Collections.Stack
    $stack.Push([IO.DirectoryInfo]$Root)
    while ($stack.Count) {
        $dir = $stack.Pop()
        try {
            foreach ($e in $dir.EnumerateFileSystemInfos()) {
                if ($e -is [IO.DirectoryInfo]) {
                    if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($e) }
                } else { $e }
            }
        } catch { }
    }
}
# Run a console program hidden and capture its output as UTF-8 (winget prints Unicode names).
function Invoke-Native([string]$Exe, [string]$Arguments, [int]$TimeoutSec = 600) {
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $p.WaitForExit(500)) {   # check twice a second whether the user pressed Cancel
        if (($Job -and $Job.Cancel) -or (Get-Date) -gt $deadline) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ Out = ''; Code = -1; TimedOut = -not ($Job -and $Job.Cancel); Cancelled = [bool]($Job -and $Job.Cancel) }
        }
    }
    [pscustomobject]@{ Out = $out.Result + $err.Result; Code = $p.ExitCode; TimedOut = $false; Cancelled = $false }
}
function Set-JobProgress([string]$Text, [int]$Value = -1, [int]$Max = 0) {
    if ($Job) { $Job.Text = $Text; $Job.Value = $Value; $Job.Max = $Max }
}
function Test-Cancelled { [bool]($Job -and $Job.Cancel) }
'@

# Looks at this PC for the Check and Sign out pages. Reads only.
$CheckWork = {
    param($a)
    # The newest complete PC Move folder made on this PC, on any other drive.
    $bundle = $null
    foreach ($root in $a.Roots) {
        foreach ($c in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'PC Move - *' -ErrorAction SilentlyContinue)) {
            try { $m = Get-Content -LiteralPath (Join-Path $c.FullName 'pc-move.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { continue }
            if ($m.From.Pc -ne $env:COMPUTERNAME -or -not $m.Complete) { continue }
            $when = try { [datetime]$m.Created } catch { continue }
            if (-not $bundle -or $when -gt $bundle.When) { $bundle = [pscustomobject]@{ Dir = $c.FullName; When = $when; Folders = @($m.Folders | Where-Object Complete | ForEach-Object Key) } }
        }
    }
    # Personal folders: how much is only on this PC, and how much changed after the PC Move folder was made.
    $folders = foreach ($f in $a.Folders) {
        Set-JobProgress "looking at $($f.Name)"
        $o = [ordered]@{ Key = $f.Key; Name = $f.Name; Path = $f.Path; OneDrive = $f.OneDrive; Bytes = 0.0; Files = 0; Newer = 0; InBundle = [bool]($bundle -and $f.Key -in $bundle.Folders) }
        if (-not $f.OneDrive) {
            foreach ($e in Get-FilesSafe $f.Path) {
                if (Test-Cancelled) { break }
                if ($e.Name -in 'desktop.ini', 'thumbs.db') { continue }
                $o.Bytes += $e.Length; $o.Files++
                if ($o.InBundle -and $e.LastWriteTime -gt $bundle.When) { $o.Newer++ }
            }
        }
        [pscustomobject]$o
    }
    # Mail kept on this PC: Outlook data files outside the personal folders, and Thunderbird profiles.
    Set-JobProgress 'looking for e-mail'
    $pst = @(foreach ($d in $a.MailDirs) { if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -Recurse -Filter *.pst -File -ErrorAction SilentlyContinue } })
    $tb = Join-Path $env:APPDATA 'Thunderbird\Profiles'
    $tbBytes = 0.0; foreach ($e in Get-FilesSafe $tb) { $tbBytes += $e.Length }
    # Folders you made yourself in the root of the Windows drive.
    Set-JobProgress 'looking at the Windows drive'
    $own = foreach ($d in Get-ChildItem -LiteralPath "$($a.SystemDrive)\" -Directory -Force -ErrorAction SilentlyContinue) {
        if ($d.Attributes -band [IO.FileAttributes]'Hidden, System' -or $d.Name -like '$*' -or $d.Name -match $a.KnownRx) { continue }
        $b = 0.0; $n = 0
        foreach ($e in Get-FilesSafe $d.FullName) { $b += $e.Length; $n++; if ($n -ge 100000 -or (Test-Cancelled)) { break } }
        if ($n) { [pscustomobject]@{ Name = $d.Name; Path = $d.FullName; Bytes = $b; Files = $n } }
    }
    # Other drives inside the PC (not USB disks): the reset leaves them alone unless you ask.
    $usb = @{}
    try { foreach ($p in Get-Partition -ErrorAction Stop) { if ($p.DriveLetter -and (Get-Disk -Number $p.DiskNumber -ErrorAction Stop).BusType -in 'USB', 'SD', 'MMC') { $usb["$($p.DriveLetter):"] = $true } } } catch { }
    $drives = foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            $n = $d.Name.TrimEnd('\')
            if ($d.IsReady -and $d.DriveType -eq 'Fixed' -and $n -ne $a.SystemDrive -and -not $usb[$n]) { [pscustomobject]@{ Name = $n; Label = $d.VolumeLabel; Used = [double]($d.TotalSize - $d.TotalFreeSpace) } }
        } catch { }
    }
    # Other people's accounts: their files go too.
    $others = @(foreach ($u in Get-ChildItem -LiteralPath (Split-Path $a.Profile) -Directory -ErrorAction SilentlyContinue) {
        if ($u.FullName -eq $a.Profile -or $u.Name -match '^(Public|Default|Default User|All Users|defaultuser\d*|WDAGUtilityAccount|WsiAccount)$' -or $u.Name -like '.*') { continue }
        $u.Name
    })
    # Browsers: profiles that are not signed in keep their bookmarks and passwords only on this PC.
    $browsers = @(foreach ($b in $a.Browsers) {
        try { $ls = Get-Content -LiteralPath (Join-Path $b.Dir 'Local State') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { continue }
        foreach ($p in $ls.profile.info_cache.PSObject.Properties) {
            [pscustomobject]@{ Browser = $b.Name; Profile = "$($p.Value.name)"; Account = "$($p.Value.user_name)" }
        }
    })
    foreach ($p in Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles') -Directory -ErrorAction SilentlyContinue) {
        if (-not (Test-Path -LiteralPath (Join-Path $p.FullName 'places.sqlite'))) { continue }
        $acct = ''
        try { $acct = "$((Get-Content -LiteralPath (Join-Path $p.FullName 'signedInUser.json') -Raw -ErrorAction Stop | ConvertFrom-Json).accountData.email)" } catch { }
        $browsers += [pscustomobject]@{ Browser = 'Firefox'; Profile = ($p.Name -replace '^[^.]+\.', ''); Account = $acct }
    }
    # The Windows licence: activated? Built into the PC (the next owner keeps it)?
    Set-JobProgress 'looking at the Windows licence'
    $lic = $null
    try {
        $p = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | Select-Object -First 1
        $oa3 = try { [bool](Get-CimInstance SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey } catch { $false }
        if ($p) { $lic = [pscustomobject]@{ Activated = ($p.LicenseStatus -eq 1); Channel = "$($p.ProductKeyChannel)"; Firmware = $oa3 } }
    } catch { }
    # Installed programs, for the Sign out steps.
    $names = @($(foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | ForEach-Object { "$($_.DisplayName)".Trim() }
    }) | Sort-Object -Unique)
    $appx = try { @(Get-AppxPackage -ErrorAction Stop | ForEach-Object Name) } catch { @() }
    [pscustomobject]@{ Bundle = $bundle; Folders = @($folders); Pst = @($pst | ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Bytes = $_.Length } })
                       Thunderbird = $tbBytes; Own = @($own); Drives = @($drives); Others = $others; Browsers = $browsers; Licence = $lic
                       Programs = $names; Appx = $appx; Cancelled = (Test-Cancelled) }
}

# The specs for the buyer. Reads only; the drive's wear needs administrator.
$SpecWork = {
    param($a)
    $s = [ordered]@{}
    $cs = Get-CimInstance Win32_ComputerSystem
    $csp = Get-CimInstance Win32_ComputerSystemProduct
    $bios = Get-CimInstance Win32_BIOS
    $maker = "$($cs.Manufacturer)".Trim() -replace '(?i)\s*(Inc\.?|Corporation|Co\.,? ?Ltd\.?|Computer)$', ''
    $model = "$($cs.Model)".Trim()
    if ($maker -match '^LENOVO' -and $csp.Version -and $csp.Version -notmatch '^(None|Lenovo)$') { $model = "$($csp.Version) ($model)" }   # Lenovo puts the name people know in Version
    $s.Pc = ("$maker $model" -replace '\s+', ' ').Trim()
    $s.Serial = "$($bios.SerialNumber)".Trim()
    $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)[0]
    $s.Kind = if ($chassis -in 8, 9, 10, 14, 31, 32) { 'Laptop' } elseif ($chassis -in 30) { 'Tablet' } elseif ($chassis -eq 13) { 'All-in-one' } elseif ($chassis -in 3, 4, 5, 6, 7, 15, 16, 35, 36) { 'Desktop PC' } else { '' }
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $s.Cpu = ("$($cpu.Name)" -replace '\((R|TM|tm)\)|CPU|\d+(th|rd|nd|st) Gen ', '' -replace '\s+@.*$', '' -replace '\s+', ' ').Trim()
    $s.Cores = [int]$cpu.NumberOfCores; $s.Threads = [int]$cpu.NumberOfLogicalProcessors
    $mem = @(Get-CimInstance Win32_PhysicalMemory)
    $s.RamBytes = [double](($mem | Measure-Object Capacity -Sum).Sum)
    if (-not $s.RamBytes) { $s.RamBytes = [double]$cs.TotalPhysicalMemory }
    $s.RamType = switch ([int]@($mem)[0].SMBIOSMemoryType) { 20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 29 { 'LPDDR3' } 30 { 'LPDDR4' } 34 { 'DDR5' } 35 { 'LPDDR5' } default { '' } }
    $s.RamSpeed = [int]$(if (@($mem)[0].ConfiguredClockSpeed) { @($mem)[0].ConfiguredClockSpeed } else { @($mem)[0].Speed })
    $s.Slots = [int]((Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum)
    $s.SlotsUsed = $mem.Count
    $s.Disks = @(try {
        foreach ($d in Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.BusType -notin 'USB', 'SD', 'MMC', 'File Backed Virtual', 'Virtual' } | Sort-Object DeviceId) {
            $wear = $null; $hours = $null
            if ($a.IsAdmin) { try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop; $wear = $rc.Wear; $hours = $rc.PowerOnHours } catch { } }
            [pscustomobject]@{ Name = "$($d.FriendlyName)".Trim(); Size = [double]$d.Size; Media = "$($d.MediaType)"; Bus = "$($d.BusType)"; Health = "$($d.HealthStatus)"; Wear = $wear; Hours = $hours }
        }
    } catch { })
    $s.Gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name)".Trim() -replace '\((R|TM)\)', '' } |
        Where-Object { $_ -and $_ -notmatch '(?i)Microsoft Basic|Remote|Virtual|Parsec|DisplayLink|Mirage|Citrix' } | Select-Object -Unique)
    # The built-in screen's size (from the screen's own data) and resolution.
    $s.ScreenInch = $null
    try {
        $conn = @(Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams -ErrorAction Stop)
        $inner = @($conn | Where-Object { [uint32]$_.VideoOutputTechnology -in 6, 11, 13, 2147483648 } | ForEach-Object InstanceName)
        foreach ($p in Get-CimInstance -Namespace root\wmi WmiMonitorBasicDisplayParams -ErrorAction Stop) {
            if ($p.InstanceName -notin $inner -or -not $p.MaxHorizontalImageSize) { continue }
            $s.ScreenInch = [Math]::Round([Math]::Sqrt([Math]::Pow($p.MaxHorizontalImageSize, 2) + [Math]::Pow($p.MaxVerticalImageSize, 2)) / 2.54, 1)
        }
    } catch { }
    $scr = @([Windows.Forms.Screen]::AllScreens)
    $s.Resolution = if ($scr.Count -eq 1) { "$($scr[0].Bounds.Width) x $($scr[0].Bounds.Height)" } else { '' }
    # Battery: Windows' own battery report has the design and the current full capacity.
    $s.Battery = $null
    if (@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count) {
        $f = Join-Path $env:TEMP "pchandoff-battery-$PID.xml"
        $x = Invoke-Native "$env:windir\System32\powercfg.exe" "/batteryreport /xml /output `"$f`"" 60
        try {
            [xml]$r = Get-Content -LiteralPath $f -Raw -ErrorAction Stop
            $bat = @($r.BatteryReport.Batteries.Battery)[0]
            $design = [double]$bat.DesignCapacity; $full = [double]$bat.FullChargeCapacity
            if ($design -gt 0) { $s.Battery = [pscustomobject]@{ Health = [int][Math]::Min(100, [Math]::Round(100 * $full / $design)); Cycles = [int]$bat.CycleCount; Design = $design; Full = $full } }
        } catch { }
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }
    # Windows, and whether it can run Windows 11 (Windows keeps the result of its own upgrade check).
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $s.Win11 = [int]$cv.CurrentBuild -ge 22000
    $s.Windows = "$(if ($s.Win11) { "$($cv.ProductName)" -replace 'Windows 10', 'Windows 11' } else { $cv.ProductName }) $($cv.DisplayVersion)".Trim()
    $s.Win11Ready = $null
    if (-not $s.Win11) {
        foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators' -ErrorAction SilentlyContinue) {
            $red = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).RedReason
            if ($null -ne $red) { $s.Win11Ready = ("$red" -eq 'NONE') }
        }
    }
    [pscustomobject]$s
}

$script:Jobs = New-Object System.Collections.ArrayList
# -Label shows the job in the activity bar at the bottom of the window; -Cancellable adds a Cancel button.
# The Done block gets the results, and the job's state as a second argument ($State.Cancel says if it was stopped).
function Start-Bg([scriptblock]$Work, $Arg, [scriptblock]$Done, [string]$Label, [switch]$Cancellable) {
    $code = "param(`$BgArg)`n$Helpers`n& {`n$Work`n} `$BgArg"
    $state = [hashtable]::Synchronized(@{ Text = ''; Value = -1; Max = 0; Cancel = $false })
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('Job', $state)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($code).AddArgument($Arg)
    [void]$script:Jobs.Add(@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Done = $Done; Label = $Label; State = $state; Cancellable = [bool]$Cancellable })
    if ($activity) { Update-ActivityBar }
}
$JobTimer = New-Object Windows.Forms.Timer
$JobTimer.Interval = 250
$JobTimer.Add_Tick({
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        [void]$script:Jobs.Remove($j)
        $what = if ($j.Label) { $j.Label } else { 'a background check' }
        try { $result = @($j.PS.EndInvoke($j.Handle)) }
        catch {
            $result = @(); Write-AppError "$what (background)" $_
            if ((Show-Msg "Something went wrong:`n$($_.Exception.Message)`n`nReport this problem? (Opens GitHub with the details filled in - you see everything before you send it.)" 'YesNo' 'Warning') -eq 'Yes') { Open-ProblemReport 'bug' }
        }
        foreach ($e in @($j.PS.Streams.Error)) { Write-AppError "$what (background)" $e }
        $j.PS.Dispose(); $j.RS.Dispose()
        try { & $j.Done $result $j.State } catch { Write-AppError "$what (showing the result)" $_ }
    }
    if ($activity) { Update-ActivityBar }
})
$JobTimer.Start()

# ---------------------------------------------------------------------------
# Window, theme and layout helpers (the same look as PC Tune-Up)
# ---------------------------------------------------------------------------
function Rgb([int]$R, [int]$G, [int]$B) { [Drawing.Color]::FromArgb($R, $G, $B) }
$WindowsDark = (Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme') -eq 0
$Dark = switch ($Settings.Theme) { 'dark' { $true } 'light' { $false } default { $WindowsDark } }
$Theme = if (-not $Dark) {
    @{  Bg = (Rgb 255 255 255); Input = (Rgb 255 255 255); Side = (Rgb 243 244 246); Hover = (Rgb 229 231 235)
        Text = (Rgb 32 32 32); Dim = (Rgb 105 105 110); Border = (Rgb 206 209 214); Soft = (Rgb 246 247 249)
        Accent = (Rgb 0 120 110); AccentDark = (Rgb 0 98 90); AccentSoft = (Rgb 220 240 237); AccentText = (Rgb 0 110 100)
        WarnBg = (Rgb 255 245 219); WarnText = (Rgb 128 68 0)
        Bad = (Rgb 176 32 32); Warn = (Rgb 196 98 0); Good = (Rgb 20 120 50); Muted = (Rgb 130 130 135) }
} else {
    @{  Bg = (Rgb 32 32 34); Input = (Rgb 45 45 48); Side = (Rgb 43 43 46); Hover = (Rgb 58 58 62)
        Text = (Rgb 236 236 236); Dim = (Rgb 165 165 170); Border = (Rgb 82 82 88); Soft = (Rgb 44 44 48)
        Accent = (Rgb 0 128 116); AccentDark = (Rgb 0 106 96); AccentSoft = (Rgb 30 66 62); AccentText = (Rgb 100 215 200)
        WarnBg = (Rgb 64 50 22); WarnText = (Rgb 255 208 130)
        Bad = (Rgb 255 120 110); Warn = (Rgb 255 178 80); Good = (Rgb 110 205 135); Muted = (Rgb 140 140 146) }
}
function Set-DarkChrome($Control, [string]$ThemeName = 'DarkMode_Explorer') {
    if (-not $Dark) { return }
    try { [void][PcHandoff.Native]::SetWindowTheme($Control.Handle, $ThemeName, $null) } catch { }
}
$Font = New-Object Drawing.Font('Segoe UI', 9.75)
$FontBold = New-Object Drawing.Font('Segoe UI Semibold', 9.75)
$FontSmall = New-Object Drawing.Font('Segoe UI Semibold', 8.25)
$FontTitle = New-Object Drawing.Font('Segoe UI Semibold', 16)
$FontBig = New-Object Drawing.Font('Segoe UI Semibold', 13)
$form = New-Object Windows.Forms.Form
$form.Text = "PC Hand-off $AppVersion" + $(if ($IsAdmin) { '  (Administrator)' } else { '' })
$form.AutoScaleMode = 'None'
$form.ClientSize = New-Object Drawing.Size(1040, 680)
$form.StartPosition = 'CenterScreen'
$form.Font = $Font; $form.BackColor = $Theme.Bg; $form.ForeColor = $Theme.Text
$form.Add_HandleCreated({
    if ($Dark) { $on = 1; try { [void][PcHandoff.Native]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) } catch { } }   # 20 = dark title bar
})
if ($RunningAsExe) { try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($SelfExe) } catch { } }

$content = New-Object Windows.Forms.Panel
$content.Dock = 'Fill'; $content.BackColor = $Theme.Bg
$sidebar = New-Object Windows.Forms.Panel
$sidebar.Dock = 'Left'; $sidebar.Width = 196; $sidebar.BackColor = $Theme.Side
$form.Controls.Add($content); $form.Controls.Add($sidebar)
$script:Pages = New-Object System.Collections.ArrayList

function New-Page([string]$Title, [string]$IntroText) {
    $page = New-Object Windows.Forms.Panel
    $page.Name = $Title; $page.Text = $Title; $page.Dock = 'Fill'; $page.Visible = $false
    $page.Padding = New-Object Windows.Forms.Padding(26, 16, 26, 12); $page.BackColor = $Theme.Bg
    $content.Controls.Add($page)
    [void]$script:Pages.Add($page)
    $head = New-Object Windows.Forms.Panel
    $head.Dock = 'Top'; $head.Height = 80
    $t = New-Object Windows.Forms.Label
    $t.Text = $Title; $t.Font = $FontTitle; $t.Dock = 'Top'; $t.Height = 36
    $d = New-Object Windows.Forms.Label
    $d.Text = $IntroText; $d.ForeColor = $Theme.Dim; $d.Dock = 'Fill'
    $head.Controls.Add($d); $head.Controls.Add($t)
    $page.Tag = $head
    $page
}
# Docking is laid out last-added-first, so: Fill control, then bottom, then top controls from the lowest one upward.
function Set-PageLayout($Page, $Fill, [object[]]$Tops, $Bottom) {
    $n = 0; foreach ($t in $Tops) { $t.TabIndex = $n++ }; $Fill.TabIndex = $n++; if ($Bottom) { $Bottom.TabIndex = $n }
    if ($Fill -is [Windows.Forms.ListView]) { $Fill.AccessibleName = "$($Page.Name)"; $Fill.AccessibleDescription = $Page.Tag.Controls[0].Text }
    $Page.Controls.Add($Fill)
    if ($Bottom) { $Page.Controls.Add($Bottom) }
    [array]::Reverse($Tops)
    foreach ($t in $Tops) { $Page.Controls.Add($t) }
    $Page.Controls.Add($Page.Tag)
}
function New-ButtonBar([object[]]$Buttons) {
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'; $bar.WrapContents = $true
    $bar.Padding = New-Object Windows.Forms.Padding(0, 2, 0, 6)
    foreach ($b in $Buttons) { $bar.Controls.Add($b) }
    $bar
}
function New-Button([string]$Text) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.AutoSize = $true; $b.MinimumSize = New-Object Drawing.Size(0, 34)
    $b.Padding = New-Object Windows.Forms.Padding(10, 0, 10, 0); $b.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 6)
    $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.BackColor = $Theme.Bg; $b.ForeColor = $Theme.Text; $b.FlatAppearance.BorderColor = $Theme.Border; $b.FlatAppearance.MouseOverBackColor = $Theme.Soft
    $b.FlatAppearance.BorderSize = 0
    $b.Add_Paint({ param($sender, $e) Draw-Button $sender $e.Graphics })
    $b.Add_MouseEnter({ $script:HotButton = $this; $this.Invalidate() })
    $b.Add_MouseLeave({ if ($script:HotButton -eq $this) { $script:HotButton = $null }; $this.Invalidate() })
    $b
}
function New-RoundRect([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [single][Math]::Max([double]1, [Math]::Min([double]($R * 2), [Math]::Min([double]$W, [double]$H)))
    $p.AddArc($X, $Y, $d, $d, 180, 90); $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90); $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90); $p.CloseFigure()
    $p
}
function Draw-Button($B, $G) {
    $G.SmoothingMode = 'AntiAlias'
    $G.Clear($(if ($B.Parent) { $B.Parent.BackColor } else { $Theme.Bg }))
    $primary = $B.BackColor.ToArgb() -eq $Theme.Accent.ToArgb()
    $fill = if (-not $B.Enabled) { if ($primary) { $Theme.Soft } else { $B.BackColor } } elseif ($script:HotButton -eq $B) { $B.FlatAppearance.MouseOverBackColor } else { $B.BackColor }
    $path = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 6)
    $br = New-Object Drawing.SolidBrush($fill); $G.FillPath($br, $path); $br.Dispose()
    if (-not $primary -or -not $B.Enabled) { $pen = New-Object Drawing.Pen($(if ($script:HotButton -eq $B -and $B.Enabled) { $Theme.Dim } else { $Theme.Border })); $G.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
    $flags = [Windows.Forms.TextFormatFlags]'VerticalCenter, EndEllipsis'
    if ($B.TextAlign -in 'MiddleLeft', 'TopLeft', 'BottomLeft') { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::Left } else { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::HorizontalCenter }
    if ($B.Text -match "`n") { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::WordBreak }
    if (-not $B.UseMnemonic) { $flags = $flags -bor [Windows.Forms.TextFormatFlags]::NoPrefix }
    $r = if ($flags -band [Windows.Forms.TextFormatFlags]::HorizontalCenter) { New-Object Drawing.Rectangle(2, 0, ($B.Width - 4), $B.Height) }
         else { New-Object Drawing.Rectangle($B.Padding.Left, 0, ($B.Width - $B.Padding.Horizontal), $B.Height) }
    [Windows.Forms.TextRenderer]::DrawText($G, $B.Text, $B.Font, $r, $(if ($B.Enabled) { $B.ForeColor } else { $Theme.Muted }), $flags)
    if ($B.Focused -and $B.ShowFocusCues) {
        $fp = New-RoundRect 2.5 2.5 ($B.Width - 5.5) ($B.Height - 5.5) (Px 4)
        $pen = New-Object Drawing.Pen($(if ($primary) { [Drawing.Color]::White } else { $Theme.Accent }), 1); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose()
    }
}
function Set-Primary($Button) {
    $Button.Font = $FontBold; $Button.FlatAppearance.MouseOverBackColor = $Theme.AccentDark
    $Button.Add_EnabledChanged({ Update-PrimaryLook $this })
    Update-PrimaryLook $Button
}
function Update-PrimaryLook($Button) {
    if ($Button.Enabled) { $Button.BackColor = $Theme.Accent; $Button.ForeColor = [Drawing.Color]::White; $Button.FlatAppearance.BorderSize = 0 }
    else { $Button.BackColor = $Theme.Soft; $Button.ForeColor = $Theme.Dim; $Button.FlatAppearance.BorderSize = 1 }
}
$script:HotRows = @{}
function Set-HotRow($Lv, $Item) {
    $k = $Lv.GetHashCode(); $old = $script:HotRows[$k]
    if ($old -eq $Item) { return }
    foreach ($pair in @(@($old, $Theme.Bg), @($Item, $Theme.Hover))) {
        $it = $pair[0]; if (-not $it -or -not $it.ListView) { continue }
        $it.BackColor = $pair[1]; if (-not $it.UseItemStyleForSubItems) { foreach ($si in $it.SubItems) { $si.BackColor = $pair[1] } }
    }
    $script:HotRows[$k] = $Item
}
# The status column shows a coloured dot and word; the rest of the row stays easy to read.
function Set-RowStatus($Item, [int]$Col, [string]$Text, $Color) {
    $Item.UseItemStyleForSubItems = $false
    foreach ($si in $Item.SubItems) { $si.ForeColor = $Theme.Text }
    $si = $Item.SubItems[$Col]
    if ($Color.ToArgb() -eq $Theme.Muted.ToArgb()) { $si.Text = T $Text; foreach ($s in $Item.SubItems) { $s.ForeColor = $Theme.Muted }; return }
    $si.Text = "$([char]0x25CF)  $(T $Text)"; $si.ForeColor = $Color
}
function New-ListView([bool]$Checks, [object[]]$Columns) {
    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $Checks; $lv.Dock = 'Fill'; $lv.ShowItemToolTips = $true
    $lv.BorderStyle = 'None'; $lv.HeaderStyle = 'Nonclickable'; $lv.BackColor = $Theme.Bg; $lv.ForeColor = $Theme.Text
    $rows = New-Object Windows.Forms.ImageList; $rows.ImageSize = New-Object Drawing.Size(1, (Px 28))   # taller rows
    $lv.Add_MouseMove({ Set-HotRow $this ($this.GetItemAt($_.X, $_.Y)) })
    $lv.Add_MouseLeave({ Set-HotRow $this $null })
    $lv.SmallImageList = $rows
    for ($i = 0; $i -lt $Columns.Count; $i += 2) { [void]$lv.Columns.Add($Columns[$i], (Px $Columns[$i + 1])) }
    if ($Dark) {   # the native header ignores colours, so draw it; rows still draw themselves
        $lv.OwnerDraw = $true
        $lv.Add_DrawColumnHeader({
            param($sender, $e)
            $fillR = $e.Bounds
            if ($e.ColumnIndex -eq $sender.Columns.Count - 1) { $fillR = New-Object Drawing.Rectangle($e.Bounds.X, $e.Bounds.Y, [Math]::Max($e.Bounds.Width, $sender.Width - $e.Bounds.X), $e.Bounds.Height) }
            $brush = New-Object Drawing.SolidBrush($Theme.Side); $e.Graphics.FillRectangle($brush, $fillR); $brush.Dispose()
            $r = $e.Bounds; $r.X += (Px 5); $r.Width -= (Px 5)
            [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $sender.Font, $r, $Theme.Dim, 'VerticalCenter, Left, EndEllipsis')
        })
        $lv.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
        $lv.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })
    }
    $lv.Add_HandleCreated({
        Set-DarkChrome $this
        $header = [PcHandoff.Native]::SendMessage($this.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero)   # LVM_GETHEADER
        if ($Dark -and $header -ne [IntPtr]::Zero) { try { [void][PcHandoff.Native]::SetWindowTheme($header, 'DarkMode_ItemsView', $null) } catch { } }
    })
    $lv.Tag = @($lv.Columns | ForEach-Object Width)   # designed widths
    $lv.Add_Resize({ Resize-LastColumn $this })
    $lv
}
# Let the last column take the remaining width, so lists never scroll sideways.
function Resize-LastColumn($Lv) {
    $n = $Lv.Columns.Count
    if ($n -lt 2) { return }
    $avail = $Lv.ClientSize.Width - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2
    $design = @($Lv.Tag)
    $fixed = 0; for ($i = 0; $i -lt $n - 1; $i++) { $fixed += $design[$i] }
    $scale = [Math]::Min(1.0, [Math]::Max(0.3, ($avail - 160) / [Math]::Max(1, $fixed)))
    $used = 0
    for ($i = 0; $i -lt $n - 1; $i++) { $w = [int]($design[$i] * $scale); $Lv.Columns[$i].Width = $w; $used += $w }
    $Lv.Columns[$n - 1].Width = [Math]::Max(120, $avail - $used)
}
function New-Status {
    $l = New-Object Windows.Forms.Label
    $l.Dock = 'Bottom'; $l.Height = 32; $l.TextAlign = 'BottomLeft'; $l.ForeColor = $Theme.Dim; $l.AutoEllipsis = $true
    $l
}
# A coloured note above a list (where things are saved, what was found); grows to fit its text.
function New-Note {
    $l = New-Object Windows.Forms.Label
    $l.Dock = 'Top'; $l.Height = 0; $l.BackColor = $Theme.AccentSoft; $l.ForeColor = $Theme.Text
    $l.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 8)
    $l.Add_TextChanged({ Resize-Note $this }); $l.Add_Resize({ Resize-Note $this })
    $l
}
function Resize-Note($L) {
    if (-not $L.Text) { if ($L.Height) { $L.Height = 0 }; return }
    $sz = [Windows.Forms.TextRenderer]::MeasureText($L.Text, $L.Font, (New-Object Drawing.Size(($L.Width - $L.Padding.Horizontal), 0)), 'WordBreak')
    $h = $sz.Height + $L.Padding.Vertical + 2
    if ($L.Height -ne $h) { $L.Height = $h }
}
function New-Check([string]$Text, [bool]$Checked) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $Text; $c.Checked = $Checked; $c.AutoSize = $true; $c.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 0)
    $c
}
function Add-Row($Lv, [object[]]$Cells, $Tag = $null, [bool]$Checked = $false) {
    $it = New-Object Windows.Forms.ListViewItem((T ([string]$Cells[0])))
    foreach ($c in $Cells[1..($Cells.Count - 1)]) { [void]$it.SubItems.Add((T ([string]$c))) }
    $it.Tag = $Tag; $it.Checked = $Checked
    [void]$Lv.Items.Add($it)
    $it
}

# ===========================================================================
# 1. Start
# ===========================================================================
$pgStart = New-Page 'Start' 'PC Hand-off gets your old PC ready to sell, give away or recycle: nothing of yours left behind, no accounts still signed in, and a clean drive.'
$startFlow = New-Object Windows.Forms.FlowLayoutPanel
$startFlow.Dock = 'Fill'; $startFlow.FlowDirection = 'TopDown'; $startFlow.WrapContents = $false; $startFlow.AutoScroll = $true
$startTiles = New-Object Windows.Forms.FlowLayoutPanel
$startTiles.AutoSize = $true; $startTiles.WrapContents = $true; $startTiles.MaximumSize = New-Object Drawing.Size(700, 0); $startTiles.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 10)
# A big choice button: a title in a large font, an explanation under it. The first line of Text is the title.
function New-Tile([string]$Text, [bool]$Primary) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text; $b.Size = New-Object Drawing.Size(330, 104); $b.Margin = New-Object Windows.Forms.Padding(0, 0, 14, 8)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.UseVisualStyleBackColor = $false; $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.Tag = $Primary
    $b.Add_Paint({ param($s, $e) Draw-Tile $s $e.Graphics })
    $b.Add_MouseEnter({ $script:HotButton = $this; $this.Invalidate() })
    $b.Add_MouseLeave({ if ($script:HotButton -eq $this) { $script:HotButton = $null }; $this.Invalidate() })
    $b
}
function Draw-Tile($B, $G) {
    $G.SmoothingMode = 'AntiAlias'; $G.Clear($B.Parent.BackColor)
    $hot = $script:HotButton -eq $B
    $fill = if ($B.Tag) { if ($hot) { $Theme.AccentDark } else { $Theme.Accent } } elseif ($hot) { $Theme.Soft } else { $Theme.Bg }
    $path = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 8)
    $br = New-Object Drawing.SolidBrush($fill); $G.FillPath($br, $path); $br.Dispose()
    if (-not $B.Tag) { $pen = New-Object Drawing.Pen($(if ($hot) { $Theme.Dim } else { $Theme.Border })); $G.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
    $title, $sub = "$($B.Text)" -split "`r?`n", 2
    $fg = if ($B.Tag) { [Drawing.Color]::White } else { $Theme.Text }
    $pad = Px 20
    $th = [Windows.Forms.TextRenderer]::MeasureText($title, $FontBig).Height
    $sh = [Windows.Forms.TextRenderer]::MeasureText($sub, $Font, (New-Object Drawing.Size(($B.Width - 2 * $pad), 0)), 'WordBreak').Height
    $y = [int](($B.Height - $th - (Px 4) - $sh) / 2)
    [Windows.Forms.TextRenderer]::DrawText($G, $title, $FontBig, (New-Object Drawing.Rectangle($pad, $y, ($B.Width - 2 * $pad), $th)), $fg, 'Left, NoPrefix')
    [Windows.Forms.TextRenderer]::DrawText($G, $sub, $Font, (New-Object Drawing.Rectangle($pad, ($y + $th + (Px 4)), ($B.Width - 2 * $pad), $sh)), $(if ($B.Tag) { [Drawing.Color]::FromArgb(225, 255, 255, 255) } else { $Theme.Dim }), 'Left, WordBreak, NoPrefix')
    if ($B.Focused -and $B.ShowFocusCues) { $fp = New-RoundRect 3.5 3.5 ($B.Width - 7.5) ($B.Height - 7.5) (Px 6); $pen = New-Object Drawing.Pen($fg); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose() }
}
$tileCheck = New-Tile "1. Check`nLooking at this PC..." $true
$tileSign = New-Tile "2. Sign out`nLicences and devices tied to this PC." $false
$tileBuyer = New-Tile "3. For the buyer`nThe specs, ready for your ad or the new owner." $false
$tileWipe = New-Tile "4. Wipe`nWindows' own reset, explained step by step." $false
$startTiles.Controls.AddRange(@($tileCheck, $tileSign, $tileBuyer, $tileWipe))
$startNote = New-Object Windows.Forms.Label
$startNote.AutoSize = $true; $startNote.MaximumSize = New-Object Drawing.Size(680, 0); $startNote.ForeColor = $Theme.Dim; $startNote.Margin = New-Object Windows.Forms.Padding(0, 10, 0, 0)
$startNote.Text = "PC Hand-off only looks and opens the right places: nothing on this PC changes until you start the reset yourself. Nothing is sent anywhere.`n`nMoving to a new PC? Take your programs, files and settings along with PC Move first."
$lnkMove = New-Object Windows.Forms.LinkLabel
$lnkMove.Text = 'Get PC Move'; $lnkMove.AutoSize = $true; $lnkMove.LinkColor = $Theme.AccentText; $lnkMove.ActiveLinkColor = $Theme.AccentText
$lnkMove.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 0)
$lnkMove.Add_LinkClicked({ Open-PcMove })
$startFlow.Controls.AddRange(@($startTiles, $startNote, $lnkMove))
Set-PageLayout $pgStart $startFlow @()
$tileCheck.Add_Click({ Show-Page $pgCheck })
$tileSign.Add_Click({ Show-Page $pgSign })
$tileBuyer.Add_Click({ Show-Page $pgBuyer })
$tileWipe.Add_Click({ Show-Page $pgWipe })
function Open-PcMove { if (Test-Path -LiteralPath $PcMoveExe) { Start-Process $PcMoveExe } else { Start-Process $PcMoveUrl } }
# The tiles say how far you are; the first step that still has something open is the coloured one.
function Update-StartTiles {
    $checkLeft = Get-CheckLeft; $signLeft = Get-StepsLeft
    $tileCheck.Text = "1. Check`n" + $(if (-not $script:CheckResult) { 'Looking at this PC...' } elseif ($checkLeft) { "$checkLeft thing(s) to look at before you wipe." } else { 'Nothing left behind - all done.' })
    $tileSign.Text = "2. Sign out`n" + $(if ($null -eq $script:Steps) { 'Licences and devices tied to this PC.' } elseif ($signLeft) { "$signLeft step(s) left." } else { 'All signed out - all done.' })
    $first = if (-not $script:CheckResult -or $checkLeft) { $tileCheck } elseif ($signLeft) { $tileSign } else { $tileWipe }
    foreach ($t in $tileCheck, $tileSign, $tileBuyer, $tileWipe) { $t.Tag = ($t -eq $first); $t.Invalidate() }
    Update-WipeNote
}

# ===========================================================================
# 2. Check: is everything of yours somewhere else?
# ===========================================================================
$pgCheck = New-Page 'Check' 'What the reset would wipe that may not be anywhere else yet. Click a row and Open to take care of it, then tick it. Green rows are fine.'
$btnCheckDo = New-Button 'Open'
$btnCheckAgain = New-Button 'Look again'
$lblCheckNote = New-Note
$lvCheck = New-ListView $true @('What', 230, 'Status', 260, 'Details', 300)
$lblCheck = New-Status
Set-PageLayout $pgCheck $lvCheck @((New-ButtonBar @($btnCheckDo, $btnCheckAgain)), $lblCheckNote) $lblCheck
function Get-Done { if (Test-Path $StepsFile) { try { @(Get-Content $StepsFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { @() } } else { @() } }
function Save-Done([string]$Id, [bool]$On) {
    $list = @(Get-Done | Where-Object { $_ -ne $Id })
    if ($On) { $list += $Id }
    ConvertTo-Json @($list) | Set-Content $StepsFile -Encoding UTF8
}
function Start-Check {
    if ($script:Jobs | Where-Object { $_.Label -eq 'Looking at this PC' }) { return }
    $script:CheckResult = $null
    $btnCheckAgain.Enabled = $false
    $lblCheck.Text = 'Looking at this PC...'
    $roots = @(foreach ($d in [IO.DriveInfo]::GetDrives()) { try { if ($d.IsReady -and $d.DriveType -in 'Removable', 'Fixed' -and $d.Name -ne "$env:SystemDrive\") { $d.RootDirectory.FullName } } catch { } })
    $arg = @{ Roots = $roots; Folders = @(Get-PersonalFolders); SystemDrive = $env:SystemDrive; Profile = $env:USERPROFILE; KnownRx = $RootKnownRx
              MailDirs = @((Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook')); Browsers = $ChromiumBrowsers }   # Outlook files in Documents go along with Documents
    $script:BitLocker = Get-BitLockerState $env:SystemDrive
    $script:MsAccount = Test-MicrosoftAccount
    Start-Bg -Label 'Looking at this PC' -Cancellable $CheckWork $arg {
        param($res, $state)
        $btnCheckAgain.Enabled = $true
        $script:CheckResult = @($res)[0]
        Show-Check
        Update-Steps
    }
}
function Show-Check {
    $r = $script:CheckResult
    if (-not $r) { return }
    $done = @{}; foreach ($k in @(Get-Done)) { $done["$k"] = $true }
    $rows = @()
    # Id, What, Status, Details, Ok, Do
    $b = $r.Bundle
    if ($b) { $rows += @{ Id = 'bundle'; What = 'PC Move folder'; Status = "made $($b.When.ToString('d MMMM yyyy'))"; Details = $b.Dir; Ok = $true; Do = @{ Type = 'Select'; Path = $b.Dir } } }
    foreach ($f in $r.Folders) {
        $row = @{ Id = "folder|$($f.Key)"; What = $f.Name; Do = @{ Type = 'Folder'; Path = $f.Path } }
        if ($f.OneDrive) { $row.Status = 'in OneDrive'; $row.Details = 'Comes back when you sign in to OneDrive on another PC.'; $row.Ok = $true }
        elseif (-not $f.Files) { continue }
        elseif ($f.InBundle -and -not $f.Newer) { $row.Status = 'packed up with PC Move'; $row.Details = "$($f.Files) file(s), $(Format-Size $f.Bytes) - nothing changed since."; $row.Ok = $true }
        elseif ($f.InBundle) { $row.Status = "$($f.Newer) file(s) changed since PC Move"; $row.Details = 'Pack up again with PC Move, or copy these files yourself.'; $row.Ok = $false; $row.Do = @{ Type = 'PcMove' } }
        else { $row.Status = 'only on this PC'; $row.Details = "$($f.Files) file(s), $(Format-Size $f.Bytes). Take them along with PC Move, or copy them to a USB drive."; $row.Ok = $false; $row.Do = @{ Type = 'PcMove' } }
        $rows += $row
    }
    foreach ($p in $r.Pst) { $rows += @{ Id = "pst|$($p.Path)"; What = 'Outlook mail file'; Status = 'only on this PC'; Details = "$(Split-Path $p.Path -Leaf), $(Format-Size $p.Bytes). Close Outlook, then copy it to a USB drive."; Ok = $false; Do = @{ Type = 'Select'; Path = $p.Path } } }
    if ($r.Thunderbird -gt 1MB) { $rows += @{ Id = 'thunderbird'; What = 'Thunderbird mail'; Status = 'kept on this PC'; Details = "$(Format-Size $r.Thunderbird). Mail in an IMAP account is also on the server; other mail is only here. Copy the profile folder to keep it."; Ok = $false; Do = @{ Type = 'Folder'; Path = (Join-Path $env:APPDATA 'Thunderbird\Profiles') } } }
    foreach ($o in $r.Own) { $rows += @{ Id = "own|$($o.Path)"; What = "Folder $($o.Path)"; Status = 'outside your personal folders'; Details = "$($o.Files) file(s), $(Format-Size $o.Bytes). PC Move does not take this folder - copy it yourself if you need it."; Ok = $false; Do = @{ Type = 'Folder'; Path = $o.Path } } }
    foreach ($d in $r.Drives) {
        $name = if ($d.Label) { "Drive $($d.Name) ($($d.Label))" } else { "Drive $($d.Name)" }
        $rows += @{ Id = "drive|$($d.Name)"; What = $name; Status = "$(Format-Size $d.Used) in use"; Details = 'A second drive in this PC. The reset only clears it if you turn on "Delete files from all drives".'; Ok = $false; Do = @{ Type = 'Folder'; Path = "$($d.Name)\" } }
    }
    if ($r.Others) { $rows += @{ Id = 'others'; What = 'Other accounts on this PC'; Status = "$(@($r.Others) -join ', ')"; Details = 'Their files are wiped too. Ask them to save what they need.'; Ok = $false; Do = @{ Type = 'Url'; Url = 'ms-settings:otherusers' } } }
    foreach ($bw in $r.Browsers) {
        $what = if ($bw.Profile) { "$($bw.Browser) ($($bw.Profile))" } else { $bw.Browser }
        if ($bw.Account) { $rows += @{ Id = "browser|$($bw.Browser)|$($bw.Profile)"; What = $what; Status = 'signed in'; Details = "As $($bw.Account): bookmarks and passwords come back when you sign in on another PC."; Ok = $true; Do = @{ Type = 'Browser'; Browser = $bw.Browser } } }
        else { $rows += @{ Id = "browser|$($bw.Browser)|$($bw.Profile)"; What = $what; Status = 'not signed in'; Details = 'Its bookmarks and saved passwords are only on this PC. Sign in to the browser, or export the passwords (PC Move takes the bookmarks).'; Ok = $false; Do = @{ Type = 'Browser'; Browser = $bw.Browser } } }
    }
    if ($script:BitLocker -eq 'on') { $rows += @{ Id = 'bitlocker'; What = 'Drive encryption (BitLocker)'; Status = 'on'; Details = 'Have your recovery key at hand: the reset may ask for it. It is in your Microsoft account.'; Ok = $false; Do = @{ Type = 'Url'; Url = 'https://aka.ms/myrecoverykey' } } }
    elseif ($script:BitLocker -eq 'off') { $rows += @{ Id = 'bitlocker'; What = 'Drive encryption (BitLocker)'; Status = 'off'; Details = 'No recovery key needed. Turn on "Clean data" in the reset, so deleted files cannot be recovered.'; Ok = $true; Do = @{ Type = 'Show'; Text = 'No recovery key needed. Turn on "Clean data" in the reset, so deleted files cannot be recovered.' } } }
    $l = $r.Licence
    if ($l) {
        if ($l.Activated -and $l.Firmware) { $rows += @{ Id = 'licence'; What = 'Windows licence'; Status = 'built into this PC'; Details = 'Windows activates by itself after the reset - the next owner keeps it.'; Ok = $true; Do = @{ Type = 'Url'; Url = 'ms-settings:activation' } } }
        elseif ($l.Activated) { $rows += @{ Id = 'licence'; What = 'Windows licence'; Status = 'activated'; Details = "Licence type: $($l.Channel). Windows usually activates again by itself after the reset; check it before you hand the PC over."; Ok = $true; Do = @{ Type = 'Url'; Url = 'ms-settings:activation' } } }
        else { $rows += @{ Id = 'licence'; What = 'Windows licence'; Status = 'not activated'; Details = 'Tell the buyer: Windows on this PC is not activated.'; Ok = $false; Do = @{ Type = 'Url'; Url = 'ms-settings:activation' } } }
    }
    $script:CheckRows = @($rows | Sort-Object { [int]$_.Ok })
    $script:CheckLoading = $true
    $lvCheck.BeginUpdate(); $lvCheck.Items.Clear()
    foreach ($row in $script:CheckRows) {
        $row.Done = [bool]$done["check|$($row.Id)"]
        $it = Add-Row $lvCheck @($row.What, '', $row.Details) $row ($row.Ok -or $row.Done)
        $it.ToolTipText = T $row.Details
        if ($row.Ok) { Set-RowStatus $it 1 $row.Status $Theme.Good }
        elseif ($row.Done) { Set-RowStatus $it 1 $row.Status $Theme.Muted }
        else { Set-RowStatus $it 1 $row.Status $Theme.Warn }
    }
    $lvCheck.EndUpdate()
    $script:CheckLoading = $false
    $lblCheckNote.Text = if ($r.Cancelled) { 'Stopped before the end - click Look again to finish.' } elseif ($b) { '' } else { 'No PC Move folder from this PC was found. Plug in the drive you packed up to, then click Look again - or move your files with PC Move first.' }
    Update-CheckStatus
}
# Counted from the rows themselves, not the list: while Windows creates the list it sends every tick again, half-done.
function Get-CheckLeft { @($script:CheckRows | Where-Object { -not $_.Ok -and -not $_.Done }).Count }
function Update-CheckStatus {
    $left = Get-CheckLeft
    $lblCheck.Text = if (-not $script:CheckResult) { 'Looking at this PC...' } elseif ($left) { "$left thing(s) to look at. Tick a row when it is taken care of." } else { 'Nothing left behind. Next: Sign out.' }
    Set-NavBadge 'Check' $left
    Update-StartTiles
}
$lvCheck.Add_ItemCheck({
    if ($script:CheckLoading) { return }
    $row = $lvCheck.Items[$_.Index].Tag
    if ($row.Ok) { $_.NewValue = 'Checked'; return }   # green rows stay ticked
})
$lvCheck.Add_ItemChecked({
    if ($script:CheckLoading) { return }
    $it = $_.Item; $row = $it.Tag
    if ($row.Ok -or [bool]$row.Done -eq $it.Checked) { return }
    $row.Done = $it.Checked
    Save-Done "check|$($row.Id)" $it.Checked
    Set-RowStatus $it 1 $row.Status $(if ($it.Checked) { $Theme.Muted } else { $Theme.Warn })
    Update-CheckStatus
})
function Invoke-Do($Do) {
    switch ($Do.Type) {
        'Folder' { if (Test-Path -LiteralPath $Do.Path) { Start-Process explorer.exe "`"$($Do.Path)`"" } }
        'Select' { Start-Process explorer.exe "/select,`"$($Do.Path)`"" }
        'PcMove' { Open-PcMove }
        'Url' { Start-Process $Do.Url }
        'Show' { Show-Msg $Do.Text | Out-Null }
        'Browser' {
            $exe = @($BrowserExe[$Do.Browser] | Where-Object { Test-Path -LiteralPath $_ })[0]
            if (-not $exe) { Show-Msg "$($Do.Browser) is not installed in the usual place. Open it yourself." | Out-Null }
            elseif ($BrowserPasswords[$Do.Browser]) { Start-Process $exe $BrowserPasswords[$Do.Browser] }
            else { Start-Process $exe }
        }
    }
}
$btnCheckDo.Add_Click({ $it = @($lvCheck.SelectedItems)[0]; if ($it) { Invoke-Do $it.Tag.Do } else { Show-Msg 'Click a row in the list first.' | Out-Null } })
$lvCheck.Add_DoubleClick({ $it = @($lvCheck.SelectedItems)[0]; if ($it) { Invoke-Do $it.Tag.Do } })
$btnCheckAgain.Add_Click({ Start-Check })

# ===========================================================================
# 3. Sign out: licences and devices tied to this PC
# ===========================================================================
$pgSign = New-Page 'Sign out' 'Some programs count this PC against a limit, or stay linked to your accounts after a reset. Free them now. Click a step and Open, then tick it.'
$btnStepDo = New-Button 'Open'
$lvSign = New-ListView $true @('Step', 330, 'How', 460)
$lblSign = New-Status
Set-PageLayout $pgSign $lvSign @((New-ButtonBar @($btnStepDo))) $lblSign
function Get-SignSteps {
    $r = $script:CheckResult
    if (-not $r) { return }
    $items = @()
    foreach ($s in $ServiceCatalog) {
        $found = @()
        if ($s.Match) { $found += @($r.Programs | Where-Object { $_ -match $s.Match } | ForEach-Object { [regex]::Match($_, $s.Match).Value.Trim() }) }
        if ($s.Appx -and @($r.Appx | Where-Object { $_ -match $s.Appx })) { $found += 'app' }
        if (-not $found) { continue }
        if ($s.Text -match '\{0\}') {
            foreach ($name in $found | Where-Object { $_ -ne 'app' } | Select-Object -Unique) {
                $url = if ($s.Id -eq 'av') { $AccountUrls[$name] } else { $null }
                $items += @{ Id = "$($s.Id)|$name"; Text = ($s.Text -replace '\{0\}', $name); Why = $s.Why; Url = $url; Search = "$name sign out deactivate computer" }
            }
        } else { $items += @{ Id = $s.Id; Text = $s.Text; Why = $s.Why; Url = $s.Url } }
    }
    $items += @{ Id = 'other'; Text = 'Anything else with a licence or "deactivate" in its menu'; Why = 'For example tax software, photo and music software, or a VPN. Look through the Start menu.'; Url = 'ms-settings:appsfeatures' }
    if ($script:MsAccount) { $items += @{ Id = 'msaccount'; Text = 'Last, after the reset: remove this PC from your Microsoft account'; Why = 'At account.microsoft.com/devices: choose this PC, then Remove device. This also takes it out of Find my device.'; Url = 'https://account.microsoft.com/devices' } }
    $items
}
function Update-Steps {
    $done = @{}; foreach ($k in @(Get-Done)) { $done["$k"] = $true }
    $script:Steps = @(Get-SignSteps)
    $script:SignLoading = $true
    $lvSign.BeginUpdate(); $lvSign.Items.Clear()
    foreach ($s in $script:Steps) {
        $s.Done = [bool]$done["sign|$($s.Id)"]
        $it = Add-Row $lvSign @($s.Text, $s.Why) $s $s.Done
        $it.ToolTipText = T $s.Why
        if ($s.Done) { $it.ForeColor = $Theme.Muted }
    }
    $lvSign.EndUpdate()
    $script:SignLoading = $false
    if (-not $script:CheckResult) { $script:Steps = $null }
    Update-SignStatus
}
function Get-StepsLeft { @($script:Steps | Where-Object { $_ -and -not $_.Done }).Count }
function Update-SignStatus {
    $left = Get-StepsLeft
    $lblSign.Text = if (-not $script:CheckResult) { 'Looking at this PC...' } elseif ($left) { "$left step(s) left." } else { 'All signed out. Next: For the buyer, then Wipe.' }
    Set-NavBadge 'Sign out' $left
    Update-StartTiles
}
$lvSign.Add_ItemChecked({
    if ($script:SignLoading -or [bool]$_.Item.Tag.Done -eq $_.Item.Checked) { return }
    $_.Item.Tag.Done = $_.Item.Checked
    Save-Done "sign|$($_.Item.Tag.Id)" $_.Item.Checked
    $_.Item.ForeColor = if ($_.Item.Checked) { $Theme.Muted } else { $Theme.Text }
    Update-SignStatus
})
function Invoke-Step($S) {
    if ($S.Url) { Start-Process $S.Url }
    elseif ($S.Search) { Start-Process "https://www.bing.com/search?q=$([uri]::EscapeDataString($S.Search))" }
    else { Show-Msg "$($S.Text)`n`n$($S.Why)" | Out-Null }
}
$btnStepDo.Add_Click({ $it = @($lvSign.SelectedItems)[0]; if ($it) { Invoke-Step $it.Tag } else { Show-Msg 'Click a step in the list first.' | Out-Null } })
$lvSign.Add_DoubleClick({ $it = @($lvSign.SelectedItems)[0]; if ($it) { Invoke-Step $it.Tag } })

# ===========================================================================
# 4. For the buyer: the specs, to copy into an ad or give to the new owner
# ===========================================================================
$pgBuyer = New-Page 'For the buyer' 'What is in this PC, in plain words - for your ad, or to give to the new owner. You can change the text before you copy or save it.'
$btnSpecCopy = New-Button 'Copy'
$btnSpecSave = New-Button 'Save as...'
$chkSerial = New-Check 'Include the serial number' $false
$chkSerial.Margin = New-Object Windows.Forms.Padding(4, 8, 0, 0)
$txtSpec = New-Object Windows.Forms.TextBox
$txtSpec.Multiline = $true; $txtSpec.ScrollBars = 'Vertical'; $txtSpec.Dock = 'Fill'; $txtSpec.BorderStyle = 'FixedSingle'
$txtSpec.Font = New-Object Drawing.Font('Consolas', 10); $txtSpec.BackColor = $Theme.Input; $txtSpec.ForeColor = $Theme.Text
$txtSpec.Add_HandleCreated({ Set-DarkChrome $this })
$lblSpec = New-Status
Set-PageLayout $pgBuyer $txtSpec @((New-ButtonBar @($btnSpecCopy, $btnSpecSave, $chkSerial))) $lblSpec
function Start-Specs {
    $btnSpecCopy.Enabled = $false; $btnSpecSave.Enabled = $false
    $txtSpec.Text = ''
    $lblSpec.Text = 'Looking at the hardware...'
    Start-Bg -Label 'Reading the specs' $SpecWork @{ IsAdmin = $IsAdmin } {
        param($res)
        $script:Spec = @($res)[0]
        $btnSpecCopy.Enabled = $true; $btnSpecSave.Enabled = $true
        Show-Specs
    }
}
# The sheet, in the app's language. Each line is "Label: value".
function Format-Specs($S, [bool]$Serial) {
    $lines = New-Object Collections.Generic.List[string]
    $add = { param($label, $value) if ("$value".Trim()) { $lines.Add("$((T $label) + ':') $value") } }
    $title = if ($S.Kind) { "$($S.Pc) - $(T $S.Kind)" } else { $S.Pc }
    $lines.Add($title); $lines.Add('=' * [Math]::Min(60, $title.Length)); $lines.Add('')
    & $add 'Processor' $(if ($S.Cores) { "$($S.Cpu) ($(T "$($S.Cores) cores, $($S.Threads) threads"))" } else { $S.Cpu })
    $ram = "$([Math]::Round($S.RamBytes / 1GB)) GB" + $(if ($S.RamType) { " $($S.RamType)" }) + $(if ($S.RamSpeed) { " $($S.RamSpeed) MT/s" })
    if ($S.Slots -gt 0 -and $S.SlotsUsed -gt 0) { $ram += " ($(T "$($S.SlotsUsed) of $($S.Slots) slots used"))" }
    & $add 'Memory' $ram
    foreach ($d in $S.Disks) {
        $kind = if ($d.Bus -eq 'NVMe') { 'NVMe SSD' } elseif ($d.Media -eq 'SSD') { 'SSD' } elseif ($d.Media -eq 'HDD') { T 'hard disk' } else { '' }
        $size = if ($d.Size -ge 1e12) { '{0:N1} TB' -f ($d.Size / 1e12) } else { '{0:N0} GB' -f ($d.Size / 1e9) }   # as printed on the box
        $v = "$size $kind ($($d.Name))" -replace '\s+', ' '
        $health = @()
        if ($d.Health -and $d.Health -ne 'Healthy') { $health += T "health: $($d.Health)" }
        elseif ($d.Health) { $health += T 'healthy' }
        if ($null -ne $d.Wear) { $health += T "$(100 - [int]$d.Wear)% life left" }
        if ($d.Hours) { $health += T "$('{0:N0}' -f $d.Hours) hours in use" }
        if ($health) { $v += ", $($health -join ', ')" }
        & $add 'Storage' $v
    }
    & $add 'Graphics' ($S.Gpu -join ', ')
    $scr = @(); if ($S.ScreenInch) { $scr += "$($S.ScreenInch.ToString('0.#'))""" }; if ($S.Resolution) { $scr += $S.Resolution }
    & $add 'Screen' ($scr -join ', ')
    if ($S.Battery) { & $add 'Battery' $(if ($S.Battery.Cycles) { T "$($S.Battery.Health)% of its original capacity, $($S.Battery.Cycles) charge cycles" } else { T "$($S.Battery.Health)% of its original capacity" }) }
    & $add 'Windows' $S.Windows
    $l = if ($script:CheckResult) { $script:CheckResult.Licence } else { $null }
    if ($l -and $l.Activated) { & $add 'Licence' $(if ($l.Firmware) { T 'built into this PC (activates by itself)' } else { T 'activated' }) }
    if (-not $S.Win11 -and $null -ne $S.Win11Ready) { & $add 'Windows 11' $(if ($S.Win11Ready) { T 'can be upgraded for free' } else { T 'not supported on this PC' }) }
    if ($Serial -and $S.Serial -and $S.Serial -notmatch '(?i)^(default|to be filled|system serial|0+)') { & $add 'Serial number' $S.Serial }
    $lines.Add('')
    $lines.Add((T 'Wiped with Windows'' own reset ("Remove everything").'))
    $lines -join "`r`n"
}
function Show-Specs {
    if (-not $script:Spec) { return }
    $txtSpec.Text = Format-Specs $script:Spec $chkSerial.Checked
    $lblSpec.Text = if ($IsAdmin) { 'Ready. Copy it, or save it to a USB drive (the reset wipes this PC''s desktop too).' } else { 'Ready. Run as administrator to add how worn the drive is.' }
}
$chkSerial.Add_CheckedChanged({ Show-Specs })
$btnSpecCopy.Add_Click({ if ($txtSpec.Text) { [Windows.Forms.Clipboard]::SetText($txtSpec.Text); $lblSpec.Text = 'Copied. Paste it into your ad or an e-mail.' } })
$btnSpecSave.Add_Click({
    $dlg = New-Object Windows.Forms.SaveFileDialog
    $dlg.Filter = "$(T 'Text file') (*.txt)|*.txt"
    $dlg.FileName = ("$(T 'PC for sale') - $($script:Spec.Pc).txt" -replace '[\\/:*?"<>|]', '')
    $usb = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Removable' })[0]
    $dlg.InitialDirectory = if ($usb) { $usb.RootDirectory.FullName } else { [Environment]::GetFolderPath('MyDocuments') }
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    try { [IO.File]::WriteAllText($dlg.FileName, $txtSpec.Text, (New-Object Text.UTF8Encoding($true))); $lblSpec.Text = "Saved: $($dlg.FileName)" }
    catch { Show-Msg "Couldn't save: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null }
})

# ===========================================================================
# 5. Wipe: Windows' own reset, explained
# ===========================================================================
$pgWipe = New-Page 'Wipe' 'Windows'' own reset puts Windows back as new and removes everything of yours. PC Hand-off starts it and tells you what to choose.'
$wipeFlow = New-Object Windows.Forms.FlowLayoutPanel
$wipeFlow.Dock = 'Fill'; $wipeFlow.FlowDirection = 'TopDown'; $wipeFlow.WrapContents = $false; $wipeFlow.AutoScroll = $true
$lblWipeOpen = New-Note
$lblWipeOpen.Dock = 'None'; $lblWipeOpen.Width = 680; $lblWipeOpen.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
$wipeHow = New-Object Windows.Forms.Label
$wipeHow.AutoSize = $true; $wipeHow.MaximumSize = New-Object Drawing.Size(680, 0); $wipeHow.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 8)
$wipeHow.Text = "How the reset goes`n`n1.  Plug in the charger. The PC must stay on until the end.`n`n2.  Click ""Start the reset"" and allow it. Windows asks what to keep: choose ""Remove everything"".`n`n3.  Choose ""Cloud download"" or ""Local reinstall"" - both work. Cloud download needs internet, and also repairs a damaged Windows.`n`n4.  At ""Additional settings"", click ""Change settings"" and turn on ""Clean data"": it overwrites the drive so deleted files cannot be recovered. If the PC has a second drive, also turn on ""Delete files from all drives"".`n`n5.  Click ""Reset"". It takes one to several hours, and the PC restarts a few times.`n`n6.  When the PC shows the first set-up screen (choose your country or region), switch it off. The new owner sets it up from there."
$btnReset = New-Button 'Start the reset...'
$btnRecovery = New-Button 'Open Recovery in Settings'
$wipeBar = New-ButtonBar @($btnReset, $btnRecovery); $wipeBar.Dock = 'None'
$wipeFamily = New-Object Windows.Forms.Label
$wipeFamily.AutoSize = $true; $wipeFamily.MaximumSize = New-Object Drawing.Size(680, 0); $wipeFamily.ForeColor = $Theme.Dim; $wipeFamily.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 4)
$wipeFamily.Text = 'Staying in the family? Then you don''t have to reset: add an account for the new user, and remove your own account once they are set up.'
$btnFamily = New-Button 'Add an account for someone'
$familyBar = New-ButtonBar @($btnFamily); $familyBar.Dock = 'None'
$wipeFlow.Controls.AddRange(@($lblWipeOpen, $wipeHow, $wipeBar, $wipeFamily, $familyBar))
Set-PageLayout $pgWipe $wipeFlow @()
function Update-WipeNote {
    $c = Get-CheckLeft; $s = Get-StepsLeft
    if (-not $script:CheckResult) { $lblWipeOpen.Text = 'PC Hand-off is still looking at this PC - see Check.'; $lblWipeOpen.BackColor = $Theme.WarnBg; $lblWipeOpen.ForeColor = $Theme.WarnText }
    elseif ($c -or $s) { $lblWipeOpen.Text = "Still open: $c thing(s) on the Check page and $s step(s) on the Sign out page. After the reset they can't be done any more."; $lblWipeOpen.BackColor = $Theme.WarnBg; $lblWipeOpen.ForeColor = $Theme.WarnText }
    else { $lblWipeOpen.Text = 'Everything is checked and signed out. Ready for the reset.'; $lblWipeOpen.BackColor = $Theme.AccentSoft; $lblWipeOpen.ForeColor = $Theme.Text }
}
$btnReset.Add_Click({
    $c = Get-CheckLeft; $s = Get-StepsLeft
    $q = if ($c -or $s) { "There are still $c thing(s) to check and $s step(s) to sign out. Everything of yours on this PC will be gone after the reset.`n`nStart the reset anyway?" }
         else { "Start Windows' reset now?`n`nRemember: ""Remove everything"", and turn on ""Clean data"" at Additional settings." }
    if ((Show-Msg $q 'YesNo' 'Warning') -ne 'Yes') { return }
    Write-Log 'Started the Windows reset'
    try { Start-Process $ResetExe '-factoryreset' -ErrorAction Stop }
    catch { Start-Process 'ms-settings:recovery' }   # "Reset this PC" is there too
})
$btnRecovery.Add_Click({ Start-Process 'ms-settings:recovery' })
$btnFamily.Add_Click({ Start-Process 'ms-settings:otherusers' })

# ===========================================================================
# 6. Settings
# ===========================================================================
$pgSet = New-Page 'Settings' 'How PC Hand-off looks and behaves. Changes are saved straight away.'
$setFlow = New-Object Windows.Forms.FlowLayoutPanel
$setFlow.Dock = 'Fill'; $setFlow.FlowDirection = 'TopDown'; $setFlow.WrapContents = $false; $setFlow.AutoScroll = $true
Set-PageLayout $pgSet $setFlow @()
function Add-SetSection([string]$Title, [string]$Hint) {
    $t = New-Object Windows.Forms.Label
    $t.Text = $Title; $t.Font = $FontBold; $t.AutoSize = $true; $t.Margin = New-Object Windows.Forms.Padding(0, 16, 0, 2)
    $setFlow.Controls.Add($t)
    if ($Hint) {
        $h = New-Object Windows.Forms.Label
        $h.Text = $Hint; $h.ForeColor = $Theme.Dim; $h.AutoSize = $true; $h.MaximumSize = New-Object Drawing.Size((Px 720), 0)
        $h.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 4)
        $setFlow.Controls.Add($h)
    }
}
function Add-SetRow([object[]]$Controls) {
    $row = New-Object Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true; $row.WrapContents = $false; $row.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 2)
    foreach ($c in $Controls) { $row.Controls.Add($c) }
    $setFlow.Controls.Add($row)
}
function New-Choice([string[]]$Labels, [string[]]$Values, [string]$Current) {
    $c = New-Object Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.Width = 270; $c.FlatStyle = 'Flat'; $c.BackColor = $Theme.Input; $c.ForeColor = $Theme.Text
    $c.Margin = New-Object Windows.Forms.Padding(0, 4, 10, 0)
    foreach ($l in $Labels) { [void]$c.Items.Add((T $l)) }
    $c.SelectedIndex = [Math]::Max(0, [array]::IndexOf($Values, $Current))
    $c.Tag = $Values
    $c.Add_HandleCreated({ Set-DarkChrome $this 'DarkMode_CFD' })
    $c
}
function Restart-App {
    if ($RunningAsExe) { Start-Process $SelfExe } else { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
    $form.Close()
}

Add-SetSection 'Language' 'Takes effect when PC Hand-off restarts.'
$cmbLang = New-Choice @('Automatic (Windows language)', 'English', 'Nederlands', 'Deutsch', 'Français', 'Español', 'Italiano', 'Polski') @('auto', 'en', 'nl', 'de', 'fr', 'es', 'it', 'pl') $Settings.Language
$btnLangRestart = New-Button 'Restart now'
Add-SetRow @($cmbLang, $btnLangRestart)
$cmbLang.Add_SelectedIndexChanged({ $Settings.Language = $this.Tag[$this.SelectedIndex]; Save-Settings })
$btnLangRestart.Add_Click({ Restart-App })

Add-SetSection 'Theme' 'Light, dark, or the same as Windows. Takes effect when PC Hand-off restarts.'
$cmbTheme = New-Choice @('Same as Windows', 'Light', 'Dark') @('system', 'light', 'dark') $Settings.Theme
$btnThemeRestart = New-Button 'Restart now'
Add-SetRow @($cmbTheme, $btnThemeRestart)
$cmbTheme.Add_SelectedIndexChanged({ $Settings.Theme = $this.Tag[$this.SelectedIndex]; Save-Settings })
$btnThemeRestart.Add_Click({ Restart-App })


Add-SetSection 'Updates' "You have version $AppVersion. New versions come from github.com/$UpdateRepo and are checked against GitHub's checksum before they are installed."
$chkUpd = New-Check 'Check for updates when PC Hand-off starts' ([bool]$Settings.CheckUpdates)
$chkUpd.Add_CheckedChanged({ $Settings.CheckUpdates = $this.Checked; Save-Settings })
$btnUpdate = New-Button 'Check for updates now'
Add-SetRow @($chkUpd); Add-SetRow @($btnUpdate)

Add-SetSection 'Install' 'PC Hand-off runs straight from the file - installing is not needed. Install it if you want it in the Start menu and in Settings > Apps.'
$btnInstall = New-Button 'Install on this PC'; $btnUninstall = New-Button 'Uninstall'
Add-SetRow @($btnInstall, $btnUninstall)
$btnInstall.Enabled = $RunningAsExe -and -not $IsInstalled -and -not $FromWinget
$btnUninstall.Enabled = $IsInstalled
$btnInstall.Add_Click({ Install-App -Launch })
$btnUninstall.Add_Click({ Uninstall-App })

Add-SetSection 'Files' "PC Hand-off keeps a log of what it did and its settings in $DataDir."
$btnLog = New-Button 'Open the log'; $btnDataDir = New-Button 'Open the folder'
Add-SetRow @($btnLog, $btnDataDir)
$btnLog.Add_Click({ if (Test-Path $LogFile) { Start-Process notepad.exe "`"$LogFile`"" } else { Show-Msg 'Nothing has been logged yet.' | Out-Null } })
$btnDataDir.Add_Click({ Start-Process explorer.exe "`"$DataDir`"" })

# --- Report a problem / suggest an idea: a GitHub issue filled in with the version, Windows and recent errors ---
function Get-ProblemInfo {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = "$($cv.CurrentBuild).$($cv.UBR)"
    $prod = if ([int]$cv.CurrentBuild -ge 22000) { "$($cv.ProductName)" -replace 'Windows 10', 'Windows 11' } else { "$($cv.ProductName)" }
    $how = if ($FromWinget) { 'winget' } elseif ($IsInstalled) { 'installed' } elseif ($RunningAsExe) { 'exe, not installed' } else { 'script' }
    $clean = { param($t) $t = "$t"; foreach ($p in @($env:USERPROFILE, $env:COMPUTERNAME, $env:USERNAME) | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object Length -Descending) { $t = $t -ireplace [regex]::Escape($p), '<hidden>' }; $t }
    [pscustomobject]@{
        Version = "$AppVersion ($how, $(if ($IsAdmin) { 'administrator' } else { 'normal user' }), language $Lang)"
        Windows = "$prod $($cv.DisplayVersion) (build $build)"
        Errors  = (@(Get-AppErrors 14) | Select-Object -Last 15 | ForEach-Object { & $clean $_ }) -join "`n"
    }
}
function Open-ProblemReport([string]$Kind = 'bug') {
    $i = Get-ProblemInfo
    if ($Kind -eq 'bug') {
        $preview = "This opens GitHub with a new problem report, filled in with:`n`n  Version: $($i.Version)`n  Windows: $($i.Windows)`n  Recent errors: $(if ($i.Errors) { "$(@($i.Errors -split "`n").Count) line(s) (your name, folders and PC name are blanked out)" } else { 'none' })`n`nYou can read and change everything there before you press Submit. You need a free GitHub account."
        if ((Show-Msg $preview 'OKCancel' 'Information') -ne 'OK') { return }
        $q = "template=bug.yml&version=$([uri]::EscapeDataString($i.Version))&windows=$([uri]::EscapeDataString($i.Windows))"
        $err = $i.Errors; while ($err -and ([uri]::EscapeDataString($err)).Length -gt 5500) { $err = ($err -split "`n" | Select-Object -Skip 1) -join "`n" }
        if ($err) { $q += "&errors=$([uri]::EscapeDataString($err))" }
    } else { $q = "template=idea.yml&version=$([uri]::EscapeDataString($i.Version))" }
    Start-Process "https://github.com/$UpdateRepo/issues/new?$q"
}
Add-SetSection 'Help and feedback' 'Something not working, or an idea? It opens a report on GitHub with the version, Windows and recent errors already filled in (your name, folders and PC name are blanked out) - you see everything before you send it.'
$btnBug = New-Button 'Report a problem...'; $btnIdea = New-Button 'Suggest an idea...'
Add-SetRow @($btnBug, $btnIdea)
$btnBug.Add_Click({ Open-ProblemReport 'bug' })
$btnIdea.Add_Click({ Open-ProblemReport 'idea' })

Add-SetSection 'About' "PC Hand-off $AppVersion - free and open source (MIT licence). Privacy: PC Hand-off only reads from this PC and sends nothing anywhere. The only internet use is the update check (GitHub)."
$lnkRepo = New-Object Windows.Forms.LinkLabel
$lnkRepo.Text = "github.com/$UpdateRepo"; $lnkRepo.AutoSize = $true; $lnkRepo.LinkColor = $Theme.AccentText; $lnkRepo.ActiveLinkColor = $Theme.AccentText
$lnkRepo.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 12)
$lnkRepo.Add_LinkClicked({ Start-Process "https://github.com/$UpdateRepo" })
$setFlow.Controls.Add($lnkRepo)

# --- Install / uninstall (per user: no administrator, no installer program) ---
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCHandoff'
$StartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Hand-off.lnk'
function Get-ShortcutTarget([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $sh = New-Object -ComObject WScript.Shell
    try { $sc = $sh.CreateShortcut($Path); $t = $sc.TargetPath; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sc); $t }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}
function New-Shortcut([string]$Path, [string]$Target) {
    $sh = New-Object -ComObject WScript.Shell
    try {
        $sc = $sh.CreateShortcut($Path)
        $sc.TargetPath = $Target; $sc.WorkingDirectory = Split-Path $Target; $sc.IconLocation = "$Target,0"
        $sc.Description = 'Get your old PC ready to sell or give away'
        $sc.Save()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sc)
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}
function Install-App([switch]$Launch) {
    if (-not $RunningAsExe) { Show-Msg 'Install from PC-Handoff.exe, not from the script.' | Out-Null; return }
    try {
        New-Item -ItemType Directory -Force $InstallDir | Out-Null
        if ($SelfExe -ne $InstalledExe) { Copy-Item -LiteralPath $SelfExe -Destination $InstalledExe -Force -ErrorAction Stop }
        New-Shortcut $StartMenuLink $InstalledExe
        New-Item -Path $UninstallKey -Force | Out-Null
        $vals = [ordered]@{ DisplayName = 'PC Hand-off'; DisplayVersion = $AppVersion; Publisher = 'PC Hand-off (open source)'; DisplayIcon = "$InstalledExe,0"
                            InstallLocation = $InstallDir; UninstallString = "`"$InstalledExe`" /uninstall"; URLInfoAbout = "https://github.com/$UpdateRepo"
                            HelpLink = "https://github.com/$UpdateRepo/issues" }
        foreach ($k in $vals.Keys) { Set-ItemProperty -Path $UninstallKey -Name $k -Value $vals[$k] }
        foreach ($k in 'NoModify', 'NoRepair') { Set-ItemProperty -Path $UninstallKey -Name $k -Value 1 -Type DWord }
        Set-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value ([int]((Get-Item -LiteralPath $InstalledExe).Length / 1KB)) -Type DWord
        Write-Log "Installed PC Hand-off $AppVersion in $InstallDir"
    } catch { Show-Msg "Installing failed: $($_.Exception.Message)" 'OK' 'Warning' | Out-Null; return }
    if ($Launch -and $SelfExe -ne $InstalledExe) {
        Show-Msg 'PC Hand-off is installed. It is in the Start menu, and you can uninstall it in Settings > Apps.' | Out-Null
        Start-Process $InstalledExe
        $form.Close()
    }
}
function Uninstall-App {
    if ((Show-Msg 'Remove PC Hand-off from this PC?' 'YesNo' 'Question') -ne 'Yes') { return }
    $wipe = (Show-Msg 'Also delete its settings and log?' 'YesNo' 'Question') -eq 'Yes'
    try { if ((Get-ShortcutTarget $StartMenuLink) -eq $InstalledExe) { Remove-Item $StartMenuLink -Force } } catch { }
    Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    if ($wipe) { Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue }
    $self = $SelfExe -eq $InstalledExe
    if (-not $self) { Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
    Show-Msg 'PC Hand-off has been removed.' | Out-Null
    if ($self) {
        # A running program can't delete itself: a hidden helper waits until this process has ended, then removes the folder.
        $dir = $InstallDir -replace "'", "''"
        $cmd = "Wait-Process -Id $PID -Timeout 60 -ErrorAction SilentlyContinue; " +
               "for (`$i = 0; `$i -lt 20 -and (Test-Path -LiteralPath '$dir'); `$i++) { Start-Sleep 1; Remove-Item -LiteralPath '$dir' -Recurse -Force -ErrorAction SilentlyContinue }"
        Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$cmd`"" -WindowStyle Hidden -WorkingDirectory $env:TEMP
    }
    $form.Close()
}

# --- Updates: the latest GitHub release, checked against GitHub's SHA-256 before it replaces this exe ---
$UpdateCheckWork = {
    param($repo)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'PC-Handoff' } -TimeoutSec 15
        $asset = @($r.assets | Where-Object name -eq 'PC-Handoff.exe')[0]
        [pscustomobject]@{ Version = ($r.tag_name -replace '^v', ''); Notes = [string]$r.body; Url = $asset.browser_download_url
                           Digest = [string]$asset.digest; Page = $r.html_url; Error = $null }
    } catch { [pscustomobject]@{ Error = $_.Exception.Message } }
}
$UpdateDownloadWork = {
    param($info)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $file = Join-Path $env:TEMP "PC-Handoff-$($info.Version).exe"
    try {
        Invoke-WebRequest $info.Url -OutFile $file -UseBasicParsing -Headers @{ 'User-Agent' = 'PC-Handoff' } -TimeoutSec 120
        if ($info.Digest -match '^sha256:([0-9a-f]{64})$') {
            if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) { Remove-Item $file -Force; throw 'downloaded file is damaged (checksum mismatch)' }
        }
        [pscustomobject]@{ File = $file; Error = $null }
    } catch { [pscustomobject]@{ File = $null; Error = $_.Exception.Message } }
}
function Start-UpdateCheck([switch]$Silent) {
    $btnUpdate.Enabled = $false
    $script:UpdateSilent = [bool]$Silent
    Start-Bg $UpdateCheckWork $UpdateRepo {
        param($r)
        $btnUpdate.Enabled = $true
        $r = $r[0]
        if ($r.Error) { if (-not $script:UpdateSilent) { Show-Msg "Couldn't check for updates:`n$($r.Error)" 'OK' 'Warning' | Out-Null }; return }
        $newer = try { [version]$r.Version -gt [version]$AppVersion } catch { $false }
        if (-not $newer) { if (-not $script:UpdateSilent) { Show-Msg "You have the latest version ($AppVersion)." | Out-Null }; return }
        $notes = (($r.Notes -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 8) -join "`n").Trim()
        if ($FromWinget) {
            if ((Show-Msg "PC Hand-off $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nIt was installed with winget, so winget updates it. Update now? (A window opens; start PC Hand-off again afterwards.)" 'YesNo' 'Information') -eq 'Yes') {
                Start-Process cmd.exe '/c winget upgrade --id MichaelKloprogge.PCHandoff --exact --accept-source-agreements & pause'
                $form.Close()
            }
            return
        }
        if (-not $RunningAsExe -or -not $r.Url) {
            if ((Show-Msg "PC Hand-off $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nOpen the download page?" 'YesNo' 'Information') -eq 'Yes') { Start-Process $r.Page }
            return
        }
        if ((Show-Msg "PC Hand-off $($r.Version) is available (you have $AppVersion).`n`n$notes`n`nUpdate now? The app restarts by itself." 'YesNo' 'Information') -ne 'Yes') { return }
        $btnUpdate.Enabled = $false; $btnUpdate.Text = 'Downloading...'
        $script:UpdateInfo = $r
        Start-Bg -Label 'Downloading the update' $UpdateDownloadWork $r {
            param($d)
            $d = $d[0]
            $btnUpdate.Text = 'Check for updates now'; $btnUpdate.Enabled = $true
            if ($d.Error) { Show-Msg "Update failed: $($d.Error)" 'OK' 'Warning' | Out-Null; return }
            # A running exe can be renamed but not overwritten: move it aside, put the new one in its place, restart.
            $old = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
            try {
                Remove-Item $old -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $SelfExe -Destination $old -ErrorAction Stop
                try { Move-Item -LiteralPath $d.File -Destination $SelfExe -ErrorAction Stop }
                catch { Move-Item -LiteralPath $old -Destination $SelfExe; throw }
            } catch {
                Show-Msg "Couldn't replace the app file ($($_.Exception.Message)). Download it yourself from:`n$($script:UpdateInfo.Page)" 'OK' 'Warning' | Out-Null
                return
            }
            Write-Log "Updated PC Hand-off $AppVersion -> $($script:UpdateInfo.Version)"
            Start-Process $SelfExe
            $form.Close()
        }
    }
}
$btnUpdate.Add_Click({ Start-UpdateCheck })
$OldExeCleanupWork = {
    param($old)
    for ($i = 0; $i -lt 30 -and (Test-Path -LiteralPath $old); $i++) { Start-Sleep 2; Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
}

# ===========================================================================
# Sidebar
# ===========================================================================
$NavPages = @('Start', 'Check', 'Sign out', 'For the buyer', 'Wipe', 'Settings')
$script:NavButtons = @{}
$script:PageLoaders = @{ 'For the buyer' = { Start-Specs } }
$script:Loaded = @{}
function Show-Page($Page) {
    $script:CurrentPage = $Page
    foreach ($p in $script:Pages) { $p.Visible = ($p -eq $Page) }
    foreach ($b in $script:NavButtons.Values) {
        $on = $b.Tag -eq $Page
        $b.BackColor = if ($on) { $Theme.AccentSoft } else { $Theme.Side }
        $b.ForeColor = if ($on) { $Theme.AccentText } else { $Theme.Text }
        $b.Font = if ($on) { $FontBold } else { $Font }
        $b.Invalidate()
    }
    $n = $Page.Name
    if (-not $script:Loaded[$n] -and $script:PageLoaders.ContainsKey($n)) { $script:Loaded[$n] = $true; & $script:PageLoaders[$n] }
}
function Set-NavBadge([string]$Name, $Count) {
    $b = $script:NavButtons[$Name]
    if ($b) { $b.Text = if ($Count) { "$(T $Name)  ($Count)" } else { T $Name } }
}
$IconFontName = if ((New-Object Drawing.Text.InstalledFontCollection).Families.Name -contains 'Segoe Fluent Icons') { 'Segoe Fluent Icons' } else { 'Segoe MDL2 Assets' }
$IconFont = New-Object Drawing.Font($IconFontName, 11)
$NavIcons = @{ Start = 0xE80F; Check = 0xE9D5; 'Sign out' = 0xF3B1; 'For the buyer' = 0xE7C3; Wipe = 0xE74D; Settings = 0xE713 }
function Draw-NavButton($B, $G) {
    $G.SmoothingMode = 'AntiAlias'
    $G.Clear($Theme.Side)
    $on = $B.BackColor.ToArgb() -eq $Theme.AccentSoft.ToArgb()
    if ($on -or $script:HotNav -eq $B) {
        $p = New-RoundRect 0.5 0.5 ($B.Width - 1.5) ($B.Height - 1.5) (Px 5)
        $br = New-Object Drawing.SolidBrush($(if ($on) { $Theme.AccentSoft } else { $Theme.Hover })); $G.FillPath($br, $p); $br.Dispose(); $p.Dispose()
    }
    if ($on) {   # the bar on the left, like Windows 11 Settings
        $h = [single]($B.Height * 0.5); $bar = New-RoundRect 1 (($B.Height - $h) / 2) (Px 3) $h (Px 2)
        $br = New-Object Drawing.SolidBrush($Theme.Accent); $G.FillPath($br, $bar); $br.Dispose(); $bar.Dispose()
    }
    $x = Px 10
    $code = $NavIcons[$B.AccessibleName]
    if ($code) {
        [Windows.Forms.TextRenderer]::DrawText($G, [string][char]$code, $IconFont, (New-Object Drawing.Rectangle($x, 0, (Px 20), $B.Height)), $(if ($on) { $Theme.AccentText } else { $Theme.Dim }), 'VerticalCenter, HorizontalCenter, NoPrefix')
        $x += Px 30
    }
    $text = $B.Text; $right = $B.Width - (Px 4)
    if ($text -match '^(.*?)\s+\((\d+)\)$') {   # a count is drawn as a small pill on the right
        $text = $Matches[1]; $count = $Matches[2]
        $pw = [Windows.Forms.TextRenderer]::MeasureText($count, $FontSmall).Width + (Px 8); $ph = Px 17
        $px = $B.Width - (Px 6) - $pw; $py = [int](($B.Height - $ph) / 2)
        $pill = New-RoundRect $px $py $pw $ph ($ph / 2)
        $br = New-Object Drawing.SolidBrush($(if ($on) { $Theme.Bg } else { $Theme.Hover })); $G.FillPath($br, $pill); $br.Dispose(); $pill.Dispose()
        [Windows.Forms.TextRenderer]::DrawText($G, $count, $FontSmall, (New-Object Drawing.Rectangle($px, $py, $pw, $ph)), $(if ($on) { $Theme.AccentText } else { $Theme.Dim }), 'VerticalCenter, HorizontalCenter, NoPrefix')
        $right = $px - (Px 4)
    }
    [Windows.Forms.TextRenderer]::DrawText($G, $text, $B.Font, (New-Object Drawing.Rectangle($x, 0, ($right - $x), $B.Height)), $B.ForeColor, 'VerticalCenter, Left, EndEllipsis, NoPrefix')
    if ($B.Focused -and $B.ShowFocusCues) { $fp = New-RoundRect 1.5 1.5 ($B.Width - 3.5) ($B.Height - 3.5) (Px 4); $pen = New-Object Drawing.Pen($Theme.Accent); $pen.DashStyle = 'Dot'; $G.DrawPath($pen, $fp); $pen.Dispose(); $fp.Dispose() }
}
$nav = New-Object Windows.Forms.FlowLayoutPanel
$nav.Dock = 'Fill'; $nav.FlowDirection = 'TopDown'; $nav.WrapContents = $false; $nav.AutoScroll = $true
$nav.Padding = New-Object Windows.Forms.Padding(12, 10, 12, 2)
$appName = New-Object Windows.Forms.Label
$appName.Text = 'PC Hand-off'; $appName.Font = $FontBig; $appName.AutoSize = $true; $appName.Margin = New-Object Windows.Forms.Padding(6, 0, 0, 0)
$appVer = New-Object Windows.Forms.Label
$appVer.Text = "Version $AppVersion"; $appVer.ForeColor = $Theme.Dim; $appVer.AutoSize = $true; $appVer.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 10)
$nav.Controls.AddRange(@($appName, $appVer))
foreach ($name in $NavPages) {
    $page = $script:Pages | Where-Object Name -eq $name | Select-Object -First 1
    $b = New-Object Windows.Forms.Button
    $b.Text = $name; $b.Tag = $page; $b.Width = 170; $b.Height = 32; $b.TextAlign = 'MiddleLeft'
    $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $Theme.Hover
    $b.BackColor = $Theme.Side; $b.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 2); $b.Cursor = [Windows.Forms.Cursors]::Hand
    $b.AccessibleName = $name
    $b.Add_Click({ Show-Page $this.Tag })
    $b.Add_Paint({ param($sender, $e) Draw-NavButton $sender $e.Graphics })
    $b.Add_MouseEnter({ $script:HotNav = $this; $this.Invalidate() })
    $b.Add_MouseLeave({ if ($script:HotNav -eq $this) { $script:HotNav = $null }; $this.Invalidate() })
    $b.Add_GotFocus({ $this.Invalidate() }); $b.Add_LostFocus({ $this.Invalidate() })
    $script:NavButtons[$name] = $b
    $nav.Controls.Add($b)
}
$sidebar.Controls.Add($nav)
if (-not $IsAdmin) {
    $adm = New-Object Windows.Forms.Panel
    $adm.Dock = 'Bottom'; $adm.Height = 116; $adm.Padding = New-Object Windows.Forms.Padding(14, 6, 14, 10)
    $admL = New-Object Windows.Forms.Label
    $admL.Dock = 'Fill'; $admL.ForeColor = $Theme.Dim; $admL.Font = New-Object Drawing.Font('Segoe UI', 8.25)
    $admL.Text = 'As administrator, PC Hand-off can also read how worn the drive is, for the buyer.'
    $admB = New-Button 'Run as administrator'
    $admB.AutoSize = $false; $admB.Dock = 'Bottom'; $admB.Height = 32
    $admB.Add_Click({
        try {
            if ($RunningAsExe) { Start-Process $SelfExe -Verb RunAs }
            else { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
            $form.Close()
        } catch { }   # the person said no to the Windows prompt
    })
    $adm.Controls.AddRange(@($admL, $admB))
    $sidebar.Controls.Add($adm)
}
foreach ($b in @($btnCheckDo, $btnStepDo, $btnSpecCopy, $btnReset)) { Set-Primary $b }

# ---------------------------------------------------------------------------
# Activity bar: what is running in the background, its progress, and Cancel
# ---------------------------------------------------------------------------
$activity = New-Object Windows.Forms.Panel
$activity.Dock = 'Bottom'; $activity.Height = 42; $activity.BackColor = $Theme.Soft; $activity.Visible = $false
$activity.Padding = New-Object Windows.Forms.Padding(26, 7, 26, 7)
$actText = New-Object Windows.Forms.Label
$actText.Dock = 'Fill'; $actText.TextAlign = 'MiddleLeft'; $actText.AutoEllipsis = $true
$actBar = New-Object Windows.Forms.PictureBox
$actBar.Dock = 'Right'; $actBar.Width = 220; $actBar.BackColor = $Theme.Soft
$script:ActProg = @{ Max = 0; Value = 0; Pos = 0.0 }
$actBar.Add_Paint({ param($sender, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $h = [single](Px 6); $y = ($sender.Height - $h) / 2; $w = [single]($sender.Width - 2)
    $track = New-RoundRect 1 $y $w $h ($h / 2); $br = New-Object Drawing.SolidBrush($Theme.Border); $g.FillPath($br, $track); $br.Dispose(); $track.Dispose()
    $p = $script:ActProg
    if ($p.Max -gt 0) { $x0 = 1; $fw = [single]([Math]::Max([double]$h, $w * [Math]::Min([double]1, [double]$p.Value / [double]$p.Max))) }
    else { $fw = [single]($w * 0.3); $x0 = 1 + ($w - $fw) * (0.5 - 0.5 * [Math]::Cos($p.Pos)) }
    $fill = New-RoundRect $x0 $y $fw $h ($h / 2); $br = New-Object Drawing.SolidBrush($Theme.Accent); $g.FillPath($br, $fill); $br.Dispose(); $fill.Dispose()
})
$actAnim = New-Object Windows.Forms.Timer; $actAnim.Interval = 40
$actAnim.Add_Tick({ if ($activity.Visible -and $script:ActProg.Max -le 0) { $script:ActProg.Pos += 0.08; $actBar.Invalidate() } })
$actAnim.Start()
$actGap = New-Object Windows.Forms.Panel; $actGap.Dock = 'Right'; $actGap.Width = 10
$actCancel = New-Button 'Cancel'
$actCancel.AutoSize = $false; $actCancel.Dock = 'Right'; $actCancel.Width = 96
$activity.Controls.Add($actText); $activity.Controls.Add($actBar); $activity.Controls.Add($actGap); $activity.Controls.Add($actCancel)
$content.Controls.Add($activity); $activity.SendToBack()
$actCancel.Add_Click({ if ($this.Tag) { $this.Tag.State.Cancel = $true; Update-ActivityBar } })
function Update-ActivityBar {
    $running = @($script:Jobs | Where-Object { $_.Label } | Sort-Object { -[int]$_.Cancellable })
    if (-not $running) { if ($activity.Visible) { $activity.Visible = $false }; return }
    $j = $running[0]
    $t = (T $j.Label) + $(if ($j.State.Text) { ": $(T $j.State.Text)" })
    if ($actText.Text -ne $t) { $actText.Text = $t }
    $script:ActProg.Max = [Math]::Max(0, $j.State.Max); $script:ActProg.Value = [Math]::Max(0, $j.State.Value); $actBar.Invalidate()
    $actCancel.Visible = $j.Cancellable; $actCancel.Tag = $j
    $actCancel.Enabled = -not $j.State.Cancel
    $actCancel.Text = if ($j.State.Cancel) { 'Stopping...' } else { 'Cancel' }
    if (-not $activity.Visible) { $activity.Visible = $true }
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
function Write-Cli([string]$Text) { try { [Console]::Out.WriteLine((T $Text)) } catch { } }
if ($Cli.Help -or $Cli.Install -or $Cli.Uninstall) {
    if ($RunningAsExe -and [PcHandoff.Native]::AttachConsole(-1)) { $w = New-Object IO.StreamWriter([Console]::OpenStandardOutput()); $w.AutoFlush = $true; [Console]::SetOut($w) }
    if ($Cli.Install) { Install-App; Write-Cli "PC Hand-off installed in $InstallDir" }
    elseif ($Cli.Uninstall) { Uninstall-App }
    else { Write-Cli "PC Hand-off $AppVersion`n`n  PC-Handoff.exe                   open PC Hand-off`n  PC-Handoff.exe /install | /uninstall  install or remove for this user" }
    $JobTimer.Stop()
    return
}
Enable-Translation $form
foreach ($n in $NavPages) { Set-NavBadge $n 0 }
Show-Page $pgStart
Update-Steps; Start-Check
$form.Add_Shown({
    if ($Settings.CheckUpdates) { Start-UpdateCheck -Silent }
    if ($IsInstalled) { try { Set-ItemProperty -Path $UninstallKey -Name DisplayVersion -Value $AppVersion -ErrorAction Stop } catch { } }
    $oldExe = [IO.Path]::ChangeExtension($SelfExe, '.old.exe')
    if ($RunningAsExe -and (Test-Path -LiteralPath $oldExe)) { Start-Bg $OldExeCleanupWork $oldExe { } }
})
# Grow every control by the screen scaling (fonts already scale on their own; list columns and row heights were sized with Px).
if ($DpiScale -ne 1) { $form.Scale((New-Object Drawing.SizeF($DpiScale, $DpiScale))) }
$work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object Drawing.Size([Math]::Min($form.Width, $work.Width - 40), [Math]::Min($form.Height, $work.Height - 40))
$form.MinimumSize = New-Object Drawing.Size((Px 900), (Px 560))
[void]$form.ShowDialog()
$JobTimer.Stop()
