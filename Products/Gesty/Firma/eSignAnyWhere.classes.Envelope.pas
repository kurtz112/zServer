unit eSignAnyWhere.classes.Envelope;

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
  TAllowedSignatureTypes = class;
  TContactInformation = class;
  TDateFields = class;
  TElements = class;
  TFieldDefinition = class;
  TFullNameFields = class;
  TIncludedEmailAppLinks = class;
  TPosition = class;
  TPredefinedFieldElements = class;
  TRecipientConfiguration = class;
  TSign = class;
  TSignatures = class;
  TSignAutomatic = class;
  TSize = class;
  TStampImprintConfiguration = class;
  TTaskConfiguration = class;
  TTextFields = class;
  TTextFormat = class;
  TVisibilityOptions = class;
  TVisibleSignatures = class;

  TTaskConfiguration = class
  private
    FBatchGroup: string;
  published
    property BatchGroup: string read FBatchGroup write FBatchGroup;
  end;

  TReminderConfiguration = class
  private
    FBeforeExpirationInDays: Integer;
    FEnabled: Boolean;
    FFirstReminderInDays: Integer;
    FReminderResendIntervalInDays: Integer;
  published
    property BeforeExpirationInDays: Integer read FBeforeExpirationInDays write FBeforeExpirationInDays;
    property Enabled: Boolean read FEnabled write FEnabled;
    property FirstReminderInDays: Integer read FFirstReminderInDays write FFirstReminderInDays;
    property ReminderResendIntervalInDays: Integer read FReminderResendIntervalInDays write FReminderResendIntervalInDays;
  end;

  TExpirationConfiguration = class
  private
    FExpirationInSecondsAfterSending: Integer;
  published
    property ExpirationInSecondsAfterSending: Integer read FExpirationInSecondsAfterSending write FExpirationInSecondsAfterSending;
  end;

  TEmailConfiguration = class
  private
    FMessage: string;
    FSubject: string;
  published
    property Message: string read FMessage write FMessage;
    property Subject: string read FSubject write FSubject;
  end;

  TDocuments = class
  private
    FDocumentNumber: Integer;
    FFileId: string;
  published
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property FileId: string read FFileId write FFileId;
  end;

  TVisibilityOptions = class
  private
    FDocumentNumber: Integer;
    FIsHidden: Boolean;
  published
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property IsHidden: Boolean read FIsHidden write FIsHidden;
  end;

  TIncludedEmailAppLinks = class
  private
    FAndroId: Boolean;
    FIOS: Boolean;
    FWindows: Boolean;
  published
    property AndroId: Boolean read FAndroId write FAndroId;
    property IOS: Boolean read FIOS write FIOS;
    property Windows: Boolean read FWindows write FWindows;
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

  TRecipientConfiguration = class
  private
    FAllowAccessAfterFinish: Boolean;
    FAllowDelegation: Boolean;
    FContactInformation: TContactInformation;
    FIncludedEmailAppLinks: TIncludedEmailAppLinks;
    FNotificationChannel: string;
    FRequireViewContentBeforeFormFilling: Boolean;
  published
    property AllowAccessAfterFinish: Boolean read FAllowAccessAfterFinish write FAllowAccessAfterFinish;
    property AllowDelegation: Boolean read FAllowDelegation write FAllowDelegation;
    property ContactInformation: TContactInformation read FContactInformation;
    property IncludedEmailAppLinks: TIncludedEmailAppLinks read FIncludedEmailAppLinks;
    property NotificationChannel: string read FNotificationChannel write FNotificationChannel;
    property RequireViewContentBeforeFormFilling: Boolean read FRequireViewContentBeforeFormFilling write FRequireViewContentBeforeFormFilling;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TTextFormat = class
  private
    FBold: Boolean;
    FFontName: string;
    FFontSizeInPt: Double;
    FItalic: Boolean;
    FTextAlign: string;
    FTextColor: string;
  published
    property Bold: Boolean read FBold write FBold;
    property FontName: string read FFontName write FFontName;
    property FontSizeInPt: Double read FFontSizeInPt write FFontSizeInPt;
    property Italic: Boolean read FItalic write FItalic;
    property TextAlign: string read FTextAlign write FTextAlign;
    property TextColor: string read FTextColor write FTextColor;
  end;

  TSize = class
  private
    FHeight: Double;
    FWidth: Double;
  published
    property Height: Double read FHeight write FHeight;
    property Width: Double read FWidth write FWidth;
  end;

  TPosition = class
  private
    FPageNumber: Integer;
    FX: Double;
    FY: Double;
  published
    property PageNumber: Integer read FPageNumber write FPageNumber;
    property X: Double read FX write FX;
    property Y: Double read FY write FY;
  end;

  TFieldDefinition = class
  private
    FPosition: TPosition;
    FSize: TSize;
    FTextFormat: TTextFormat;
  published
    property Position: TPosition read FPosition;
    property Size: TSize read FSize;
    property TextFormat: TTextFormat read FTextFormat;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TStampImprintConfiguration = class
  private
    FDisplayExtraInformation: Boolean;
    FDisplayIp: Boolean;
    FDisplayName: Boolean;
    FDisplayPhoneNumber: Boolean;
    FDisplaySignatureDate: Boolean;
    FDisplayTransactionId: Boolean;
    FDisplayTransactionToken: Boolean;
    FFontName: string;
    FFontSizeInPt: Integer;
  published
    property DisplayExtraInformation: Boolean read FDisplayExtraInformation write FDisplayExtraInformation;
    property DisplayIp: Boolean read FDisplayIp write FDisplayIp;
    property DisplayName: Boolean read FDisplayName write FDisplayName;
    property DisplayPhoneNumber: Boolean read FDisplayPhoneNumber write FDisplayPhoneNumber;
    property DisplaySignatureDate: Boolean read FDisplaySignatureDate write FDisplaySignatureDate;
    property DisplayTransactionId: Boolean read FDisplayTransactionId write FDisplayTransactionId;
    property DisplayTransactionToken: Boolean read FDisplayTransactionToken write FDisplayTransactionToken;
    property FontName: string read FFontName write FFontName;
    property FontSizeInPt: Integer read FFontSizeInPt write FFontSizeInPt;
  end;

  TOneTimePassword = class
  private
    FPreferred: Boolean;
    FStampImprintConfiguration: TStampImprintConfiguration;
    FUseExternalSignatureImage: string;
  published
    property Preferred: Boolean read FPreferred write FPreferred;
    property StampImprintConfiguration: TStampImprintConfiguration read FStampImprintConfiguration;
    property UseExternalSignatureImage: string read FUseExternalSignatureImage write FUseExternalSignatureImage;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TAllowedSignatureTypes = class
  private
    FOneTimePassword: TOneTimePassword;
  published
    property OneTimePassword: TOneTimePassword read FOneTimePassword;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TSignatures = class
  private
    FAllowedSignatureTypes: TAllowedSignatureTypes;
    FDisplayName: string;
    FDocumentNumber: Integer;
    FElementId: string;
    FFieldDefinition: TFieldDefinition;
    FRequired: Boolean;
    FTaskConfiguration: TTaskConfiguration;
    FUseExternalTimestampServer: Boolean;
  published
    property AllowedSignatureTypes: TAllowedSignatureTypes read FAllowedSignatureTypes;
    property DisplayName: string read FDisplayName write FDisplayName;
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property ElementId: string read FElementId write FElementId;
    property FieldDefinition: TFieldDefinition read FFieldDefinition;
    property Required: Boolean read FRequired write FRequired;
    property TaskConfiguration: TTaskConfiguration read FTaskConfiguration;
    property UseExternalTimestampServer: Boolean read FUseExternalTimestampServer write FUseExternalTimestampServer;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TTextFields = class
  end;

  TFullNameFields = class
  end;

  TDateFields = class
  end;

  TPredefinedFieldElements = class(TJsonDTO)
  private
    [JSONName('dateFields'), JSONMarshalled(False)]
    FDateFieldsArray: TArray<TDateFields>;
    [GenericListReflect]
    FDateFields: TObjectList<TDateFields>;
    [JSONName('fullNameFields'), JSONMarshalled(False)]
    FFullNameFieldsArray: TArray<TFullNameFields>;
    [GenericListReflect]
    FFullNameFields: TObjectList<TFullNameFields>;
    [JSONName('textFields'), JSONMarshalled(False)]
    FTextFieldsArray: TArray<TTextFields>;
    [GenericListReflect]
    FTextFields: TObjectList<TTextFields>;
    function GetDateFields: TObjectList<TDateFields>;
    function GetFullNameFields: TObjectList<TFullNameFields>;
    function GetTextFields: TObjectList<TTextFields>;
  protected
    function GetAsJson: string; override;
  published
    property DateFields: TObjectList<TDateFields> read GetDateFields;
    property FullNameFields: TObjectList<TFullNameFields> read GetFullNameFields;
    property TextFields: TObjectList<TTextFields> read GetTextFields;
  public
    destructor Destroy; override;
  end;

  TElements = class(TJsonDTO)
  private
    FPredefinedFieldElements: TPredefinedFieldElements;
    [JSONName('signatures'), JSONMarshalled(False)]
    FSignaturesArray: TArray<TSignatures>;
    [GenericListReflect]
    FSignatures: TObjectList<TSignatures>;
    function GetSignatures: TObjectList<TSignatures>;
  protected
    function GetAsJson: string; override;
  published
    property PredefinedFieldElements: TPredefinedFieldElements read FPredefinedFieldElements;
    property Signatures: TObjectList<TSignatures> read GetSignatures;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

  TBatchConfiguration = class
  private
    FMode: string;
    FRequireScrollingOverAllSignaturesBeforeSigning: Boolean;
  published
    property Mode: string read FMode write FMode;
    property RequireScrollingOverAllSignaturesBeforeSigning: Boolean read FRequireScrollingOverAllSignaturesBeforeSigning write FRequireScrollingOverAllSignaturesBeforeSigning;
  end;

  TSign = class
  private
    FBatchConfiguration: TBatchConfiguration;
    FElements: TElements;
    FRecipientConfiguration: TRecipientConfiguration;
    FSequenceMode: string;
    FSigningGroup: string;
  published
    property BatchConfiguration: TBatchConfiguration read FBatchConfiguration;
    property Elements: TElements read FElements;
    property RecipientConfiguration: TRecipientConfiguration read FRecipientConfiguration;
    property SequenceMode: string read FSequenceMode write FSequenceMode;
    property SigningGroup: string read FSigningGroup write FSigningGroup;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TAction = class
  private
    FSendCopy: string;
    FSign: TSign;
    FSignAutomatic: TSignAutomatic;
  published
    property SendCopy: string read FSendCopy write FSendCopy;
    property Sign: TSign read FSign write FSign;
    property SignAutomatic: TSignAutomatic read FSignAutomatic write FSignAutomatic;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TVisibleSignatures = class
  private
    FDocumentNumber: Integer;
    FUseExternalTimestampServer: Boolean;
    FFieldDefinition: TFieldDefinition;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property UseExternalTimestampServer: Boolean read FUseExternalTimestampServer write FUseExternalTimestampServer;

    // zz aggiunta
    property FieldDefinition: TFieldDefinition read FFieldDefinition write FFieldDefinition;
  end;

  TSignAutomatic = class(TJsonDTO)
  private
    FProfileId: string;
    FRenderingLanguageCode: string;
    [JSONName('VisibleSignatures'), JSONMarshalled(False)]
    FVisibleSignaturesArray: TArray<TVisibleSignatures>;
    [GenericListReflect]
    FVisibleSignatures: TObjectList<TVisibleSignatures>;
    function GetVisibleSignatures: TObjectList<TVisibleSignatures>;
  protected
    function GetAsJson: string; override;
  published
    property ProfileId: string read FProfileId write FProfileId;
    property RenderingLanguageCode: string read FRenderingLanguageCode write FRenderingLanguageCode;
    property VisibleSignatures: TObjectList<TVisibleSignatures> read GetVisibleSignatures;
  public
    destructor Destroy; override;
  end;

  TActivities = class(TJsonDTO)
  private
    FAction: TAction;
    [JSONName('visibilityOptions'), JSONMarshalled(False)]
    FVisibilityOptionsArray: TArray<TVisibilityOptions>;
    [GenericListReflect]
    FVisibilityOptions: TObjectList<TVisibilityOptions>;
    function GetVisibilityOptions: TObjectList<TVisibilityOptions>;
  protected
    function GetAsJson: string; override;
  published
    property Action: TAction read FAction;
    property VisibilityOptions: TObjectList<TVisibilityOptions> read GetVisibilityOptions;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

  TEnvelope = class(TJsonDTO)
  private
    [JSONName('activities'), JSONMarshalled(False)]
    FActivitiesArray: TArray<TActivities>;
    [GenericListReflect]
    FActivities: TObjectList<TActivities>;
    FAddDocumentTimestamp: Boolean;
    [JSONName('documents'), JSONMarshalled(False)]
    FDocumentsArray: TArray<TDocuments>;
    [GenericListReflect]
    FDocuments: TObjectList<TDocuments>;
    FEmailConfiguration: TEmailConfiguration;
    FExpirationConfiguration: TExpirationConfiguration;
    FLockFormFieldsOnFinish: Boolean;
    FName: string;
    FReminderConfiguration: TReminderConfiguration;
    FShareWithTeam: Boolean;
    function GetActivities: TObjectList<TActivities>;
    function GetDocuments: TObjectList<TDocuments>;
  protected
    function GetAsJson: string; override;
  published
    property Activities: TObjectList<TActivities> read GetActivities;
    property AddDocumentTimestamp: Boolean read FAddDocumentTimestamp write FAddDocumentTimestamp;
    property Documents: TObjectList<TDocuments> read GetDocuments;
    property EmailConfiguration: TEmailConfiguration read FEmailConfiguration;
    property ExpirationConfiguration: TExpirationConfiguration read FExpirationConfiguration;
    property LockFormFieldsOnFinish: Boolean read FLockFormFieldsOnFinish write FLockFormFieldsOnFinish;
    property Name: string read FName write FName;
    property ReminderConfiguration: TReminderConfiguration read FReminderConfiguration;
    property ShareWithTeam: Boolean read FShareWithTeam write FShareWithTeam;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

