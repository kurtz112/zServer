unit Metadata.Editor.Controller;

// ---------------------------------------------------------------------------
// TMetaEditorController: l'editor dei metadati di BaseWeb, /api/meta.
//
// Riscritto sul modello attuale (BASE_WEB_FORM_CONTAINER, GRID_COLUMNS,
// _CUSTOM): ogni lettura passa dalle _LOAD e ogni scrittura dalle _SAVE e
// _DELETE del pacchetto BASE_WEB_TABLE_IO, attraverso TMetadataTransfer.
// Niente SQL sulle tabelle: cosi' la parte SQL e' la stessa in WT e Gesty e
// le colonne che il client vede sono quelle che il pacchetto espone.
//
// Regole comuni:
// - ogni azione, lettura compresa, richiede BASE_WEB_METADATI (OnBeforeAction);
// - PUT e' un aggiornamento parziale: la riga esistente viene riletta, il
//   corpo vi si sovrappone e la _SAVE riscrive tutto (nessun UPDATE dinamico);
// - POST crea, con le chiavi nel corpo; risponde 201 con la riga riletta;
// - le SQL del dataset viaggiano in Base64 (UTF-16, come il resto di zServer)
//   quando il corpo porta "SQL_BASE64": true, perche' contengono apici e
//   a capo che hanno gia' dato problemi; in lettura escono come testo;
// - le cancellazioni rifiutate dal pacchetto (contenitore con figli, lookup
//   o picklist in uso) tornano come 400 con il messaggio del database,
//   tradotto da TBaseController.OnException;
// - BASE_WEB_DATASETS_META si rigenera da sola con i trigger: zServer non ha
//   una cache da invalidare. L'unica rotta che spegne la rigenerazione,
//   form/save-all, la riaccende in un finally sulla stessa connessione.
//
// Rotte (tutte sotto /api/meta):
//   GET  /access, /domains, /authorizations
//   GET  /datasets[?dm=], /datasets/($id)         POST /datasets
//   PUT  /datasets/($id)                           DELETE /datasets/($id)
//   PUT  /datasets/($id)/authorization             GET /datasets/($id)/preview
//   POST /datasets/($id)/rebuild-meta              POST /rebuild-all
//   POST /datasets/($id)/check-sql
//   GET  /datasets/($id)/fields                    GET  /datasets/($id)/fields/sync-preview
//   POST /datasets/($id)/fields/sync
//   PUT|DELETE /datasets/($id)/fields/($field)
//   GET  /datasets/($id)/grid
//   PUT|DELETE /datasets/($id)/grid/bands/($name), /grid/columns/($field)
//   GET  /datasets/($id)/form                      POST /datasets/($id)/form/save-all
//   PUT|DELETE /datasets/($id)/form/groups|tabbed|tabs|fields|buttons|empty/($name)
//   GET  /datasets/($id)/custom
//   PUT|DELETE /datasets/($id)/custom/($sezione)[/($chiave)]
//   GET  /lookups, /lookups/($id)                  POST /lookups
//   PUT|DELETE /lookups/($id)                      PUT|DELETE /lookups/($id)/columns/($field)
//   GET  /picklists, /picklists/($id)              POST /picklists
//   PUT|DELETE /picklists/($id)
//   GET  /export[?datasets=&dm=&escludi_dm=&format=json|sql]
//   POST /import                                   POST /import/script
// ---------------------------------------------------------------------------

interface

uses
  MVCFramework,
  MVCFramework.Commons,
  System.SysUtils,
  System.JSON,
  System.Classes,
  FireDAC.Comp.Client,
  Base.Controller,
  Metadata.Transfer.Service;

