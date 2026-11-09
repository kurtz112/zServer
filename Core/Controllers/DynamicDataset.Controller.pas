// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-06
// ---------------------------------------------------------------------------
unit DynamicDataset.Controller;

{
  DynamicDataset.Controller
  ─────────────────────────
  Controller DMVC che gestisce operazioni CRUD dinamiche su dataset configurati
  nella tabella BASE_WEB_DATASETS, con supporto pieno al CustomStore di DevExtreme.

  Dipendenze chiave:
  DevExtremeHelper → parsing loadOptions, generazione SQL, risposta DevExtreme
  Data.Service     → accesso dati Firebird (query parametriche)
  fib.SqlTxtRtns   → manipolazione testo SQL (AddToWhereClause, SetOrderClause)
  App.Profile      → perimetro di visibilita e verifiche che dipendono dal prodotto

  Flusso GetData:
  1. Legge configurazione dataset da BASE_WEB_DATASETS
  2. Verifica l'autorizzazione dichiarata dal dataset (Z6)
  3. Sostituisce i segnaposto di sessione nella SQL (Z4) e lega i parametri
     propri del dataset ai valori arrivati con la richiesta
  4. Parsa le loadOptions DevExtreme (filter genera parametri bindati)
  5. Compone l'SQL finale aggiungendo WHERE, ORDER BY, ROWS
  6. Esegue con TDataService.ExecuteQuery(SQL, Helper.Params)
  7. Gestisce eventuale grouping in-memory
  8. Restituisce la risposta nel formato atteso da DevExtreme CustomStore
}

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Logger,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller,
  Data.Service,
  DevExtremeHelper;

