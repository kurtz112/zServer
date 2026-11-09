unit eSignAnyWhere.params;

interface

uses
  System.SysUtils;

type
  TeSignAnyWhereEmailParams = record
  public
    procedure Init;
    procedure Assign(src: TeSignAnyWhereEmailParams);
  private
    FRequireViewContentBeforeFormFilling: boolean;
    Femail: string;
    FAllowAccessAfterFinish: boolean;
    FCognome: string;
    FTelefono: string;
    FNotificationChannel: string;
    FNome: string;
    FAllowDelegation: boolean;
    FAppLinks_AndroId: boolean;
    FAppLinks_IOS: boolean;
    FAppLinks_Windows: boolean;
    FIdentificativoFirmaRemota: string;
    FLanguageCode: string;
    FPlaceHolder: string;
    FSequenceMode: string;
    FSigningGroup: string;
    procedure SetCognome(const Value: string);
    procedure Setemail(const Value: string);
    procedure SetIdentificativoFirmaRemota(const Value: string);
    procedure SetNome(const Value: string);
    procedure SetPlaceHolder(const Value: string);
    procedure SetTelefono(const Value: string);
  public
    property AllowAccessAfterFinish: boolean read FAllowAccessAfterFinish write FAllowAccessAfterFinish;
    property AllowDelegation: boolean read FAllowDelegation write FAllowDelegation;

    property AppLinks_AndroId: boolean read FAppLinks_AndroId write FAppLinks_AndroId;
    property AppLinks_IOS: boolean read FAppLinks_IOS write FAppLinks_IOS;
    property AppLinks_Windows: boolean read FAppLinks_Windows write FAppLinks_Windows;

    property RequireViewContentBeforeFormFilling: boolean read FRequireViewContentBeforeFormFilling write FRequireViewContentBeforeFormFilling;
    property LanguageCode: string read FLanguageCode write FLanguageCode;
    property NotificationChannel: string read FNotificationChannel write FNotificationChannel;

    property SequenceMode: string read FSequenceMode write FSequenceMode;
    property SigningGroup: string read FSigningGroup write FSigningGroup;
  public
    property IdentificativoFirmaRemota: string read FIdentificativoFirmaRemota write SetIdentificativoFirmaRemota;
    property PlaceHolder: string read FPlaceHolder write SetPlaceHolder;
    property Cognome: string read FCognome write SetCognome;
    property Nome: string read FNome write SetNome;
    property email: string read Femail write Setemail;
    property Telefono: string read FTelefono write SetTelefono;
  end;

  TeSignAnyWhereParams = record
  private
    FAddDocumentTimestamp: boolean;
    FBeforeExpirationInDays: integer;
    FEmailConfigurationMessage: string;
    FEmailConfigurationSubject: string;
    FEnvelopeId: string;
    FEnvelopeName: string;
    FExpirationInSecondsAfterSending: integer;
    FFileId: string;
    FFirmaRemota1: TeSignAnyWhereEmailParams;
    FFirmaRemota2: TeSignAnyWhereEmailParams;
    FFirmaOTP: TeSignAnyWhereEmailParams;
    FFirstReminderInDays: integer;
    FIdent: String;
    FLogResponse: boolean;
    FReminder: boolean;
    FReminderResendIntervalInDays: integer;
    FShareWithTeam: boolean;
  private
    procedure SetAddDocumentTimestamp(const Value: boolean);
    procedure SetBeforeExpirationInDays(const Value: integer);
    procedure SetEmailConfigurationMessage(const Value: string);
    procedure SetEmailConfigurationSubject(const Value: string);
    procedure SetFileId(const Value: string);
    procedure SetEnvelopeId(const Value: string);
    procedure SetEnvelopeName(const Value: string);
    procedure SetExpirationInSecondsAfterSending(const Value: integer);
    procedure SetFirmaRemota1(const Value: TeSignAnyWhereEmailParams);
    procedure SetFirmaRemota2(const Value: TeSignAnyWhereEmailParams);
    procedure SetFirmaOTP(const Value: TeSignAnyWhereEmailParams);
    procedure SetFirstReminderInDays(const Value: integer);
    procedure SetIdent(const Value: String);
    procedure SetLogResponse(const Value: boolean);
    procedure SetReminder(const Value: boolean);
    procedure SetReminderResendIntervalInDays(const Value: integer);
    procedure SetShareWithTeam(const Value: boolean);
  public
    procedure Init;
    procedure Assign(src: TeSignAnyWhereParams);

    procedure CheckFileId;
    procedure CheckEnvelopeId;
  public
    property EnvelopeName: string read FEnvelopeName write SetEnvelopeName;
    property Ident: String read FIdent write SetIdent;

    property AddDocumentTimestamp: boolean read FAddDocumentTimestamp write SetAddDocumentTimestamp;
    property ShareWithTeam: boolean read FShareWithTeam write SetShareWithTeam;

    property EmailConfigurationSubject: string read FEmailConfigurationSubject write SetEmailConfigurationSubject;
    property EmailConfigurationMessage: string read FEmailConfigurationMessage write SetEmailConfigurationMessage;

    //
    property Reminder: boolean read FReminder write SetReminder;
    property FirstReminderInDays: integer read FFirstReminderInDays write SetFirstReminderInDays;
    property ReminderResendIntervalInDays: integer read FReminderResendIntervalInDays write SetReminderResendIntervalInDays;
    property BeforeExpirationInDays: integer read FBeforeExpirationInDays write SetBeforeExpirationInDays;
    property ExpirationInSecondsAfterSending: integer read FExpirationInSecondsAfterSending write SetExpirationInSecondsAfterSending;

    property LogResponse: boolean read FLogResponse write SetLogResponse;

    property FirmaRemota1: TeSignAnyWhereEmailParams read FFirmaRemota1 write SetFirmaRemota1;
    property FirmaRemota2: TeSignAnyWhereEmailParams read FFirmaRemota2 write SetFirmaRemota2;
    property FirmaOTP: TeSignAnyWhereEmailParams read FFirmaOTP write SetFirmaOTP;
  public
    property FileId: string read FFileId write SetFileId;
    property EnvelopeId: string read FEnvelopeId write SetEnvelopeId;
  end;

