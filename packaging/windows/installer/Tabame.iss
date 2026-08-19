#define AppName "Tabame"
#define AppPublisher "Far Se"
#define AppExeName "tabame.exe"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef VersionInfoVersion
  #define VersionInfoVersion "0.0.0.0"
#endif
#ifndef PayloadDir
  #define PayloadDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputBaseName
  #define OutputBaseName "tabame-windows-x64-setup"
#endif
#ifndef RepoRoot
  #define RepoRoot "."
#endif

[Setup]
; Never change AppId: Inno Setup uses it to find and upgrade an existing install.
AppId={{7B6E8B79-4F74-4D31-AB9F-0E6A4C0B6B8C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/Far-Se/tabame
AppSupportURL=https://github.com/Far-Se/tabame/issues
AppUpdatesURL=https://github.com/Far-Se/tabame/releases
DefaultDirName={localappdata}\Programs\Tabame
DefaultGroupName=Tabame
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.17763
UsePreviousAppDir=yes
CloseApplications=force
CloseApplicationsFilter=tabame.exe
RestartApplications=no
RestartIfNeededByRun=no
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern dynamic
SetupLogging=yes
Uninstallable=yes
UninstallDisplayName=Tabame
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion={#VersionInfoVersion}
VersionInfoDescription=Tabame Windows installer
VersionInfoProductName=Tabame
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright=Copyright (c) 2022-2026 Far Se
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
LicenseFile={#RepoRoot}\LICENSE

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tabame"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\Tabame"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch Tabame"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
  ErrorMessage: String;
begin
  Result := True;

  { Close Tabame and its child processes before the uninstaller removes files. }
  if not Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/T /F /IM "{#AppExeName}"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    ErrorMessage := 'Windows could not start the command that closes Tabame. ' +
      'Close Tabame manually, then try uninstalling again.';
    Log(ErrorMessage + ' ' + SysErrorMessage(ResultCode));
    if not UninstallSilent then
      MsgBox(ErrorMessage, mbError, MB_OK);
    Result := False;
    Exit;
  end;

  { taskkill returns 128 when no matching process exists. }
  if (ResultCode <> 0) and (ResultCode <> 128) then
  begin
    ErrorMessage := 'Tabame is still running and Windows could not close it. ' +
      'Close Tabame manually (use Task Manager if it is running as administrator), ' +
      'then try uninstalling again.';
    Log(Format('%s taskkill exit code: %d.', [ErrorMessage, ResultCode]));
    if not UninstallSilent then
      MsgBox(ErrorMessage, mbError, MB_OK);
    Result := False;
  end;
end;
