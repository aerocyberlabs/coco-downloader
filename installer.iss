; Inno Setup script for ACL Downloader
; Build: run with ISCC on Windows after PyInstaller output exists in dist\acl-downloader

; Define macros with priority: CLI /D > env > default
#ifdef MyAppName
  ; provided by /D on command line
#else
  #if GetEnv("APP_NAME") != ""
    #define MyAppName GetEnv("APP_NAME")
  #else
    #define MyAppName "Coco Downloader"
  #endif
#endif

#ifdef MyAppSlug
  ; provided by /D on command line
#else
  #if GetEnv("APP_SLUG") != ""
    #define MyAppSlug GetEnv("APP_SLUG")
  #else
    #define MyAppSlug "coco-downloader"
  #endif
#endif

#ifdef MyAppVersion
  ; provided by /D on command line
#else
  #if GetEnv("APP_VERSION") != ""
    #define MyAppVersion GetEnv("APP_VERSION")
  #else
    #define MyAppVersion "0.1.0"
  #endif
#endif
#define MyAppPublisher "ACL"

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
SignedUninstaller=no


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Main executable (unsigned by default)
Source: "dist\{#MyAppSlug}\{#MyAppSlug}.exe"; DestDir: "{app}"; Flags: ignoreversion; 
; Include the rest of the files
Source: "dist\{#MyAppSlug}\*"; Excludes: "{#MyAppSlug}.exe"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppSlug}.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppSlug}.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppSlug}.exe"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
