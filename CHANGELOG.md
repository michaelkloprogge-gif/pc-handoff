# Changelog

## 1.0.1

- Rows and steps you ticked were forgotten after a restart when there were two or more. Fixed.
- Ready for the Microsoft Store: the Store version leaves installing and updating to the Store.
- Available with winget: `winget install MichaelKloprogge.PCHandoff` (once the package is approved).

## 1.0.0

First version.

- **Check:** before you wipe, it shows what may not be anywhere else yet: personal folders (in OneDrive, packed up with PC Move and how many files changed since, or only on this PC), Outlook and Thunderbird mail, folders you made on the Windows drive, a second drive, other people's accounts, browser profiles that aren't signed in, BitLocker and the Windows licence.
- **Sign out:** licences and devices tied to this PC, found from the installed programs (Microsoft 365, iTunes, iCloud, Adobe, Steam, game launchers, Dropbox, Spotify, Netflix, Kindle, WhatsApp, Telegram, Signal, antivirus, password managers, music software), each with a button that opens the right page.
- **For the buyer:** the specs in plain words to copy or save - processor, memory and free slots, drive and its health, graphics, screen, battery health, Windows, licence and Windows 11 support.
- **Wipe:** starts Windows' own reset and explains every choice (Remove everything, Clean data, all drives).
- Only reads from the PC; English, Dutch, German, French, Spanish, Italian and Polish; light and dark theme; updates itself from GitHub.