implementation

{ TRecipientConfiguration }

constructor TRecipientConfiguration.Create;
begin
  inherited;
  FContactInformation := TContactInformation.Create;
  FIncludedEmailAppLinks := TIncludedEmailAppLinks.Create;
end;

destructor TRecipientConfiguration.Destroy;
begin
  FContactInformation.Free;
  FIncludedEmailAppLinks.Free;
  inherited;
end;

{ TFieldDefinition }

constructor TFieldDefinition.Create;
begin
  inherited;
  FPosition := TPosition.Create;
  FSize := TSize.Create;
  FTextFormat := TTextFormat.Create;
end;

destructor TFieldDefinition.Destroy;
begin
  FPosition.Free;
  FSize.Free;
  FTextFormat.Free;
  inherited;
end;

{ TAllowedSignatureTypes }

constructor TAllowedSignatureTypes.Create;
begin
  inherited;
  FOneTimePassword := TOneTimePassword.Create;
end;

destructor TAllowedSignatureTypes.Destroy;
begin
  FOneTimePassword.Free;
  inherited;
end;

{ TSignatures }

constructor TSignatures.Create;
begin
  inherited;
  FAllowedSignatureTypes := TAllowedSignatureTypes.Create;
  FFieldDefinition := TFieldDefinition.Create;
  FTaskConfiguration := TTaskConfiguration.Create;
