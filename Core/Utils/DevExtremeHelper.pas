unit DevExtremeHelper;

{
  DevExtreme.Helper - Unit unificata per integrazione DevExtreme CustomStore con backend Firebird/DMVC
  =====================================================================================================

  Principi architetturali
  ───────────────────────
  • TDevExtremeHelper è una CLASS con stato (parametri bindati, whitelist campi).
  • NESSUN valore viene mai interpolato inline nell'SQL: tutti i valori dinamici
  (filter, insert, update, delete, key) diventano parametri FireDAC (:nome).
  Questo elimina il rischio di SQL injection e delega il type-handling a FireDAC.
  • La whitelist dei campi è opzionale: se vuota si usa solo la sanitizzazione
  sintattica (caratteri alfanumerici + _).
  • La paginazione usa la sintassi Firebird nativa: ROWS <start> TO <end>.

  Conversione tipi JSON → Variant (JSONValueToVariant)
  ─────────────────────────────────────────────────────
  TJSONNull    → Null (Variant)        → FireDAC: NULL
  TJSONBool    → Boolean Variant       → FireDAC: ftBoolean
  TJSONNumber  → Integer o Double      → FireDAC: ftInteger / ftFloat
  TJSONString  → se data ISO 8601 estesa (AAAA-MM-GG[THH:MM...]) → TDateTime Variant → FireDAC: ftDateTime
  → altrimenti → string Variant    → FireDAC: ftString

  Pattern DML nel Controller
  ──────────────────────────
  // GET (filter parametrico)
  LoadOptions := Helper.ParseLoadOptions(Request, FieldNames);
  SQL := fib.SqlTxtRtns.AddToWhereClause(BaseSQL, LoadOptions.Filter, True);
  Data := TDataService.ExecuteQuery(SQL, Helper.Params);

  // INSERT
  Helper.BuildInsertSQL(DatasetConfig, RecordData, SQL, Params);
  Result := TDataService.ExecuteInsert(SQL, Params);
  Params.Free;

  // UPDATE
  Helper.BuildUpdateSQL(DatasetConfig, RecordData, KeyValue, SQL, Params);
  Result := TDataService.ExecuteUpdate(SQL, Params);
  Params.Free;

  // DELETE
  Helper.BuildDeleteSQL(DatasetConfig, KeyValue, SQL, Params);
  Result := TDataService.ExecuteDelete(SQL, Params);
  Params.Free;
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Web.HTTPApp,
  MVCFramework,
  Data.Service;

type
  // ──────────────────────────────────────────────────────────────────────────
  // Record di trasporto delle LoadOptions già parsate e pronte per l'SQL
  // ──────────────────────────────────────────────────────────────────────────
  TDevExtremeLoadOptions = record
    Skip: Integer;
    Take: Integer;
    RequireTotalCount: Boolean;
    RequireGroupCount: Boolean;
    /// <summary>Clausola WHERE già pronta (senza la keyword WHERE), con parametri :P1, :P2 ...</summary>
    Filter: string;
    /// <summary> parametri opzionali usati dai lookup
    SearchExpr: string;
    SearchOperation: string;
    SearchValue: string;
    /// <summary>Clausola ORDER BY già pronta (senza la keyword ORDER BY)</summary>
    Sort: string;
    Group: string;
    Select: string;
    /// <summary>Clausola ROWS x TO y per Firebird</summary>
    Pagination: string;
    procedure Init;
  end;

  // ──────────────────────────────────────────────────────────────────────────
  // Record di trasporto della risposta DevExtreme
  // ──────────────────────────────────────────────────────────────────────────
  TDevExtremeDataResponse = record
    Data: TJSONArray;
    TotalCount: Integer;
    GroupCount: Integer;
    Summary: TJSONArray;
    procedure Init;
    /// <summary>Libera Data e Summary. Chiamare dopo aver serializzato la risposta.</summary>
    procedure Done;
  end;

  // ──────────────────────────────────────────────────────────────────────────
  // Helper principale - classe con stato
  // ──────────────────────────────────────────────────────────────────────────
  TDevExtremeHelper = class
  private
    procedure LogRequest(const title: String; const Request: TMVCWebRequest);
  private
    FWhiteList: TStringList;
    FParams: TParamValues;
    FParamCounter: Integer;
    // Colonna del dataset -> espressione che la produce nella SELECT
    // (AGORA_ZZ_TIPOLOGIE_CAMPI.TIPOLOGIA_TICKET, COALESCE(...)): vedi
    // ImpostaSqlDelDataset
    FEspressioniCampi: TDictionary<string, string>;

    // ── Sanitizzazione e validazione ──
    function SanitizeIdentifier(const AIdentifier: string): string;
    function EspressioneDelCampo(const Campo: string): string;
    function IsFieldAllowed(const AFieldName: string): Boolean;
    function QuoteSQLIdentifier(const Identifier: string): string;

    // ── Conversione TJSONValue → Variant tipizzato per FireDAC ──
    /// <summary>
    /// Converte un TJSONValue nel Variant con il tipo Delphi più appropriato,
    /// così ApplyParams di TDataService può inferire il tipo FireDAC corretto.
    /// TJSONNull   → Null variant   (FireDAC NULL)
    /// TJSONBool   → Boolean        (ftBoolean)
    /// TJSONNumber → Int64 o Double (ftLargeint / ftFloat)
    /// TJSONString → TDateTime se ISO8601, altrimenti string
    /// </summary>
    function JSONValueToVariant(const Value: TJSONValue): Variant;

    // ── Parsing interno ──
    function InternalParseFilter(const FilterJson: string): string;
    function ProcessFilterArray(AFilterArray: TJSONArray): string;
    function MapOperator(const ADevExOp: string): string;
    function InternalParseSort(const SortJson: string): string;
    function BuildPaginationFirebird(Skip, Take: Integer): string;

    // ── Costruzione parametri DML da JSON body ──
    /// <summary>
    /// Converte un TJSONObject (body della request) in un TParamValues
    /// con Variant tipizzati. Il chiamante è owner del dizionario restituito.
    /// </summary>
    function JSONObjectToParams(const RecordData: TJSONObject): TParamValues;
  public
    constructor Create;
    destructor Destroy; override;

    // ── Whitelist campi (opzionale) ──
    /// <summary>
    /// Imposta la whitelist dei campi ammessi nel filter/sort.
    /// Se vuota viene usata solo la sanitizzazione sintattica.
    /// Tipicamente popolata con i FieldNames della SelectSQL di configurazione.
    /// </summary>
    procedure SetWhiteList(const FieldNamesCsv: string); overload;
    procedure SetWhiteList(const AList: TStringList); overload;

    /// <summary>
    /// Legge la lista dei campi della SELECT del dataset e ricorda, per ogni
    /// colonna, l'espressione che la produce. Filtri e ricerche usano poi
    /// quell'espressione al posto del nome nudo: con una join fra tabelle
    /// che hanno colonne omonime il nome nudo nel WHERE e' ambiguo (SQL -204),
    /// e un alias di colonna nel WHERE non e' ammesso. Da chiamare prima di
    /// ParseLoadOptions; senza chiamata resta il comportamento di prima.
    /// </summary>
    procedure ImpostaSqlDelDataset(const SelectSQL: string);

    /// <summary>
    /// Nomi delle colonne della SELECT (uno per riga), letti dal testo senza passare dal
    /// database. Stringa vuota se il testo non basta (SELECT *, T.*, colonna calcolata senza
    /// alias, FIRST/SKIP): chi chiama ripiega allora sulla lettura dal database.
    /// Serve perche' ogni lettura dal database (Query.GetFieldNames e FieldDefs.Update)
    /// esegue la SELECT intera non filtrata: Cdr.Anagrafiche 3,9 s.
    /// </summary>
    class function NomiCampiDallaSelect(const SelectSQL: string): string; static;

    // ── Parsing LoadOptions (GET) ──
    /// <summary>
    /// Parsa i parametri DevExtreme dalla query string della request DMVC.
    /// Dopo la chiamata, i parametri bindati del filter sono in Self.Params.
    /// Passare Self.Params a TDataService.ExecuteQuery(SQL, Helper.Params).
    /// NON liberare Self.Params: è owned dall'helper.
    /// </summary>
    function ParseLoadOptions(const Request: TMVCWebRequest; const FieldNamesCsv: string = ''): TDevExtremeLoadOptions;

    // ── Lookup ──
    function BuildSearchClause(const SearchExpr, SearchOperation, SearchValue: string): string;

    // ── Raggruppamento in-memory ──
    function ProcessGrouping(const Data: TJSONArray; const LoadOptions: TDevExtremeLoadOptions): TDevExtremeDataResponse;

    // ── DML parametrico (INSERT / UPDATE / DELETE) ──
    //
    // Tutti e tre i metodi producono:
    // OutSQL    → SQL con placeholder :nomecampo (mai valori inline)
    // OutParams → TParamValues con Variant tipizzati (caller è owner → liberare dopo l'uso)
    //
    // Se DatasetConfig.InsertSQL/UpdateSQL/DeleteSQL è non vuoto, viene usato come
    // template (i placeholder devono già avere il nome del campo JSON, più :KEY per
    // update/delete). Altrimenti l'SQL viene generato automaticamente dalla TableName.

    /// <summary>
    /// Prepara SQL e parametri per INSERT.
    /// Template SQL: usa :nomecampo per ogni campo del body.
    /// SQL generato: INSERT INTO TableName ("f1","f2",...) VALUES (:f1,:f2,...)
    /// </summary>
    procedure BuildInsertSQL(const DatasetConfig: TDatasetConfig; const RecordData: TJSONObject; out OutSQL: string; out OutParams: TParamValues);

    /// <summary>
    /// Prepara SQL e parametri per UPDATE.
    /// Template SQL: usa :nomecampo + :KEY (placeholder chiave primaria).
    /// SQL generato: UPDATE TableName SET "f1"=:f1,... WHERE "PK"=:KEY
    /// Il valore di KeyValue viene aggiunto ai parametri come :KEY.
    /// </summary>
    procedure BuildUpdateSQL(const DatasetConfig: TDatasetConfig; const RecordData: TJSONObject; const KeyValue: string; out OutSQL: string; out OutParams: TParamValues);

    /// <summary>
    /// Prepara SQL e parametri per DELETE.
    /// Template SQL: deve contenere :KEY come placeholder della chiave.
    /// SQL generato: DELETE FROM TableName WHERE "PK"=:KEY
    /// OutParams conterrà solo {"KEY": KeyValue}.
    /// </summary>
    procedure BuildDeleteSQL(const DatasetConfig: TDatasetConfig; const KeyValue: string; out OutSQL: string; out OutParams: TParamValues);

    // ── Stored Procedure ──
    function ParseStoredProcParams(const RequestData: TJSONObject): TParamValues;

    // ── Utilità body ──
    function BodyAsJSONObject(const body: string): TJSONObject;

    // ── Costruzione risposta JSON DevExtreme ──
    function CreateDevExtremeResponse(const Response: TDevExtremeDataResponse): TJSONObject;

    /// <summary>Parametri bindati generati dall'ultimo ParseLoadOptions. Owned dall'helper.</summary>
    property Params: TParamValues read FParams;
  end;

implementation

uses
  System.StrUtils,
  System.Variants,
  System.DateUtils,
  System.Generics.Defaults,
  MVCFramework.Commons,
  MVCFramework.Logger,
  fib.SqlTxtRtns;

{ TDevExtremeLoadOptions }

procedure TDevExtremeLoadOptions.Init;
begin
  Skip := 0;
  Take := 0;
  RequireTotalCount := False;
  RequireGroupCount := False;
  Filter := '';
  SearchExpr := '';
  SearchOperation := '';
  SearchValue := '';
  Sort := '';
  Group := '';
  Select := '';
  Pagination := '';
end;

{ TDevExtremeDataResponse }

procedure TDevExtremeDataResponse.Init;
begin
  Data := nil;
  TotalCount := -1;
  GroupCount := -1;
  Summary := nil;
end;

procedure TDevExtremeDataResponse.Done;
begin
  FreeAndNil(Data);
  FreeAndNil(Summary);
end;

{ TDevExtremeHelper }

constructor TDevExtremeHelper.Create;
begin
  inherited;
  FWhiteList := TStringList.Create;
  FWhiteList.CaseSensitive := False;
  FParams := TParamValues.Create;
  FParamCounter := 0;
  FEspressioniCampi := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
end;

destructor TDevExtremeHelper.Destroy;
begin
  FWhiteList.Free;
  FParams.Free;
  FEspressioniCampi.Free;
  inherited;
end;

// ────────────────────────────────────────────────────────────────────────────
// Sanitizzazione e validazione
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.SanitizeIdentifier(const AIdentifier: string): string;
var
  C: Char;
begin
  Result := AIdentifier.Trim;
  if Result.IsEmpty then
    raise Exception.Create('Identificatore campo vuoto');
  for C in Result do
    if not CharInSet(C, ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) then
      raise Exception.CreateFmt('Identificatore non valido: "%s"', [Result]);
  if not IsFieldAllowed(Result) then
    raise Exception.CreateFmt('Campo non autorizzato: "%s"', [Result]);
end;

function TDevExtremeHelper.IsFieldAllowed(const AFieldName: string): Boolean;
begin
  // Se whitelist vuota: accetta qualsiasi nome sanitizzato
  if FWhiteList.Count = 0 then
    Exit(True);
  Result := FWhiteList.IndexOf(AFieldName) <> -1;
end;

function TDevExtremeHelper.QuoteSQLIdentifier(const Identifier: string): string;
begin
  // Doppi apici Firebird, escapa gli eventuali " interni
  Result := '"' + StringReplace(Identifier, '"', '""', [rfReplaceAll]) + '"';
end;

// ────────────────────────────────────────────────────────────────────────────
// Gestione whitelist
// ────────────────────────────────────────────────────────────────────────────

procedure TDevExtremeHelper.SetWhiteList(const FieldNamesCsv: string);
begin
  FWhiteList.Clear;
  if not FieldNamesCsv.IsEmpty then
    FWhiteList.CommaText := FieldNamesCsv;
end;

procedure TDevExtremeHelper.SetWhiteList(const AList: TStringList);
begin
  FWhiteList.Assign(AList);
end;

// ────────────────────────────────────────────────────────────────────────────
// Espressioni dei campi della SELECT
// ────────────────────────────────────────────────────────────────────────────

// Divide la lista dei campi sulle virgole di primo livello: quelle dentro
// parentesi, stringhe, identificatori fra doppi apici e commenti non contano.
function ElementiDellaLista(const ListaCampi: string): TArray<string>;
var
  Elementi: TList<string>;
  Inizio, Posizione, Profondita: Integer;
  Carattere: Char;
begin
  Elementi := TList<string>.Create;
  try
    Inizio := 1;
    Profondita := 0;
    Posizione := 1;
    while Posizione <= Length(ListaCampi) do
    begin
      Carattere := ListaCampi[Posizione];
      case Carattere of
        '''', '"':
          begin
            Inc(Posizione);
            while (Posizione <= Length(ListaCampi)) and (ListaCampi[Posizione] <> Carattere) do
              Inc(Posizione);
          end;
        '-':
          if (Posizione < Length(ListaCampi)) and (ListaCampi[Posizione + 1] = '-') then
            while (Posizione <= Length(ListaCampi)) and not CharInSet(ListaCampi[Posizione], [#10, #13]) do
              Inc(Posizione);
        '/':
          if (Posizione < Length(ListaCampi)) and (ListaCampi[Posizione + 1] = '*') then
          begin
            Inc(Posizione, 2);
            while (Posizione < Length(ListaCampi)) and not((ListaCampi[Posizione] = '*') and (ListaCampi[Posizione + 1] = '/')) do
              Inc(Posizione);
            Inc(Posizione);
          end;
        '(':
          Inc(Profondita);
        ')':
          Dec(Profondita);
        ',':
          if Profondita = 0 then
          begin
            Elementi.Add(Copy(ListaCampi, Inizio, Posizione - Inizio).Trim);
            Inizio := Posizione + 1;
          end;
      end;
      Inc(Posizione);
    end;
    Elementi.Add(Copy(ListaCampi, Inizio, MaxInt).Trim);
    Result := Elementi.ToArray;
  finally
    Elementi.Free;
  end;
end;

// Identificatore semplice (NOME_CAMPO) o fra doppi apici ("Nome")
function EIdentificatore(const Testo: string): Boolean;
var
  Carattere: Char;
begin
  if Testo.IsEmpty then
    Exit(False);

  if Testo.StartsWith('"') then
    Exit((Length(Testo) > 2) and Testo.EndsWith('"') and (Pos('"', Copy(Testo, 2, Length(Testo) - 2)) = 0));

  if not CharInSet(Testo[1], ['A' .. 'Z', 'a' .. 'z', '_']) then
    Exit(False);

  for Carattere in Testo do
    if not CharInSet(Carattere, ['A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '$']) then
      Exit(False);

  Result := True;
end;

function SenzaDoppiApici(const Testo: string): string;
begin
  if Testo.StartsWith('"') and Testo.EndsWith('"') then
    Result := Copy(Testo, 2, Length(Testo) - 2)
  else
    Result := UpperCase(Testo);
end;

// Ultimo spazio di primo livello: separa l'espressione dall'alias di colonna
function UltimoSpazioDiPrimoLivello(const Testo: string): Integer;
var
  Posizione, Profondita: Integer;
  Carattere: Char;
begin
  Result := 0;
  Profondita := 0;
  Posizione := 1;
  while Posizione <= Length(Testo) do
  begin
    Carattere := Testo[Posizione];
    case Carattere of
      '''', '"':
        begin
          Inc(Posizione);
          while (Posizione <= Length(Testo)) and (Testo[Posizione] <> Carattere) do
            Inc(Posizione);
        end;
      '(':
        Inc(Profondita);
      ')':
        Dec(Profondita);
      ' ', #9, #10, #13:
        if Profondita = 0 then
          Result := Posizione;
    end;
    Inc(Posizione);
  end;
end;

// Da un elemento della lista dei campi ricava il nome della colonna prodotta
// e l'espressione che la calcola:
//   T.CAMPO              -> CAMPO = T.CAMPO
//   T.CAMPO ALIAS        -> ALIAS = T.CAMPO
//   COALESCE(...) AS X   -> X     = COALESCE(...)
// Un campo senza tabella e senza alias non serve: il nome nudo e' gia' la
// sua espressione.
function SeparaColonna(const Elemento: string; out Nome, Espressione: string): Boolean;
const
  // Parole che chiudono un'espressione senza alias (CASE ... END, X IS NULL)
  NonAlias: array [0 .. 4] of string = ('END', 'NULL', 'TRUE', 'FALSE', 'UNKNOWN');
var
  Testo, Coda, Testa: string;
  Spazio, Punto: Integer;
begin
  Result := False;
  Nome := '';
  Espressione := '';

  Testo := Elemento.Trim;
  if Testo.IsEmpty or Testo.EndsWith('*') then
    Exit;

  Spazio := UltimoSpazioDiPrimoLivello(Testo);
  if Spazio > 0 then
  begin
    Coda := Copy(Testo, Spazio + 1, MaxInt).Trim;
    Testa := Copy(Testo, 1, Spazio - 1).TrimRight;

    if EIdentificatore(Coda) and not MatchText(Coda, NonAlias) and not Testa.IsEmpty and
      not CharInSet(Testa[Length(Testa)], ['+', '-', '*', '/', '|', '=', '<', '>', '(', ',']) then
    begin
      if EndsText(' AS', Testa) or EndsText(')AS', Testa) or SameText(Testa, 'AS') then
        Testa := Copy(Testa, 1, Length(Testa) - 2).TrimRight;
      if Testa.IsEmpty then
        Exit;

      Nome := SenzaDoppiApici(Coda);
      Espressione := Testa;
      Exit(True);
    end;
  end;

  // Senza alias: solo un campo qualificato TABELLA.CAMPO
  Punto := Testo.LastIndexOf('.') + 1;
  if (Punto > 1) and EIdentificatore(Copy(Testo, 1, Punto - 1)) and EIdentificatore(Copy(Testo, Punto + 1, MaxInt)) then
  begin
    Nome := SenzaDoppiApici(Copy(Testo, Punto + 1, MaxInt));
    Espressione := Testo;
    Result := True;
  end;
end;

procedure TDevExtremeHelper.ImpostaSqlDelDataset(const SelectSQL: string);
var
  Lista: string;
  Elemento, Nome, Espressione: string;
begin
  FEspressioniCampi.Clear;

  if SelectSQL.Trim.IsEmpty then
    Exit;

  Lista := fib.SqlTxtRtns.FieldsClause(SelectSQL).Trim;

  // SELECT DISTINCT / ALL: la parola non appartiene al primo campo
  if StartsText('DISTINCT', Lista) and (Length(Lista) > 8) and CharInSet(Lista[9], [' ', #9, #10, #13]) then
    Lista := Copy(Lista, 9, MaxInt).Trim
  else if StartsText('ALL', Lista) and (Length(Lista) > 3) and CharInSet(Lista[4], [' ', #9, #10, #13]) then
    Lista := Copy(Lista, 4, MaxInt).Trim;

  for Elemento in ElementiDellaLista(Lista) do
    if SeparaColonna(Elemento, Nome, Espressione) and not SameText(Nome, Espressione) then
      // Due colonne con lo stesso nome: si tiene la prima, come fa il dataset
      FEspressioniCampi.TryAdd(Nome, Espressione);
end;

class function TDevExtremeHelper.NomiCampiDallaSelect(const SelectSQL: string): string;
var
  Lista, Elemento, Nome, Espressione: string;
  Nomi: TStringList;
begin
  Result := '';

  if SelectSQL.Trim.IsEmpty then
    Exit;

  Lista := fib.SqlTxtRtns.FieldsClause(SelectSQL).Trim;
  if Lista.IsEmpty then
    Exit;

  // FIRST e SKIP, e DISTINCT/ALL: la parola non appartiene al primo campo
  if StartsText('FIRST ', Lista) or StartsText('SKIP ', Lista) then
    Exit;
  if StartsText('DISTINCT', Lista) and (Length(Lista) > 8) and CharInSet(Lista[9], [' ', #9, #10, #13]) then
    Lista := Copy(Lista, 9, MaxInt).Trim
  else if StartsText('ALL', Lista) and (Length(Lista) > 3) and CharInSet(Lista[4], [' ', #9, #10, #13]) then
    Lista := Copy(Lista, 4, MaxInt).Trim;

  Nomi := TStringList.Create;
  try
    for Elemento in ElementiDellaLista(Lista) do
    begin
      if SeparaColonna(Elemento, Nome, Espressione) then
        Nomi.Add(Nome)
      else if EIdentificatore(Elemento.Trim) then
        // colonna semplice senza tabella ne' alias
        Nomi.Add(SenzaDoppiApici(Elemento.Trim))
      else
        // non si capisce il nome (*, espressione senza alias): meglio chiedere al database
        Exit('');
    end;

    Result := Nomi.Text;
  finally
    Nomi.Free;
  end;
end;

function TDevExtremeHelper.EspressioneDelCampo(const Campo: string): string;
begin
  if not FEspressioniCampi.TryGetValue(Campo, Result) then
    Result := Campo;
end;

// ────────────────────────────────────────────────────────────────────────────
// Conversione TJSONValue → Variant tipizzato
// ────────────────────────────────────────────────────────────────────────────

// Data ISO 8601 in forma estesa: AAAA-MM-GG, da sola o seguita dall'ora
// (separata da T o da uno spazio). La validita' del valore la controlla poi
// TryISO8601ToDate.
function SembraDataIsoEstesa(const Testo: string): Boolean;
const
  PosizioniCifre: array [0 .. 7] of Integer = (1, 2, 3, 4, 6, 7, 9, 10);
var
  Posizione: Integer;
begin
  Result := False;

  if Length(Testo) < 10 then
    Exit;

  if (Testo[5] <> '-') or (Testo[8] <> '-') then
    Exit;

  for Posizione in PosizioniCifre do
    if not CharInSet(Testo[Posizione], ['0' .. '9']) then
      Exit;

  Result := (Length(Testo) = 10) or CharInSet(Testo[11], ['T', 't', ' ']);
end;

function TDevExtremeHelper.JSONValueToVariant(const Value: TJSONValue): Variant;
var
  DT: TDateTime;
  IntVal: Int64;
  DblVal: Double;
  NumStr: string;
begin
  // NULL
  if (Value = nil) or (Value is TJSONNull) then
  begin
    Result := Null;
    Exit;
  end;

  // Boolean → Boolean variant → FireDAC ftBoolean
  if Value is TJSONBool then
  begin
    Result := TJSONBool(Value).AsBoolean;
    Exit;
  end;

  // Number → prova Int64, altrimenti Double → FireDAC ftLargeint / ftFloat
  if Value is TJSONNumber then
  begin
    NumStr := TJSONNumber(Value).Value;
    // Se non contiene separatore decimale proviamo integer
    if (Pos('.', NumStr) = 0) and (Pos('e', LowerCase(NumStr)) = 0) then
    begin
      if TryStrToInt64(NumStr, IntVal) then
      begin
        Result := IntVal;
        Exit;
      end;
    end;
    // Altrimenti float (separatore sempre '.' nel JSON)
    NumStr := StringReplace(NumStr, '.', FormatSettings.DecimalSeparator, [rfReplaceAll]);
    if TryStrToFloat(NumStr, DblVal) then
      Result := DblVal
    else
      Result := TJSONNumber(Value).Value; // fallback stringa
    Exit;
  end;

  // String: prova parsing ISO 8601 → TDateTime variant → FireDAC ftDateTime
  // Altrimenti rimane string → ftString
  // Solo la forma estesa con i trattini: TryISO8601ToDate accetta anche la
  // forma compatta, e un codice di otto cifre ("20121212") o una settimana
  // ("2026W42") diventerebbero una data in un campo di testo.
  if Value is TJSONString then
  begin
    var
    S := TJSONString(Value).Value;
    // ioNoTZIsLocal: senza fuso la data e' gia' ora locale e resta com'e';
    // con Z o con lo scostamento viene portata all'ora locale
    if SembraDataIsoEstesa(S) and TryISO8601ToDate(S, DT, [ioNoTZIsLocal]) then
      Result := DT // VarType = varDate → FireDAC ftDateTime
    else
      Result := S;
    Exit;
  end;

  // Fallback: qualsiasi altro tipo JSON → stringa
  Result := Value.Value;
end;

// ────────────────────────────────────────────────────────────────────────────
// Conversione TJSONObject → TParamValues (body DML)
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.JSONObjectToParams(const RecordData: TJSONObject): TParamValues;
var
  Pair: TJSONPair;
begin
  Result := TParamValues.Create;
  try
    for Pair in RecordData do
      Result.AddOrSetValue(Pair.JsonString.Value, JSONValueToVariant(Pair.JsonValue));
  except
    Result.Free;
    raise;
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Parsing Filter → clausola WHERE con parametri bindati
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.MapOperator(const ADevExOp: string): string;
begin
  case IndexStr(LowerCase(ADevExOp), ['=', '<>', '>', '>=', '<', '<=', 'contains', 'notcontains', 'startswith', 'endswith']) of
    0:
      Result := '=';
    1:
      Result := '<>';
    2:
      Result := '>';
    3:
      Result := '>=';
    4:
      Result := '<';
    5:
      Result := '<=';
    6, 7, 8, 9:
      Result := 'LIKE';
  else
    raise Exception.CreateFmt('Operatore DevExtreme non supportato: "%s"', [ADevExOp]);
  end;
end;

function TDevExtremeHelper.ProcessFilterArray(AFilterArray: TJSONArray): string;
var
  FieldName, Op, RawValue, ParamName, LogicOp: string;
  SubResults: TStringList;
  I: Integer;
  Item: TJSONValue;
begin
  Result := '';
  if AFilterArray.Count = 0 then
    Exit;

  // ── NOT unario di DevExtreme: ["!", [...]] ──
  // Va controllato prima del caso A: il secondo elemento e' un array, non
  // l'operatore, e dentro il caso A il ramo non si eseguiva mai (la
  // negazione spariva e la SQL restituiva le righe da escludere)
  if (AFilterArray.Count = 2) and (AFilterArray.Items[0] is TJSONString) and
    (AFilterArray.Items[0].Value = '!') and (AFilterArray.Items[1] is TJSONArray) then
  begin
    Result := ProcessFilterArray(TJSONArray(AFilterArray.Items[1]));
    if not Result.IsEmpty then
      Result := 'NOT ' + Result;
    Exit;
  end;

  // ── Caso A: filtro semplice ["campo", "operatore", valore] ──
  // Discriminante: il secondo elemento è una stringa (l'operatore), non un array
  if (AFilterArray.Count >= 2) and
   (AFilterArray.Items[0] is TJSONString) and
  (AFilterArray.Items[1] is TJSONString) then
  begin
    if AFilterArray.Count < 3 then
      Exit;

    // Il nome passa la whitelist, poi diventa l'espressione della SELECT:
    // il nome nudo nel WHERE e' ambiguo quando la join ha colonne omonime
    FieldName := EspressioneDelCampo(SanitizeIdentifier(AFilterArray.Items[0].Value));
    Op := LowerCase(AFilterArray.Items[1].Value);
    RawValue := AFilterArray.Items[2].Value;

    Inc(FParamCounter);
    ParamName := 'P' + IntToStr(FParamCounter);

    // Adatta il valore per LIKE
    case IndexStr(Op, ['contains', 'notcontains', 'startswith', 'endswith']) of
      0:
        RawValue := '%' + RawValue + '%'; // contains
      1:
        RawValue := '%' + RawValue + '%'; // notcontains → NOT LIKE
      2:
        ; // startswith: STARTING WITH non vuole il '%'
      3:
        RawValue := '%' + RawValue; // endswith
    end;

    // Numeri e booleani passano tipizzati: come testo "45.4" diventava 454,
    // perche' il punto per FireDAC e' il separatore delle migliaia
    if not MatchStr(Op, ['contains', 'notcontains', 'startswith', 'endswith']) and
      ((AFilterArray.Items[2] is TJSONNumber) or (AFilterArray.Items[2] is TJSONBool)) then
      FParams.AddOrSetValue(ParamName, JSONValueToVariant(AFilterArray.Items[2]))
    else
      FParams.AddOrSetValue(ParamName, RawValue);

    // Costruisci l'espressione SQL
    // Per confronti stringa con LIKE usiamo UPPER su entrambi i lati
    if Op = 'notcontains' then
      Result := Format('(UPPER(%s) NOT LIKE UPPER(:%s))', [FieldName, ParamName])
    else
      if Op = 'startswith' then
        // STARTING WITH sul campo nudo: Firebird usa l'indice (con UPPER no, scansione
        // completa della tabella). Le colonne di testo dei database sono UNICODE_CI_AI,
        // quindi il confronto resta senza distinzione fra maiuscole e minuscole
        // (il valore non porta il '%' finale: STARTING WITH lo leggerebbe come carattere).
        Result := Format('(%s STARTING WITH :%s)', [FieldName, ParamName])
      else
      if MatchStr(Op, ['contains', 'endswith']) then
        Result := Format('(UPPER(%s) LIKE UPPER(:%s))', [FieldName, ParamName])
      else
        // Operatori di confronto standard
        Result := Format('(%s %s :%s)', [FieldName, MapOperator(Op), ParamName]);

    Exit;
  end;

  // ── Caso B: array di condizioni con operatori logici ──
  // Struttura: [ [cond1], "and", [cond2], "or", [cond3] ]
  SubResults := TStringList.Create;
  try
    SubResults.QuoteChar := #0;
    LogicOp := 'AND'; // default
    for I := 0 to AFilterArray.Count - 1 do
    begin
      Item := AFilterArray.Items[I];
      if Item is TJSONArray then
      begin
        var
        Sub := ProcessFilterArray(TJSONArray(Item));
        if not Sub.IsEmpty then
          SubResults.Add(Sub);
      end
      else
        if Item is TJSONString then
        begin
          var
          S := UpperCase(Item.Value);
          if (S = 'AND') or (S = 'OR') then
            LogicOp := S;
          // "!" qui viene ignorato: il NOT unario e' gestito in testa
        end;
    end;

    if SubResults.Count > 0 then
      Result := '(' + SubResults.DelimitedText.Replace(SubResults.Delimiter, ' ' + LogicOp + ' ') + ')'
    else
      Result := '';
  finally
    SubResults.Free;
  end;
end;

function TDevExtremeHelper.InternalParseFilter(const FilterJson: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  if FilterJson.IsEmpty or (FilterJson = 'null') then
    Exit;

  V := TJSONObject.ParseJSONValue(FilterJson);
  if not Assigned(V) then
    Exit;
  try
    if V is TJSONArray then
      Result := ProcessFilterArray(TJSONArray(V))
    else
      LogE('ParseFilter: il JSON del filter non è un array: ' + FilterJson);
  finally
    V.Free;
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Parsing Sort → clausola ORDER BY (senza keyword)
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.InternalParseSort(const SortJson: string): string;
var
  V: TJSONValue;
  Arr: TJSONArray;
  Parts: TStringList;
  I: Integer;
  Selector: string;
  Desc: Boolean;
begin
  Result := '';
  if SortJson.IsEmpty or (SortJson = 'null') then
    Exit;

  V := TJSONObject.ParseJSONValue(SortJson);
  if not Assigned(V) then
    Exit;
  try
    if not(V is TJSONArray) then
      Exit;

    Arr := TJSONArray(V);
    Parts := TStringList.Create;
    try
      Parts.QuoteChar := #0;

      for I := 0 to Arr.Count - 1 do
      begin
        if not(Arr.Items[I] is TJSONObject) then
          Continue;
        var
        Obj := TJSONObject(Arr.Items[I]);
        Selector := SanitizeIdentifier(Obj.GetValue<string>('selector', ''));
        if Selector.IsEmpty then
          Continue;
        Desc := Obj.GetValue<Boolean>('desc', False);
        Parts.Add(Selector + IfThen(Desc, ' DESC', ' ASC'));
      end;
      if Parts.Count > 0 then
        Result := Parts.DelimitedText.Replace(Parts.Delimiter, ', ');
    finally
      Parts.Free;
    end;
  finally
    V.Free;
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Paginazione Firebird: ROWS <start> TO <end>
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.BuildPaginationFirebird(Skip, Take: Integer): string;
begin
  Result := '';
  if Skip < 0 then
    Skip := 0;
  if Take > 0 then
    Result := Format('ROWS %d TO %d', [Skip + 1, Skip + Take])
  else
    if Skip > 0 then
      // Solo skip senza take: usa un limite alto (non ideale, ma compatibile)
      Result := Format('ROWS %d TO %d', [Skip + 1, 2147483647]);
end;

// ────────────────────────────────────────────────────────────────────────────
// ParseLoadOptions - punto di ingresso principale dal Controller
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.ParseLoadOptions(const Request: TMVCWebRequest; const FieldNamesCsv: string): TDevExtremeLoadOptions;
begin
  LogRequest('ParseLoadOptions', Request);
  // ZC 02.11.2026: prima qui si azzeravano FParams e FParamCounter. GetData
  // chiama ParseLoadOptions dopo SqlDelDataset, che ha gia' messo in FParams i
  // segnaposto di sessione (CTX_USER_ID per :##USER_ID, CTX_ID_SESSIONE...) e i
  // parametri propri del dataset presi dall'indirizzo (:DAL_GIORNO...): il Clear
  // li cancellava e la SQL girava con quei parametri nulli, zero righe per i
  // dataset Gera.* di WT. L'helper nasce nuovo a ogni richiesta, quindi non c'e'
  // stato da azzerare: i filtri aggiungono P1, P2... a quanto c'e' gia'.
  // ZC 02.11.2026: vanno tolti solo i P1, P2... di un caricamento precedente
  // sullo stesso helper (i test lo riusano) e il contatore riparte da zero:
  // i segnaposto di sessione e i parametri del dataset restano.
  var NomiDaTogliere := TList<string>.Create;
  try
    for var NomeParametro in FParams.Keys do
      if (Length(NomeParametro) > 1) and (NomeParametro[1] = 'P') and
        (StrToIntDef(Copy(NomeParametro, 2, MaxInt), -1) > 0) then
        NomiDaTogliere.Add(NomeParametro);
    for var NomeParametro in NomiDaTogliere do
      FParams.Remove(NomeParametro);
  finally
    NomiDaTogliere.Free;
  end;
  FParamCounter := 0;

  // Imposta whitelist se fornita
  if not FieldNamesCsv.IsEmpty then
    SetWhiteList(FieldNamesCsv);

  Result.Init;
  Result.Skip := StrToIntDef(Request.Params['skip'], 0);
  Result.Take := StrToIntDef(Request.Params['take'], 0);
  Result.RequireTotalCount := SameText(Request.Params['requireTotalCount'], 'true');
  Result.RequireGroupCount := SameText(Request.Params['requireGroupCount'], 'true');
  Result.Group := Request.Params['group'].Trim;
  Result.Select := Request.Params['select'].Trim;

  Result.SearchExpr := Request.Params['searchExpr'];
  Result.SearchOperation := Request.Params['searchOperation'];
  Result.SearchValue := Request.Params['searchValue'];

  // Filter: genera clausola WHERE con parametri bindati in FParams
  var
  FilterRaw := Request.Params['filter'].Trim;
  LogD(FilterRaw);
  if not FilterRaw.IsEmpty then
  begin
    Result.Filter := InternalParseFilter(FilterRaw);
    // Nota: FParams è ora popolato con i parametri :P1, :P2 ...
  end;

  // Sort: genera clausola ORDER BY (campi separati da virgola, senza keyword)
  var
  SortRaw := Request.Params['sort'].Trim;
  if not SortRaw.IsEmpty then
    Result.Sort := InternalParseSort(SortRaw);

  // Paginazione Firebird
  Result.Pagination := BuildPaginationFirebird(Result.Skip, Result.Take);
end;

// ────────────────────────────────────────────────────────────────────────────
// Lookup: ricerca semplice sul campo indicato da searchExpr
// ────────────────────────────────────────────────────────────────────────────

// I campi di searchExpr. DevExtreme lo manda come nome solo ("NOME" o NOME)
// oppure, quando la casella cerca su piu' campi, come elenco JSON
// (["COGNOME","NOME"]).
function CampiDiRicerca(const SearchExpr: string): TArray<string>;
var
  Testo: string;
  Elenco: TJSONValue;
  Elemento: TJSONValue;
  Campi: TList<string>;
begin
  Testo := SearchExpr.Trim;

  if not Testo.StartsWith('[') then
    Exit(TArray<string>.Create(Testo.DeQuotedString('"')));

  Elenco := TJSONObject.ParseJSONValue(Testo);
  try
    if not(Elenco is TJSONArray) then
      raise Exception.CreateFmt('searchExpr non valido: %s', [Testo]);

    Campi := TList<string>.Create;
    try
      for Elemento in TJSONArray(Elenco) do
      begin
        if not(Elemento is TJSONString) then
          raise Exception.CreateFmt('searchExpr non valido: %s', [Testo]);
        Campi.Add(TJSONString(Elemento).Value);
      end;
      Result := Campi.ToArray;
    finally
      FreeAndNil(Campi);
    end;
  finally
    FreeAndNil(Elenco);
  end;
end;

function TDevExtremeHelper.BuildSearchClause(const SearchExpr, SearchOperation, SearchValue: string): string;
var
  Campi: TArray<string>;
  Campo: string;
  SafeField: string;
  ParamName: string;
  Valore: string;
  Modello: string;
  Congiunzione: string;
  Condizioni: TList<string>;
begin
  // Z12 - Il valore cercato non entra piu' nel testo della SQL protetto dal
  // raddoppio degli apici di QuotedStr: diventa un parametro legato, con la
  // stessa numerazione che InternalParseFilter usa gia' per i filtri.
  Result := '';

  if SearchExpr.IsEmpty or SearchValue.IsEmpty then
    Exit;

  // Congiunzione: una ricerca positiva trova la riga se un campo qualunque
  // corrisponde (OR, come DevExtreme), una negativa se nessuno corrisponde (AND).
  Congiunzione := ' OR ';

  case IndexStr(LowerCase(SearchOperation), ['contains', 'notcontains', 'startswith', 'endswith', '=', '<>']) of
    0:
      begin
        Valore := '%' + SearchValue + '%';
        Modello := 'UPPER(%s) LIKE UPPER(:%s)';
      end;
    1:
      begin
        Valore := '%' + SearchValue + '%';
        Modello := 'UPPER(%s) NOT LIKE UPPER(:%s)';
        Congiunzione := ' AND ';
      end;
    2:
      begin
        // STARTING WITH sul campo nudo: usa l'indice, senza '%' nel valore
        Valore := SearchValue;
        Modello := '%s STARTING WITH :%s';
      end;
    3:
      begin
        Valore := '%' + SearchValue;
        Modello := 'UPPER(%s) LIKE UPPER(:%s)';
      end;
    4:
      begin
        Valore := SearchValue;
        Modello := '%s = :%s';
      end;
    5:
      begin
        Valore := SearchValue;
        Modello := '%s <> :%s';
        Congiunzione := ' AND ';
      end;
  else
    // Default: contains
    Valore := '%' + SearchValue + '%';
    Modello := 'UPPER(%s) LIKE UPPER(:%s)';
  end;

  Campi := CampiDiRicerca(SearchExpr);

  // Un parametro per campo, con lo stesso valore: ogni nome compare una
  // volta sola nella SQL, qualunque sia il modo in cui il driver li lega.
  Condizioni := TList<string>.Create;
  try
    for Campo in Campi do
    begin
      SafeField := EspressioneDelCampo(SanitizeIdentifier(Campo));

      Inc(FParamCounter);
      ParamName := 'P' + IntToStr(FParamCounter);

      Condizioni.Add(Format(Modello, [SafeField, ParamName]));
      FParams.AddOrSetValue(ParamName, Valore);
    end;

    if Condizioni.Count = 1 then
      Result := Condizioni[0]
    else if Condizioni.Count > 1 then
      Result := '(' + string.Join(Congiunzione, Condizioni.ToArray) + ')';
  finally
    FreeAndNil(Condizioni);
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Raggruppamento in-memory
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.ProcessGrouping(const Data: TJSONArray; const LoadOptions: TDevExtremeLoadOptions): TDevExtremeDataResponse;
var
  GroupArray: TJSONArray;
  GroupField: string;
  Groups: TDictionary<string, TJSONArray>;
  Item: TJSONObject;
  GroupKey: string;
  I: Integer;
begin
  Result.Init;
  Result.Data := TJSONArray.Create;
  Result.TotalCount := 0;
  Result.GroupCount := 0;
  Result.Summary := nil;

  if LoadOptions.Group.IsEmpty then
  begin
    for I := 0 to Data.Count - 1 do
      Result.Data.AddElement(Data.Items[I].Clone as TJSONValue);
    Result.TotalCount := Data.Count;
    Exit;
  end;

  try
    GroupArray := TJSONObject.ParseJSONValue(LoadOptions.Group) as TJSONArray;
    if not Assigned(GroupArray) then
    begin
      for I := 0 to Data.Count - 1 do
        Result.Data.AddElement(Data.Items[I].Clone as TJSONValue);
      Result.TotalCount := Data.Count;
      Exit;
    end;

    try
      if GroupArray.Count = 0 then
        Exit;

      if GroupArray.Items[0] is TJSONObject then
        GroupField := TJSONObject(GroupArray.Items[0]).GetValue<string>('selector')
      else
        GroupField := GroupArray.Items[0].Value;

      Groups := TDictionary<string, TJSONArray>.Create;
      try
        for I := 0 to Data.Count - 1 do
        begin
          Item := TJSONObject(Data.Items[I]);
          GroupKey := Item.GetValue<string>(GroupField, '(null)');
          if not Groups.ContainsKey(GroupKey) then
            Groups.Add(GroupKey, TJSONArray.Create);
          Groups[GroupKey].AddElement(Item.Clone as TJSONObject);
        end;

        for var Pair in Groups do
        begin
          var
          GroupObj := TJSONObject.Create;
          GroupObj.AddPair('key', Pair.Key);
          GroupObj.AddPair('items', Pair.Value);
          GroupObj.AddPair('count', TJSONNumber.Create(Pair.Value.Count));
          Result.Data.AddElement(GroupObj);
        end;

        Result.GroupCount := Groups.Count;
        Result.TotalCount := Data.Count;
      finally
        Groups.Free; // i TJSONArray sono ora owned dai GroupObj nel Result.Data
      end;
    finally
      GroupArray.Free;
    end;
  except
    on E: Exception do
    begin
      LogE(Format('ProcessGrouping - Errore: %s', [E.Message]));
      Result.Data.Free;
      Result.Data := TJSONArray.Create;
      for I := 0 to Data.Count - 1 do
        Result.Data.AddElement(Data.Items[I].Clone as TJSONValue);
      Result.TotalCount := Data.Count;
    end;
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Costruzione risposta DevExtreme
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.CreateDevExtremeResponse(const Response: TDevExtremeDataResponse): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('data', Response.Data.Clone as TJSONArray);
  if Response.TotalCount >= 0 then
    Result.AddPair('totalCount', TJSONNumber.Create(Response.TotalCount));
  if Response.GroupCount > 0 then
    Result.AddPair('groupCount', TJSONNumber.Create(Response.GroupCount));
  if Assigned(Response.Summary) then
    Result.AddPair('summary', Response.Summary.Clone as TJSONArray);
end;

// ────────────────────────────────────────────────────────────────────────────
// DML parametrico: BuildInsertSQL / BuildUpdateSQL / BuildDeleteSQL
//
// STRATEGIA COMUNE
// ─────────────────
// • Se il DatasetConfig ha già l'SQL (InsertSQL / UpdateSQL / DeleteSQL):
// → viene usato così com'è come template; i placeholder devono avere
// esattamente il nome del campo JSON (:COGNOME, :ETA, ...) oppure :KEY.
// → non viene alterato in nessun modo: il template deve già essere corretto.
//
// • Se l'SQL NON è nel config (stringa vuota):
// → viene generato automaticamente con placeholder :nomecampo.
// → i campi della PK vengono esclusi dal SET dell'UPDATE.
//
// In entrambi i casi OutParams contiene i Variant tipizzati per FireDAC.
// ────────────────────────────────────────────────────────────────────────────

procedure TDevExtremeHelper.BuildInsertSQL(const DatasetConfig: TDatasetConfig; const RecordData: TJSONObject; out OutSQL: string; out OutParams: TParamValues);
var
  Fields, Placeholders: TStringBuilder;
  Pair: TJSONPair;
  FieldName: string;
  First: Boolean;
begin
  // Params: tutti i campi del body JSON, con Variant tipizzati
  OutParams := JSONObjectToParams(RecordData);

  if DatasetConfig.InsertSQL <> '' then
  begin
    // Template già definito: usalo direttamente.
    // I placeholder :nomecampo devono corrispondere alle chiavi di OutParams.
    OutSQL := DatasetConfig.InsertSQL;
    Exit;
  end;

  // Generazione automatica: INSERT INTO "Table" ("f1","f2",...) VALUES (:f1,:f2,...)
  Fields := TStringBuilder.Create;
  Placeholders := TStringBuilder.Create;
  try
    First := True;
    for Pair in RecordData do
    begin
      FieldName := Pair.JsonString.Value;
      if not First then
      begin
        Fields.Append(', ');
        Placeholders.Append(', ');
      end;
      First := False;
      Fields.Append(QuoteSQLIdentifier(FieldName));
      Placeholders.Append(':' + FieldName);
    end;
    OutSQL := Format('INSERT INTO %s (%s) VALUES (%s)', [QuoteSQLIdentifier(DatasetConfig.TableName), Fields.ToString, Placeholders.ToString]);
  finally
    Fields.Free;
    Placeholders.Free;
  end;
end;

procedure TDevExtremeHelper.BuildUpdateSQL(const DatasetConfig: TDatasetConfig; const RecordData: TJSONObject; const KeyValue: string; out OutSQL: string; out OutParams: TParamValues);
var
  SetClauses: TStringBuilder;
  Pair: TJSONPair;
  FieldName: string;
  First: Boolean;
begin
  // Params: tutti i campi del body + :KEY per la chiave primaria
  OutParams := JSONObjectToParams(RecordData);
  OutParams.AddOrSetValue('KEY', KeyValue); // aggiunge/sovrascrive :KEY

  if DatasetConfig.UpdateSQL <> '' then
  begin
    // Template già definito: usalo direttamente.
    // Deve contenere :nomecampo per i campi e :KEY per la PK.
    OutSQL := DatasetConfig.UpdateSQL;
    Exit;
  end;

  // Generazione automatica: UPDATE "Table" SET "f1"=:f1, ... WHERE "PK"=:KEY
  // I campi coincidenti con PrimaryKeyField vengono esclusi dal SET.
  SetClauses := TStringBuilder.Create;
  try
    First := True;
    for Pair in RecordData do
    begin
      FieldName := Pair.JsonString.Value;
      // Esclude la colonna PK dal SET (è già nel WHERE come :KEY)
      if SameText(FieldName, DatasetConfig.PrimaryKeyField) then
        Continue;
      if not First then
        SetClauses.Append(', ');
      First := False;
      SetClauses.Append(QuoteSQLIdentifier(FieldName));
      SetClauses.Append(' = :');
      SetClauses.Append(FieldName);
    end;

    if First then
      raise Exception.Create('BuildUpdateSQL: nessun campo modificabile nel body (solo PK?)');

    OutSQL := Format('UPDATE %s SET %s WHERE %s = :KEY', [QuoteSQLIdentifier(DatasetConfig.TableName), SetClauses.ToString, QuoteSQLIdentifier(DatasetConfig.PrimaryKeyField)]);
  finally
    SetClauses.Free;
  end;
end;

procedure TDevExtremeHelper.BuildDeleteSQL(const DatasetConfig: TDatasetConfig; const KeyValue: string; out OutSQL: string; out OutParams: TParamValues);
begin
  // Per DELETE il solo parametro necessario è la chiave primaria
  OutParams := TParamValues.Create;
  OutParams.Add('KEY', KeyValue); // sempre stringa: la PK arriva dal path REST

  if DatasetConfig.DeleteSQL <> '' then
  begin
    // Template già definito: deve contenere :KEY
    OutSQL := DatasetConfig.DeleteSQL;
    Exit;
  end;

  // Generazione automatica
  OutSQL := Format('DELETE FROM %s WHERE %s = :KEY', [QuoteSQLIdentifier(DatasetConfig.TableName), QuoteSQLIdentifier(DatasetConfig.PrimaryKeyField)]);
end;

// ────────────────────────────────────────────────────────────────────────────
// Stored Procedure
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.ParseStoredProcParams(const RequestData: TJSONObject): TParamValues;
var
  InputArray: TJSONArray;
  ParamObj: TJSONObject;
  I: Integer;
begin
  Result := TParamValues.Create;
  try
    if RequestData.TryGetValue<TJSONArray>('inputParams', InputArray) then
      for I := 0 to InputArray.Count - 1 do
      begin
        ParamObj := TJSONObject(InputArray.Items[I]);

        // Un valore null (o assente) non e' un testo: GetValue<string> lo
        // leggeva come "null" e la procedura rispondeva 500 su un parametro
        // numerico. Il parametro si salta, e la procedura usa il suo predefinito.
        if not(ParamObj.GetValue('value') is TJSONNull) and Assigned(ParamObj.GetValue('value')) then
          Result.Add(ParamObj.GetValue<string>('name'), ParamObj.GetValue<string>('value'));
      end;
  except
    Result.Free;
    raise;
  end;
end;

// ────────────────────────────────────────────────────────────────────────────
// Utilità
// ────────────────────────────────────────────────────────────────────────────

function TDevExtremeHelper.BodyAsJSONObject(const body: string): TJSONObject;
var
  Valore: TJSONValue;
begin
  // Un array e' JSON valido ma non un oggetto: con "as TJSONObject" diventava
  // EInvalidCast, cioe' un errore 500 invece di un rifiuto della richiesta
  Valore := TJSONObject.ParseJSONValue(body);

  if not(Valore is TJSONObject) then
  begin
    FreeAndNil(Valore);
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Corpo della richiesta non valido: atteso un oggetto JSON.');
  end;

  Result := TJSONObject(Valore);
end;

procedure TDevExtremeHelper.LogRequest(const title: String; const Request: TMVCWebRequest);
var
  ParamName: string;
begin

  LogD(title);
  LogD(Request.QueryString);
  for ParamName in Request.ParamNames do
    LogD(ParamName + ': ' + Request.Params[ParamName]);

  LogD('body: ' + Request.body);
end;

end.
