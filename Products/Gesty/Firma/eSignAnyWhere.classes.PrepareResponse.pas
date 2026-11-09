unit eSignAnyWhere.classes.PrepareResponse;

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
  TAttachments = class;
  TCheckBoxes = class;
  TClickToSign = class;
  TComboBoxes = class;
  TFieldDefinition = class;
  THyperLinks = class;
  TLinkConfiguration = class;
  TListBoxes = class;
  TPosition = class;
  TRadioButtons = class;
  TSignaturePlugins = class;
  TSignatures = class;
  TSignAutomatic = class;
  TSize = class;
  TTaskConfiguration = class;
  TTextBoxes = class;
  TVisibleSignatures = class;

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
  published
    property Position: TPosition read FPosition;
    property Size: TSize read FSize;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TVisibleSignatures = class
  private
    FDocumentNumber: Integer;
    FFieldDefinition: TFieldDefinition;
    FId: string;
    FUseExternalTimestampServer: Boolean;
  published
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property FieldDefinition: TFieldDefinition read FFieldDefinition;
    property Id: string read FId write FId;
    property UseExternalTimestampServer: Boolean read FUseExternalTimestampServer write FUseExternalTimestampServer;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TSignAutomatic = class(TJsonDTO)
  private
    [JSONName('VisibleSignatures'), JSONMarshalled(False)]
    FVisibleSignaturesArray: TArray<TVisibleSignatures>;
    [GenericListReflect]
    FVisibleSignatures: TObjectList<TVisibleSignatures>;
    function GetVisibleSignatures: TObjectList<TVisibleSignatures>;
  protected
    function GetAsJson: string; override;
  published
    property VisibleSignatures: TObjectList<TVisibleSignatures> read GetVisibleSignatures;
  public
    destructor Destroy; override;
  end;

  TAction = class
  private
    FSignAutomatic: TSignAutomatic;
  published
    property SignAutomatic: TSignAutomatic read FSignAutomatic;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TActivities = class
  private
    FAction: TAction;
  published
    property Action: TAction read FAction;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  THyperLinks = class
  private
    FDocumentNumber: Integer;
    FFieldDefinition: TFieldDefinition;
    FId: string;
    FUri: string;
  published
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property FieldDefinition: TFieldDefinition read FFieldDefinition;
    property Id: string read FId write FId;
    property Uri: string read FUri write FUri;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TLinkConfiguration = class(TJsonDTO)
  private
    [JSONName('HyperLinks'), JSONMarshalled(False)]
    FHyperLinksArray: TArray<THyperLinks>;
    [GenericListReflect]
    FHyperLinks: TObjectList<THyperLinks>;
    function GetHyperLinks: TObjectList<THyperLinks>;
  protected
    function GetAsJson: string; override;
  published
    property HyperLinks: TObjectList<THyperLinks> read GetHyperLinks;
  public
    destructor Destroy; override;
  end;

  TAttachments = class
  end;

  TTaskConfiguration = class
  end;

  TSignaturePlugins = class
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

  TClickToSign = class
  private
    FUseExternalSignatureImage: string;
  published
    property UseExternalSignatureImage: string read FUseExternalSignatureImage write FUseExternalSignatureImage;
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

  TAllowedSignatureTypes = class(TJsonDTO)
  private
    FClickToSign: TClickToSign;
    FOneTimePassword: TOneTimePassword;
    [JSONName('SignaturePlugins'), JSONMarshalled(False)]
    FSignaturePluginsArray: TArray<TSignaturePlugins>;
    [GenericListReflect]
    FSignaturePlugins: TObjectList<TSignaturePlugins>;
    function GetSignaturePlugins: TObjectList<TSignaturePlugins>;
  protected
    function GetAsJson: string; override;
  published
    property ClickToSign: TClickToSign read FClickToSign;
    property OneTimePassword: TOneTimePassword read FOneTimePassword;
    property SignaturePlugins: TObjectList<TSignaturePlugins> read GetSignaturePlugins;
  public
    constructor Create; override;
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
  published
    property AllowedSignatureTypes: TAllowedSignatureTypes read FAllowedSignatureTypes;
    property DisplayName: string read FDisplayName write FDisplayName;
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property ElementId: string read FElementId write FElementId;
    property FieldDefinition: TFieldDefinition read FFieldDefinition;
    property Required: Boolean read FRequired write FRequired;
    property TaskConfiguration: TTaskConfiguration read FTaskConfiguration;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TListBoxes = class
  end;

  TRadioButtons = class
  end;

  TComboBoxes = class
  end;

  TCheckBoxes = class
  end;

  TTextBoxes = class
  end;

  TUnassignedElements = class(TJsonDTO)
  private
    [JSONName('Attachments'), JSONMarshalled(False)]
    FAttachmentsArray: TArray<TAttachments>;
    [GenericListReflect]
    FAttachments: TObjectList<TAttachments>;
    [JSONName('CheckBoxes'), JSONMarshalled(False)]
    FCheckBoxesArray: TArray<TCheckBoxes>;
    [GenericListReflect]
    FCheckBoxes: TObjectList<TCheckBoxes>;
    [JSONName('ComboBoxes'), JSONMarshalled(False)]
    FComboBoxesArray: TArray<TComboBoxes>;
    [GenericListReflect]
    FComboBoxes: TObjectList<TComboBoxes>;
    FLinkConfiguration: TLinkConfiguration;
    [JSONName('ListBoxes'), JSONMarshalled(False)]
    FListBoxesArray: TArray<TListBoxes>;
    [GenericListReflect]
    FListBoxes: TObjectList<TListBoxes>;
    [JSONName('RadioButtons'), JSONMarshalled(False)]
    FRadioButtonsArray: TArray<TRadioButtons>;
    [GenericListReflect]
    FRadioButtons: TObjectList<TRadioButtons>;
    [JSONName('Signatures'), JSONMarshalled(False)]
    FSignaturesArray: TArray<TSignatures>;
    [GenericListReflect]
    FSignatures: TObjectList<TSignatures>;
    [JSONName('TextBoxes'), JSONMarshalled(False)]
    FTextBoxesArray: TArray<TTextBoxes>;
    [GenericListReflect]
    FTextBoxes: TObjectList<TTextBoxes>;
    function GetAttachments: TObjectList<TAttachments>;
    function GetCheckBoxes: TObjectList<TCheckBoxes>;
    function GetComboBoxes: TObjectList<TComboBoxes>;
    function GetListBoxes: TObjectList<TListBoxes>;
    function GetRadioButtons: TObjectList<TRadioButtons>;
    function GetSignatures: TObjectList<TSignatures>;
    function GetTextBoxes: TObjectList<TTextBoxes>;
  protected
    function GetAsJson: string; override;
  published
    property Attachments: TObjectList<TAttachments> read GetAttachments;
    property CheckBoxes: TObjectList<TCheckBoxes> read GetCheckBoxes;
    property ComboBoxes: TObjectList<TComboBoxes> read GetComboBoxes;
    property LinkConfiguration: TLinkConfiguration read FLinkConfiguration;
    property ListBoxes: TObjectList<TListBoxes> read GetListBoxes;
    property RadioButtons: TObjectList<TRadioButtons> read GetRadioButtons;
    property Signatures: TObjectList<TSignatures> read GetSignatures;
    property TextBoxes: TObjectList<TTextBoxes> read GetTextBoxes;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

  TPrepareResponse = class(TJsonDTO)
  private
    [JSONName('Activities'), JSONMarshalled(False)]
    FActivitiesArray: TArray<TActivities>;
    [GenericListReflect]
    FActivities: TObjectList<TActivities>;
    FUnassignedElements: TUnassignedElements;
    function GetActivities: TObjectList<TActivities>;
  protected
    function GetAsJson: string; override;
  published
    property Activities: TObjectList<TActivities> read GetActivities;
    property UnassignedElements: TUnassignedElements read FUnassignedElements;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

