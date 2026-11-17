; Nami's Windows installer (Inno Setup 6). Build it with:
;   ISCC.exe /DAppVersion=0.8.3 mobile\windows\installer\nami.iss
; after `flutter build windows --release`. It installs for the current user only
; (no administrator prompt), adds Nami to the Start menu, and upgrades in place.
; Settings, sources and the AniList login live in %APPDATA%\com.raphr\nami and
; are never touched, by installing or uninstalling.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define Build "..\..\build\windows\x64\runner\Release"
; The 64-bit System32: the compiler is a 32-bit program, which Windows sends to SysWOW64.
#define System GetEnv('SystemRoot') + "\Sysnative"

[Setup]
; Never change: later installers find and replace this installation by it.
AppId={{581F5381-193B-4CBE-98A8-1DC5A70664C3}
AppName=Nami
AppVersion={#AppVersion}
AppVerName=Nami {#AppVersion}
AppPublisher=raph559
AppPublisherURL=https://github.com/raph559/Nami
AppSupportURL=https://github.com/raph559/Nami/issues
DefaultDirName={autopf}\Nami
DefaultGroupName=Nami
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=Nami-{#AppVersion}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nami.exe
UninstallDisplayName=Nami
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The app, without the browser data a run leaves next to it.
Source: "{#Build}\*"; DestDir: "{app}"; Excludes: "nami.exe.WebView2"; Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft's C++ runtime, next to the app so it starts on a PC that never had it.
Source: "{#System}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#System}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#System}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
; An upgrade starts from a clean folder, so files an older version had do not linger.
Type: filesandordirs; Name: "{app}\data"

[Icons]
; In the Start menu, so typing "Nami" in Start finds it.
Name: "{autoprograms}\Nami"; Filename: "{app}\nami.exe"
Name: "{autodesktop}\Nami"; Filename: "{app}\nami.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nami.exe"; Description: "{cm:LaunchProgram,Nami}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; What Nami's own runs create in its folder.
Type: filesandordirs; Name: "{app}\nami.exe.WebView2"