end;

destructor TSignatures.Destroy;
begin
  FAllowedSignatureTypes.Free;
  FFieldDefinition.Free;
  FTaskConfiguration.Free;
  inherited;
end;

{ TPredefinedFieldElements }

destructor TPredefinedFieldElements.Destroy;
begin
  GetDateFields.Free;
  GetFullNameFields.Free;
  GetTextFields.Free;
  inherited;
end;

function TPredefinedFieldElements.GetDateFields: TObjectList<TDateFields>;
begin
  Result := ObjectList<TDateFields>(FDateFields, FDateFieldsArray);
end;

function TPredefinedFieldElements.GetFullNameFields: TObjectList<TFullNameFields>;
begin
  Result := ObjectList<TFullNameFields>(FFullNameFields, FFullNameFieldsArray);
end;

function TPredefinedFieldElements.GetTextFields: TObjectList<TTextFields>;
begin
  Result := ObjectList<TTextFields>(FTextFields, FTextFieldsArray);
end;

function TPredefinedFieldElements.GetAsJson: string;
begin
  RefreshArray<TDateFields>(FDateFields, FDateFieldsArray);
  RefreshArray<TFullNameFields>(FFullNameFields, FFullNameFieldsArray);
  RefreshArray<TTextFields>(FTextFields, FTextFieldsArray);
  Result := inherited;