implementation

{ TFieldDefinition }

constructor TFieldDefinition.Create;
begin
  inherited;
  FPosition := TPosition.Create;
  FSize := TSize.Create;
end;

destructor TFieldDefinition.Destroy;
begin
  FPosition.Free;
  FSize.Free;
  inherited;
end;

{ TVisibleSignatures }

constructor TVisibleSignatures.Create;
begin
  inherited;
  FFieldDefinition := TFieldDefinition.Create;
end;

destructor TVisibleSignatures.Destroy;
begin
  FFieldDefinition.Free;
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

{ TAction }

constructor TAction.Create;
begin
  inherited;
  FSignAutomatic := TSignAutomatic.Create;
end;

destructor TAction.Destroy;
begin
  FSignAutomatic.Free;
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

{ THyperLinks }

constructor THyperLinks.Create;
begin
  inherited;
  FFieldDefinition := TFieldDefinition.Create;
end;

destructor THyperLinks.Destroy;
begin
  FFieldDefinition.Free;
  inherited;
end;

{ TLinkConfiguration }

destructor TLinkConfiguration.Destroy;
begin
  GetHyperLinks.Free;
  inherited;
end;

function TLinkConfiguration.GetHyperLinks: TObjectList<THyperLinks>;
begin
  Result := ObjectList<THyperLinks>(FHyperLinks, FHyperLinksArray);
