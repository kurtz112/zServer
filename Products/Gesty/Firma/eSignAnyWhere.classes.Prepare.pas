unit eSignAnyWhere.classes.Prepare;

interface

uses
  system.SysUtils,
  system.classes,
  system.Generics.Collections,
  REST.Json.Types,
  zz.Json.DTO;

{$M+}

type
  TSigStringConfigurations = class
  private
    FClearSigString: Boolean;
    FEndPattern: string;
    FSearchEntireWordOnly: Boolean;
    FStartPattern: string;
  published
    property ClearSigString: Boolean read FClearSigString write FClearSigString;
    property EndPattern: string read FEndPattern write FEndPattern;
    property SearchEntireWordOnly: Boolean read FSearchEntireWordOnly write FSearchEntireWordOnly;
    property StartPattern: string read FStartPattern write FStartPattern;
  end;

  TPrepareRequest = class(TJsonDTO)
  private
    FClearAdvancedDocumentTags: Boolean;
    [JSONName('FileIds')]
    FFileIdsArray: TArray<string>;
    [JSONMarshalled(False)]
    FFileIds: TList<string>;
    [JSONName('SigStringConfigurations'), JSONMarshalled(False)]
    FSigStringConfigurationsArray: TArray<TSigStringConfigurations>;
    [GenericListReflect]
    FSigStringConfigurations: TObjectList<TSigStringConfigurations>;
    function GetFileIds: TList<string>;
    function GetSigStringConfigurations: TObjectList<TSigStringConfigurations>;
  protected
    function GetAsJson: string; override;
  published
    property FileIds: TList<string> read GetFileIds;
    property ClearAdvancedDocumentTags: Boolean read FClearAdvancedDocumentTags write FClearAdvancedDocumentTags;
    property SigStringConfigurations: TObjectList<TSigStringConfigurations> read GetSigStringConfigurations;
  public
    destructor Destroy; override;
  end;

implementation

{ TRoot }

destructor TPrepareRequest.Destroy;
begin
  GetFileIds.Free;
  GetSigStringConfigurations.Free;
  inherited;
end;

function TPrepareRequest.GetFileIds: TList<string>;
begin
  Result := List<string>(FFileIds, FFileIdsArray);
end;

function TPrepareRequest.GetSigStringConfigurations: TObjectList<TSigStringConfigurations>;
begin
  Result := ObjectList<TSigStringConfigurations>(FSigStringConfigurations, FSigStringConfigurationsArray);
end;

function TPrepareRequest.GetAsJson: string;
begin
  RefreshArray<string>(FFileIds, FFileIdsArray);
  RefreshArray<TSigStringConfigurations>(FSigStringConfigurations, FSigStringConfigurationsArray);
  Result := inherited;
end;

end.
