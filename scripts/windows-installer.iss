#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\\dist"
#endif
#ifndef OutputDir
  #define OutputDir "..\\dist"
#endif
#ifndef OutputName
  #define OutputName "LyricPoster-windows-x64-setup"
#endif

#define AppId "{{1B60D4C8-4892-4F5D-AC34-05DBF2D11621}"

[Setup]
AppId={#AppId}
AppName=词笺 · Lyric Poster
AppVersion={#AppVersion}
AppPublisher=yipianxiaoye
AppPublisherURL=https://github.com/yipianxiaoye/lyric-poster
AppSupportURL=https://github.com/yipianxiaoye/lyric-poster/issues
AppUpdatesURL=https://github.com/yipianxiaoye/lyric-poster/releases/latest
DefaultDirName={localappdata}\Programs\LyricPoster
DefaultGroupName=词笺
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UsePreviousAppDir=yes
CloseApplications=yes
CloseApplicationsFilter=lyric_poster.exe
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lyric_poster.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ShowLanguageDialog=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\词笺"; Filename: "{app}\lyric_poster.exe"
Name: "{autodesktop}\词笺"; Filename: "{app}\lyric_poster.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lyric_poster.exe"; Description: "启动词笺"; Flags: nowait postinstall skipifsilent
Filename: "{app}\lyric_poster.exe"; Description: "启动更新后的词笺"; Flags: nowait postinstall; Check: IsUpdateRun

[Code]
function IsUpdateRun: Boolean;
begin
  Result := CompareText(ExpandConstant('{param:UPDATE|0}'), '1') = 0;
end;
