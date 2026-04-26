; ─────────────────────────────────────────────────────────────────────────────
; PC Health Monitor — Inno Setup 6 installer script (WPF / .NET 8 edition)
;
; Usage:
;   Local:  iscc installer.iss
;   CI:     Patched automatically by GitHub Actions (AppVersion, PublishDir)
;
; Output:  dist\PCHealthMonitor-Setup-<version>.exe
; Requires: Inno Setup 6.3+ (https://jrsoftware.org/isinfo.php)
; ─────────────────────────────────────────────────────────────────────────────

#define AppName        "PC Health Monitor"
#define AppVersion     "2.0.0"
#define AppPublisher   "Rotem Zussman"
#define AppURL         "https://github.com/Rzuss/PC-Health-Monitor"
#define AppExeName     "PCHealthMonitor.exe"
#define AppID          "{{B3D9F4A2-7C1E-4D8B-A5F6-2E0C8B3D1F9A}"
#define PublishDir     "PCHealthMonitor\bin\Release\net8.0-windows\win-x64\publish"

[Setup]
; ── Identity ──────────────────────────────────────────────────────────────────
AppId={#AppID}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases

; ── Paths & output ────────────────────────────────────────────────────────────
DefaultDirName={localappdata}\PCHealthMonitor
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=PCHealthMonitor-Setup-{#AppVersion}

; ── UI & behaviour ────────────────────────────────────────────────────────────
WizardStyle=modern
WizardResizable=yes
DisableProgramGroupPage=yes
AllowNoIcons=yes
; No admin required — installs to %LocalAppData%
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; ── Compression ───────────────────────────────────────────────────────────────
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes

; ── Version info (shown in Programs & Features) ───────────────────────────────
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Installer
VersionInfoCopyright=Copyright © 2026 {#AppPublisher}
VersionInfoProductVersion={#AppVersion}

; ── Uninstall ─────────────────────────────────────────────────────────────────
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
CreateUninstallRegKey=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";  Description: "Create a &desktop shortcut";    GroupDescription: "Shortcuts:"; Flags: checked
Name: "startuptask";  Description: "Start with &Windows (background)"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
; ── Self-contained single-file exe (produced by dotnet publish -c Release) ───
; All .NET 8 runtime dependencies are embedded — no prerequisite installer needed.
Source: "{#PublishDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; ── App icon (for shortcuts) ──────────────────────────────────────────────────
Source: "PCHealthMonitor\Assets\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Desktop shortcut
Name: "{autodesktop}\{#AppName}";
  Filename: "{app}\{#AppExeName}";
  IconFilename: "{app}\icon.ico";
  Comment: "Real-time PC health dashboard";
  Tasks: desktopicon

; Start Menu
Name: "{group}\{#AppName}";
  Filename: "{app}\{#AppExeName}";
  IconFilename: "{app}\icon.ico";
  Comment: "Real-time PC health dashboard"

Name: "{group}\Uninstall {#AppName}";
  Filename: "{uninstallexe}"

[Registry]
; ── Windows startup (optional task) ───────────────────────────────────────────
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run";
  ValueType: string; ValueName: "PCHealthMonitor";
  ValueData: """{app}\{#AppExeName}"" --silent";
  Flags: uninsdeletevalue; Tasks: startuptask

[Run]
; Offer to launch after install
Filename: "{app}\{#AppExeName}";
  Description: "Launch {#AppName} now";
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove generated log files on uninstall
Type: filesandordirs; Name: "{localappdata}\PCHealthMonitor\Logs"

[Code]
// ── Pre-install checks ────────────────────────────────────────────────────────
function InitializeSetup(): Boolean;
var
  WinVer: TWindowsVersion;
begin
  Result := True;

  // Require Windows 10 (build 10240) or later
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

// ── Post-uninstall cleanup ────────────────────────────────────────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Remove settings.json from %AppData%\PCHealthMonitor if the user
    // did not have the Logs folder (i.e. they want a clean uninstall)
    AppDataDir := ExpandConstant('{localappdata}\PCHealthMonitor');
    if DirExists(AppDataDir) then
    begin
      if MsgBox(
        'Remove all PC Health Monitor data and settings?' + #13#10 +
        '(Logs and preferences stored in ' + AppDataDir + ')',
        mbConfirmation, MB_YESNO) = IDYES then
      begin
        DelTree(AppDataDir, True, True, True);
      end;
    end;
  end;
end;