end;

{ TElements }

constructor TElements.Create;
begin
  inherited;
  FPredefinedFieldElements := TPredefinedFieldElements.Create;
end;

destructor TElements.Destroy;
begin
  FPredefinedFieldElements.Free;
  GetSignatures.Free;
  inherited;
end;

function TElements.GetSignatures: TObjectList<TSignatures>;
begin
  Result := ObjectList<TSignatures>(FSignatures, FSignaturesArray);
end;

function TElements.GetAsJson: string;
begin
  RefreshArray<TSignatures>(FSignatures, FSignaturesArray);
  Result := inherited;
end;

{ TSign }

constructor TSign.Create;
begin
  inherited;
  FElements := TElements.Create;
  FRecipientConfiguration := TRecipientConfiguration.Create;
  FBatchConfiguration := TBatchConfiguration.Create;
end;

destructor TSign.Destroy;
begin
  FElements.Free;
  FRecipientConfiguration.Free;
  FBatchConfiguration.Free;
  inherited;
end;

{ TAction }

constructor TAction.Create;
begin
  inherited;
  FSendCopy := '';
  // Rendere le props modificabili, senda creazione di default
  FSign := nil; // TSign.Create;
  FSignAutomatic := nil; // TSignAutomatic.Create;
end;

destructor TAction.Destroy;
begin
  FSign.Free;
  FSignAutomatic.Free;
  inherited;
