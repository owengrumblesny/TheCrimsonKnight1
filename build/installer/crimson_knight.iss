; Crimson Knight: Windows installer (Inno Setup 6).
; Build the game first (build/build_windows.ps1), then:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" build\installer\crimson_knight.iss
; or run build_windows.ps1 -Installer. Output: dist\CrimsonKnight-Setup.exe
; Override the version with /DAppVersion=1.2.3.

#ifndef AppVersion
  #define AppVersion "0.9.0"
#endif
#define AppName "Crimson Knight"
#define AppExe "CrimsonKnight.exe"
#define Src "..\..\dist\windows"

[Setup]
; keep AppId fixed forever: upgrades and the uninstaller find the install by it
AppId={{8E33347A-5137-45B1-99C4-B878197B0A3E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Owen Enterprises
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=CrimsonKnight-Setup
SetupIconFile=..\icon\crimson_knight.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
; R.E.D.'s local AI is not packed into Setup (it is 1.3 GB): the game downloads it from the official releases on
; first launch when this is ticked (Settings > R.E.D. AI can do it any time), and keeps it updated
Name: "redai"; Description: "Download R.E.D.'s offline AI on first launch (voice, brain, ears: about 1.3 GB)"; GroupDescription: "R.E.D. AI:"

[Files]
Source: "{#Src}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
; Godot writes a console wrapper when debug/export_console_wrapper is on; ship it when present
Source: "{#Src}\CrimsonKnight.console.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[INI]
Filename: "{app}\install.ini"; Section: "red"; Key: "autodownload"; String: "1"; Tasks: redai

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autoprograms}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; R.E.D. writes nothing into {app}; saves and settings live in %APPDATA%\Godot\app_userdata and are kept
Type: dirifempty; Name: "{app}\ai"
Type: files; Name: "{app}\install.ini"
