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

[Types]
Name: "full"; Description: "Full (game + R.E.D. AI)"
Name: "compact"; Description: "Game only"
Name: "custom"; Description: "Custom"; Flags: iscustom

[Components]
Name: "game"; Description: "Crimson Knight"; Types: full compact custom; Flags: fixed
Name: "red"; Description: "R.E.D. AI voice + brain (1.3 GB)"; Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Src}\{#AppExe}"; DestDir: "{app}"; Components: game; Flags: ignoreversion
; Godot writes a console wrapper when debug/export_console_wrapper is on; ship it when present
Source: "{#Src}\CrimsonKnight.console.exe"; DestDir: "{app}"; Components: game; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#Src}\ai\*"; DestDir: "{app}\ai"; Components: red; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autoprograms}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; R.E.D. writes nothing into {app}; saves and settings live in %APPDATA%\Godot\app_userdata and are kept
Type: dirifempty; Name: "{app}\ai"
