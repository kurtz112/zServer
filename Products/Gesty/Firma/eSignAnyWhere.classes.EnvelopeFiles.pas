unit eSignAnyWhere.classes.EnvelopeFiles;

interface

uses
  system.SysUtils,
  system.classes,
  system.Generics.Collections,
  REST.Json.Types,
  zz.Json.DTO;

{$M+}

type
  TAttachments = class;

  TLegalDocuments = class
  end;

  TAuditTrail = class
  private
    FFileId: string;
    FXmlFileId: string;
  published
    property FileId: string read FFileId write FFileId;
    property XmlFileId: string read FXmlFileId write FXmlFileId;
  end;

  TAttachments = class
  end;

  TDocuments = class(TJsonDTO)
  private
    [JSONName('Attachments'), JSONMarshalled(False)]
    FAttachmentsArray: TArray<TAttachments>;
    [GenericListReflect]
    FAttachments: TObjectList<TAttachments>;
    FDocumentNumber: Integer;
    FFileId: string;
    FFileName: string;
    FPageCount: Integer;
    function GetAttachments: TObjectList<TAttachments>;
  protected
    function GetAsJson: string; override;
  published
    property Attachments: TObjectList<TAttachments> read GetAttachments;
    property DocumentNumber: Integer read FDocumentNumber write FDocumentNumber;
    property FileId: string read FFileId write FFileId;
    property FileName: string read FFileName write FFileName;
    property PageCount: Integer read FPageCount write FPageCount;
  public
    destructor Destroy; override;
  end;

  TEnvelopeFilesResponse = class(TJsonDTO)
  private
    FAuditTrail: TAuditTrail;
    [JSONName('Documents'), JSONMarshalled(False)]
    FDocumentsArray: TArray<TDocuments>;
    [GenericListReflect]
    FDocuments: TObjectList<TDocuments>;
    [JSONName('LegalDocuments'), JSONMarshalled(False)]
    FLegalDocumentsArray: TArray<TLegalDocuments>;
    [GenericListReflect]
    FLegalDocuments: TObjectList<TLegalDocuments>;
    function GetDocuments: TObjectList<TDocuments>;
    function GetLegalDocuments: TObjectList<TLegalDocuments>;
  protected
    function GetAsJson: string; override;
  published
    property AuditTrail: TAuditTrail read FAuditTrail;
    property Documents: TObjectList<TDocuments> read GetDocuments;
    property LegalDocuments: TObjectList<TLegalDocuments> read GetLegalDocuments;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

implementation

{ TDocuments }

destructor TDocuments.Destroy;
begin
  GetAttachments.Free;
  inherited;
end;

function TDocuments.GetAttachments: TObjectList<TAttachments>;
begin
  Result := ObjectList<TAttachments>(FAttachments, FAttachmentsArray);
end;

function TDocuments.GetAsJson: string;
begin
  RefreshArray<TAttachments>(FAttachments, FAttachmentsArray);
  Result := inherited;
end;

{ TRoot }

constructor TEnvelopeFilesResponse.Create;
begin
  inherited;
  FAuditTrail := TAuditTrail.Create;
end;

destructor TEnvelopeFilesResponse.Destroy;
begin
  FAuditTrail.Free;
  GetDocuments.Free;
  GetLegalDocuments.Free;
  inherited;
end;

function TEnvelopeFilesResponse.GetDocuments: TObjectList<TDocuments>;
begin
  Result := ObjectList<TDocuments>(FDocuments, FDocumentsArray);
end;

function TEnvelopeFilesResponse.GetLegalDocuments: TObjectList<TLegalDocuments>;
begin
  Result := ObjectList<TLegalDocuments>(FLegalDocuments, FLegalDocumentsArray);
end;

function TEnvelopeFilesResponse.GetAsJson: string;
begin
  RefreshArray<TDocuments>(FDocuments, FDocumentsArray);
  RefreshArray<TLegalDocuments>(FLegalDocuments, FLegalDocumentsArray);
  Result := inherited;
end;

end.