end;

{ TSignAutomatic }

destructor TSignAutomatic.Destroy;
begin
  GetVisibleSignatures.Free;
  inherited;
end;

function TSignAutomatic.GetVisibleSignatures: TObjectList<TVisibleSignatures>;
begin
  Result := ObjectList<TVisibleSignatures>(FVisibleSignatures, FVisibleSignaturesArray);
end;

function TSignAutomatic.GetAsJson: string;
begin
  RefreshArray<TVisibleSignatures>(FVisibleSignatures, FVisibleSignaturesArray);
  Result := inherited;
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
  GetVisibilityOptions.Free;
  inherited;
end;

function TActivities.GetVisibilityOptions: TObjectList<TVisibilityOptions>;
begin
  Result := ObjectList<TVisibilityOptions>(FVisibilityOptions, FVisibilityOptionsArray);
end;

function TActivities.GetAsJson: string;
begin
  RefreshArray<TVisibilityOptions>(FVisibilityOptions, FVisibilityOptionsArray);
  Result := inherited;
end;

{ TRoot }

constructor TEnvelope.Create;
begin
  inherited;
  FEmailConfiguration := TEmailConfiguration.Create;
  FExpirationConfiguration := TExpirationConfiguration.Create;
  FReminderConfiguration := TReminderConfiguration.Create;
end;

destructor TEnvelope.Destroy;
begin
  FEmailConfiguration.Free;
  FExpirationConfiguration.Free;
  FReminderConfiguration.Free;
  GetActivities.Free;
  GetDocuments.Free;
  inherited;
end;

function TEnvelope.GetActivities: TObjectList<TActivities>;
begin
  Result := ObjectList<TActivities>(FActivities, FActivitiesArray);
end;

function TEnvelope.GetDocuments: TObjectList<TDocuments>;
begin
  Result := ObjectList<TDocuments>(FDocuments, FDocumentsArray);
end;

function TEnvelope.GetAsJson: string;
begin
  RefreshArray<TActivities>(FActivities, FActivitiesArray);
  RefreshArray<TDocuments>(FDocuments, FDocumentsArray);
  Result := inherited;
end;

{ TVisibleSignatures }

constructor TVisibleSignatures.Create;
begin
  inherited Create;
  FFieldDefinition := nil;
end;

destructor TVisibleSignatures.Destroy;
begin
  FFieldDefinition.Free;
  inherited;
end;

{ TOneTimePassword }

constructor TOneTimePassword.Create;
begin
  inherited;
  FStampImprintConfiguration := TStampImprintConfiguration.Create;
end;

destructor TOneTimePassword.Destroy;
begin
  FStampImprintConfiguration.Free;
  inherited;
end;

end.
