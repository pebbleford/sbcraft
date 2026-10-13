# Adds "SBCraft" to your Steam library as a non-Steam game that runs launcher\SBCraft.exe.
# Steam must be closed while its shortcuts.vdf is edited (it rewrites the file on exit): this asks Steam to shut down,
# backs the file up (shortcuts.vdf.sbcraft-backup), adds the entry (once), and starts Steam again.
#   -NoRestart   don't shut Steam down / start it again (Steam must already be closed)
param([switch]$NoRestart, [string]$VdfPath) # -VdfPath: edit this file instead (testing)
$ErrorActionPreference = 'Stop'
$Exe = Join-Path $PSScriptRoot 'SBCraft.exe'
if (-not (Test-Path $Exe)) { throw "build the launcher first: launcher\build.bat ($Exe is missing)" }
$Name = 'SBCraft'

$steamExe = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamExe
$steamDir = Split-Path -Parent $steamExe
# the Steam account that logged in last (its userdata folder has the newest localconfig.vdf)
$user = Get-ChildItem (Join-Path $steamDir 'userdata') -Directory |
	Where-Object { Test-Path (Join-Path $_.FullName 'config\localconfig.vdf') } |
	Sort-Object { (Get-Item (Join-Path $_.FullName 'config\localconfig.vdf')).LastWriteTime } -Descending |
	Select-Object -First 1
if (-not $user) { throw "no Steam user folder found under $steamDir\userdata" }
$vdf = if ($VdfPath) { $VdfPath } else { Join-Path $user.FullName 'config\shortcuts.vdf' }

$running = if ($VdfPath) { $null } else { Get-Process -Name steam -ErrorAction SilentlyContinue }
if ($running) {
	if ($NoRestart) { throw 'Steam is running: close it first (or run without -NoRestart)' }
	Write-Host 'Closing Steam...'
	Start-Process $steamExe -ArgumentList '-shutdown'
	$deadline = (Get-Date).AddSeconds(60)
	while (Get-Process -Name steam -ErrorAction SilentlyContinue) {
		if ((Get-Date) -gt $deadline) { throw "Steam didn't close within a minute" }
		Start-Sleep -Seconds 1
	}
	Start-Sleep -Seconds 2
}

# binary VDF helpers (Latin-1 keeps every byte as one char)
$enc = [Text.Encoding]::GetEncoding(28591)
function Str([string]$k, [string]$v) { [byte[]](@(1) + $enc.GetBytes($k) + @(0) + [Text.Encoding]::UTF8.GetBytes($v) + @(0)) }
function Int([string]$k, [int]$v) { [byte[]](@(2) + $enc.GetBytes($k) + @(0) + [BitConverter]::GetBytes($v)) }

if (Test-Path $vdf) {
	$bytes = [IO.File]::ReadAllBytes($vdf)
	Copy-Item $vdf "$vdf.sbcraft-backup" -Force
} else {
	$bytes = [byte[]](@(0) + $enc.GetBytes('shortcuts') + @(0, 8, 8))
}
$text = $enc.GetString($bytes)
if ($text.Contains("`u{1}AppName`u{0}$Name`u{0}") -or $text.Contains("`u{1}appname`u{0}$Name`u{0}")) {
	Write-Host "Steam already has a '$Name' shortcut: nothing to do."
} else {
	if ($bytes.Length -lt 2 -or $bytes[-1] -ne 8 -or $bytes[-2] -ne 8) { throw "unexpected shortcuts.vdf format: $vdf (left untouched)" }
	$index = 0
	foreach ($m in [regex]::Matches($text, "`u{0}(\d+)`u{0}[`u{1}`u{2}]")) { $index = [Math]::Max($index, [int]$m.Groups[1].Value + 1) }
	# Steam's id for a non-Steam shortcut: CRC32 of exe + name, with the top bit set
	# (decimal constants: PowerShell reads 0xFFFFFFFF and 0xEDB88320 as negative Int32)
	[uint64]$poly = 3988292384; [uint64]$mask = 4294967295
	$crcTable = 0..255 | ForEach-Object { [uint64]$c = $_; for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = $poly -bxor ($c -shr 1) } else { $c = $c -shr 1 } }; $c }
	[uint64]$crc = $mask
	foreach ($b in [Text.Encoding]::UTF8.GetBytes("`"$Exe`"$Name")) { $crc = $crcTable[[int](($crc -bxor $b) -band 255)] -bxor ($crc -shr 8) }
	[uint64]$id = (($crc -bxor $mask) -bor 2147483648) -band $mask
	$appId = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$id), 0)
	$entry = [byte[]](@(0) + $enc.GetBytes("$index") + @(0)) +
		(Int 'appid' $appId) + (Str 'AppName' $Name) + (Str 'Exe' "`"$Exe`"") + (Str 'StartDir' "`"$PSScriptRoot\`"") +
		(Str 'icon' '') + (Str 'ShortcutPath' '') + (Str 'LaunchOptions' '') + (Int 'IsHidden' 0) +
		(Int 'AllowDesktopConfig' 1) + (Int 'AllowOverlay' 1) + (Int 'OpenVR' 0) + (Int 'Devkit' 0) +
		(Str 'DevkitGameID' '') + (Int 'DevkitOverrideAppID' 0) + (Int 'LastPlayTime' 0) + (Str 'FlatpakAppID' '') +
		[byte[]](@(0) + $enc.GetBytes('tags') + @(0, 8)) + [byte[]](@(8))
	$out = [byte[]]($bytes[0..($bytes.Length - 3)] + $entry + @(8, 8))
	[IO.File]::WriteAllBytes($vdf, $out)
	Write-Host "Added '$Name' to Steam ($vdf, entry $index). Backup: $vdf.sbcraft-backup"
}

if ($running -and -not $NoRestart) {
	Write-Host 'Starting Steam...'
	Start-Process $steamExe
}
