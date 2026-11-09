; Inno Setup script for the native AuraTube Windows app.
; Built by AuraTubeWindows/build.ps1: iscc /DAppVersion=x.y.z /DSourceDir=<publish dir> /DOutputDir=<dist>

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
AppId={{6E2B7C1A-6F0B-4C55-9C3E-AF7A2D5E0B11}
AppName=AuraTube
AppVersion={#AppVersion}
AppPublisher=AuraTube
AppPublisherURL=https://github.com/tung68nt/AuraTube
DefaultDirName={localappdata}\Programs\AuraTube Native
DefaultGroupName=AuraTube
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=AuraTube-Windows-Setup-v{#AppVersion}
SetupIconFile=..\src\AuraTube\Assets\AuraTube.ico
UninstallDisplayIcon={app}\AuraTube.exe
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=force

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\AuraTube"; Filename: "{app}\AuraTube.exe"
Name: "{autodesktop}\AuraTube"; Filename: "{app}\AuraTube.exe"; Tasks: desktopicon

[Run]
; Interactive install: offer to launch. Silent install (auto-update): always relaunch.
Filename: "{app}\AuraTube.exe"; Description: "{cm:LaunchProgram,AuraTube}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\AuraTube.exe"; Flags: nowait; Check: WizardSilent
