unit LoggerPro.SmartInspectAppender;

interface

uses
  System.SysUtils,
  LoggerPro;

type
  TLoggerProSmartInspectAppender = class(TLoggerProAppenderBase)
  public
    procedure WriteLog(const aLogItem: TLogItem); override;
    procedure Setup; override;
    procedure TearDown; override;
  end;

implementation

uses
  SmartInspect.Core.SiAuto,
  SmartInspect.Core,
  LoggerPro.Builder,
  MVCFramework.Logger;

{ TLoggerProSmartInspectAppender }

procedure TLoggerProSmartInspectAppender.Setup;
begin
  inherited;
  // Opzionale: Configura SmartInspect qui se non lo fai altrove
  Si.Enabled := True;
end;

procedure TLoggerProSmartInspectAppender.TearDown;
begin
  inherited;
end;

procedure TLoggerProSmartInspectAppender.WriteLog(const aLogItem: TLogItem);
begin
  // Mappatura dei livelli di log tra LoggerPro e SmartInspect
  case aLogItem.LogType of
    TLogType.Debug:
      SiMain.LogDebug(aLogItem.LogMessage);
    TLogType.Info:
      SiMain.LogVerbose(aLogItem.LogMessage);
    TLogType.Warning:
      SiMain.LogWarning(aLogItem.LogMessage);
    TLogType.Error:
      SiMain.LogError(aLogItem.LogMessage);
    TLogType.Fatal:
      SiMain.LogFatal(aLogItem.LogMessage);
  else
    SiMain.LogMessage(aLogItem.LogMessage);
  end;
end;


// var
// _Log: ILogWriter;

initialization

var
  _Log: ILogWriter := LoggerProBuilder
  .WriteToFile
    .WithLogsFolder('logs')
    .WithMaxBackupFiles(5)
    .WithMaxFileSizeInKB(10000)
  .Done
  .WriteToConsole
  .Done
  .WriteToAppender(TLoggerProSmartInspectAppender.Create)
  .Build;

 SetDefaultLogger(_Log);

end.