end;

function TLinkConfiguration.GetAsJson: string;
begin
  RefreshArray<THyperLinks>(FHyperLinks, FHyperLinksArray);
  Result := inherited;
end;

{ TAllowedSignatureTypes }

constructor TAllowedSignatureTypes.Create;
begin
  inherited;
  FClickToSign := TClickToSign.Create;
  FOneTimePassword := TOneTimePassword.Create;
end;

destructor TAllowedSignatureTypes.Destroy;
begin
  FClickToSign.Free;
  FOneTimePassword.Free;
  GetSignaturePlugins.Free;
  inherited;
end;

function TAllowedSignatureTypes.GetSignaturePlugins: TObjectList<TSignaturePlugins>;
begin
  Result := ObjectList<TSignaturePlugins>(FSignaturePlugins, FSignaturePluginsArray);
end;

function TAllowedSignatureTypes.GetAsJson: string;
begin
  RefreshArray<TSignaturePlugins>(FSignaturePlugins, FSignaturePluginsArray);
  Result := inherited;
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

{ TUnassignedElements }

constructor TUnassignedElements.Create;
begin
  inherited;
  FLinkConfiguration := TLinkConfiguration.Create;
end;

destructor TUnassignedElements.Destroy;
begin
  FLinkConfiguration.Free;
  GetTextBoxes.Free;
  GetCheckBoxes.Free;
  GetComboBoxes.Free;
  GetRadioButtons.Free;
  GetListBoxes.Free;
  GetSignatures.Free;
  GetAttachments.Free;
  inherited;
end;

function TUnassignedElements.GetAttachments: TObjectList<TAttachments>;
begin
  Result := ObjectList<TAttachments>(FAttachments, FAttachmentsArray);
end;

function TUnassignedElements.GetCheckBoxes: TObjectList<TCheckBoxes>;
begin
  Result := ObjectList<TCheckBoxes>(FCheckBoxes, FCheckBoxesArray);
end;

function TUnassignedElements.GetComboBoxes: TObjectList<TComboBoxes>;
begin
  Result := ObjectList<TComboBoxes>(FComboBoxes, FComboBoxesArray);
end;

function TUnassignedElements.GetListBoxes: TObjectList<TListBoxes>;
begin
  Result := ObjectList<TListBoxes>(FListBoxes, FListBoxesArray);
end;

function TUnassignedElements.GetRadioButtons: TObjectList<TRadioButtons>;
begin
  Result := ObjectList<TRadioButtons>(FRadioButtons, FRadioButtonsArray);
end;

function TUnassignedElements.GetSignatures: TObjectList<TSignatures>;
begin
  Result := ObjectList<TSignatures>(FSignatures, FSignaturesArray);
end;

function TUnassignedElements.GetTextBoxes: TObjectList<TTextBoxes>;
begin
  Result := ObjectList<TTextBoxes>(FTextBoxes, FTextBoxesArray);
end;

function TUnassignedElements.GetAsJson: string;
begin
  RefreshArray<TAttachments>(FAttachments, FAttachmentsArray);
  RefreshArray<TCheckBoxes>(FCheckBoxes, FCheckBoxesArray);
  RefreshArray<TComboBoxes>(FComboBoxes, FComboBoxesArray);
  RefreshArray<TListBoxes>(FListBoxes, FListBoxesArray);
  RefreshArray<TRadioButtons>(FRadioButtons, FRadioButtonsArray);
  RefreshArray<TSignatures>(FSignatures, FSignaturesArray);
  RefreshArray<TTextBoxes>(FTextBoxes, FTextBoxesArray);
  Result := inherited;
end;

{ TRoot }

constructor TPrepareResponse.Create;
begin
  inherited;
  FUnassignedElements := TUnassignedElements.Create;
end;

destructor TPrepareResponse.Destroy;
begin
  FUnassignedElements.Free;
  GetActivities.Free;
  inherited;
end;

function TPrepareResponse.GetActivities: TObjectList<TActivities>;
begin
  Result := ObjectList<TActivities>(FActivities, FActivitiesArray);
end;

function TPrepareResponse.GetAsJson: string;
begin
  RefreshArray<TActivities>(FActivities, FActivitiesArray);
  Result := inherited;
end;

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