implementation

procedure TeSignAnyWhereParams.Init;
begin

  FEnvelopeName := '';
  FFileId := '';
  FEnvelopeId := '';

  FIdent := '';
  FAddDocumentTimestamp := false;
  FShareWithTeam := false;
  FReminder := True;
  FFirstReminderInDays := 1;
  FReminderResendIntervalInDays := 1;
  FBeforeExpirationInDays := 3;
  FExpirationInSecondsAfterSending := 2419200;

  FEmailConfigurationSubject := 'Per favore firmi il contratto allegato';
  FEmailConfigurationMessage := 'Gentile #RecipientFirstName# #RecipientLastName#\n\n#PersonalMessage#\n\nla prego di firmare la pratica #EnvelopeName#\n\nLa pratica scadrà il #ExpirationDate#0';

  FLogResponse := True;

  FFirmaRemota1.Init;
  FFirmaRemota2.Init;
  FFirmaOTP.Init;
end;

procedure TeSignAnyWhereParams.Assign(src: TeSignAnyWhereParams);
begin
  //
  FEnvelopeName := src.EnvelopeName;
  FFileId := src.FileId;
  FEnvelopeId := src.EnvelopeId;
  //
  FIdent := src.Ident;
  FAddDocumentTimestamp := src.AddDocumentTimestamp;
  FShareWithTeam := src.ShareWithTeam;
  FReminder := src.Reminder;
  FFirstReminderInDays := src.FirstReminderInDays;
  FReminderResendIntervalInDays := src.ReminderResendIntervalInDays;
  FBeforeExpirationInDays := src.BeforeExpirationInDays;
  FExpirationInSecondsAfterSending := src.ExpirationInSecondsAfterSending;

  FEmailConfigurationSubject := src.EmailConfigurationSubject;
  FEmailConfigurationMessage := src.EmailConfigurationMessage;

  FLogResponse := src.LogResponse;

  FFirmaRemota1.Assign(src.FirmaRemota1);
  FFirmaRemota2.Assign(src.FirmaRemota2);
  FFirmaOTP.Assign(src.FirmaOTP);
end;

procedure TeSignAnyWhereParams.CheckEnvelopeId;
begin

  if EnvelopeId.IsEmpty then
    raise Exception.Create('EnvelopeId non specificato.');
end;

procedure TeSignAnyWhereParams.CheckFileId;
begin

  if FileId.IsEmpty then
    raise Exception.Create('FileId non specificato.');
end;

procedure TeSignAnyWhereParams.SetAddDocumentTimestamp(const Value: boolean);
begin
  FAddDocumentTimestamp := Value;
end;

procedure TeSignAnyWhereParams.SetBeforeExpirationInDays(const Value: integer);
begin
  FBeforeExpirationInDays := Value;
end;

procedure TeSignAnyWhereParams.SetEmailConfigurationMessage(const Value: string);
begin
  FEmailConfigurationMessage := Value;
