; Inno Setup script for ACL Downloader
; Build: run with ISCC on Windows after PyInstaller output exists in dist\acl-downloader

#define MyAppName GetEnv("APP_NAME")
#if MyAppName == ""
#define MyAppName "Coco Downloader"
#endif
#define MyAppSlug GetEnv("APP_SLUG")
#if MyAppSlug == ""
#define MyAppSlug "coco-downloader"
#endif
#define MyAppVersion GetEnv("APP_VERSION")
#if MyAppVersion == ""
#define MyAppVersion "0.1.0"
#endif
#define MyAppPublisher "ACL"
#define MyAppExeName "{#MyAppSlug}.exe"

[Setup]
AppId={{9F0F7C8C-9F3E-49E3-9A1C-7D7F0E8D4A6B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={pf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableDirPage=no
DisableProgramGroupPage=yes
OutputDir=installer-output
OutputBaseFilename={#MyAppSlug}-Setup-x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma
SolidCompression=yes
SetupLogging=yes
WizardStyle=modern
SignedUninstaller=yes
SignTool=ms

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Sign the main executable inside the installer
Source: "dist\{#MyAppSlug}\{#MyAppSlug}.exe"; DestDir: "{app}"; Flags: ignoreversion; SignTool=ms
; Include the rest of the files
Source: "dist\{#MyAppSlug}\*"; Excludes: "{#MyAppSlug}.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[SignTool]
; Uses environment variables set by CI to locate PFX and password
#define CodeSignPfx GetEnv("WINDOWS_CERT_PFX_PATH")
#define CodeSignPass GetEnv("WINDOWS_CERT_PASSWORD")
#define TimeStampUrl GetEnv("WINDOWS_TIMESTAMP_URL")
#if TimeStampUrl == ""
#define TimeStampUrl "https://timestamp.digicert.com"
#endif
ms=cmd /c "signtool sign /fd SHA256 /f \"{#CodeSignPfx}\" /p \"{#CodeSignPass}\" /tr \"{#TimeStampUrl}\" /td SHA256 $f"
