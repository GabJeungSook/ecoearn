; EcoEarn Windows installer (Inno Setup 6). Built by GitHub Actions
; (.github/workflows/release.yml):
;   iscc /DAppVersion=1.0.N /DSourceDir=<Flutter Release folder> installer\ecoearn.iss
;
; Installs for the current user only (no admin rights needed), so the in-app
; updater can run it quietly. The database lives in %APPDATA%, not here, so
; installing or updating never touches students, deposits or payments.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: updates find the installed copy by it.
AppId={{D2FD31BB-5EF3-41B2-8F15-30131F36417B}
AppName=EcoEarn
AppVersion={#AppVersion}
AppPublisher=EcoEarn
DefaultDirName={localappdata}\Programs\EcoEarn
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=EcoEarn-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\ecoearn_app.exe
; Close a running EcoEarn before replacing its files.
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\EcoEarn"; Filename: "{app}\ecoearn_app.exe"
Name: "{userdesktop}\EcoEarn"; Filename: "{app}\ecoearn_app.exe"; Tasks: desktopicon

[Run]
; Opens EcoEarn when installing by hand (a checkbox on the last page)...
Filename: "{app}\ecoearn_app.exe"; Description: "Open EcoEarn"; Flags: nowait postinstall skipifsilent
; ...and after a quiet update from inside the app, so it comes straight back.
Filename: "{app}\ecoearn_app.exe"; Flags: nowait; Check: WizardSilent