type

  [MVCPath('/api/meta')]
  TMetaEditorController = class(TBaseController)
  private
    function TabellaDiSezione(const Sezione: string; Custom: Boolean = False): TTabellaBaseWeb;
    function ParametroElenco(const Nome: string): TArray<string>;
    function CorpoDataset: TJSONObject;
    procedure RenderRighe(const T: TTabellaBaseWeb; const Chiavi: array of string);
    procedure RenderRigaOppure404(const T: TTabellaBaseWeb; const Chiavi: array of string; const Messaggio: string);
    procedure SalvaDaCorpo(const T: TTabellaBaseWeb; const Chiavi: array of string; Corpo: TJSONObject);
    procedure EliminaRiga(const T: TTabellaBaseWeb; const Chiavi: array of string);
    function SqlConSegnapostoLegati(const SQL: string): string;
    function CampiDellaSelect(Connessione: TFDConnection; const SQL: string): TJSONArray;
  protected
    // Ogni azione, lettura compresa, richiede l'autorizzazione BASE_WEB_METADATI
    procedure OnBeforeAction(aContext: TWebContext; const aActionName: string; var AHandled: Boolean); override;
  public
    { Servizio }
    [MVCPath('/access')]
    [MVCHTTPMethod([httpGET])]
    procedure GetAccess;
    [MVCPath('/domains')]
    [MVCHTTPMethod([httpGET])]
    procedure GetDomains;
    [MVCPath('/authorizations')]
    [MVCHTTPMethod([httpGET])]
    procedure GetAuthorizations;

    { Dataset }
    [MVCPath('/datasets')]
    [MVCHTTPMethod([httpGET])]
    procedure GetDatasets;
    [MVCPath('/datasets/($id)')]
    [MVCHTTPMethod([httpGET])]
    procedure GetDataset(const id: string);
    [MVCPath('/datasets')]
    [MVCHTTPMethod([httpPOST])]
    procedure CreateDataset;
    [MVCPath('/datasets/($id)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateDataset(const id: string);
    [MVCPath('/datasets/($id)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteDataset(const id: string);
    [MVCPath('/datasets/($id)/authorization')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateAuthorization(const id: string);
    [MVCPath('/datasets/($id)/preview')]
    [MVCHTTPMethod([httpGET])]
    procedure PreviewMetadata(const id: string);
    [MVCPath('/datasets/($id)/rebuild-meta')]
    [MVCHTTPMethod([httpPOST])]
    procedure RebuildMeta(const id: string);
    [MVCPath('/rebuild-all')]
    [MVCHTTPMethod([httpPOST])]
    procedure RebuildAll;
    [MVCPath('/datasets/($id)/check-sql')]
    [MVCHTTPMethod([httpPOST])]
    procedure CheckSql(const id: string);

    { Campi }
    [MVCPath('/datasets/($id)/fields')]
    [MVCHTTPMethod([httpGET])]
    procedure GetFields(const id: string);
    [MVCPath('/datasets/($id)/fields/sync-preview')]
    [MVCHTTPMethod([httpGET])]
    procedure SyncFieldsPreview(const id: string);
    [MVCPath('/datasets/($id)/fields/sync')]
    [MVCHTTPMethod([httpPOST])]
    procedure SyncFields(const id: string);
    [MVCPath('/datasets/($id)/fields/($field)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateField(const id, field: string);
    [MVCPath('/datasets/($id)/fields/($field)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteField(const id, field: string);

    { Griglia }
    [MVCPath('/datasets/($id)/grid')]
    [MVCHTTPMethod([httpGET])]
    procedure GetGrid(const id: string);
    [MVCPath('/datasets/($id)/grid/bands/($name)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateBand(const id, name: string);
    [MVCPath('/datasets/($id)/grid/bands/($name)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteBand(const id, name: string);
    [MVCPath('/datasets/($id)/grid/columns/($field)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateColumn(const id, field: string);
    [MVCPath('/datasets/($id)/grid/columns/($field)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteColumn(const id, field: string);

    { Form }
    [MVCPath('/datasets/($id)/form')]
    [MVCHTTPMethod([httpGET])]
    procedure GetForm(const id: string);
    [MVCPath('/datasets/($id)/form/save-all')]
    [MVCHTTPMethod([httpPOST])]
    procedure SaveFormAll(const id: string);
    [MVCPath('/datasets/($id)/form/($sezione)/($name)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateFormItem(const id, sezione, name: string);
    [MVCPath('/datasets/($id)/form/($sezione)/($name)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteFormItem(const id, sezione, name: string);

    { Sovrascritture per cliente }
    [MVCPath('/datasets/($id)/custom')]
    [MVCHTTPMethod([httpGET])]
    procedure GetCustom(const id: string);
    [MVCPath('/datasets/($id)/custom/($sezione)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateCustomDataset(const id, sezione: string);
    [MVCPath('/datasets/($id)/custom/($sezione)/($chiave)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateCustom(const id, sezione, chiave: string);
    [MVCPath('/datasets/($id)/custom/($sezione)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteCustomDataset(const id, sezione: string);
    [MVCPath('/datasets/($id)/custom/($sezione)/($chiave)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteCustom(const id, sezione, chiave: string);

    { Lookup }
    [MVCPath('/lookups')]
    [MVCHTTPMethod([httpGET])]
    procedure GetLookups;
    [MVCPath('/lookups/($id)')]
    [MVCHTTPMethod([httpGET])]
    procedure GetLookup(const id: string);
    [MVCPath('/lookups')]
    [MVCHTTPMethod([httpPOST])]
    procedure CreateLookup;
    [MVCPath('/lookups/($id)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateLookup(const id: string);
    [MVCPath('/lookups/($id)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteLookup(const id: string);
    [MVCPath('/lookups/($id)/columns/($field)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdateLookupColumn(const id, field: string);
    [MVCPath('/lookups/($id)/columns/($field)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeleteLookupColumn(const id, field: string);

    { Picklist }
    [MVCPath('/picklists')]
    [MVCHTTPMethod([httpGET])]
    procedure GetPicklists;
    [MVCPath('/picklists/($id)')]
    [MVCHTTPMethod([httpGET])]
    procedure GetPicklist(const id: string);
    [MVCPath('/picklists')]
    [MVCHTTPMethod([httpPOST])]
    procedure CreatePicklist;
    [MVCPath('/picklists/($id)')]
    [MVCHTTPMethod([httpPUT])]
    procedure UpdatePicklist(const id: string);
    [MVCPath('/picklists/($id)')]
    [MVCHTTPMethod([httpDELETE])]
    procedure DeletePicklist(const id: string);

    { Trasporto }
    [MVCPath('/export')]
    [MVCHTTPMethod([httpGET])]
    procedure ExportMetadata;
    [MVCPath('/import')]
    [MVCHTTPMethod([httpPOST])]
    procedure ImportMetadata;
    [MVCPath('/import/script')]
    [MVCHTTPMethod([httpPOST])]
    procedure ImportScript;
  end;

/// <summary>
/// Autorizzazione che protegge la modifica dei metadati di BaseWeb (dataset,
/// campi, gruppi, lookup, picklist) e la lettura del loro editor.
/// </summary>
const
  AutorizzazioneMetadati = 'BASE_WEB_METADATI';

/// <summary>
/// Solleva 403 se l'utente della richiesta non ha AutorizzazioneMetadati.
/// Condivisa da TMetaEditorController e TMetadataPatchController.
/// </summary>
procedure RichiediAutorizzazioneMetadati;

implementation

uses
  System.Variants,
  System.StrUtils,
  System.NetEncoding,
  System.Generics.Collections,
  System.RegularExpressions,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  Data.Service,
  FiredacHelper,
  fib.SqlTxtRtns;

// Chi puo' scrivere i metadati puo' anche cambiare SQL_SELECT, SQL_INSERT,
// SQL_UPDATE e SQL_DELETE di qualunque dataset, cioe' le istruzioni che
// zServer esegue per tutti gli altri utenti: per questo il controllo vale
// anche per le letture (GetDatasets restituisce il testo di quelle istruzioni)
// e non basta avere un ruolo qualsiasi nel token. La verifica e' quella di
// USR_AUTHORIZATION_CHECK, identica in WT e in Gesty, e funziona perche' il
// middleware di autenticazione ha gia' dichiarato l'utente alla connessione
// (punto Z3). Una richiesta negata risponde 403 con il messaggio del database.
procedure RichiediAutorizzazioneMetadati;
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('AUTHORIZATION', AutorizzazioneMetadati);
    Parametri.Add('ERROR_MSG', '');

    try
      Esito := TDataService.ExecuteStoredProc('USR_AUTHORIZATION_CHECK', Parametri);
      Esito.Free;
    except
      on E: Exception do
        raise EMVCException.Create(HTTP_STATUS.Forbidden, E.Message);
    end;
  finally
    Parametri.Free;
  end;
end;

procedure TMetaEditorController.OnBeforeAction(aContext: TWebContext; const aActionName: string; var AHandled: Boolean);
begin
  RichiediAutorizzazioneMetadati;
  inherited;
end;

{ Appoggio }

type
  // Per leggere i campi di una SELECT senza eseguirla: DoCreateFields e' protetto
  TFDQueryAperta = class(TFDQuery);

// Stessa decodifica di DynamicDataset.Controller: il client codifica il testo UTF-16
function DecodificaBase64(const Testo: string): string;
begin
  if Testo.IsEmpty then
    Exit('');
  Result := TEncoding.Unicode.GetString(TNetEncoding.Base64.DecodeStringToBytes(Testo));
end;

function Valore(Oggetto: TJSONObject; const Nome: string): string;
var
  V: TJSONValue;
begin
  V := Oggetto.GetValue(Nome);
  if (V = nil) or (V is TJSONNull) then
    Result := ''
  else
    Result := V.Value;
end;

function TMetaEditorController.TabellaDiSezione(const Sezione: string; Custom: Boolean): TTabellaBaseWeb;
begin
  if not TMetadataTransfer.TrovaTabella(Sezione, Custom, Result) then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Sezione dei metadati sconosciuta: ' + Sezione);
end;

function TMetaEditorController.ParametroElenco(const Nome: string): TArray<string>;
var
  Testo: string;
  Voce: string;
  Elenco: TList<string>;
begin
  Testo := ParamByName(Nome);
  Elenco := TList<string>.Create;
  try
    for Voce in Testo.Split([',', ';']) do
      if not Voce.Trim.IsEmpty then
        Elenco.Add(Voce.Trim);
    Result := Elenco.ToArray;
  finally
    Elenco.Free;
  end;
end;

// Il corpo di un dataset: con "SQL_BASE64": true le cinque SQL arrivano in Base64
function TMetaEditorController.CorpoDataset: TJSONObject;
const
  ColonneSql: array [0 .. 4] of string = ('SQL_SELECT', 'SQL_COUNT', 'SQL_INSERT', 'SQL_UPDATE', 'SQL_DELETE');
var
  Colonna: string;
  Testo: string;
begin
  Result := CorpoJson;
  if Result.GetValue<Boolean>('SQL_BASE64', False) then
  begin
    for Colonna in ColonneSql do
      if Result.GetValue(Colonna) <> nil then
      begin
        Testo := DecodificaBase64(Valore(Result, Colonna));
        Result.RemovePair(Colonna).Free;
        Result.AddPair(Colonna, Testo);
      end;
    Result.RemovePair('SQL_BASE64').Free;
  end;
end;

procedure TMetaEditorController.RenderRighe(const T: TTabellaBaseWeb; const Chiavi: array of string);
var
  Connessione: TFDConnection;
  Righe: TJSONArray;
begin
  Connessione := PrendiConnessione;
  try
    Righe := TMetadataTransfer.Carica(Connessione, T, Chiavi);
  finally
    RilasciaConnessione(Connessione);
  end;
  try
    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    Righe.Free;
  end;
end;

procedure TMetaEditorController.RenderRigaOppure404(const T: TTabellaBaseWeb; const Chiavi: array of string; const Messaggio: string);
var
  Connessione: TFDConnection;
  Riga: TJSONObject;
begin
  Connessione := PrendiConnessione;
  try
    Riga := TMetadataTransfer.CaricaRiga(Connessione, T, Chiavi);
  finally
    RilasciaConnessione(Connessione);
  end;
  if Riga = nil then
    raise EMVCException.Create(HTTP_STATUS.NotFound, Messaggio);
  RenderJson(Riga);
end;

// PUT e POST: unione con la riga esistente, _SAVE, risposta con la riga riletta
// (200 se esisteva, 201 se e' nuova). Il corpo viene liberato qui.
procedure TMetaEditorController.SalvaDaCorpo(const T: TTabellaBaseWeb; const Chiavi: array of string; Corpo: TJSONObject);
var
  Connessione: TFDConnection;
  Creato: Boolean;
  Riga: TJSONObject;
begin
  try
    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        TMetadataTransfer.SalvaUnendo(Connessione, T, Chiavi, Corpo, Creato);
        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;
      Riga := TMetadataTransfer.CaricaRiga(Connessione, T, Chiavi);
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    Corpo.Free;
  end;

  if Riga = nil then
    Riga := TJSONObject.Create.AddPair('success', TJSONBool.Create(True));
  try
    if Creato then
      RenderTestoJson(HTTP_STATUS.Created, Riga)
    else
      RenderTestoJson(HTTP_STATUS.OK, Riga);
  finally
    Riga.Free;
  end;
end;

procedure TMetaEditorController.EliminaRiga(const T: TTabellaBaseWeb; const Chiavi: array of string);
var
  Connessione: TFDConnection;
begin
  Connessione := PrendiConnessione;
  try
    if TMetadataTransfer.CaricaRiga(Connessione, T, Chiavi) = nil then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Elemento non trovato');
    ApriTransazione(Connessione);
    try
      TMetadataTransfer.Elimina(Connessione, T, Chiavi);
      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderEsito(True);
end;

// I segnaposto di sessione (:##USER_ID, :##BELFIORE...) non sono parametri
// validi per FireDAC: per preparare la SQL si sostituiscono con parametri
// legati come fa DynamicDataset.Controller. Qui nessuna riga viene letta,
// quindi i valori restano a NULL.
function TMetaEditorController.SqlConSegnapostoLegati(const SQL: string): string;
begin
  Result := SQL.Replace(':##USER_ID', ':CTX_USER_ID', [rfReplaceAll, rfIgnoreCase]).Replace(':##ID_SESSIONE', ':CTX_ID_SESSIONE', [rfReplaceAll, rfIgnoreCase]).Replace(':##BELFIORE', ':CTX_BELFIORE', [rfReplaceAll, rfIgnoreCase])
    .Replace(':##ID_AZIENDA', ':CTX_ID_AZIENDA', [rfReplaceAll, rfIgnoreCase]).Replace(':##AZIENDA_DI_LAVORO', ':CTX_ID_AZIENDA', [rfReplaceAll, rfIgnoreCase]);
end;

// Nome e origine (TABELLA.COLONNA) di ogni colonna della SELECT, senza
// eseguirla: Prepare, FieldDefs e creazione dei campi, come GeneraCampi del
// Designer. L'origine viene da FireDAC; per le espressioni senza tabella si
// prova a leggerla dal testo della SELECT.
function TMetaEditorController.CampiDellaSelect(Connessione: TFDConnection; const SQL: string): TJSONArray;
var
  Query: TFDQuery;
  Campo: TField;
  Colonna: TFDDatSColumn;
  Tabella, NomeColonna, Origine, DalTesto: string;
begin
  Result := TJSONArray.Create;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text := SqlConSegnapostoLegati(SQL);
    Query.Prepare;
    Query.FieldDefs.Updated := False;
    Query.FieldDefs.Update;
    TFDQueryAperta(Query).DoCreateFields;

    for Campo in Query.Fields do
    begin
      Tabella := '';
      NomeColonna := '';
      if Assigned(Query.Table) and (Query.Table.Columns.IndexOfName(Campo.FieldName) <> -1) then
      begin
        Colonna := Query.Table.Columns.ColumnByName(Campo.FieldName);
        NomeColonna := Colonna.OriginColName.Trim.Replace('"', '', [rfReplaceAll]);
        Tabella := Colonna.OriginTabName.Trim.Replace('"', '', [rfReplaceAll]);
      end;
      if Tabella.IsEmpty then
      begin
        DalTesto := FieldNameFromSelect(Query.SQL.Text, Campo.FieldName);
        if DalTesto.Contains('.') then
          Tabella := DalTesto.Substring(0, DalTesto.IndexOf('.'));
      end;
      if NomeColonna.IsEmpty then
        NomeColonna := Campo.FieldName;
      if Tabella.IsEmpty then
        Origine := NomeColonna
      else
        Origine := Tabella + '.' + NomeColonna;

      Result.AddElement(TJSONObject.Create.AddPair('FIELD', Campo.FieldName).AddPair('FIELD_ORIGIN', Origine).AddPair('DATA_TYPE', FieldTypeNames[Campo.DataType]));
    end;
  finally
    Query.Free;
  end;
end;

{ Servizio }

// Serve al client per mostrare o nascondere la voce di menu: il token porta
// solo il ruolo, non le autorizzazioni, e il controllo vero e' in OnBeforeAction
procedure TMetaEditorController.GetAccess;
begin
  RenderJson(TJSONObject.Create.AddPair('enabled', TJSONBool.Create(True)));
end;

// I valori ammessi dei domini BASE_WEB_*, letti dal database: dal commento
// nel formato "Descrizione = CODICE" (regola SQL 3.2.5) e, in mancanza, dal
// CHECK (VALUE IN (...)). Cosi' il client non ha elenchi chiusi copiati nel
// codice e un dominio ampliato compare da solo nelle discese.
procedure TMetaEditorController.GetDomains;
var
  Connessione: TFDConnection;
  Domini: TJSONArray;
  Dominio: TJSONValue;
  Valori: TJSONArray;
  Risposta: TJSONArray;
  Descrizione, Controllo, RigaTesto, Codice, Testo: string;
  Trovato: TMatch;
  Posizione: Integer;
begin
  Connessione := PrendiConnessione;
  try
    Domini := TDataService.ExecuteQuery(Connessione, 'SELECT RDB$FIELDS.RDB$FIELD_NAME AS DOMINIO, RDB$FIELDS.RDB$VALIDATION_SOURCE AS CONTROLLO, RDB$FIELDS.RDB$DESCRIPTION AS DESCRIZIONE ' +
      'FROM RDB$FIELDS WHERE RDB$FIELDS.RDB$FIELD_NAME STARTING WITH ''BASE_WEB_'' AND COALESCE(RDB$FIELDS.RDB$SYSTEM_FLAG, 0) = 0 ORDER BY RDB$FIELDS.RDB$FIELD_NAME', False);
  finally
    RilasciaConnessione(Connessione);
  end;

  Risposta := TJSONArray.Create;
  try
    for Dominio in Domini do
    begin
      Valori := TJSONArray.Create;
      Descrizione := Valore(TJSONObject(Dominio), 'DESCRIZIONE');
      Controllo := Valore(TJSONObject(Dominio), 'CONTROLLO');

      if not Descrizione.Trim.IsEmpty then
        for RigaTesto in Descrizione.Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
        begin
          Posizione := RigaTesto.LastIndexOf('=');
          if Posizione <= 0 then
            Continue;
          Testo := RigaTesto.Substring(0, Posizione).Trim;
          Codice := RigaTesto.Substring(Posizione + 1).Trim;
          if Codice.IsEmpty then
            Continue;
          Valori.AddElement(TJSONObject.Create.AddPair('value', Codice).AddPair('text', Testo));
        end;

      if (Valori.Count = 0) and Controllo.ToUpper.Contains('VALUE IN') then
        for Trovato in TRegEx.Matches(Controllo, '''([^'']*)''') do
          Valori.AddElement(TJSONObject.Create.AddPair('value', Trovato.Groups[1].Value).AddPair('text', Trovato.Groups[1].Value));

      if Valori.Count = 0 then
      begin
        Valori.Free;
        Continue;
      end;
      Risposta.AddElement(TJSONObject.Create.AddPair('domain', Valore(TJSONObject(Dominio), 'DOMINIO').Trim).AddPair('values', Valori));
    end;
    Domini.Free;
    RenderTestoJson(HTTP_STATUS.OK, Risposta);
  finally
    Risposta.Free;
  end;
end;

// Le autorizzazioni fra cui scegliere quella del dataset (BASE_WEB_DATASETS.AUTHORIZATION)
procedure TMetaEditorController.GetAuthorizations;
var
  Connessione: TFDConnection;
  Righe: TJSONArray;
begin
  Connessione := PrendiConnessione;
  try
    Righe := TDataService.ExecuteQuery(Connessione, 'SELECT USR_AUTHORIZATIONS.AUTHORIZATION, USR_AUTHORIZATIONS.NOTE FROM USR_AUTHORIZATIONS ORDER BY USR_AUTHORIZATIONS.AUTHORIZATION', False);
  finally
    RilasciaConnessione(Connessione);
  end;
  try
    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    Righe.Free;
  end;
end;

{ Dataset }

procedure TMetaEditorController.GetDatasets;
var
  Connessione: TFDConnection;
  Righe, Filtrate: TJSONArray;
  Riga: TJSONValue;
  Modulo: string;
begin
  Modulo := ParamByName('dm').Trim;
  Connessione := PrendiConnessione;
  try
    Righe := TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('datasets'), ['']);
  finally
    RilasciaConnessione(Connessione);
  end;
  try
    if Modulo.IsEmpty then
      RenderTestoJson(HTTP_STATUS.OK, Righe)
    else
    begin
      Filtrate := TJSONArray.Create;
      try
        for Riga in Righe do
          if SameText(Valore(TJSONObject(Riga), 'DM'), Modulo) then
            Filtrate.AddElement(Riga.Clone as TJSONValue);
        RenderTestoJson(HTTP_STATUS.OK, Filtrate);
      finally
        Filtrate.Free;
      end;
    end;
  finally
    Righe.Free;
  end;
end;

procedure TMetaEditorController.GetDataset(const id: string);
begin
  RenderRigaOppure404(TMetadataTransfer.Tabella('datasets'), [id], 'Dataset non trovato: ' + id);
end;

procedure TMetaEditorController.CreateDataset;
var
  Corpo: TJSONObject;
  Nome: string;
begin
  Corpo := CorpoDataset;
  Nome := Valore(Corpo, 'DATASET').Trim;
  if Nome.IsEmpty then
  begin
    Corpo.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'DATASET obbligatorio');
  end;
  SalvaDaCorpo(TMetadataTransfer.Tabella('datasets'), [Nome], Corpo);
end;

procedure TMetaEditorController.UpdateDataset(const id: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('datasets'), [id], CorpoDataset);
end;

procedure TMetaEditorController.DeleteDataset(const id: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('datasets'), [id]);
end;

// Corpo: { "AUTHORIZATION": "CODICE" } oppure null per toglierla
procedure TMetaEditorController.UpdateAuthorization(const id: string);
var
  Corpo: TJSONObject;
  Connessione: TFDConnection;
begin
  Corpo := CorpoJson;
  try
    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        TMetadataTransfer.ImpostaAutorizzazione(Connessione, id, Valore(Corpo, 'AUTHORIZATION'));
        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    Corpo.Free;
  end;
  RenderRigaOppure404(TMetadataTransfer.Tabella('datasets'), [id], 'Dataset non trovato: ' + id);
end;

// Il JSON che il client riceve da /api/data/{ds}/metadata, com'e' adesso
procedure TMetaEditorController.PreviewMetadata(const id: string);
var
  Connessione: TFDConnection;
  Parametri: TParamValues;
  Riga: TJSONObject;
  Testo: string;
  Meta: TJSONValue;
begin
  Parametri := TParamValues.Create;
  Connessione := PrendiConnessione;
  try
    Parametri.Add('DS', id);
    Riga := TDataService.ExecuteQuerySingleRow(Connessione, 'SELECT JSON_RESULT FROM BASE_WEB.LOAD_DATASET_METADATA(:DS)', Parametri, False);
  finally
    RilasciaConnessione(Connessione);
    Parametri.Free;
  end;

  if Riga = nil then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dataset non trovato: ' + id);
  try
    Testo := Valore(Riga, 'JSON_RESULT');
  finally
    Riga.Free;
  end;
  if Testo.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Nessun metadato generato per ' + id);

  Meta := TJSONObject.ParseJSONValue(Testo);
  if Meta = nil then
    raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Il JSON generato dal database non e'' valido');
  try
    RenderTestoJson(HTTP_STATUS.OK, Meta);
  finally
    Meta.Free;
  end;
end;

// Per quando il dizionario dati cambia senza toccare le tabelle BASE_WEB_*
procedure TMetaEditorController.RebuildMeta(const id: string);
var
  Connessione: TFDConnection;
begin
  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      TMetadataTransfer.RigeneraMeta(Connessione, id);
      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderEsito(True);
end;

procedure TMetaEditorController.RebuildAll;
var
  Connessione: TFDConnection;
begin
  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      TMetadataTransfer.RigeneraTuttiIMeta(Connessione);
      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderEsito(True);
end;

// Prepara le cinque SQL senza eseguirle. Corpo facoltativo con le SQL da
// provare (Base64 con SQL_BASE64); senza corpo si provano quelle salvate.
// Risposta: [{ "istruzione": "SQL_SELECT", "ok": true, "messaggio": "", "campi": [...] }, ...]
procedure TMetaEditorController.CheckSql(const id: string);
const
  Istruzioni: array [0 .. 4] of string = ('SQL_SELECT', 'SQL_COUNT', 'SQL_INSERT', 'SQL_UPDATE', 'SQL_DELETE');
var
  Corpo: TJSONObject;
  Connessione: TFDConnection;
  Risposta: TJSONArray;
  Esito: TJSONObject;
  Istruzione, Testo: string;
  Comando: TFDCommand;
  Campi: TJSONArray;
begin
  if Context.Request.Body.Trim.IsEmpty then
    Corpo := nil
  else
    Corpo := CorpoDataset;
  Risposta := TJSONArray.Create;
  Connessione := PrendiConnessione;
  try
    if Corpo = nil then
    begin
      Corpo := TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('datasets'), [id]);
      if Corpo = nil then
        raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dataset non trovato: ' + id);
    end;

    for Istruzione in Istruzioni do
    begin
      Testo := Valore(Corpo, Istruzione);
      if Testo.Trim.IsEmpty then
        Continue;
      Esito := TJSONObject.Create.AddPair('istruzione', Istruzione);
      Risposta.AddElement(Esito);
      try
        if Istruzione = 'SQL_SELECT' then
        begin
          Campi := CampiDellaSelect(Connessione, Testo);
          Esito.AddPair('campi', Campi);
        end
        else
        begin
          Comando := TFDCommand.Create(nil);
          try
            Comando.Connection := Connessione;
            Comando.CommandText.Text := SqlConSegnapostoLegati(Testo);
            Comando.Prepare;
          finally
            Comando.Free;
          end;
        end;
        Esito.AddPair('ok', TJSONBool.Create(True));
        Esito.AddPair('messaggio', '');
      except
        on E: Exception do
        begin
          Esito.AddPair('ok', TJSONBool.Create(False));
          Esito.AddPair('messaggio', E.Message);
        end;
      end;
    end;
    // la preparazione puo' aver aperto una transazione di sola lettura
    Annulla(Connessione);
  finally
    RilasciaConnessione(Connessione);
    Corpo.Free;
  end;
  try
    RenderTestoJson(HTTP_STATUS.OK, Risposta);
  finally
    Risposta.Free;
  end;
end;

{ Campi }

procedure TMetaEditorController.GetFields(const id: string);
begin
  RenderRighe(TMetadataTransfer.Tabella('fields'), [id, '']);
end;

// Cosa farebbe "Genera campi dalla SELECT": i campi letti dalla SELECT con la
// loro origine, quali esistono gia' e quali verrebbero eliminati perche' non
// stanno piu' nella SELECT (DATASETS_FIELDS_SYNC li cancella, in cascata su
// colonna e posizione nella form).
procedure TMetaEditorController.SyncFieldsPreview(const id: string);
var
  Connessione: TFDConnection;
  Dataset: TJSONObject;
  Campi, Esistenti, DaEliminare: TJSONArray;
  Campo, Esistente: TJSONValue;
  Nomi: TDictionary<string, Boolean>;
  Risposta: TJSONObject;
begin
  Connessione := PrendiConnessione;
  try
    Dataset := TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('datasets'), [id]);
    if Dataset = nil then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dataset non trovato: ' + id);
    try
      Campi := CampiDellaSelect(Connessione, Valore(Dataset, 'SQL_SELECT'));
    finally
      Dataset.Free;
    end;
    Esistenti := TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('fields'), [id, '']);
    Annulla(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  Nomi := TDictionary<string, Boolean>.Create;
  Risposta := TJSONObject.Create;
  try
    for Esistente in Esistenti do
      Nomi.AddOrSetValue(Valore(TJSONObject(Esistente), 'FIELD').ToUpper, True);
    for Campo in Campi do
      TJSONObject(Campo).AddPair('esistente', TJSONBool.Create(Nomi.ContainsKey(Valore(TJSONObject(Campo), 'FIELD').ToUpper)));

    Nomi.Clear;
    for Campo in Campi do
      Nomi.AddOrSetValue(Valore(TJSONObject(Campo), 'FIELD').ToUpper, True);
    DaEliminare := TJSONArray.Create;
    for Esistente in Esistenti do
      if not Nomi.ContainsKey(Valore(TJSONObject(Esistente), 'FIELD').ToUpper) then
        DaEliminare.Add(Valore(TJSONObject(Esistente), 'FIELD'));

    Risposta.AddPair('campi', Campi);
    Risposta.AddPair('daEliminare', DaEliminare);
    Esistenti.Free;
    RenderJson(Risposta);
    Risposta := nil;
  finally
    Risposta.Free;
    Nomi.Free;
  end;
end;

// BASE_WEB.DATASETS_FIELDS_SYNC: cancella i campi che non stanno piu' nella
// SELECT, aggiunge i nuovi dal dizionario dati con colonna della griglia e
// posizione nella form, crea picklist e lookup che mancano. La rigenerazione
// dei META resta spenta per tutta la procedura e si riaccende nel finally.
procedure TMetaEditorController.SyncFields(const id: string);
var
  Connessione: TFDConnection;
  Dataset: TJSONObject;
  Campi: TJSONArray;
  Campo: TJSONValue;
  Nomi, Origini: TStringBuilder;
  Procedura: TFDStoredProc;
begin
  Nomi := TStringBuilder.Create;
  Origini := TStringBuilder.Create;
  Connessione := PrendiConnessione;
  try
    Dataset := TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('datasets'), [id]);
    if Dataset = nil then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dataset non trovato: ' + id);
    try
      Campi := CampiDellaSelect(Connessione, Valore(Dataset, 'SQL_SELECT'));
    finally
      Dataset.Free;
    end;
    try
      for Campo in Campi do
      begin
        Nomi.AppendLine(Valore(TJSONObject(Campo), 'FIELD'));
        Origini.AppendLine(Valore(TJSONObject(Campo), 'FIELD') + '=' + Valore(TJSONObject(Campo), 'FIELD_ORIGIN'));
      end;
    finally
      Campi.Free;
    end;

    ApriTransazione(Connessione);
    try
      TMetadataTransfer.DisattivaRigenerazioneMeta(Connessione);
      try
        Procedura := TFDStoredProc.Create(nil);
        try
          Procedura.Connection := Connessione;
          Procedura.StoredProcName := 'BASE_WEB.DATASETS_FIELDS_SYNC';
          Procedura.Prepare;
          Procedura.Params.ParamByName('DATASET').AsString := id;
          // Senza l'a capo finale di AppendLine: DATASETS_FIELDS_SYNC spezza il
          // testo in righe e su una riga vuota in fondo fallisce (SUBSTRING con
          // lunghezza -1, perche' POSITION('=', '') vale 0)
          Procedura.Params.ParamByName('FIELDS').AsWideMemo := Nomi.ToString.TrimRight([#13, #10]);
          Procedura.Params.ParamByName('FIELD_ORIGINS').AsWideMemo := Origini.ToString.TrimRight([#13, #10]);
          Procedura.ExecProc;
        finally
          Procedura.Free;
        end;
      finally
        TMetadataTransfer.RiattivaRigenerazioneMeta(Connessione, id);
      end;
      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;
  finally
    RilasciaConnessione(Connessione);
    Origini.Free;
    Nomi.Free;
  end;

  RenderRighe(TMetadataTransfer.Tabella('fields'), [id, '']);
end;

procedure TMetaEditorController.UpdateField(const id, field: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('fields'), [id, field], CorpoJson);
end;

procedure TMetaEditorController.DeleteField(const id, field: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('fields'), [id, field]);
end;

{ Griglia }

procedure TMetaEditorController.GetGrid(const id: string);
var
  Connessione: TFDConnection;
  Risposta: TJSONObject;
begin
  Risposta := TJSONObject.Create;
  Connessione := PrendiConnessione;
  try
    Risposta.AddPair('bands', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('gridBands'), [id, '']));
    Risposta.AddPair('columns', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('gridColumns'), [id, '']));
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderJson(Risposta);
end;

procedure TMetaEditorController.UpdateBand(const id, name: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('gridBands'), [id, name], CorpoJson);
end;

procedure TMetaEditorController.DeleteBand(const id, name: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('gridBands'), [id, name]);
end;

procedure TMetaEditorController.UpdateColumn(const id, field: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('gridColumns'), [id, field], CorpoJson);
end;

procedure TMetaEditorController.DeleteColumn(const id, field: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('gridColumns'), [id, field]);
end;

{ Form }

// L'albero intero: contenitori (supertipo), le tre specializzazioni e le foglie
procedure TMetaEditorController.GetForm(const id: string);
var
  Connessione: TFDConnection;
  Risposta: TJSONObject;
  Contenitori: TTabellaBaseWeb;
begin
  // BASE_WEB_FORM_CONTAINER non e' nel catalogo del trasporto (lo scrivono
  // GROUPS/TABBED/TABS_SAVE), ma la sua _LOAD da' l'albero in una lettura sola
  Contenitori.Sezione := 'containers';
  Contenitori.Tabella := 'BASE_WEB_FORM_CONTAINER';
  Contenitori.Chiavi := ['DATASET', 'CONTAINER_NAME', 'CONTAINER_TYPE'];

  Risposta := TJSONObject.Create;
  Connessione := PrendiConnessione;
  try
    Risposta.AddPair('containers', TMetadataTransfer.Carica(Connessione, Contenitori, [id, '', '']));
    Risposta.AddPair('groups', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formGroups'), [id, '']));
    Risposta.AddPair('tabbed', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formTabbed'), [id, '']));
    Risposta.AddPair('tabs', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formTabs'), [id, '']));
    Risposta.AddPair('fields', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formFields'), [id, '']));
    Risposta.AddPair('buttons', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formButtons'), [id, '']));
    Risposta.AddPair('empty', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('formEmpty'), [id, '']));
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderJson(Risposta);
end;

function SezioneForm(const Nome: string): string;
begin
  if SameText(Nome, 'groups') then
    Result := 'formGroups'
  else
    if SameText(Nome, 'tabbed') then
      Result := 'formTabbed'
    else
      if SameText(Nome, 'tabs') then
        Result := 'formTabs'
      else
        if SameText(Nome, 'fields') then
          Result := 'formFields'
        else
          if SameText(Nome, 'buttons') then
            Result := 'formButtons'
          else
            if SameText(Nome, 'empty') then
              Result := 'formEmpty'
            else
              raise EMVCException.Create(HTTP_STATUS.NotFound, 'Parte della form sconosciuta: ' + Nome);
end;

// Riordino di molti elementi in un colpo (trascinamento): corpo
// { "groups": [...], "tabbed": [...], "tabs": [...], "fields": [...], "buttons": [...], "empty": [...] }
// con le righe intere o parziali. Una transazione, META spento e riacceso
// nel finally sulla stessa connessione (ENABLE(dataset) rigenera il JSON).
procedure TMetaEditorController.SaveFormAll(const id: string);
var
  Corpo: TJSONObject;
  Connessione: TFDConnection;
  Creato: Boolean;

  function Sezione(const Nome: string): TJSONArray;
  var
    V: TJSONValue;
  begin
    V := Corpo.GetValue(Nome);
    if V is TJSONArray then
      Result := TJSONArray(V)
    else
      Result := nil;
  end;

  procedure SalvaFoglie(const Nome, NomeSezione: string);
  var
    Righe: TJSONArray;
    Riga: TJSONValue;
    T: TTabellaBaseWeb;
  begin
    Righe := Sezione(Nome);
    if Righe = nil then
      Exit;
    T := TMetadataTransfer.Tabella(NomeSezione);
    for Riga in Righe do
      TMetadataTransfer.SalvaUnendo(Connessione, T, [id, Valore(TJSONObject(Riga), T.ColonnaChiave)], TJSONObject(Riga), Creato);
  end;

begin
  Corpo := CorpoJson;
  try
    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        TMetadataTransfer.DisattivaRigenerazioneMeta(Connessione);
        try
          TMetadataTransfer.SalvaContenitori(Connessione, Sezione('groups'), Sezione('tabbed'), Sezione('tabs'));
          SalvaFoglie('fields', 'formFields');
          SalvaFoglie('buttons', 'formButtons');
          SalvaFoglie('empty', 'formEmpty');
        finally
          TMetadataTransfer.RiattivaRigenerazioneMeta(Connessione, id);
        end;
        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    Corpo.Free;
  end;
  GetForm(id);
end;

procedure TMetaEditorController.UpdateFormItem(const id, sezione, name: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella(SezioneForm(sezione)), [id, name], CorpoJson);
end;

procedure TMetaEditorController.DeleteFormItem(const id, sezione, name: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella(SezioneForm(sezione)), [id, name]);
end;

{ Sovrascritture per cliente (_CUSTOM) }

// Tutte le righe _CUSTOM del dataset, una sezione per tabella, con gli stessi
// nomi di sezione delle righe di base: l'editor le affianca
procedure TMetaEditorController.GetCustom(const id: string);
var
  Connessione: TFDConnection;
  Risposta: TJSONObject;
  T: TTabellaBaseWeb;
begin
  Risposta := TJSONObject.Create;
  Connessione := PrendiConnessione;
  try
    for T in TMetadataTransfer.TabelleCustom do
      if Length(T.Chiavi) = 1 then
        Risposta.AddPair(T.Sezione, TMetadataTransfer.Carica(Connessione, T, [id]))
      else
        Risposta.AddPair(T.Sezione, TMetadataTransfer.Carica(Connessione, T, [id, '']));
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderJson(Risposta);
end;

procedure TMetaEditorController.UpdateCustomDataset(const id, sezione: string);
var
  T: TTabellaBaseWeb;
begin
  T := TabellaDiSezione(sezione, True);
  if Length(T.Chiavi) <> 1 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La sezione ' + sezione + ' richiede la chiave dell''elemento');
  if SameText(sezione, 'datasets') then
    SalvaDaCorpo(T, [id], CorpoDataset)
  else
    SalvaDaCorpo(T, [id], CorpoJson);
end;

procedure TMetaEditorController.UpdateCustom(const id, sezione, chiave: string);
var
  T: TTabellaBaseWeb;
begin
  T := TabellaDiSezione(sezione, True);
  if Length(T.Chiavi) <> 2 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La sezione ' + sezione + ' non ha una chiave oltre al dataset');
  SalvaDaCorpo(T, [id, chiave], CorpoJson);
end;

procedure TMetaEditorController.DeleteCustomDataset(const id, sezione: string);
var
  T: TTabellaBaseWeb;
begin
  T := TabellaDiSezione(sezione, True);
  if Length(T.Chiavi) <> 1 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La sezione ' + sezione + ' richiede la chiave dell''elemento');
  EliminaRiga(T, [id]);
end;

procedure TMetaEditorController.DeleteCustom(const id, sezione, chiave: string);
var
  T: TTabellaBaseWeb;
begin
  T := TabellaDiSezione(sezione, True);
  if Length(T.Chiavi) <> 2 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La sezione ' + sezione + ' non ha una chiave oltre al dataset');
  EliminaRiga(T, [id, chiave]);
end;

{ Lookup }

procedure TMetaEditorController.GetLookups;
begin
  RenderRighe(TMetadataTransfer.Tabella('lookups'), ['']);
end;

// Il lookup con le sue colonne
procedure TMetaEditorController.GetLookup(const id: string);
var
  Connessione: TFDConnection;
  Riga: TJSONObject;
begin
  Connessione := PrendiConnessione;
  try
    Riga := TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('lookups'), [id]);
    if Riga = nil then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Lookup non trovato: ' + id);
    Riga.AddPair('columns', TMetadataTransfer.Carica(Connessione, TMetadataTransfer.Tabella('lookupColumns'), [id, '']));
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderJson(Riga);
end;

procedure TMetaEditorController.CreateLookup;
var
  Corpo: TJSONObject;
  Nome: string;
begin
  Corpo := CorpoJson;
  Nome := Valore(Corpo, 'LOOKUP').Trim;
  if Nome.IsEmpty then
  begin
    Corpo.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'LOOKUP obbligatorio');
  end;
  SalvaDaCorpo(TMetadataTransfer.Tabella('lookups'), [Nome], Corpo);
end;

procedure TMetaEditorController.UpdateLookup(const id: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('lookups'), [id], CorpoJson);
end;

procedure TMetaEditorController.DeleteLookup(const id: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('lookups'), [id]);
end;

procedure TMetaEditorController.UpdateLookupColumn(const id, field: string);
begin
  SalvaDaCorpo(TMetadataTransfer.Tabella('lookupColumns'), [id, field], CorpoJson);
end;

procedure TMetaEditorController.DeleteLookupColumn(const id, field: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('lookupColumns'), [id, field]);
end;

{ Picklist }

procedure TMetaEditorController.GetPicklists;
begin
  RenderRighe(TMetadataTransfer.Tabella('picklists'), ['']);
end;

// La picklist con le voci generate dai trigger a partire da ITEMS ("Nome=Valore", una per riga)
procedure TMetaEditorController.GetPicklist(const id: string);
var
  Connessione: TFDConnection;
  Riga: TJSONObject;
  Voci: TTabellaBaseWeb;
begin
  Voci.Sezione := 'picklistItems';
  Voci.Tabella := 'BASE_WEB_PICKLISTS_ITEMS';
  Voci.Chiavi := ['PICKLIST', 'NOME'];

  Connessione := PrendiConnessione;
  try
    Riga := TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('picklists'), [id]);
    if Riga = nil then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Picklist non trovata: ' + id);
    Riga.AddPair('items', TMetadataTransfer.Carica(Connessione, Voci, [id, '']));
  finally
    RilasciaConnessione(Connessione);
  end;
  RenderJson(Riga);
end;

// ITEMS deve essere testo "Nome=Valore" una voce per riga: un JSON passerebbe
// il parser dei trigger e produrrebbe voci spezzate
procedure TMetaEditorController.CreatePicklist;
var
  Corpo: TJSONObject;
  Nome: string;
begin
  Corpo := CorpoJson;
  Nome := Valore(Corpo, 'PICKLIST').Trim;
  if Nome.IsEmpty then
  begin
    Corpo.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'PICKLIST obbligatoria');
  end;
  if Valore(Corpo, 'ITEMS').TrimLeft.StartsWith('[') then
  begin
    Corpo.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'ITEMS deve essere testo nel formato Nome=Valore, una voce per riga, non JSON');
  end;
  SalvaDaCorpo(TMetadataTransfer.Tabella('picklists'), [Nome], Corpo);
end;

procedure TMetaEditorController.UpdatePicklist(const id: string);
var
  Corpo: TJSONObject;
begin
  Corpo := CorpoJson;
  if Valore(Corpo, 'ITEMS').TrimLeft.StartsWith('[') then
  begin
    Corpo.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'ITEMS deve essere testo nel formato Nome=Valore, una voce per riga, non JSON');
  end;
  SalvaDaCorpo(TMetadataTransfer.Tabella('picklists'), [id], Corpo);
end;

procedure TMetaEditorController.DeletePicklist(const id: string);
begin
  EliminaRiga(TMetadataTransfer.Tabella('picklists'), [id]);
end;

{ Trasporto }

// ?datasets=A,B  ?dm=Agora  ?escludi_dm=Agora  ?format=json|sql
procedure TMetaEditorController.ExportMetadata;
var
  Connessione: TFDConnection;
  Filtro: TFiltroEsportazione;
  Pacchetto: TJSONObject;
  Script: string;
begin
  Filtro.Datasets := ParametroElenco('datasets');
  Filtro.Dm := ParametroElenco('dm');
  Filtro.EscludiDm := ParametroElenco('escludi_dm');

  Connessione := PrendiConnessione;
  try
    Pacchetto := TMetadataTransfer.Esporta(Connessione, Filtro, Connessione.Params.Database);
    Annulla(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;
  try
    if SameText(ParamByName('format'), 'sql') then
    begin
      Script := TMetadataTransfer.ScriptSql(Pacchetto);
      Context.Response.ContentType := 'text/plain; charset=utf-8';
      Context.Response.SetCustomHeader('Content-Disposition', 'attachment; filename="baseweb-metadati.sql"');
      Render(HTTP_STATUS.OK, Script);
    end
    else
    begin
      Context.Response.SetCustomHeader('Content-Disposition', 'attachment; filename="baseweb-metadati.json"');
      RenderTestoJson(HTTP_STATUS.OK, Pacchetto);
    end;
  finally
    Pacchetto.Free;
  end;
end;

// Corpo: il pacchetto JSON di /export. Una transazione: tutto o niente.
procedure TMetaEditorController.ImportMetadata;
var
  Pacchetto: TJSONObject;
  Connessione: TFDConnection;
  Esito: TJSONObject;
begin
  Pacchetto := CorpoJson;
  try
    Connessione := PrendiConnessione;
    try
      Esito := TMetadataTransfer.Importa(Connessione, Pacchetto);
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    Pacchetto.Free;
  end;
  RenderJson(Esito);
end;

// Corpo: il pacchetto JSON di /export. Risposta: lo script SQL equivalente,
// per i clienti dove l'importazione passa da zBuilder o da IBEScript.
procedure TMetaEditorController.ImportScript;
var
  Pacchetto: TJSONObject;
  Script: string;
begin
  Pacchetto := CorpoJson;
  try
    Script := TMetadataTransfer.ScriptSql(Pacchetto);
  finally
    Pacchetto.Free;
  end;
  Context.Response.ContentType := 'text/plain; charset=utf-8';
  Context.Response.SetCustomHeader('Content-Disposition', 'attachment; filename="baseweb-metadati.sql"');
  Render(HTTP_STATUS.OK, Script);
end;

end.
