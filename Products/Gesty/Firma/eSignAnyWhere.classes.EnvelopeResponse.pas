unit eSignAnyWhere.classes.EnvelopeResponse;

interface

uses
  system.SysUtils,
  system.classes,
  system.Generics.Collections,
  REST.Json.Types,
  zz.Json.DTO;

{$M+}

type
  TAction = class;
  TContactInformation = class;
  TSign = class;
  TSignAutomatic = class;

  TSenderUserInformation = class
  private
    FEmail: string;
    FGivenName: string;
    FSurname: string;
  published
    property Email: string read FEmail write FEmail;
    property GivenName: string read FGivenName write FGivenName;
    property Surname: string read FSurname write FSurname;
  end;

  TContactInformation = class
  private
    FEmail: string;
    FGivenName: string;
    FLanguageCode: string;
    FPhoneNumber: string;
    FSurname: string;
  published
    property Email: string read FEmail write FEmail;
    property GivenName: string read FGivenName write FGivenName;
    property LanguageCode: string read FLanguageCode write FLanguageCode;
    property PhoneNumber: string read FPhoneNumber write FPhoneNumber;
    property Surname: string read FSurname write FSurname;
  end;

  TSign = class
  private
    FContactInformation: TContactInformation;
    FSigningGroup: Integer;
  published
    property ContactInformation: TContactInformation read FContactInformation;
    property SigningGroup: Integer read FSigningGroup write FSigningGroup;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TAction = class
  private
    FSign: TSign;
    FSignAutomatic: TSignAutomatic;
  published
    property Sign: TSign read FSign;
    property SignAutomatic: TSignAutomatic read FSignAutomatic;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TSignAutomatic = class
  private
    FProfileId: string;
    FRenderingLanguageCode: string;
  published
    property ProfileId: string read FProfileId write FProfileId;
    property RenderingLanguageCode: string read FRenderingLanguageCode write FRenderingLanguageCode;
  end;

  TActivities = class
  private
    FAction: TAction;
    [SuppressZero]
    FFinishedDate: TDateTime;
    FId: string;
    FStatus: string;
  published
    property Action: TAction read FAction;
    property FinishedDate: TDateTime read FFinishedDate write FFinishedDate;
    property Id: string read FId write FId;
    property Status: string read FStatus write FStatus;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TEnvelopeResponse = class(TJsonDTO)
  private
    [JSONName('Activities'), JSONMarshalled(False)]
    FActivitiesArray: TArray<TActivities>;
    [GenericListReflect]
    FActivities: TObjectList<TActivities>;
    FEnvelopeStatus: string;
    FId: string;
    FName: string;
    FSenderUserInformation: TSenderUserInformation;
    [SuppressZero]
    FSentDate: TDateTime;
    function GetActivities: TObjectList<TActivities>;
  protected
    function GetAsJson: string; override;
  published
    property Activities: TObjectList<TActivities> read GetActivities;
    property EnvelopeStatus: string read FEnvelopeStatus write FEnvelopeStatus;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property SenderUserInformation: TSenderUserInformation read FSenderUserInformation;
    property SentDate: TDateTime read FSentDate write FSentDate;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

implementation

{ TSign }

constructor TSign.Create;
begin
  inherited;
  FContactInformation := TContactInformation.Create;
end;

destructor TSign.Destroy;
begin
  FContactInformation.Free;
  inherited;
end;

{ TAction }

constructor TAction.Create;
begin
  inherited;
  FSignAutomatic := TSignAutomatic.Create;
  FSign := TSign.Create;
end;

destructor TAction.Destroy;
begin
  FSignAutomatic.Free;
  FSign.Free;
  inherited;
end;

{ TActivities }

constructor TActivities.Create;
begin
  inherited;
  FAction := TAction.Create;
end;

destructor TActivities.Destroy;
begin
  FAction.Free;
  inherited;
end;

{ TRoot }

constructor TEnvelopeResponse.Create;
begin
  inherited;
  FSenderUserInformation := TSenderUserInformation.Create;
end;

destructor TEnvelopeResponse.Destroy;
begin
  FSenderUserInformation.Free;
  GetActivities.Free;
  inherited;
end;

function TEnvelopeResponse.GetActivities: TObjectList<TActivities>;
begin
  Result := ObjectList<TActivities>(FActivities, FActivitiesArray);
end;

function TEnvelopeResponse.GetAsJson: string;
begin
  RefreshArray<TActivities>(FActivities, FActivitiesArray);
  Result := inherited;
end;

end.
