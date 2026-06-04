; Inno Setup 6 — Junior Eventos (Windows)
; Requisito: https://jrsoftware.org/isdl.php
; Alinear MyAppVersion con pubspec.yaml (línea version: X.Y.Z+build → aquí X.Y.Z).
;
; Nombre del .exe del instalador: "Setup Junior Eventos v" + versión (| no es válido en nombres de archivo en Windows).
; ISPP reserva "checked" en [Tasks] Flags — la tarea desktopicon se marca por código abajo.

#define MyAppName "Junior Eventos"
#define MyShortcutName "Junior Eventos"
#define MyAppVersion "3.6.0"
#define MyAppPublisher "Junior Eventos"
#define MyAppExeName "arguello_events.exe"
#define SourceIcon "..\\windows\\runner\\resources\\app_icon.ico"

[Setup]
AppId={{A7E2F9B1-4C3D-5E6F-8091-2B3C4D5E6F70}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=Setup Junior Eventos v{#MyAppVersion}
SetupIconFile={#SourceIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no
PrivilegesRequired=admin
; Propiedades del Setup.exe en el explorador (icono = SetupIconFile arriba)
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoProductTextVersion={#MyAppVersion}

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo Junior Eventos en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Icono del acceso = app .exe (recursos) — coherente con el instalador (mismo app_icon en el build).
Name: "{group}\{#MyShortcutName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyShortcutName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
procedure InitializeWizard;
begin
  WizardSelectTasks('desktopicon');
end;
