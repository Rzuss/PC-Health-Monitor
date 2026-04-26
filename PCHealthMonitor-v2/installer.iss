; ─────────────────────────────────────────────────────────────────────────────
; PC Health Monitor — Inno Setup 6 installer script (WPF / .NET 8 edition)
;
; Usage:
;   Local:  iscc installer.iss          (run from PCHealthMonitor-v2\)
;   CI:     Patched automatically by GitHub Actions
;
; Output:  dist\PCHealthMonitor-Setup-<version>.exe
; Requires: Inno Setup 6.3+  https://jrsoftware.org/isinfo.php
; ─────────────────────────────────────────────────────────────────────────────

#define AppName      "PC Health Monitor"
#define AppVersion   "2.0.0"
#define AppPublisher "Rotem Zussman"
#define AppURL       "https://github.com/Rzuss/PC-Health-Monitor"
#define AppExeName   "PCHealthMonitor.exe"
#define AppID        "{{B3D9F4A2-7C1E-4D8B-A5F6-2E0C8B3D1F9A}"
#define PublishDir   "PCHealthMonitor\bin\Release\net8.0-windows\win-x64\publish"

; ── Setup ────────────────────────────────────────────────────────────────────
[Setup]
AppId={#AppID}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={localappdata}\PCHealthMonitor
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=PCHealthMonitor-Setup-{#AppVersion}
WizardStyle=modern
WizardResizable=yes
DisableProgramGroupPage=yes
AllowNoIcons=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Installer
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}
VersionInfoProductVersion={#AppVersion}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
CreateUninstallRegKey=yes

; ── Languages ─────────────────────────────────────────────────────────────────
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; ── Tasks ─────────────────────────────────────────────────────────────────────
[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checked
Name: "startuptask"; Description: "Start with &Windows (silent background cleanup)"; GroupDescription: "Startup:"; Flags: unchecked

; ── Files ─────────────────────────────────────────────────────────────────────
[Files]
; Self-contained single-file exe — .NET 8 runtime embedded, no prerequisite needed
Source: "{#PublishDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; App icon used by shortcuts
Source: "PCHealthMonitor\Assets\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

; ── Icons ─────────────────────────────────────────────────────────────────────
[Icons]
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\icon.ico"; Comment: "Real-time PC health dashboard"; Tasks: desktopicon
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\icon.ico"; Comment: "Real-time PC health dashboard"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

; ── Registry ──────────────────────────────────────────────────────────────────
[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "PCHealthMonitor"; ValueData: """{app}\{#AppExeName}"" --silent"; Flags: uninsdeletevalue; Tasks: startuptask

; ── Run after install ─────────────────────────────────────────────────────────
[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName} now"; Flags: nowait postinstall skipifsilent

; ── Uninstall cleanup ─────────────────────────────────────────────────────────
[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\PCHealthMonitor\Logs"

; ── Code ──────────────────────────────────────────────────────────────────────
[Code]
function InitializeSetup(): Boolean;
var
  WinVer: TWindowsVersion;
begin
  Result := True;
  GetWindowsVersionEx(WinVer);
  if WinVer.Major < 10 then
  begin
    MsgBox(
      'PC Health Monitor requires Windows 10 or later.' + #13#10 +
      'Your system is running an older version of Windows.',
      mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    AppDataDir := ExpandConstant('{localappdata}\PCHealthMonitor');
    if DirExists(AppDataDir) then
    begin
      if MsgBox(
        'Remove all PC Health Monitor data and settings?' + #13#10 +
        '(Stored in: ' + AppDataDir + ')',
        mbConfirmation, MB_YESNO) = IDYES then
      begin
        DelTree(AppDataDir, True, True, True);
      end;
    end;
  end;
end;