type

  [MVCPath('/api/data')]
  [MVCDoc('Controller dinamico per gestione dataset con supporto DevExtreme CustomStore')]
  TDynamicDatasetController = class(TBaseController)
  private
    function GetDatasetConfig(const DatasetId: string): TDatasetConfig;
    function GetTotalCount(const BaseSQL: string; Helper: TDevExtremeHelper): Integer;

    procedure VerificaAutorizzazione(const DatasetConfig: TDatasetConfig; const Scrittura: Boolean);
    procedure VerificaCodiceAutorizzazione(const Codice, Oggetto: string);
    procedure VerificaArea(const Tipo, Nome, Oggetto: string);
    procedure VerificaModulo(const Modulo, Oggetto: string; const Scrittura: Boolean);
    function ProceduraEsposta(const NomeRichiesto: string): string;
    procedure VerificaAmbitoDelCorpo(const DatasetConfig: TDatasetConfig; RecordData: TJSONObject; const Obbligatorio: Boolean);
    procedure VerificaChiaveNelPerimetro(const DatasetConfig: TDatasetConfig; const KeyValue: string);
    procedure TogliCampiFuoriTabella(const DatasetConfig: TDatasetConfig; RecordData: TJSONObject);
    function RisolviSegnapostoDiSessione(const SQL: string; Helper: TDevExtremeHelper): string;
    procedure UnisciParametriDiSessione(Helper: TDevExtremeHelper; Params: TParamValues);
    procedure LegaParametriDellaRichiesta(const SQL: string; Helper: TDevExtremeHelper);
    function SqlDelDataset(const DatasetConfig: TDatasetConfig; const SQL: string; Helper: TDevExtremeHelper): string;

    //
    function BuildSQL(const BaseSQL: string; LoadOptions: TDevExtremeLoadOptions; Helper: TDevExtremeHelper; const ApplySort: boolean = true; const ForcedPagination: string = ''): string;
  public
    [MVCPath('/($idDataset)/metadata')]
    [MVCHTTPMethod([httpGET])]
    procedure GetMetadata(const idDataset: string);

    [MVCPath('/($idDataset)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Recupera dati da dataset dinamico con supporto LoadOptions DevExtreme')]
    [MVCSwagSummary('Dataset', 'Ottieni dati dataset', 'default')]
    [MVCSwagParam(plPath, 'idDataset', 'ID o nome del dataset', ptString, true)]
    [MVCSwagParam(plQuery, 'filter', 'Filtri DevExtreme (JSON)', ptString, False)]
    [MVCSwagParam(plQuery, 'sort', 'Ordinamento DevExtreme (JSON)', ptString, False)]
    [MVCSwagParam(plQuery, 'skip', 'Record da saltare (paging)', ptInteger, False)]
    [MVCSwagParam(plQuery, 'take', 'Record da recuperare (paging)', ptInteger, False)]
    [MVCSwagParam(plQuery, 'group', 'Raggruppamento DevExtreme (JSON)', ptString, False)]
    [MVCSwagParam(plQuery, 'requireTotalCount', 'Richiedi conteggio totale', ptBoolean, False)]
    [MVCSwagParam(plQuery, 'requireGroupCount', 'Richiedi conteggio per gruppo', ptBoolean, False)]
    [MVCSwagParam(plQuery, 'belfiore', 'Comune di lavoro, verificato sui comuni abilitati', ptString, False)]
    [MVCSwagParam(plQuery, 'idAzienda', 'Azienda di lavoro, verificata sulle aziende abilitate', ptInteger, False)]
    [MVCSwagResponses(200, 'Dataset recuperato con successo')]
    [MVCSwagResponses(400, 'Richiesta database non valida')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    [MVCSwagResponses(403, 'Autorizzazione mancante per questo dataset')]
    procedure GetData(idDataset: string);

    [MVCPath('/($idDataset)')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Inserisce un nuovo record nel dataset')]
    [MVCSwagSummary('Dataset', 'Inserisci record', 'default')]
    [MVCSwagParam(plPath, 'idDataset', 'ID o nome del dataset', ptString, true)]
    [MVCSwagResponses(201, 'Record creato con successo')]
    [MVCSwagResponses(400, 'Richiesta database non valida')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    procedure InsertData(idDataset: string);

    [MVCPath('/($idDataset)/($key)')]
    [MVCHTTPMethod([httpPUT])]
    [MVCDoc('Aggiorna un record esistente nel dataset')]
    [MVCSwagSummary('Dataset', 'Aggiorna record', 'default')]
    [MVCSwagParam(plPath, 'idDataset', 'ID o nome del dataset', ptString, true)]
    [MVCSwagParam(plPath, 'key', 'Chiave primaria del record', ptString, true)]
    [MVCSwagResponses(200, 'Record aggiornato con successo')]
    [MVCSwagResponses(400, 'Richiesta database non valida')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    procedure UpdateData(idDataset: string; key: string);

    [MVCPath('/($idDataset)/($key)')]
    [MVCHTTPMethod([httpDELETE])]
    [MVCDoc('Elimina un record dal dataset')]
    [MVCSwagSummary('Dataset', 'Elimina record', 'default')]
    [MVCSwagParam(plPath, 'idDataset', 'ID o nome del dataset', ptString, true)]
    [MVCSwagParam(plPath, 'key', 'Chiave primaria del record', ptString, true)]
    [MVCSwagResponses(204, 'Record eliminato con successo')]
    [MVCSwagResponses(400, 'Richiesta database non valida')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    procedure DeleteData(idDataset: string; key: string);

    [MVCPath('/sp/($procName)')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Esegue una stored procedure con parametri')]
    [MVCSwagSummary('Dataset', 'Esegui stored procedure', 'default')]
    [MVCSwagParam(plPath, 'procName', 'Nome della stored procedure', ptString, true)]
    [MVCSwagResponses(200, 'Procedura eseguita con successo')]
    [MVCSwagResponses(400, 'Richiesta database non valida')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    [MVCSwagResponses(403, 'Procedura non esposta in BASE_WEB_PROCEDURE o autorizzazione mancante')]
    procedure ExecuteStoredProcedure(procName: string);

    // Z9 - GetLookupData eliminato: era marcato «eliminare» nel sorgente e
    // faceva, con meno controlli, quello che fa GetData. Le caselle a
    // discesa usano GetData con searchExpr/searchValue, che e' lo stesso
    // punto di ingresso di tutto il resto e passa dalle stesse verifiche.
  end;

implementation

uses
  System.Diagnostics,
  System.NetEncoding,
  System.IoUtils,
  System.Variants,
  System.StrUtils,
  System.RegularExpressions,
  App.Profile,
  Session.Context,
  Connection.Pool,
  fib.SqlTxtRtns;

const
  // Z4 - Segnaposto di sessione, nello stile del :##AZIENDA_DI_LAVORO dei
  // metadati LZ. Vengono sostituiti con parametri legati, non con valori
  // scritti nel testo della SQL.
  SEGNAPOSTO_USER_ID = ':##USER_ID';
  SEGNAPOSTO_ID_SESSIONE = ':##ID_SESSIONE';
  SEGNAPOSTO_BELFIORE = ':##BELFIORE';
  SEGNAPOSTO_ID_AZIENDA = ':##ID_AZIENDA';

  PARAMETRO_USER_ID = 'CTX_USER_ID';
  PARAMETRO_ID_SESSIONE = 'CTX_ID_SESSIONE';
  PARAMETRO_BELFIORE = 'CTX_BELFIORE';
  PARAMETRO_ID_AZIENDA = 'CTX_ID_AZIENDA';

  // Parametri che dicono chi sta chiedendo i dati: non si prendono mai dalla
  // richiesta, restano nulli come prima o li valorizza il server. Senza questo
  // elenco un browser potrebbe mandare ?ID_SESSIONE=... per un'altra sessione.
  PARAMETRI_RISERVATI: array [0 .. 7] of string = (
    'ID_SESSIONE', 'ID_SESSIONE_WEB', 'USER_ID', 'USER_NAME',
    'ID_RISORSA', 'ID_INTESTATARIO', 'ID_AZIENDA', 'BELFIORE');

  // ZC 04.11.2026: procedure in cui ID_INTESTATARIO e' la scelta del cittadino e non il
  // contesto della sessione. Prima il parametro riservato rendeva impossibile la scelta fra
  // piu' intestatari dopo l'accesso SPID (400 "Il parametro ID_INTESTATARIO non si puo'
  // indicare"). La procedura verifica da se' che l'intestatario scelto abbia lo stesso
  // codice fiscale della sessione (USR_SPID_SELEZIONA_INTESTATARIO), quindi non si puo'
  // scegliere una posizione altrui. Vale solo per le procedure elencate.
  PROCEDURE_CON_INTESTATARIO_SCELTO: array [0 .. 0] of string = (
    'WEB_CIT_LOGIN_CF_SCELTA_INTEST');

{ ══════════════════════════════════════════════════════════════════════════════
  Helper locale
  ══════════════════════════════════════════════════════════════════════════════ }

function DecodeBase64(const Base64Str: string): string;
var
  b: TBytes;
begin
  if Base64Str.IsEmpty then
    Exit('');
  b := TNetEncoding.Base64.DecodeStringToBytes(Base64Str);
  Result := TEncoding.Unicode.GetString(b);
end;

{ ══════════════════════════════════════════════════════════════════════════════
  TDynamicDatasetController
  ══════════════════════════════════════════════════════════════════════════════ }

function TDynamicDatasetController.GetDatasetConfig(const DatasetId: string): TDatasetConfig;
var
  Parametri: TParamValues;
  ConfigData: TJSONObject;
begin
  // Il nome del dataset arriva dal percorso: legato come parametro, non
  // composto nel testo della SQL.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('DS', DatasetId);
    ConfigData := TDataService.ExecuteQuerySingleRow('SELECT * FROM BASE_WEB_DATASETS WHERE BASE_WEB_DATASETS.DATASET = :DS', Parametri, False);
  finally
    FreeAndNil(Parametri);
  end;

  try
    // ZC 30.10.2026 - R-177: senza righe ExecuteQuerySingleRow non restituisce
    // nil ma un oggetto con i campi a null (come in ProceduraEsposta), quindi il
    // 404 non scattava mai e un dataset sconosciuto proseguiva con una
    // configurazione vuota (DIV-DSD-6). Serve anche a GetMetadata, che ora passa
    // da qui: senza questo controllo il suo 404 diventava un errore imprevisto.
    if (not Assigned(ConfigData)) or (not Assigned(ConfigData.GetValue('DATASET'))) or (ConfigData.GetValue('DATASET') is TJSONNull) then
      raise EMVCException.Create(HTTP_STATUS.NotFound, Format('Dataset "%s" non trovato', [DatasetId]));

    Result.DatasetId := ConfigData.GetValue<string>('DATASET');
    Result.TableName := ConfigData.GetValue<string>('RELATION_NAME');
    Result.PrimaryKeyField := ConfigData.GetValue<string>('PK_FIELDS');
    Result.SelectSQL := ConfigData.GetValue<string>('SQL_SELECT');
    Result.CountSQL := ConfigData.GetValue<string>('SQL_COUNT');
    Result.InsertSQL := ConfigData.GetValue<string>('SQL_INSERT', '');
    Result.UpdateSQL := ConfigData.GetValue<string>('SQL_UPDATE', '');
    Result.DeleteSQL := ConfigData.GetValue<string>('SQL_DELETE', '');
    Result.AllowInsert := ConfigData.GetValue<boolean>('CAN_INSERT', true);
    Result.AllowUpdate := ConfigData.GetValue<boolean>('CAN_UPDATE', true);
    Result.AllowDelete := ConfigData.GetValue<boolean>('CAN_DELETE', true);
    Result.Authorization := ConfigData.GetValue<string>('AUTHORIZATION', '');
    // ZC 06.11.2026: la colonna MODULO c'e' solo in WT (script WT-MODULI-01). La
    // lettura con SELECT * e il valore predefinito la lasciano vuota in Gesty e
    // nei database WT senza lo script: nessun controllo di modulo, come prima.
    Result.Modulo := ConfigData.GetValue<string>('MODULO', '').Trim;
  finally
    FreeAndNil(ConfigData);
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Z6 - Autorizzazione per dataset

  Prima, tolta la deroga di Z1, un operatore autenticato poteva comunque
  leggere tutti i dataset registrati, compresi quelli che non gli competono:
  OnAuthorization autorizza chiunque abbia almeno un ruolo.

  Il codice di autorizzazione sta nella colonna AUTHORIZATION di
  BASE_WEB_DATASETS e la verifica la fa USR_AUTHORIZATION_CHECK, che esiste
  identica in WT e in Gesty: i permessi restano quelli dell'applicazione,
  senza far nascere un secondo sistema di ruoli.

  USR_AUTHORIZATION_CHECK legge USR_TMP_AUTHORIZATIONS, che e' riempita da
  USR_FILL_TABELLE_TMP: funziona quindi solo su una connessione che porta il
  contesto dell'utente, cioe' dopo il punto Z3.
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.VerificaAutorizzazione(const DatasetConfig: TDatasetConfig; const Scrittura: Boolean);
begin
  VerificaCodiceAutorizzazione(DatasetConfig.Authorization, 'Dataset ' + DatasetConfig.DatasetId);
  VerificaArea('D', DatasetConfig.DatasetId, 'Dataset ' + DatasetConfig.DatasetId);
  VerificaModulo(DatasetConfig.Modulo, 'Dataset ' + DatasetConfig.DatasetId, Scrittura);
end;

// Moduli (2026-11-06, OUT\20261106-pipa-sportello-comuni-funzioni-per-comune).
// Un dataset o una procedura con un modulo si usano solo se l'utente ha quel
// modulo in almeno un comune: in lettura basta R, per le scritture e per le
// procedure serve W. Poi il perimetro della richiesta si restringe ai comuni
// in cui l'utente ha il modulo (con W, se la richiesta scrive): da li' in poi
// ClausolaPerimetro, AmbitoAmmesso e le procedure del database vedono solo
// quei comuni. E' questo che separa le deleghe: con i gruppi "riuso nel
// comune A" e "consegne nel comune B" le consegne di A non si vedono.
// Senza modulo niente cambia. Come per l'area, il rifiuto e' un 403 che non
// dice quale modulo manca.
//
// La verifica viene prima di ogni lettura dei dati, e i controller nascono per
// richiesta: la restrizione vale per questa richiesta e basta.
procedure TDynamicDatasetController.VerificaModulo(const Modulo, Oggetto: string; const Scrittura: Boolean);
var
  Riga: TModuloUtente;
  Comuni: TArray<string>;
begin
  if Modulo.IsEmpty then
    Exit;

  Comuni := [];
  for Riga in TAppProfiles.Corrente.ModuliUtente(UserName) do
    if SameText(Riga.Modulo, Modulo) and ((not Scrittura) or Riga.Scrittura) and not MatchText(Riga.Belfiore, Comuni) then
      Comuni := Comuni + [Riga.Belfiore];

  // Moduli per azienda (GeCo, 2026-11-06): nessun comune da restringere, il
  // modulo lo attiva l'azienda e chi lo usa lo decide GERA_SQUADRE_MODULI.
  // Vale sia in lettura sia in scrittura.
  if (Length(Comuni) = 0) and TAppProfiles.Corrente.ModuloAttivoPerAzienda(UserName, Modulo) then
    Exit;

  // Moduli per cittadino (Riciclario, 2026-11-06): il cittadino non ha comuni
  // assegnati, il suo comune sono quelli delle sue utenze. Si ammette l'oggetto
  // se il modulo e' attivo in almeno uno; non si restringe niente perche' i
  // dataset del cittadino filtrano gia' per il suo intestatario.
  if (Length(Comuni) = 0) and TAppProfiles.Corrente.ModuloAttivoPerCittadino(UserName, Modulo) then
    Exit;

  // Moduli per gruppo senza comune (GERA, 2026-11-07): i dati sono dell'operatore
  // e non di un comune, quindi non si restringe niente. In scrittura serve W.
  if (Length(Comuni) = 0) and TAppProfiles.Corrente.ModuloAttivoPerGruppo(UserName, Modulo, Scrittura) then
    Exit;

  if Length(Comuni) = 0 then
  begin
    Registro.Warn(Format('%s: modulo %s %s non disponibile per utente %d', [Oggetto, Modulo, IfThen(Scrittura, 'in scrittura', 'in lettura'), UserId]), 'DynamicDatasetController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Funzione non disponibile per questo utente.');
  end;

  TAppProfiles.Corrente.RestringiComuniDellaRichiesta(Comuni);
end;

// Fase 0 delle aree (2026-11-02): oltre all'autorizzazione del gruppo, il
// dataset o la procedura devono appartenere all'area della sessione. Su WT
// lo decide BASE_WEB_AREA_AMMESSO con BASE_WEB_DATASETS_AREE e
// BASE_WEB_PROCEDURE_AREE; lo sportello (Agora') e i prodotti senza aree
// passano come prima. L'area si legge dalla sessione e non dal token: dopo
// un cambio d'area un token emesso prima non porta l'area vecchia.
// Risponde 403 come una procedura non esposta, senza dire perche'.
procedure TDynamicDatasetController.VerificaArea(const Tipo, Nome, Oggetto: string);
begin
  if TAppProfiles.Corrente.AmmessoNellArea(IdSessione, Tipo, Nome) then
    Exit;

  Registro.Warn(Format('%s fuori dall''area della sessione %d, rifiutato a utente %d', [Oggetto, IdSessione, UserId]), 'DynamicDatasetController');
  raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Non disponibile in questa area.');
end;

// Verifica comune a dataset e procedure (R-123): un codice vuoto non chiede
// niente, altrimenti decide USR_AUTHORIZATION_CHECK con i permessi
// dell'applicazione. Oggetto serve solo al registro.
procedure TDynamicDatasetController.VerificaCodiceAutorizzazione(const Codice, Oggetto: string);
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  if Codice.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('AUTHORIZATION', Codice);
    Parametri.Add('ERROR_MSG', '');

    try
      Esito := TDataService.ExecuteStoredProc('USR_AUTHORIZATION_CHECK', Parametri);
      FreeAndNil(Esito);
    except
      on E: Exception do
      begin
        Registro.Warn(Format('%s negato a utente %d: %s', [Oggetto, UserId, E.Message]), 'DynamicDatasetController');
        raise EMVCException.Create(HTTP_STATUS.Forbidden, E.Message);
      end;
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// R-123 - Procedure richiamabili dal web
//
// Fino al 2026-10-26 POST /api/data/sp/:procName eseguiva qualunque procedura
// del database con i privilegi della connessione di zServer: bastava essere
// autenticati, mentre i dataset passano da AUTHORIZATION. Ora la procedura
// deve stare in BASE_WEB_PROCEDURE con ATTIVA vera, e se la riga ha un codice
// in AUTHORIZATION lo si verifica come per i dataset.
//
// Il nome arriva dal percorso: si accetta solo un identificatore Firebird
// senza virgolette, in maiuscolo, oppure PACKAGE.PROCEDURA per le procedure
// di un package (FireDAC divide da solo le due parti), e si legge l'elenco
// con un parametro legato.
// Una procedura non elencata risponde 403 come una non autorizzata, cosi' chi
// prova i nomi non scopre quali esistono nel database.
// Restituisce il nome come sta nell'elenco, da passare a ExecuteStoredProc.
function TDynamicDatasetController.ProceduraEsposta(const NomeRichiesto: string): string;
var
  Parametri: TParamValues;
  Riga: TJSONObject;
  Codice: string;
  Modulo: string;
begin
  Result := NomeRichiesto.Trim.ToUpper;

  if not TRegEx.IsMatch(Result, '^[A-Z][A-Z0-9_$]{0,62}(\.[A-Z][A-Z0-9_$]{0,62})?$') then
  begin
    Registro.Warn(Format('Procedura con nome non valido rifiutata, utente %d', [UserId]), 'DynamicDatasetController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Procedura non disponibile.');
  end;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('PROCEDURA', Result);
    // ZC 06.11.2026: SELECT * invece dell'elenco delle colonne, per leggere
    // MODULO dove c'e' (WT con lo script WT-MODULI-01) senza far fallire la
    // lettura in Gesty, che non ha la colonna.
    Riga := TDataService.ExecuteQuerySingleRow(
      'SELECT BASE_WEB_PROCEDURE.* ' +
      'FROM BASE_WEB_PROCEDURE ' +
      'WHERE BASE_WEB_PROCEDURE.PROCEDURA = :PROCEDURA AND BASE_WEB_PROCEDURE.ATTIVA = TRUE',
      Parametri, False);
  finally
    FreeAndNil(Parametri);
  end;

  try
    // Senza righe ExecuteQuerySingleRow non restituisce nil ma un oggetto con
    // i campi a null: conta la PROCEDURA letta
    if (not Assigned(Riga)) or (not Assigned(Riga.GetValue('PROCEDURA'))) or (Riga.GetValue('PROCEDURA') is TJSONNull) then
    begin
      Registro.Warn(Format('Procedura %s non esposta, rifiutata a utente %d', [Result, UserId]), 'DynamicDatasetController');
      raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Procedura non disponibile.');
    end;

    Codice := Riga.GetValue<string>('AUTHORIZATION', '');
    Modulo := Riga.GetValue<string>('MODULO', '').Trim;
  finally
    FreeAndNil(Riga);
  end;

  VerificaCodiceAutorizzazione(Codice, 'Procedura ' + Result);
  VerificaArea('P', Result, 'Procedura ' + Result);
  // Una procedura scrive: serve il modulo in scrittura, e la procedura vede in
  // USR_TMP_COMUNI i soli comuni in cui l'utente lo lavora
  VerificaModulo(Modulo, 'Procedura ' + Result, True);
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Perimetro sulle scritture (decisione 17 di
  OUT\20261006-zserver-agora-anpr-firma-file-pdf)

  Fino al 2026-10-08 il perimetro del prodotto (su WT: BELFIORE fra i comuni
  dell'utente) si applicava solo alle letture. PUT e DELETE lavoravano per
  sola chiave primaria e POST accettava qualunque BELFIORE nel corpo: un
  operatore autenticato poteva modificare o cancellare una riga di un altro
  comune conoscendone la chiave. Le due verifiche qui sotto chiudono quel
  varco con la stessa clausola delle letture; dove il profilo non da' una
  clausola (Gesty, o una relazione senza BELFIORE) non cambiano niente.

  Un record fuori perimetro risponde 404 e non 403, come per i file: con
  403 chi prova le chiavi in sequenza saprebbe quali esistono.
  ────────────────────────────────────────────────────────────────────────────── }

function ValoreDelCampo(RecordData: TJSONObject; const Nome: string): TJSONValue;
var
  Pair: TJSONPair;
begin
  Result := nil;

  if not Assigned(RecordData) then
    Exit;

  for Pair in RecordData do
    if SameText(Pair.JsonString.Value, Nome) then
      Exit(Pair.JsonValue);
end;

procedure TDynamicDatasetController.VerificaAmbitoDelCorpo(const DatasetConfig: TDatasetConfig; RecordData: TJSONObject; const Obbligatorio: Boolean);
var
  Perimetro: string;
  Belfiore: string;
  IdAzienda: Int64;
  Valore: TJSONValue;
begin
  Perimetro := TAppProfiles.Corrente.ClausolaPerimetro(DatasetConfig.TableName);

  if Perimetro.Trim.IsEmpty then
    Exit;

  Belfiore := '';
  Valore := ValoreDelCampo(RecordData, 'BELFIORE');

  if Assigned(Valore) and not(Valore is TJSONNull) then
    Belfiore := Valore.Value.Trim;

  IdAzienda := 0;
  Valore := ValoreDelCampo(RecordData, 'ID_AZIENDA');

  if Valore is TJSONNumber then
    IdAzienda := TJSONNumber(Valore).AsInt64
  else
    if Assigned(Valore) and not(Valore is TJSONNull) then
      IdAzienda := StrToInt64Def(Valore.Value, 0);

  if Belfiore.IsEmpty then
  begin
    // Una riga senza comune non si vedrebbe mai dalle letture, che filtrano
    // su BELFIORE: inserirla sarebbe scriverla nel vuoto.
    if Obbligatorio then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Il dataset e'' per comune: il campo BELFIORE e'' obbligatorio.');

    if IdAzienda = 0 then
      Exit;
  end;

  if not TAppProfiles.Corrente.AmbitoAmmesso(Belfiore, IdAzienda) then
  begin
    Registro.Warn(Format('Dataset %s: scrittura fuori ambito da utente %d (comune %s, azienda %d)', [DatasetConfig.DatasetId, UserId, Belfiore, IdAzienda]), 'DynamicDatasetController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Comune o azienda non fra quelli abilitati per l''utente.');
  end;
end;

procedure TDynamicDatasetController.VerificaChiaveNelPerimetro(const DatasetConfig: TDatasetConfig; const KeyValue: string);
var
  Perimetro: string;
  SQL: string;
  Parametri: TParamValues;
begin
  Perimetro := TAppProfiles.Corrente.ClausolaPerimetro(DatasetConfig.TableName);

  if Perimetro.Trim.IsEmpty then
    Exit;

  SQL := Format('SELECT COUNT(*) FROM %s WHERE %s.%s = :KEY AND %s', [DatasetConfig.TableName, DatasetConfig.TableName, DatasetConfig.PrimaryKeyField, Perimetro]);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('KEY', KeyValue);

    if TDataService.ExecuteScalar(SQL, Parametri) = 0 then
    begin
      Registro.Warn(Format('Dataset %s: chiave %s fuori perimetro per utente %d', [DatasetConfig.DatasetId, KeyValue, UserId]), 'DynamicDatasetController');
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Record non trovato.');
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Campi del corpo che non sono colonne della tabella

  Le form di DevExtreme rimandano la riga intera, compresi i campi che la
  SELECT del dataset prende da un'altra tabella (ETICHETTA_SEZIONE di
  Agora.ConfigTipologieCampi) o calcola. Senza SQL_INSERT o SQL_UPDATE,
  BuildInsertSQL e BuildUpdateSQL mettevano ogni campo del corpo nella
  INSERT o nella SET, e Firebird rispondeva -206 "Column unknown": ogni
  dataset con un join aveva bisogno della SQL scritta a mano.

  Qui si tolgono dal corpo i campi che non sono colonne scrivibili di
  RELATION_NAME (colonne calcolate escluse), letti dal catalogo. Se il
  catalogo non restituisce colonne (relazione vuota o sconosciuta) il corpo
  resta com'e', come prima.
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.TogliCampiFuoriTabella(const DatasetConfig: TDatasetConfig; RecordData: TJSONObject);
const
  SQL_COLONNE =
    'SELECT TRIM(RDB$RELATION_FIELDS.RDB$FIELD_NAME) AS CAMPO ' +
    'FROM RDB$RELATION_FIELDS ' +
    'JOIN RDB$FIELDS ON RDB$FIELDS.RDB$FIELD_NAME = RDB$RELATION_FIELDS.RDB$FIELD_SOURCE ' +
    'WHERE RDB$RELATION_FIELDS.RDB$RELATION_NAME = :RELAZIONE ' +
    'AND RDB$FIELDS.RDB$COMPUTED_BLR IS NULL';
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Colonne: TDictionary<string, Boolean>;
  DaTogliere: TList<string>;
  Pair: TJSONPair;
  NomeCampo: string;
begin
  if not Assigned(RecordData) or DatasetConfig.TableName.Trim.IsEmpty then
    Exit;

  Colonne := TDictionary<string, Boolean>.Create;
  DaTogliere := TList<string>.Create;
  try
    Parametri := TParamValues.Create;
    try
      Parametri.Add('RELAZIONE', DatasetConfig.TableName.Trim.ToUpper);
      Righe := TDataService.ExecuteQuery(SQL_COLONNE, Parametri, False);
    finally
      FreeAndNil(Parametri);
    end;

    try
      for Riga in Righe do
        if Riga is TJSONObject then
          Colonne.AddOrSetValue(TJSONObject(Riga).GetValue<string>('CAMPO', '').ToUpper, True);
    finally
      FreeAndNil(Righe);
    end;

    if Colonne.Count = 0 then
      Exit;

    for Pair in RecordData do
    begin
      NomeCampo := Pair.JsonString.Value;
      if not Colonne.ContainsKey(NomeCampo.ToUpper) then
        DaTogliere.Add(NomeCampo);
    end;

    for NomeCampo in DaTogliere do
      RecordData.RemovePair(NomeCampo).Free;

    if DaTogliere.Count > 0 then
      Registro.Debug(Format('Dataset %s: campi non della tabella %s tolti dal corpo: %s', [DatasetConfig.DatasetId, DatasetConfig.TableName, string.Join(', ', DaTogliere.ToArray)]), 'DynamicDatasetController');
  finally
    FreeAndNil(DaTogliere);
    FreeAndNil(Colonne);
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Z4 - Segnaposto di sessione nella SQL del dataset

  Prima venivano legati come parametri solo i filtri DevExtreme: nessuna SQL
  registrata in BASE_WEB_DATASETS poteva sapere chi stava chiedendo i dati e
  per quale comune, e i parametri aggiuntivi accodati all'indirizzo dal front
  end venivano ignorati.

  Il comune e l'azienda arrivano dal browser e vengono verificati contro il
  perimetro dell'utente prima di essere usati. Il perimetro vero resta quello
  del database (USR_TMP_COMUNI): questi segnaposto servono a dire quale
  comune si sta guardando adesso, non a decidere cosa si puo' vedere.
  ────────────────────────────────────────────────────────────────────────────── }

function TDynamicDatasetController.RisolviSegnapostoDiSessione(const SQL: string; Helper: TDevExtremeHelper): string;
var
  Belfiore: string;
  IdAzienda: Int64;
begin
  Result := SQL;

  if Result.Contains(SEGNAPOSTO_USER_ID) then
  begin
    Result := Result.Replace(SEGNAPOSTO_USER_ID, ':' + PARAMETRO_USER_ID, [rfReplaceAll, rfIgnoreCase]);
    Helper.Params.AddOrSetValue(PARAMETRO_USER_ID, UserId);
  end;

  if Result.Contains(SEGNAPOSTO_ID_SESSIONE) then
  begin
    Result := Result.Replace(SEGNAPOSTO_ID_SESSIONE, ':' + PARAMETRO_ID_SESSIONE, [rfReplaceAll, rfIgnoreCase]);
    Helper.Params.AddOrSetValue(PARAMETRO_ID_SESSIONE, IdSessione);
  end;

  if not(Result.Contains(SEGNAPOSTO_BELFIORE) or Result.Contains(SEGNAPOSTO_ID_AZIENDA)) then
    Exit;

  Belfiore := ParamByName('belfiore');
  IdAzienda := ParamInt64('idAzienda');

  if not TAppProfiles.Corrente.AmbitoAmmesso(Belfiore, IdAzienda) then
  begin
    Registro.Warn(Format('Ambito non ammesso per utente %d: comune %s, azienda %d', [UserId, Belfiore, IdAzienda]), 'DynamicDatasetController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Comune o azienda di lavoro non fra quelli abilitati.');
  end;

  TSessionContextManager.ImpostaAmbito(Belfiore, IdAzienda);

  if Result.Contains(SEGNAPOSTO_BELFIORE) then
  begin
    Result := Result.Replace(SEGNAPOSTO_BELFIORE, ':' + PARAMETRO_BELFIORE, [rfReplaceAll, rfIgnoreCase]);

    if Belfiore.Trim.IsEmpty then
      Helper.Params.AddOrSetValue(PARAMETRO_BELFIORE, System.Variants.Null)
    else
      Helper.Params.AddOrSetValue(PARAMETRO_BELFIORE, Belfiore);
  end;

  if Result.Contains(SEGNAPOSTO_ID_AZIENDA) then
  begin
    Result := Result.Replace(SEGNAPOSTO_ID_AZIENDA, ':' + PARAMETRO_ID_AZIENDA, [rfReplaceAll, rfIgnoreCase]);

    if IdAzienda > 0 then
      Helper.Params.AddOrSetValue(PARAMETRO_ID_AZIENDA, IdAzienda)
    else
      Helper.Params.AddOrSetValue(PARAMETRO_ID_AZIENDA, System.Variants.Null);
  end;
end;

// Insert, update e delete eseguono con i Params costruiti da Build*SQL, non
// con Helper.Params: senza questa copia i segnaposto di sessione risolti da
// RisolviSegnapostoDiSessione (:##USER_ID, :##ID_SESSIONE...) arrivavano nulli
// a una SQL_INSERT, SQL_UPDATE o SQL_DELETE che li usa.
procedure TDynamicDatasetController.UnisciParametriDiSessione(Helper: TDevExtremeHelper; Params: TParamValues);
var
  Parametro: TPair<string, Variant>;
begin
  for Parametro in Helper.Params do
    Params.AddOrSetValue(Parametro.Key, Parametro.Value);
end;

// SQL del dataset pronta all'uso: segnaposto risolti e clausola di perimetro
// del prodotto aggiunta. Su Gesty la clausola e' vuota e non cambia niente.
// ──────────────────────────────────────────────────────────────────────────────
// Parametri propri del dataset
//
// Una SQL registrata puo' avere parametri suoi (Risorsa.Agenda: :DAL_GIORNO,
// :AL_GIORNO, :MOSTRA_*; Risorsa.Incarichi_PIP: :ID_INCARICO). Il front end li
// manda come parametri dell'indirizzo (extraParams di createDataStore, evento
// beforeLoad di zz-data-grid), ma finora nessuno li legava e arrivavano nulli.
//
// Si legano solo i nomi che compaiono come :NOME nella SQL e che la richiesta
// porta con un valore non vuoto. Restano esclusi i parametri di contesto
// (CTX_*), quelli dei filtri DevExtreme (P1, P2...) e i riservati: chi chiede i
// dati lo dice il contesto della connessione, non il browser. Il valore arriva
// come testo e TDataService lo converte nel tipo del parametro dopo il Prepare.
// ──────────────────────────────────────────────────────────────────────────────

procedure TDynamicDatasetController.LegaParametriDellaRichiesta(const SQL: string; Helper: TDevExtremeHelper);
var
  Corrispondenza: TMatch;
  Nome: string;
  Valore: string;
begin
  // ":" non preceduto da lettere, cifre o altri ":" e seguito da un nome:
  // esclude gli orari ('10:30'), che hanno una cifra dopo i due punti
  for Corrispondenza in TRegEx.Matches(SQL, '(?<![\w:]):([A-Za-z_][A-Za-z0-9_$]*)') do
  begin
    Nome := UpperCase(Corrispondenza.Groups[1].Value);

    if Nome.StartsWith('CTX_') or TRegEx.IsMatch(Nome, '^P\d+$') then
      Continue;

    if MatchText(Nome, PARAMETRI_RISERVATI) then
      Continue;

    Valore := ParamByName(Nome);
    if not Valore.IsEmpty then
      Helper.Params.AddOrSetValue(Nome, Valore);
  end;
end;

function TDynamicDatasetController.SqlDelDataset(const DatasetConfig: TDatasetConfig; const SQL: string; Helper: TDevExtremeHelper): string;
var
  Perimetro: string;
begin
  Result := RisolviSegnapostoDiSessione(SQL, Helper);

  LegaParametriDellaRichiesta(Result, Helper);

  Perimetro := TAppProfiles.Corrente.ClausolaPerimetro(DatasetConfig.TableName);

  if not Perimetro.Trim.IsEmpty then
    Result := fib.SqlTxtRtns.AddToWhereClause(Result, Perimetro, true);
end;

function TDynamicDatasetController.GetTotalCount(const BaseSQL: string; Helper: TDevExtremeHelper): Integer;
var
  CountSQL: string;
begin
  CountSQL := fib.SqlTxtRtns.CountSelect(BaseSQL);
  Result := TDataService.ExecuteScalar(CountSQL, Helper.Params);
end;

function TDynamicDatasetController.BuildSQL(const BaseSQL: string; LoadOptions: TDevExtremeLoadOptions; Helper: TDevExtremeHelper; const ApplySort: boolean = true; const ForcedPagination: string = ''): string;
var
  WhereClause: string;
begin
  Result := BaseSQL;

  // 1. Filtri DevExtreme (parametrici, :P1 :P2 ...)
  if not LoadOptions.filter.IsEmpty then
    Result := fib.SqlTxtRtns.AddToWhereClause(Result, LoadOptions.filter, true);

  // 2. Filtro search (lookup/selectBox)
  if (not LoadOptions.SearchExpr.IsEmpty) and (not LoadOptions.SearchValue.IsEmpty) then
  begin
    WhereClause := Helper.BuildSearchClause(LoadOptions.SearchExpr, LoadOptions.SearchOperation, LoadOptions.SearchValue);
    Result := fib.SqlTxtRtns.AddToWhereClause(Result, WhereClause, true);
  end;

  // 3. Ordinamento
  if not LoadOptions.Sort.IsEmpty then
    if ApplySort then
      Result := fib.SqlTxtRtns.SetOrderClause(Result, LoadOptions.Sort);

  // 4. Paginazione: ForcedPagination ha priorità (es. 'ROWS 1 TO 100' per lookup),
  // altrimenti usa quella dinamica delle LoadOptions
  if not ForcedPagination.IsEmpty then
    Result := Result + sLineBreak + ForcedPagination
  else
    if not LoadOptions.Pagination.IsEmpty then
      Result := Result + sLineBreak + LoadOptions.Pagination;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  GET /api/data/:idDataset
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.GetData(idDataset: string);
var
  CountBase: string;
  DatasetConfig: TDatasetConfig;
  LoadOptions: TDevExtremeLoadOptions;
  SQL: string;
  SelectBase: string;
  FieldNames: string;
  Data: TJSONArray;
  TotalCount: Integer;
  Response: TDevExtremeDataResponse;
  ResponseObj: TJSONObject;
  Helper: TDevExtremeHelper;
  Cronometro: TStopwatch;
begin
  Helper := TDevExtremeHelper.Create;
  try
    try
      Cronometro := TStopwatch.StartNew;
      Registro.Info(Format('GetData - dataset: %s', [idDataset]), 'DynamicDatasetController');

      Response.Init;

      // 1. Configurazione dataset
      DatasetConfig := GetDatasetConfig(idDataset);

      // 2. Autorizzazione dichiarata dal dataset (Z6)
      VerificaAutorizzazione(DatasetConfig, False);

      // 3. Segnaposto di sessione e perimetro del prodotto (Z4)
      Registro.Debug(Format('Tempi %s - configurazione e autorizzazione: %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');
      SelectBase := SqlDelDataset(DatasetConfig, DatasetConfig.SelectSQL, Helper);
      Registro.Debug(Format('Tempi %s - SqlDelDataset (segnaposto e perimetro): %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');

      // 4. Estrai nomi campi dalla SELECT per popolare la whitelist dell'helper
      // 2026-11-06: i nomi si leggono dal testo della SELECT; ogni lettura dal database
      // (Query.GetFieldNames e FieldDefs.Update) esegue la SELECT intera non filtrata
      // (Cdr.Anagrafiche: 3,9 s). Il database resta il ripiego quando il testo non basta.
      FieldNames := TDevExtremeHelper.NomiCampiDallaSelect(SelectBase);
      if FieldNames.IsEmpty then
        FieldNames := TDataService.GetFieldNames(SelectBase);
      Registro.Debug(Format('Tempi %s - GetFieldNames: %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');

      // 4b. Espressioni dei campi: filtri e ricerche le usano al posto del nome
      // nudo, ambiguo quando la SELECT unisce tabelle con colonne omonime
      Helper.ImpostaSqlDelDataset(SelectBase);
      Registro.Debug(Format('Tempi %s - ImpostaSqlDelDataset: %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');

      // 5. Parsa le LoadOptions DevExtreme
      LoadOptions := Helper.ParseLoadOptions(Context.Request, FieldNames);

      Registro.Debug(Format('LoadOptions - Skip:%d Take:%d Filter:[%s] Sort:[%s]', [LoadOptions.Skip, LoadOptions.Take, LoadOptions.filter, LoadOptions.Sort]), 'DynamicDatasetController');

      // 6. Componi SQL dati (filtri + sort + paginazione)
      SQL := BuildSQL(SelectBase, LoadOptions, Helper);
      Registro.Debug(Format('Tempi %s - ParseLoadOptions e BuildSQL: %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');

      // 7. Conteggio totale (prima di aggiungere ORDER BY e ROWS)
      if LoadOptions.RequireTotalCount then
      begin
        if not DatasetConfig.CountSQL.IsEmpty then
          CountBase := BuildSQL(SqlDelDataset(DatasetConfig, DatasetConfig.CountSQL, Helper), LoadOptions, Helper, False)
        else
          CountBase := SQL; // SQL è già filtrato — CountSelect ignora ORDER BY e ROWS

        TotalCount := GetTotalCount(CountBase, Helper);
      end
      else
        TotalCount := -1;

      // Ordinamento e paginazione sono gia' stati aggiunti da BuildSQL:
      // riaggiungerli dava due ROWS di fila quando arriva solo take senza
      // ordinamento (errore 400 «Token unknown ... ROWS»)
      Registro.Debug('SQL finale: ' + SQL, 'DynamicDatasetController');

      // 8. Esecuzione con parametri bindati
      Data := TDataService.ExecuteQuery(SQL, Helper.Params);
      Registro.Debug(Format('Tempi %s - conteggio e query dei dati: %d ms', [idDataset, Cronometro.ElapsedMilliseconds]), 'DynamicDatasetController');

      // 9. Raggruppamento in-memory (se richiesto)
      if not LoadOptions.Group.IsEmpty then
      begin
        Response := Helper.ProcessGrouping(Data, LoadOptions);
        Data.Free; // ProcessGrouping ha clonato i dati, liberiamo l'array originale
        Registro.Info(Format('GetData - %d gruppi', [Response.GroupCount]), 'DynamicDatasetController');
      end
      else
      begin
        Response.Data := Data;
        Response.TotalCount := TotalCount;
        Registro.Info(Format('GetData - %d record', [Data.Count]), 'DynamicDatasetController');
      end;

      // 10. Risposta DevExtreme
      Context.Response.CustomHeaders.Values['X-Total-Count'] := Response.TotalCount.ToString;

      ResponseObj := Helper.CreateDevExtremeResponse(Response);
      try
        RenderTestoJson(HTTP_STATUS.OK, ResponseObj);
      finally
        ResponseObj.Free;
      end;

      Response.Done;

    except
      on E: Exception do
      begin
        Registro.Error(Format('GetData - Errore dataset %s: %s', [idDataset, E.Message]), 'DynamicDatasetController');
        raise;
      end;
    end;
  finally
    Helper.Free;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  POST /api/data/:idDataset
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.InsertData(idDataset: string);
var
  DatasetConfig: TDatasetConfig;
  RecordData: TJSONObject;
  ResultData: TJSONObject;
  SQL: string;
  Params: TParamValues;
  Helper: TDevExtremeHelper;
begin
  Helper := TDevExtremeHelper.Create;
  try
    try
      Registro.Info(Format('InsertData - dataset: %s', [idDataset]), 'DynamicDatasetController');

      DatasetConfig := GetDatasetConfig(idDataset);
      VerificaAutorizzazione(DatasetConfig, True);

      if not DatasetConfig.AllowInsert then
        raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Inserimento non consentito per questo dataset');

      RecordData := Helper.BodyAsJSONObject(Context.Request.Body);

      VerificaAmbitoDelCorpo(DatasetConfig, RecordData, True);

      if DatasetConfig.InsertSQL.Trim.IsEmpty then
        TogliCampiFuoriTabella(DatasetConfig, RecordData);

      Helper.BuildInsertSQL(DatasetConfig, RecordData, SQL, Params);
      try
        SQL := RisolviSegnapostoDiSessione(SQL, Helper);
        UnisciParametriDiSessione(Helper, Params);

        Registro.Debug(Format('SQL Insert: %s | Params: %d', [SQL, Params.Count]), 'DynamicDatasetController');

        ResultData := TDataService.ExecuteInsert(SQL, Params);
        try
          Registro.Info('InsertData - Record inserito', 'DynamicDatasetController');
          Context.Response.CustomHeaders.Values['Location'] := Format('/api/data/%s', [idDataset]);
          RenderTestoJson(HTTP_STATUS.Created, ResultData);
        finally
          FreeAndNil(ResultData);
        end;
      finally
        FreeAndNil(Params);
      end;

    except
      on E: Exception do
      begin
        Registro.Error(Format('InsertData - Errore: %s', [E.Message]), 'DynamicDatasetController');
        raise;
      end;
    end;
  finally
    Helper.Free;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  PUT /api/data/:idDataset/:key
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.UpdateData(idDataset: string; key: string);
var
  DatasetConfig: TDatasetConfig;
  RecordData: TJSONObject;
  ResultData: TJSONObject;
  SQL: string;
  Params: TParamValues;
  Helper: TDevExtremeHelper;
begin
  Helper := TDevExtremeHelper.Create;
  try
    try
      Registro.Info(Format('UpdateData - dataset: %s, key: %s', [idDataset, key]), 'DynamicDatasetController');

      DatasetConfig := GetDatasetConfig(idDataset);
      VerificaAutorizzazione(DatasetConfig, True);

      if not DatasetConfig.AllowUpdate then
        raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Aggiornamento non consentito per questo dataset');

      RecordData := Helper.BodyAsJSONObject(Context.Request.Body);

      // La riga deve stare nel perimetro prima della modifica, e non puo'
      // essere spostata in un comune o in un'azienda non abilitati.
      VerificaChiaveNelPerimetro(DatasetConfig, key);
      VerificaAmbitoDelCorpo(DatasetConfig, RecordData, False);

      if DatasetConfig.UpdateSQL.Trim.IsEmpty then
        TogliCampiFuoriTabella(DatasetConfig, RecordData);

      Helper.BuildUpdateSQL(DatasetConfig, RecordData, key, SQL, Params);
      try
        SQL := RisolviSegnapostoDiSessione(SQL, Helper);
        UnisciParametriDiSessione(Helper, Params);

        Registro.Debug(Format('SQL Update: %s | Params: %d', [SQL, Params.Count]), 'DynamicDatasetController');

        ResultData := TDataService.ExecuteUpdate(SQL, Params);
        try
          Registro.Info('UpdateData - Record aggiornato', 'DynamicDatasetController');
          Context.Response.CustomHeaders.Values['Location'] := Format('/api/data/%s', [idDataset]);
          RenderTestoJson(HTTP_STATUS.OK, ResultData);
        finally
          FreeAndNil(ResultData);
        end;
      finally
        FreeAndNil(Params);
      end;

    except
      on E: Exception do
      begin
        Registro.Error(Format('UpdateData - Errore: %s', [E.Message]), 'DynamicDatasetController');
        raise;
      end;
    end;
  finally
    Helper.Free;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  DELETE /api/data/:idDataset/:key
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.DeleteData(idDataset: string; key: string);
var
  DatasetConfig: TDatasetConfig;
  SQL: string;
  Params: TParamValues;
  ResultData: TJSONObject;
  Helper: TDevExtremeHelper;
begin
  Helper := TDevExtremeHelper.Create;
  try
    try
      Registro.Info(Format('DeleteData - dataset: %s, key: %s', [idDataset, key]), 'DynamicDatasetController');

      DatasetConfig := GetDatasetConfig(idDataset);
      VerificaAutorizzazione(DatasetConfig, True);

      if not DatasetConfig.AllowDelete then
        raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Eliminazione non consentita per questo dataset');

      VerificaChiaveNelPerimetro(DatasetConfig, key);

      Helper.BuildDeleteSQL(DatasetConfig, key, SQL, Params);
      try
        SQL := RisolviSegnapostoDiSessione(SQL, Helper);
        UnisciParametriDiSessione(Helper, Params);

        Registro.Debug(Format('SQL Delete: %s | Params: %d', [SQL, Params.Count]), 'DynamicDatasetController');

        ResultData := TDataService.ExecuteDelete(SQL, Params);
        try
          Registro.Info('DeleteData - Record eliminato', 'DynamicDatasetController');
          Render(HTTP_STATUS.NoContent);
        finally
          FreeAndNil(ResultData);
        end;
      finally
        FreeAndNil(Params);
      end;

    except
      on E: Exception do
      begin
        Registro.Error(Format('DeleteData - Errore: %s', [E.Message]), 'DynamicDatasetController');
        raise;
      end;
    end;
  finally
    Helper.Free;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  POST /api/data/sp/:procName
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.ExecuteStoredProcedure(procName: string);
var
  RequestData: TJSONObject;
  ProcParams: TParamValues;
  ResultData: TJSONObject;
  Helper: TDevExtremeHelper;
  Parametro: TPair<string, Variant>;
begin
  Helper := TDevExtremeHelper.Create;
  try
    try
      Registro.Info(Format('ExecuteStoredProcedure - proc: %s', [procName]), 'DynamicDatasetController');

      // R-123: prima l'elenco e l'autorizzazione, poi il corpo della richiesta
      procName := ProceduraEsposta(procName);

      // Il corpo e' di chi lo legge: prima non veniva mai liberato
      RequestData := Helper.BodyAsJSONObject(Context.Request.Body);
      try
        ProcParams := Helper.ParseStoredProcParams(RequestData);
      finally
        FreeAndNil(RequestData);
      end;

      try
        // ZC 03.11.2026: chi chiede lo dice il token, non il corpo. Un
        // parametro riservato nel corpo e' un tentativo di parlare a nome di
        // un'altra sessione: si rifiuta e si annota. Sessione e utente della
        // procedura (se li dichiara) arrivano dal token, come nei dataset.
        for Parametro in ProcParams do
          if MatchText(Parametro.Key, PARAMETRI_RISERVATI) and
            not (SameText(Parametro.Key, 'ID_INTESTATARIO') and MatchText(procName, PROCEDURE_CON_INTESTATARIO_SCELTO)) then
          begin
            Registro.Warn(Format('Procedura %s: parametro riservato %s nel corpo, rifiutato a utente %d', [procName, Parametro.Key, UserId]), 'DynamicDatasetController');
            raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il parametro %s non si puo'' indicare nella richiesta.', [Parametro.Key]));
          end;

        ProcParams.AddOrSetValue('ID_SESSIONE', IdSessione);
        ProcParams.AddOrSetValue('ID_SESSIONE_WEB', IdSessione);
        ProcParams.AddOrSetValue('USER_ID', UserId);

        Registro.Debug(Format('Parametri proc: %d input', [ProcParams.Count]), 'DynamicDatasetController');
        ResultData := TDataService.ExecuteStoredProc(procName, ProcParams);
      finally
        FreeAndNil(ProcParams);
      end;

      Registro.Info(Format('ExecuteStoredProcedure - proc %s eseguita', [procName]), 'DynamicDatasetController');

      RenderJson(ResultData);

    except
      on E: Exception do
      begin
        Registro.Error(Format('ExecuteStoredProcedure - Errore proc %s: %s', [procName, E.Message]), 'DynamicDatasetController');
        raise;
      end;
    end;
  finally
    Helper.Free;
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  GET /api/data/:datasetId/metadata
  ────────────────────────────────────────────────────────────────────────────── }

procedure TDynamicDatasetController.GetMetadata(const idDataset: string);
const
  // ZC 30.10.2026: SQL del dataset prodotte da LOAD_DATASET_METADATA, che non
  // escono dal server (vedi sotto).
  CAMPI_SQL: array [0 .. 4] of string = ('sqlSelect', 'sqlCount', 'sqlInsert', 'sqlUpdate', 'sqlDelete');
var
  Params: TParamValues;
  Row: TJSONObject;
  JsonStr: string;
  JsonObj: TJSONObject;
  DatasetConfig: TDatasetConfig;
  CampoSql: string;
begin
  if idDataset.Trim.IsEmpty then
  begin
    Render(HTTP_STATUS.BadRequest, 'datasetId obbligatorio');
    Exit;
  end;

  // ZC 30.10.2026 - R-177, DIV-DSD-10: prima questa rotta non verificava il
  // codice AUTHORIZATION del dataset, che le rotte dei dati verificano (Z6):
  // un utente autenticato senza il permesso non leggeva le righe ma leggeva
  // struttura, campi e SQL complete di qualunque dataset registrato. Ora la
  // configurazione e la verifica sono le stesse di GetData: dataset sconosciuto
  // 404, permesso mancante 403, entrambi con il corpo JSON di TBaseController.
  DatasetConfig := GetDatasetConfig(idDataset);
  VerificaAutorizzazione(DatasetConfig, False);

  Params := TParamValues.Create;
  try
    Params.Add('DS', idDataset);
    Row := TDataService.ExecuteQuerySingleRow('SELECT JSON_RESULT FROM BASE_WEB.LOAD_DATASET_METADATA(:DS)', Params, False);
  finally
    Params.Free;
  end;

  if Row = nil then
  begin
    Render(HTTP_STATUS.NotFound, 'Dataset non trovato: ' + idDataset);
    Exit;
  end;

  try
    JsonStr := Row.GetValue<string>('JSON_RESULT', '');
    if JsonStr.IsEmpty then
    begin
      Render(HTTP_STATUS.NotFound, 'Nessun metadata per dataset: ' + idDataset);
      Exit;
    end;

    try
      JsonObj := TJSONObject.ParseJSONValue(JsonStr, true, true) as TJSONObject;
      if JsonObj = nil then
      begin
        Registro.Error('JSON metadata non valido per dataset ' + idDataset, 'DynamicDatasetController');
        Render(HTTP_STATUS.InternalServerError, 'JSON metadata non valido');
        Exit;
      end;
    except
      on E: Exception do
      begin
        Registro.Error(Format('JSON metadata non valido per dataset %s: %s', [idDataset, E.Message]), 'DynamicDatasetController');
        Render(HTTP_STATUS.InternalServerError, 'JSON metadata non valido');
        Exit;
      end;
    end;

    // ZC 30.10.2026 - R-177, DIV-DSD-10: le SQL del dataset uscivano anche
    // verso gli utenti autorizzati, ma nessun client le usa (zNg costruisce
    // griglia e scheda dai campi e chiama le rotte dei dati, che leggono le SQL
    // da BASE_WEB_DATASETS). Si tolgono prima di rispondere; l'editor dei
    // metadati le legge dalle sue rotte /api/meta.
    for CampoSql in CAMPI_SQL do
      JsonObj.RemovePair(CampoSql).Free;

    RenderJson(JsonObj);
  finally
    Row.Free;
  end;
end;

end.
