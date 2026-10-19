; Inno Setup 6 — Junior Eventos (Windows)
; Requisito: https://jrsoftware.org/isdl.php
; Alinear MyAppVersion con pubspec.yaml (línea version: X.Y.Z+build → aquí X.Y.Z).
;
; Nombre del .exe del instalador: "Setup Junior Eventos v" + versión (| no es válido en nombres de archivo en Windows).
; ISPP reserva "checked" en [Tasks] Flags — la tarea desktopicon se marca por código abajo.

#define MyAppName "Junior Eventos"
#define MyShortcutName "Junior Eventos"
#define MyAppVersion "6.1.0"
#define MyAppPublisher "LM"
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
CloseApplications=yes
CloseApplicationsFilter=arguello_events.exe
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

[InstallDelete]
; La página del celular se reemplaza entera: que no queden archivos de otra versión.
Type: filesandordirs; Name: "{app}\puesto"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; La página del celular de la puerta (build_installer.ps1 la arma en build\puesto).
; La central la busca en la carpeta "puesto" al lado del programa (paginaDelCelularProvider).
Source: "..\build\puesto\*"; DestDir: "{app}\puesto"; Excludes: "*.symbols"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Icono del acceso = app .exe (recursos) — coherente con el instalador (mismo app_icon en el build).
Name: "{group}\{#MyShortcutName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyShortcutName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Los celulares de la puerta entran a la notebook central por el wifi del router
; (CentralPuerta, puertos 8787 a 8796). Sin esta regla Windows los bloquea, y la red
; del router suele quedar como "pública": por eso profile=any. Se borra antes de
; crearla para no juntar una por cada instalación.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Junior Eventos - celulares de la puerta"""; Flags: runhidden; StatusMsg: "Preparando la puerta para los celulares..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Junior Eventos - celulares de la puerta"" dir=in action=allow program=""{app}\{#MyAppExeName}"" protocol=TCP localport=8787-8796 profile=any enable=yes"; Flags: runhidden; StatusMsg: "Preparando la puerta para los celulares..."
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Junior Eventos - celulares de la puerta"""; Flags: runhidden; RunOnceId: "BorrarReglaCelulares"

[Code]
procedure InitializeWizard;
begin
  WizardSelectTasks('desktopicon');
end;
