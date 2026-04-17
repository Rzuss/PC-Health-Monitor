; PC Health Monitor - Inno Setup Script
; Builds: PC-Health-Monitor-Setup.exe
; Requires: Inno Setup 6.x (https://jrsoftware.org/isinfo.php)

#define AppName      "PC Health Monitor"
#define AppVersion   "3.0"
#define AppPublisher "Rotem"
#define AppURL       "https://github.com/Rzuss/PC-Health-Monitor"
#define AppExeName   "PC-Health-Monitor.ps1"
#define AppID        "{{A7F3E2D1-4B8C-4F2A-9E6D-3C1B5A0F7E2D}"

[Setup]
AppId={#AppID}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={localappdata}\PC-Health-Monitor
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=PC-Health-Monitor-Setup
SetupIconFile=
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\PC-Health-Monitor.ps1
VersionInfoVersion={#AppVersion}.0.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Installer
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: checked
Name: "startmenuicon"; Description: "Create a &Start Menu shortcut"; GroupDescription: "Additional icons:"; Flags: checked

[Files]
; Core application
Source: "PC-Health-Monitor.ps1";          DestDir: "{app}"; Flags: ignoreversion
Source: "install.ps1";                     DestDir: "{app}"; Flags: ignoreversion
Source: "PC-Cleanup-Rotem.ps1";            DestDir: "{app}"; Flags: ignoreversion
Source: "Register-HealthTask.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "Create-Desktop-Shortcut.bat";     DestDir: "{app}"; Flags: ignoreversion
Source: "Launch-Monitor.vbs";              DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; Threat intelligence database
Source: "threat_intel.json";               DestDir: "{app}"; Flags: ignoreversion

; Python analytics engine (optional)
Source: "health_analyzer.py";              DestDir: "{app}"; Flags: ignoreversion
Source: "baseline_engine.py";              DestDir: "{app}"; Flags: ignoreversion

; Plugins folder
Source: "plugins\*";                       DestDir: "{app}\plugins"; Flags: ignoreversion recursesubdirs createallsubdirs

; Scripts folder
Source: "scripts\*";                       DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

; Screenshots (for reference)
Source: "screenshots\*";                   DestDir: "{app}\screenshots"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
; Desktop shortcut
Name: "{autodesktop}\PC Health Monitor";   Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\PC-Health-Monitor.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon; Comment: "Launch PC Health Monitor"

; Start Menu shortcut
Name: "{group}\PC Health Monitor";         Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\PC-Health-Monitor.ps1"""; WorkingDir: "{app}"; Tasks: startmenuicon; Comment: "Launch PC Health Monitor"
Name: "{group}\Uninstall PC Health Monitor"; Filename: "{uninstallexe}"

[Run]
; Offer to launch after install
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\PC-Health-Monitor.ps1"""; Description: "Launch PC Health Monitor now"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove generated files on uninstall
Type: filesandordirs; Name: "{app}\dist"

[Code]
// Check PowerShell version before installing
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
  PSVersion: String;
begin
  Result := True;

  // Check PowerShell 5.1+ is available
  if not Exec('powershell.exe', '-Command "$PSVersionTable.PSVersion.Major -ge 5"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox('PowerShell 5.1 or higher is required to run PC Health Monitor.' + #13#10 +
           'Windows 10 and 11 include PowerShell 5.1 by default.' + #13#10 +
           'Please ensure PowerShell is accessible on your system.', mbError, MB_OK);
    Result := False;
    Exit;
  end;

  if ResultCode <> 1 then
  begin
    MsgBox('PC Health Monitor requires PowerShell 5.1 or higher.' + #13#10 +
           'Please update PowerShell and try again.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Set execution policy for current user (non-destructive, user-scope only)
    Exec('powershell.exe',
         '-Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
