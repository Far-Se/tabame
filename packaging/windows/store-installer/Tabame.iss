#define AppName "Tabame"

#ifndef AppVersion
#define AppVersion "0.0.0"
#endif
#ifndef VersionInfoVersion
#define VersionInfoVersion "0.0.0.0"
#endif
#ifndef ReleaseDir
#define ReleaseDir "."
#endif
#ifndef OutputDir
#define OutputDir "."
#endif
#ifndef OutputBaseName
#define OutputBaseName "tabame-store-installer"
#endif
#ifndef RepoRoot
#define RepoRoot "."
#endif

[Setup]
AppId={{7B6E8B79-4F74-4D31-AB9F-0E6A4C0B6B8C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Far Se
AppPublisherURL=https://github.com/Far-Se/tabame
AppSupportURL=https://github.com/Far-Se/tabame/issues
AppUpdatesURL=https://github.com/Far-Se/tabame/releases
DefaultDirName={localappdata}\Programs\Tabame
; Keep the AppId and install directory stable so newer installers upgrade the
; existing installation instead of creating a second copy.
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.19045
; Use Windows Restart Manager to close Tabame before replacing locked files.
; The installer is also used in silent CI/update runs, so do not restart the
; old process after the files have been replaced.
CloseApplications=force
CloseApplicationsFilter=tabame.exe
RestartApplications=no
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
UninstallDisplayName=Tabame
UninstallDisplayIcon={app}\tabame.exe
VersionInfoVersion={#VersionInfoVersion}
VersionInfoDescription=Tabame Windows Store installer
VersionInfoProductName=Tabame
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany=Far Se
VersionInfoCopyright=Copyright (c) 2022 Far-Se
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico

#ifdef StoreSignToolScript
SignTool=StoreSignTool
SignedUninstaller=yes
#endif

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tabame"; Filename: "{app}\tabame.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Tabame"; Filename: "{app}\tabame.exe"; WorkingDir: "{app}"

[Run]
Filename: "{app}\tabame.exe"; Description: "Launch Tabame"; Flags: nowait postinstall skipifsilent

#ifdef StoreSignToolScript
[SignTools]
StoreSignTool=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{#StoreSignToolScript}" "$f"
#endif