end;

procedure TeSignAnyWhereParams.SetEmailConfigurationSubject(const Value: string);
begin
  FEmailConfigurationSubject := Value;
end;

procedure TeSignAnyWhereParams.SetEnvelopeId(const Value: string);
begin
  FEnvelopeId := Value;
end;

procedure TeSignAnyWhereParams.SetEnvelopeName(const Value: string);
begin
  FEnvelopeName := Value;
end;

procedure TeSignAnyWhereParams.SetExpirationInSecondsAfterSending(const Value: integer);
begin
  FExpirationInSecondsAfterSending := Value;
end;

procedure TeSignAnyWhereParams.SetFileId(const Value: string);
begin
  FFileId := Value;
end;

procedure TeSignAnyWhereParams.SetFirmaRemota1(const Value: TeSignAnyWhereEmailParams);
begin
  FFirmaRemota1.Assign(Value);
end;

procedure TeSignAnyWhereParams.SetFirmaRemota2(const Value: TeSignAnyWhereEmailParams);
begin
  FFirmaRemota2.Assign(Value);
end;

procedure TeSignAnyWhereParams.SetFirmaOTP(const Value: TeSignAnyWhereEmailParams);
begin
  FFirmaOTP.Assign(Value);
end;

procedure TeSignAnyWhereParams.SetFirstReminderInDays(const Value: integer);
begin
  FFirstReminderInDays := Value;
end;

procedure TeSignAnyWhereParams.SetIdent(const Value: String);
begin
  FIdent := Value;
end;

procedure TeSignAnyWhereParams.SetLogResponse(const Value: boolean);
begin
  FLogResponse := Value;
end;

procedure TeSignAnyWhereParams.SetReminder(const Value: boolean);
begin
  FReminder := Value;
end;

procedure TeSignAnyWhereParams.SetReminderResendIntervalInDays(const Value: integer);
begin
  FReminderResendIntervalInDays := Value;
end;

procedure TeSignAnyWhereParams.SetShareWithTeam(const Value: boolean);
begin
  FShareWithTeam := Value;
end;

{ TeSignAnyWhereEmailParams }

procedure TeSignAnyWhereEmailParams.Assign(src: TeSignAnyWhereEmailParams);
begin
  FAllowAccessAfterFinish := src.AllowAccessAfterFinish;
  FAllowDelegation := src.AllowDelegation;
  FAppLinks_AndroId := src.AppLinks_AndroId;
  FAppLinks_IOS := src.AppLinks_IOS;
  FAppLinks_Windows := src.AppLinks_Windows;
  FRequireViewContentBeforeFormFilling := src.RequireViewContentBeforeFormFilling;
  FLanguageCode := src.LanguageCode;
  FNotificationChannel := src.NotificationChannel;

  FSequenceMode := src.SequenceMode;
  FSigningGroup := src.SigningGroup;

  FIdentificativoFirmaRemota := src.IdentificativoFirmaRemota;
  FPlaceHolder := src.PlaceHolder;
  FCognome := src.Cognome;
  FNome := src.Nome;
  Femail := src.email;
  FTelefono := src.Telefono;
end;

procedure TeSignAnyWhereEmailParams.Init;
begin
  FAllowAccessAfterFinish := false;
  FAllowDelegation := false;

  FAppLinks_AndroId := True;
  FAppLinks_IOS := True;
  FAppLinks_Windows := True;

  FRequireViewContentBeforeFormFilling := false;
  FLanguageCode := 'IT';
  FNotificationChannel := 'Email';

  FSequenceMode := 'NoSequenceEnforced';
  FSigningGroup := '1';

  FIdentificativoFirmaRemota := '';
  FPlaceHolder := '';
  FCognome := '';
  FNome := '';
  Femail := '';
  FTelefono := '';
end;

procedure TeSignAnyWhereEmailParams.SetCognome(const Value: string);
begin
  FCognome := Value;
end;

procedure TeSignAnyWhereEmailParams.Setemail(const Value: string);
begin
  Femail := Value;
end;

procedure TeSignAnyWhereEmailParams.SetIdentificativoFirmaRemota(const Value: string);
begin
  FIdentificativoFirmaRemota := Value;
end;

procedure TeSignAnyWhereEmailParams.SetNome(const Value: string);
begin
  FNome := Value;
end;

procedure TeSignAnyWhereEmailParams.SetPlaceHolder(const Value: string);
begin
  FPlaceHolder := Value;
end;

procedure TeSignAnyWhereEmailParams.SetTelefono(const Value: string);
begin
  FTelefono := Value;
end;

end.
