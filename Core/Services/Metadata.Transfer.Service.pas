// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-21
// ---------------------------------------------------------------------------
unit Metadata.Transfer.Service;

// ---------------------------------------------------------------------------
// Tabelle BaseWeb attraverso il pacchetto BASE_WEB_TABLE_IO.
//
// Un solo posto che sa, per ogni tabella di base e _CUSTOM, quali sono le
// chiavi, i parametri della _SAVE e l'ordine di dipendenza. Lo usano:
// - l'editor dei metadati (/api/meta), per leggere, unire e salvare una riga
//   alla volta;
// - il trasporto dai master ai clienti: esportazione in JSON, importazione
//   in una transazione (SAVE delle righe del file, DELETE delle righe di base
//   assenti) e lo script SQL equivalente scritto dallo stesso JSON, per i
//   clienti dove l'importazione non passa da zServer.
//
// Le _CUSTOM non viaggiano mai: l'importazione non le tocca, e le chiavi
// coincidono con quelle di base, quindi sopravvivono alla sostituzione.
// Nessuna SQL sulle tabelle: solo procedure del pacchetto, cosi' la parte
// SQL resta identica in WT e in Gesty.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  /// <summary>
  /// Una tabella BaseWeb vista attraverso il pacchetto: la radice delle
  /// procedure coincide con il nome della tabella (BASE_WEB_DATASETS_FIELDS
  /// -> BASE_WEB_DATASETS_FIELDS_LOAD/_SAVE/_DELETE).
  /// </summary>
  TTabellaBaseWeb = record
    /// <summary>Nome della sezione nel pacchetto JSON e nelle rotte (datasets, fields, gridColumns...).</summary>
    Sezione: string;
    /// <summary>Tabella fisica e radice delle procedure del pacchetto.</summary>
    Tabella: string;
    /// <summary>Colonne chiave nell'ordine dei parametri della _LOAD e della _DELETE.</summary>
    Chiavi: TArray<string>;
    /// <summary>Parametri della _SAVE nell'ordine della firma: serve allo script SQL, che li passa per posizione.</summary>
    ParametriSave: TArray<string>;
    /// <summary>Colonna che lega la riga a un dataset ('' = nessuna: picklist).</summary>
    ColonnaDataset: string;
    /// <summary>Colonna del padre nello stesso albero ('' = tabella piatta).</summary>
    ColonnaPadre: string;
    /// <summary>Tabella _CUSTOM: la cancellazione si chiama _DELETE_CUSTOM e il trasporto la ignora.</summary>
    Custom: Boolean;
    function ProceduraLoad: string;
    function ProceduraSave: string;
    function ProceduraDelete: string;
    /// <summary>L'ultima chiave: quella che distingue la riga dentro il dataset o il lookup.</summary>
    function ColonnaChiave: string;
    function Contenitore: Boolean;
    /// <summary>Tipo di contenitore (group, tabbed, tab) per le tre tabelle della form, '' per le altre.</summary>
    function TipoContenitore: string;
  end;

  TFiltroEsportazione = record
    /// <summary>Nomi dei dataset da esportare (vuoto = tutti).</summary>
    Datasets: TArray<string>;
    /// <summary>Moduli (parte prima del punto) da includere.</summary>
    Dm: TArray<string>;
    /// <summary>Moduli da escludere: i dataset Agora.* di WT non vanno verso Gesty.</summary>
    EscludiDm: TArray<string>;
    function Vuoto: Boolean;
  end;

  TMetadataTransfer = class
  public const
    FormatoPacchetto = 'baseweb-metadati/1';
  private
    class function ChiaveRiga(Riga: TJSONObject; const Colonne: array of string): string; static;
    class function Testo(Riga: TJSONObject; const Colonna: string): string; static;
    class function Contiene(const Elenco: TArray<string>; const Valore: string): Boolean; static;
    class procedure AssegnaParametro(Parametro: TFDParam; Valore: TJSONValue); static;
    class function Letterale(Valore: TJSONValue): string; static;
    class function ElencoLetterali(const Valori: TList<string>): string; static;
    class function RigheSezione(Pacchetto: TJSONObject; const Sezione: string): TJSONArray; static;
    class function OrdinaPerPadre(Righe: TJSONArray; const T: TTabellaBaseWeb; DalBasso: Boolean): TList<TJSONObject>; static;
    class function OrdinaContenitori(const Righe: array of TJSONArray; DalBasso: Boolean): TList<TPair<string, TJSONObject>>; static;
    class procedure AggiungiDataset(Scope: TDictionary<string, Boolean>; const Dataset: string); static;
  public
    /// <summary>Le tabelle di base nell'ordine di salvataggio (padri prima dei figli).</summary>
    class function Tabelle: TArray<TTabellaBaseWeb>; static;
    /// <summary>Le tabelle _CUSTOM, con lo stesso nome di sezione della tabella di base.</summary>
    class function TabelleCustom: TArray<TTabellaBaseWeb>; static;
    class function TrovaTabella(const Sezione: string; Custom: Boolean; out T: TTabellaBaseWeb): Boolean; static;
    class function Tabella(const Sezione: string; Custom: Boolean = False): TTabellaBaseWeb; static;

    // ── Una riga alla volta ──
    /// <summary>SELECT * FROM <pacchetto>.<tabella>_LOAD(chiavi): '' vale NULL, cioe' tutte.</summary>
    class function Carica(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string): TJSONArray; static;
    /// <summary>La riga con quelle chiavi, nil se non c'e'.</summary>
    class function CaricaRiga(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string): TJSONObject; static;
    /// <summary>
    /// _SAVE con i parametri presi dalla riga per nome; i parametri assenti vanno a NULL.
    /// Per BASE_WEB_DATASETS scrive anche AUTHORIZATION, se la riga la porta, con la procedura dedicata.
    /// </summary>
    class procedure Salva(Connessione: TFDConnection; const T: TTabellaBaseWeb; Riga: TJSONObject); static;
    /// <summary>
    /// Aggiornamento parziale: legge la riga esistente, vi sovrappone il corpo e salva.
    /// Le chiavi passate vincono su quelle nel corpo. Creato = True se la riga non esisteva.
    /// </summary>
    class procedure SalvaUnendo(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string; Corpo: TJSONObject; out Creato: Boolean); static;
    class procedure Elimina(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string); static;
    class procedure ImpostaAutorizzazione(Connessione: TFDConnection; const Dataset, Autorizzazione: string); static;
    /// <summary>
    /// Gruppi, pannelli a schede e schede di una form in un colpo solo, per
    /// profondita' (un gruppo dentro una scheda si salva dopo la scheda):
    /// ogni riga viene unita a quella esistente. Chi chiama tiene la
    /// transazione e, se vuole, spegne la rigenerazione dei META.
    /// </summary>
    class procedure SalvaContenitori(Connessione: TFDConnection; Gruppi, Pannelli, Schede: TJSONArray); static;

    // ── Rigenerazione di BASE_WEB_DATASETS_META ──
    // La variabile di contesto e' della connessione: chi disattiva deve
    // riattivare in un finally, altrimenti la connessione torna nel pool con
    // la rigenerazione spenta per tutte le richieste successive.
    class procedure DisattivaRigenerazioneMeta(Connessione: TFDConnection); static;
    class procedure RiattivaRigenerazioneMeta(Connessione: TFDConnection; const Dataset: string = ''); static;
    class procedure RigeneraMeta(Connessione: TFDConnection; const Dataset: string); static;
    class procedure RigeneraTuttiIMeta(Connessione: TFDConnection); static;

    // ── Trasporto ──
    /// <summary>
    /// Pacchetto JSON delle tabelle di base: una sezione per tabella, righe
    /// nell'ordine delle _LOAD, senza META, DM e NAME, senza _CUSTOM. Con un
    /// filtro entrano anche i lookup e le picklist usati dai dataset scelti e i
    /// dataset sorgente di quei lookup.
    /// </summary>
    class function Esporta(Connessione: TFDConnection; const Filtro: TFiltroEsportazione; const Origine: string): TJSONObject; static;
    /// <summary>
    /// Applica un pacchetto in una transazione: _SAVE di ogni riga nell'ordine
    /// delle dipendenze, poi _DELETE delle righe di base assenti dal file
    /// (nell'ambito del pacchetto), rigenerazione dei META alla fine.
    /// Risponde con i conteggi per sezione.
    /// </summary>
    class function Importa(Connessione: TFDConnection; Pacchetto: TJSONObject): TJSONObject; static;
    /// <summary>Lo script SQL equivalente all'importazione, dallo stesso pacchetto.</summary>
    class function ScriptSql(Pacchetto: TJSONObject): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Variants,
  System.DateUtils,
  System.Math,
  System.Generics.Defaults,
  FiredacHelper;

const
  NomePacchetto = 'BASE_WEB_TABLE_IO';
  Separatore = #1;

{ TTabellaBaseWeb }

function TTabellaBaseWeb.ProceduraLoad: string;
begin
  Result := NomePacchetto + '.' + Tabella + '_LOAD';
end;

function TTabellaBaseWeb.ProceduraSave: string;
begin
  Result := NomePacchetto + '.' + Tabella + '_SAVE';
end;

function TTabellaBaseWeb.ProceduraDelete: string;
begin
  if Custom then
    Result := NomePacchetto + '.' + Tabella + '_DELETE_CUSTOM'
  else
    Result := NomePacchetto + '.' + Tabella + '_DELETE';
end;

function TTabellaBaseWeb.ColonnaChiave: string;
begin
  Result := Chiavi[High(Chiavi)];
end;

function TTabellaBaseWeb.Contenitore: Boolean;
begin
  Result := TipoContenitore <> '';
end;

function TTabellaBaseWeb.TipoContenitore: string;
begin
  if Sezione = 'formGroups' then
    Result := 'group'
  else
    if Sezione = 'formTabbed' then
      Result := 'tabbed'
    else
      if Sezione = 'formTabs' then
        Result := 'tab'
      else
        Result := '';
end;

{ TFiltroEsportazione }

function TFiltroEsportazione.Vuoto: Boolean;
begin
  Result := (Length(Datasets) = 0) and (Length(Dm) = 0) and (Length(EscludiDm) = 0);
end;

{ TMetadataTransfer: catalogo }

function Definisci(const Sezione, Tabella: string; const Chiavi, ParametriSave: array of string; const ColonnaDataset: string = 'DATASET'; const ColonnaPadre: string = ''; Custom: Boolean = False): TTabellaBaseWeb;
var
  Indice: Integer;
begin
  Result.Sezione := Sezione;
  Result.Tabella := Tabella;
  SetLength(Result.Chiavi, Length(Chiavi));
  for Indice := 0 to High(Chiavi) do
    Result.Chiavi[Indice] := Chiavi[Indice];
  SetLength(Result.ParametriSave, Length(ParametriSave));
  for Indice := 0 to High(ParametriSave) do
    Result.ParametriSave[Indice] := ParametriSave[Indice];
  Result.ColonnaDataset := ColonnaDataset;
  Result.ColonnaPadre := ColonnaPadre;
  Result.Custom := Custom;
end;

const
  ParametriDataset: array [0 .. 32] of string = ('DATASET', 'PK_FIELDS', 'RELATION_NAME', 'SEQUENCE_NAME', 'CAN_INSERT', 'CAN_UPDATE', 'CAN_DELETE', 'SQL_SELECT', 'SQL_COUNT', 'SQL_INSERT', 'SQL_UPDATE', 'SQL_DELETE', 'NOTE',
    'CAPTION', 'GRID_ALLOW_VIEW', 'GRID_EDIT_MODE', 'GRID_USE_FORM_EDIT', 'GRID_CONFIRM_DELETE', 'GRID_SELECTION_MODE', 'GRID_SELECTION_CHECKBOX', 'GRID_SELECTION_SELECTALL', 'GRID_EXPORT_ENABLED', 'GRID_EXPORT_SELECTED',
    'GRID_EXPORT_FILENAME', 'GRID_EXPORT_FORMATS', 'GRID_PAGE_SIZE', 'GRID_PAGE_SIZES', 'FORM_COL_COUNT', 'FORM_LABEL_LOC', 'FORM_LABEL_COLON', 'FORM_LAYOUT', 'FORM_WIDTH', 'FORM_HEIGHT');
  ParametriCampo: array [0 .. 14] of string = ('DATASET', 'FIELD', 'FIELD_ORIGIN', 'CAPTION', 'REQUIRED', 'READONLY', 'FIELDS_2_CLEAR', 'EDITOR_TYPE', 'PICKLIST', 'LOOKUP', 'FORM_PLACEHOLDER', 'FORM_HELP_TEXT', 'EDITOR_OPTIONS',
    'VALIDATION', 'DEPENDS_ON');
  ParametriCampoCustom: array [0 .. 11] of string = ('DATASET', 'FIELD', 'CAPTION', 'REQUIRED', 'READONLY', 'FIELDS_2_CLEAR', 'EDITOR_TYPE', 'FORM_PLACEHOLDER', 'FORM_HELP_TEXT', 'EDITOR_OPTIONS', 'VALIDATION', 'DEPENDS_ON');
  ParametriColonna: array [0 .. 24] of string = ('DATASET', 'FIELD', 'CAPTION', 'DATA_TYPE', 'BAND_NAME', 'SORT_ORDER', 'FIXED', 'FIXED_POSITION', 'VISIBLE', 'WIDTH', 'MIN_WIDTH', 'ALIGNMENT', 'FORMAT_STR', 'GROUP_INDEX',
    'SUMMARY_TYPE', 'ALLOW_FILTER', 'ALLOW_SORT', 'ALLOW_GROUP', 'ALLOW_RESIZE', 'ALLOW_REORDER', 'ALLOW_HIDING', 'HEADER_FILTER', 'WORD_WRAP', 'ENCODE_HTML', 'CSS_CLASS');
  ParametriFascia: array [0 .. 7] of string = ('DATASET', 'BAND_NAME', 'PARENT_BAND', 'CAPTION', 'SORT_ORDER', 'VISIBLE', 'ALIGNMENT', 'CSS_CLASS');
  ParametriGruppo: array [0 .. 9] of string = ('DATASET', 'GROUP_NAME', 'PARENT_CONTAINER_NAME', 'PARENT_CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'CAPTION', 'COL_SPAN', 'CSS_CLASS', 'COL_COUNT');
  ParametriGruppoCustom: array [0 .. 2] of string = ('DATASET', 'GROUP_NAME', 'COL_COUNT');
  ParametriPannello: array [0 .. 20] of string = ('DATASET', 'TABBED_NAME', 'PARENT_CONTAINER_NAME', 'PARENT_CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'CAPTION', 'COL_SPAN', 'CSS_CLASS', 'ANIMATION_ENABLED', 'SWIPE_ENABLED',
    'LOOP', 'DEFER_RENDERING', 'TABS_POSITION', 'STYLING_MODE', 'SCROLLING_ENABLED', 'SHOW_NAV_BUTTONS', 'ICON_POSITION', 'SELECTED_INDEX', 'HEIGHT', 'TAB_PANEL_OPTIONS');
  ParametriPannelloCustom: array [0 .. 13] of string = ('DATASET', 'TABBED_NAME', 'ANIMATION_ENABLED', 'SWIPE_ENABLED', 'LOOP', 'DEFER_RENDERING', 'TABS_POSITION', 'STYLING_MODE', 'SCROLLING_ENABLED', 'SHOW_NAV_BUTTONS',
    'ICON_POSITION', 'SELECTED_INDEX', 'HEIGHT', 'TAB_PANEL_OPTIONS');
  ParametriScheda: array [0 .. 14] of string = ('DATASET', 'TAB_NAME', 'TABBED_NAME', 'PARENT_CONTAINER_NAME', 'PARENT_CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'CAPTION', 'COL_SPAN', 'CSS_CLASS', 'COL_COUNT', 'DISABLED',
    'ICON', 'BADGE', 'ALIGN_ITEM_LABELS');
  ParametriSchedaCustom: array [0 .. 6] of string = ('DATASET', 'TAB_NAME', 'COL_COUNT', 'DISABLED', 'ICON', 'BADGE', 'ALIGN_ITEM_LABELS');
  ParametriCampoForm: array [0 .. 13] of string = ('DATASET', 'FIELD', 'CONTAINER_NAME', 'CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'LABEL_TEXT', 'COL_SPAN', 'LINEBREAK', 'PLACEHOLDER', 'HELP_TEXT', 'CSS_CLASS', 'REQUIRED',
    'EDITOR_OPTIONS');
  ParametriPulsante: array [0 .. 15] of string = ('DATASET', 'BUTTON_NAME', 'CONTAINER_NAME', 'CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'COL_SPAN', 'BTN_TEXT', 'BTN_TYPE', 'BTN_ICON', 'BTN_ACTION', 'BTN_HORIZONTAL_ALIGN',
    'BTN_ICON_POSITION', 'BTN_DISABLED', 'BTN_STYLING_MODE', 'CSS_CLASS');
  ParametriVuoto: array [0 .. 6] of string = ('DATASET', 'EMPTY_NAME', 'CONTAINER_NAME', 'CONTAINER_TYPE', 'SORT_ORDER', 'VISIBLE', 'COL_SPAN');
  ParametriLookup: array [0 .. 8] of string = ('LOOKUP', 'DATASET', 'FK_TABLE', 'VALUE_EXPR', 'DISPLAY_EXPR', 'PARAMS', 'MAPPINGS', 'PAGESIZE', 'DROPDOWN_WIDTH');
  ParametriColonnaLookup: array [0 .. 4] of string = ('LOOKUP', 'FIELD', 'CAPTION', 'WIDTH', 'ALIGNMENT');
  ParametriPicklist: array [0 .. 3] of string = ('PICKLIST', 'ITEMS', 'HAS_ICONS', 'META');

var
  CatalogoBase: TArray<TTabellaBaseWeb>;
  CatalogoCustom: TArray<TTabellaBaseWeb>;

class function TMetadataTransfer.Tabelle: TArray<TTabellaBaseWeb>;
begin
  if Length(CatalogoBase) = 0 then
    // Ordine di salvataggio: le picklist e i dataset non dipendono da niente;
    // i lookup dal loro dataset sorgente; i campi da lookup e picklist; il
    // resto dai campi e dal dataset. I contenitori della form sono tre
    // tabelle ma un albero solo: OrdinaContenitori li mette per profondita'.
    CatalogoBase := [
      Definisci('picklists', 'BASE_WEB_PICKLISTS', ['PICKLIST'], ParametriPicklist, ''),
      Definisci('datasets', 'BASE_WEB_DATASETS', ['DATASET'], ParametriDataset),
      Definisci('lookups', 'BASE_WEB_LOOKUPS', ['LOOKUP'], ParametriLookup),
      Definisci('lookupColumns', 'BASE_WEB_LOOKUPS_COLUMNS', ['LOOKUP', 'FIELD'], ParametriColonnaLookup, ''),
      Definisci('fields', 'BASE_WEB_DATASETS_FIELDS', ['DATASET', 'FIELD'], ParametriCampo),
      Definisci('gridBands', 'BASE_WEB_GRID_BANDS', ['DATASET', 'BAND_NAME'], ParametriFascia, 'DATASET', 'PARENT_BAND'),
      Definisci('gridColumns', 'BASE_WEB_GRID_COLUMNS', ['DATASET', 'FIELD'], ParametriColonna),
      Definisci('formGroups', 'BASE_WEB_FORM_GROUPS', ['DATASET', 'GROUP_NAME'], ParametriGruppo, 'DATASET', 'PARENT_CONTAINER_NAME'),
      Definisci('formTabbed', 'BASE_WEB_FORM_TABBED', ['DATASET', 'TABBED_NAME'], ParametriPannello, 'DATASET', 'PARENT_CONTAINER_NAME'),
      Definisci('formTabs', 'BASE_WEB_FORM_TABS', ['DATASET', 'TAB_NAME'], ParametriScheda, 'DATASET', 'PARENT_CONTAINER_NAME'),
      Definisci('formFields', 'BASE_WEB_FORM_FIELDS', ['DATASET', 'FIELD'], ParametriCampoForm),
      Definisci('formButtons', 'BASE_WEB_FORM_BUTTONS', ['DATASET', 'BUTTON_NAME'], ParametriPulsante),
      Definisci('formEmpty', 'BASE_WEB_FORM_EMPTY', ['DATASET', 'EMPTY_NAME'], ParametriVuoto)];
  Result := CatalogoBase;
end;

class function TMetadataTransfer.TabelleCustom: TArray<TTabellaBaseWeb>;
begin
  if Length(CatalogoCustom) = 0 then
    CatalogoCustom := [
      Definisci('datasets', 'BASE_WEB_DATASETS_CUSTOM', ['DATASET'], ParametriDataset, 'DATASET', '', True),
      Definisci('fields', 'BASE_WEB_DATASETS_FIELDS_CUSTOM', ['DATASET', 'FIELD'], ParametriCampoCustom, 'DATASET', '', True),
      Definisci('gridColumns', 'BASE_WEB_GRID_COLUMNS_CUSTOM', ['DATASET', 'FIELD'], ParametriColonna, 'DATASET', '', True),
      Definisci('formGroups', 'BASE_WEB_FORM_GROUPS_CUSTOM', ['DATASET', 'GROUP_NAME'], ParametriGruppoCustom, 'DATASET', '', True),
      Definisci('formTabbed', 'BASE_WEB_FORM_TABBED_CUSTOM', ['DATASET', 'TABBED_NAME'], ParametriPannelloCustom, 'DATASET', '', True),
      Definisci('formTabs', 'BASE_WEB_FORM_TABS_CUSTOM', ['DATASET', 'TAB_NAME'], ParametriSchedaCustom, 'DATASET', '', True),
      Definisci('formFields', 'BASE_WEB_FORM_FIELDS_CUSTOM', ['DATASET', 'FIELD'], ParametriCampoForm, 'DATASET', '', True),
      Definisci('formButtons', 'BASE_WEB_FORM_BUTTONS_CUSTOM', ['DATASET', 'BUTTON_NAME'], ParametriPulsante, 'DATASET', '', True),
      Definisci('formEmpty', 'BASE_WEB_FORM_EMPTY_CUSTOM', ['DATASET', 'EMPTY_NAME'], ParametriVuoto, 'DATASET', '', True)];
  Result := CatalogoCustom;
end;

class function TMetadataTransfer.TrovaTabella(const Sezione: string; Custom: Boolean; out T: TTabellaBaseWeb): Boolean;
var
  Candidata: TTabellaBaseWeb;
  Catalogo: TArray<TTabellaBaseWeb>;
begin
  if Custom then
    Catalogo := TabelleCustom
  else
    Catalogo := Tabelle;

  for Candidata in Catalogo do
    if SameText(Candidata.Sezione, Sezione) then
    begin
      T := Candidata;
      Exit(True);
    end;

  Result := False;
end;

class function TMetadataTransfer.Tabella(const Sezione: string; Custom: Boolean): TTabellaBaseWeb;
begin
  if not TrovaTabella(Sezione, Custom, Result) then
    raise Exception.CreateFmt('Sezione dei metadati sconosciuta: %s', [Sezione]);
end;

{ TMetadataTransfer: appoggio }

class function TMetadataTransfer.Testo(Riga: TJSONObject; const Colonna: string): string;
var
  Valore: TJSONValue;
begin
  Valore := Riga.GetValue(Colonna);
  if (Valore = nil) or (Valore is TJSONNull) then
    Result := ''
  else
    Result := Valore.Value;
end;

class function TMetadataTransfer.ChiaveRiga(Riga: TJSONObject; const Colonne: array of string): string;
var
  Colonna: string;
begin
  Result := '';
  for Colonna in Colonne do
    Result := Result + Testo(Riga, Colonna) + Separatore;
end;

class function TMetadataTransfer.Contiene(const Elenco: TArray<string>; const Valore: string): Boolean;
var
  Voce: string;
begin
  for Voce in Elenco do
    if SameText(Voce.Trim, Valore.Trim) then
      Exit(True);
  Result := False;
end;

// Il valore JSON entra nel parametro secondo il tipo che FireDAC ha letto al
// Prepare. Il testo vuoto vale NULL, come il SetParam del vecchio server:
// VALIDA_STR e PREPARA_PARAM del pacchetto fanno lo stesso con gli
// identificatori, e per gli altri campi un '' salvato al posto di NULL non
// avrebbe senso. Nessuna decodifica Base64 sui MEMO: sono testo, non blob.
class procedure TMetadataTransfer.AssegnaParametro(Parametro: TFDParam; Valore: TJSONValue);
var
  TestoValore: string;
  Intero: Int64;
  Decimale: Double;
  DataOra: TDateTime;
begin
  if (Valore = nil) or (Valore is TJSONNull) then
  begin
    Parametro.Clear;
    Exit;
  end;

  if Valore is TJSONBool then
  begin
    if Parametro.DataType = ftBoolean then
      Parametro.AsBoolean := TJSONBool(Valore).AsBoolean
    else
      Parametro.AsString := IfThen(TJSONBool(Valore).AsBoolean, 'TRUE', 'FALSE');
    Exit;
  end;

  if Valore is TJSONNumber then
  begin
    case Parametro.DataType of
      ftSmallint, ftInteger, ftWord, ftShortint, ftByte, ftLargeint, ftLongWord:
        Parametro.AsLargeInt := TJSONNumber(Valore).AsInt64;
      ftFloat, ftCurrency, ftBCD, ftFMTBcd, TFieldType.ftSingle, TFieldType.ftExtended:
        Parametro.AsFloat := TJSONNumber(Valore).AsDouble;
      ftBoolean:
        Parametro.AsBoolean := TJSONNumber(Valore).AsInt <> 0;
    else
      Parametro.AsString := TJSONNumber(Valore).ToString;
    end;
    Exit;
  end;

  TestoValore := Valore.Value;
  if TestoValore.IsEmpty then
  begin
    Parametro.Clear;
    Exit;
  end;

  case Parametro.DataType of
    ftBoolean:
      Parametro.AsBoolean := MatchText(TestoValore.ToLower, ['true', '1', 'yes', 't', 'si']);
    ftSmallint, ftInteger, ftWord, ftShortint, ftByte, ftLargeint, ftLongWord:
      if TryStrToInt64(TestoValore, Intero) then
        Parametro.AsLargeInt := Intero
      else
        Parametro.Clear;
    ftFloat, ftCurrency, ftBCD, ftFMTBcd, TFieldType.ftSingle, TFieldType.ftExtended:
      if TryStrToFloat(TestoValore, Decimale, TFormatSettings.Invariant) then
        Parametro.AsFloat := Decimale
      else
        Parametro.Clear;
    ftDate, ftTime, ftDateTime, ftTimeStamp:
      // Senza fuso la data e' ora locale e resta com'e' (ioNoTZIsLocal)
      if TryISO8601ToDate(TestoValore, DataOra, [ioNoTZIsLocal]) then
        Parametro.AsDateTime := DataOra
      else
        Parametro.Clear;
    ftMemo:
      Parametro.AsMemo := TestoValore;
    ftWideMemo:
      Parametro.AsWideMemo := TestoValore;
  else
    if (Parametro.Size > 0) and (TestoValore.Length > Parametro.Size) then
      Parametro.AsString := TestoValore.Substring(0, Parametro.Size)
    else
      Parametro.AsString := TestoValore;
  end;
end;

{ TMetadataTransfer: una riga alla volta }

class function TMetadataTransfer.Carica(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string): TJSONArray;
var
  Query: TFDQuery;
  Segnaposto: string;
  Indice: Integer;
begin
  Segnaposto := '';
  for Indice := 0 to High(T.Chiavi) do
    Segnaposto := Segnaposto + IfThen(Indice > 0, ', ') + ':P' + Indice.ToString;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text := Format('SELECT * FROM %s(%s)', [T.ProceduraLoad, Segnaposto]);
    Query.Prepare;
    for Indice := 0 to High(T.Chiavi) do
      if (Indice <= High(Chiavi)) and not Chiavi[Indice].Trim.IsEmpty then
        Query.Params[Indice].AsString := Chiavi[Indice].Trim
      else
        Query.Params[Indice].Clear;
    Query.Open;
    // encodeBlobs = False: i MEMO escono come testo, non in Base64
    Result := Query.DataSetToJSON(False);
  finally
    Query.Free;
  end;
end;

class function TMetadataTransfer.CaricaRiga(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string): TJSONObject;
var
  Righe: TJSONArray;
begin
  Result := nil;
  Righe := Carica(Connessione, T, Chiavi);
  try
    if Righe.Count > 0 then
      Result := TJSONObject(Righe.Items[0].Clone);
  finally
    Righe.Free;
  end;
end;

class procedure TMetadataTransfer.Salva(Connessione: TFDConnection; const T: TTabellaBaseWeb; Riga: TJSONObject);
var
  Procedura: TFDStoredProc;
  Parametro: TFDParam;
  Indice: Integer;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := T.ProceduraSave;
    Procedura.Prepare;
    for Indice := 0 to Procedura.Params.Count - 1 do
    begin
      Parametro := Procedura.Params[Indice];
      if Parametro.IsInputParam then
        AssegnaParametro(Parametro, Riga.GetValue(Parametro.Name));
    end;
    Procedura.ExecProc;
  finally
    Procedura.Free;
  end;

  // L'autorizzazione non e' fra i 33 parametri di DATASETS_SAVE (vedi la
  // procedura nel pacchetto): se la riga la porta, la scrive la sua procedura.
  if (not T.Custom) and SameText(T.Tabella, 'BASE_WEB_DATASETS') and (Riga.GetValue('AUTHORIZATION') <> nil) then
    ImpostaAutorizzazione(Connessione, Testo(Riga, 'DATASET'), Testo(Riga, 'AUTHORIZATION'));
end;

class procedure TMetadataTransfer.SalvaUnendo(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string; Corpo: TJSONObject; out Creato: Boolean);
var
  Riga: TJSONObject;
  Coppia: TJSONPair;
  Indice: Integer;
begin
  Riga := CaricaRiga(Connessione, T, Chiavi);
  Creato := Riga = nil;
  if Creato then
    Riga := TJSONObject.Create;
  try
    if Assigned(Corpo) then
      for Coppia in Corpo do
      begin
        Riga.RemovePair(Coppia.JsonString.Value).Free;
        Riga.AddPair(Coppia.JsonString.Value, Coppia.JsonValue.Clone as TJSONValue);
      end;

    // le chiavi della rotta vincono su quelle del corpo
    for Indice := 0 to High(T.Chiavi) do
      if (Indice <= High(Chiavi)) and not Chiavi[Indice].Trim.IsEmpty then
      begin
        Riga.RemovePair(T.Chiavi[Indice]).Free;
        Riga.AddPair(T.Chiavi[Indice], Chiavi[Indice].Trim);
      end;

    Salva(Connessione, T, Riga);
  finally
    Riga.Free;
  end;
end;

class procedure TMetadataTransfer.Elimina(Connessione: TFDConnection; const T: TTabellaBaseWeb; const Chiavi: array of string);
var
  Procedura: TFDStoredProc;
  Parametro: TFDParam;
  Indice: Integer;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := T.ProceduraDelete;
    Procedura.Prepare;
    // i parametri delle _DELETE hanno il nome delle colonne chiave
    for Indice := 0 to High(T.Chiavi) do
    begin
      Parametro := Procedura.Params.FindParam(T.Chiavi[Indice]);
      if not Assigned(Parametro) then
        raise Exception.CreateFmt('La procedura %s non ha il parametro %s', [T.ProceduraDelete, T.Chiavi[Indice]]);
      if (Indice <= High(Chiavi)) and not Chiavi[Indice].Trim.IsEmpty then
        Parametro.AsString := Chiavi[Indice].Trim
      else
        Parametro.Clear;
    end;
    Procedura.ExecProc;
  finally
    Procedura.Free;
  end;
end;

class procedure TMetadataTransfer.ImpostaAutorizzazione(Connessione: TFDConnection; const Dataset, Autorizzazione: string);
var
  Procedura: TFDStoredProc;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := NomePacchetto + '.BASE_WEB_DATASETS_SET_AUTHORIZATION';
    Procedura.Prepare;
    Procedura.Params.ParamByName('DATASET').AsString := Dataset;
    if Autorizzazione.Trim.IsEmpty then
      Procedura.Params.ParamByName('AUTHORIZATION').Clear
    else
      Procedura.Params.ParamByName('AUTHORIZATION').AsString := Autorizzazione.Trim;
    Procedura.ExecProc;
  finally
    Procedura.Free;
  end;
end;

class procedure TMetadataTransfer.SalvaContenitori(Connessione: TFDConnection; Gruppi, Pannelli, Schede: TJSONArray);
var
  Contenitori: TList<TPair<string, TJSONObject>>;
  Coppia: TPair<string, TJSONObject>;
  T: TTabellaBaseWeb;
  Creato: Boolean;
begin
  Contenitori := OrdinaContenitori([Gruppi, Pannelli, Schede], False);
  try
    for Coppia in Contenitori do
    begin
      T := Tabella(Coppia.Key);
      SalvaUnendo(Connessione, T, [Testo(Coppia.Value, 'DATASET'), Testo(Coppia.Value, T.ColonnaChiave)], Coppia.Value, Creato);
    end;
  finally
    Contenitori.Free;
  end;
end;

{ TMetadataTransfer: rigenerazione dei META }

class procedure TMetadataTransfer.DisattivaRigenerazioneMeta(Connessione: TFDConnection);
begin
  Connessione.ExecSQLScalar('SELECT BASE_WEB.META_UPDATE_DISABLE() FROM RDB$DATABASE');
end;

class procedure TMetadataTransfer.RiattivaRigenerazioneMeta(Connessione: TFDConnection; const Dataset: string);
begin
  // ENABLE(dataset) rigenera anche il META di quel dataset; con NULL toglie solo il blocco
  if Dataset.Trim.IsEmpty then
    Connessione.ExecSQLScalar('SELECT BASE_WEB.META_UPDATE_ENABLE(NULL) FROM RDB$DATABASE')
  else
    Connessione.ExecSQLScalar('SELECT BASE_WEB.META_UPDATE_ENABLE(:DS) FROM RDB$DATABASE', [Dataset.Trim]);
end;

class procedure TMetadataTransfer.RigeneraMeta(Connessione: TFDConnection; const Dataset: string);
begin
  Connessione.ExecSQLScalar('SELECT BASE_WEB.DATASET_BUILD_META(:DS) FROM RDB$DATABASE', [Dataset.Trim]);
end;

class procedure TMetadataTransfer.RigeneraTuttiIMeta(Connessione: TFDConnection);
begin
  Connessione.ExecSQLScalar('SELECT BASE_WEB.DATASET_BUILD_ALL_META() FROM RDB$DATABASE');
end;

{ TMetadataTransfer: ordinamenti per profondita' }

// Righe di una tabella ad albero (fasce) ordinate per profondita': padri
// prima dei figli al salvataggio, figli prima dei padri alla cancellazione.
class function TMetadataTransfer.OrdinaPerPadre(Righe: TJSONArray; const T: TTabellaBaseWeb; DalBasso: Boolean): TList<TJSONObject>;
var
  Profondita: TDictionary<string, Integer>;
  Decorate: TList<TPair<Integer, TJSONObject>>;
  Elemento: TJSONValue;
  Riga: TJSONObject;
  Chiave, Padre: string;
  Livello, Giro, Indice: Integer;
  Cambiato: Boolean;

  function ChiavePadre(R: TJSONObject): string;
  begin
    if T.ColonnaDataset.IsEmpty then
      Result := Testo(R, T.ColonnaPadre) + Separatore
    else
      Result := Testo(R, T.ColonnaDataset) + Separatore + Testo(R, T.ColonnaPadre) + Separatore;
  end;

begin
  Result := TList<TJSONObject>.Create;
  for Elemento in Righe do
    Result.Add(TJSONObject(Elemento));

  if T.ColonnaPadre.IsEmpty then
    Exit;

  Profondita := TDictionary<string, Integer>.Create;
  try
    for Riga in Result do
      Profondita.AddOrSetValue(ChiaveRiga(Riga, T.Chiavi), 0);

    // propaga la profondita' finche' non cambia piu' niente (alberi corti: poche passate)
    Giro := 0;
    repeat
      Cambiato := False;
      Inc(Giro);
      for Riga in Result do
      begin
        Padre := Testo(Riga, T.ColonnaPadre);
        if Padre.IsEmpty then
          Continue;
        Chiave := ChiaveRiga(Riga, T.Chiavi);
        if Profondita.TryGetValue(ChiavePadre(Riga), Livello) and (Profondita[Chiave] <> Livello + 1) then
        begin
          Profondita[Chiave] := Livello + 1;
          Cambiato := True;
        end;
      end;
    until (not Cambiato) or (Giro > 50);

    // ordinamento su coppie (profondita', riga): un metodo anonimo non puo'
    // chiamare le funzioni annidate, quindi la profondita' si calcola prima
    Decorate := TList<TPair<Integer, TJSONObject>>.Create;
    try
      for Riga in Result do
        Decorate.Add(TPair<Integer, TJSONObject>.Create(Profondita[ChiaveRiga(Riga, T.Chiavi)], Riga));
      Decorate.Sort(TComparer<TPair<Integer, TJSONObject>>.Construct(
        function(const Sinistra, Destra: TPair<Integer, TJSONObject>): Integer
        begin
          if DalBasso then
            Result := Destra.Key - Sinistra.Key
          else
            Result := Sinistra.Key - Destra.Key;
        end));
      Result.Clear;
      for Indice := 0 to Decorate.Count - 1 do
        Result.Add(Decorate[Indice].Value);
    finally
      Decorate.Free;
    end;
  finally
    Profondita.Free;
  end;
end;

// I contenitori della form stanno in tre tabelle (gruppi, pannelli a schede,
// schede) ma formano un albero solo: un gruppo puo' stare in una scheda, un
// pannello in un gruppo. L'identita' e' nome + tipo; il padre di una scheda,
// se il file non lo dice, e' il suo pannello (come fa TABS_SAVE).
class function TMetadataTransfer.OrdinaContenitori(const Righe: array of TJSONArray; DalBasso: Boolean): TList<TPair<string, TJSONObject>>;
var
  Profondita: TDictionary<string, Integer>;
  Decorate: TList<TPair<Integer, TPair<string, TJSONObject>>>;
  Indice, Livello, Giro: Integer;
  Elemento: TJSONValue;
  Coppia: TPair<string, TJSONObject>;
  Cambiato: Boolean;
  T: TTabellaBaseWeb;

  function Identita(const Sezione: string; R: TJSONObject): string;
  begin
    Result := Testo(R, 'DATASET') + Separatore + Testo(R, Tabella(Sezione).ColonnaChiave) + Separatore + Tabella(Sezione).TipoContenitore;
  end;

  function IdentitaPadre(const Sezione: string; R: TJSONObject): string;
  var
    Nome, Tipo: string;
  begin
    Nome := Testo(R, 'PARENT_CONTAINER_NAME');
    Tipo := Testo(R, 'PARENT_CONTAINER_TYPE');
    if Nome.IsEmpty and (Sezione = 'formTabs') then
    begin
      Nome := Testo(R, 'TABBED_NAME');
      Tipo := 'tabbed';
    end;
    if Nome.IsEmpty then
      Result := ''
    else
      Result := Testo(R, 'DATASET') + Separatore + Nome + Separatore + Tipo;
  end;

begin
  Result := TList<TPair<string, TJSONObject>>.Create;
  // l'ordine di arrivo e' quello delle sezioni: formGroups, formTabbed, formTabs
  for Indice := 0 to High(Righe) do
  begin
    case Indice of
      0: T := Tabella('formGroups');
      1: T := Tabella('formTabbed');
    else
      T := Tabella('formTabs');
    end;
    if Assigned(Righe[Indice]) then
      for Elemento in Righe[Indice] do
        Result.Add(TPair<string, TJSONObject>.Create(T.Sezione, TJSONObject(Elemento)));
  end;

  Profondita := TDictionary<string, Integer>.Create;
  try
    for Coppia in Result do
      Profondita.AddOrSetValue(Identita(Coppia.Key, Coppia.Value), 0);

    Giro := 0;
    repeat
      Cambiato := False;
      Inc(Giro);
      for Coppia in Result do
        if Profondita.TryGetValue(IdentitaPadre(Coppia.Key, Coppia.Value), Livello) and (Profondita[Identita(Coppia.Key, Coppia.Value)] <> Livello + 1) then
        begin
          Profondita[Identita(Coppia.Key, Coppia.Value)] := Livello + 1;
          Cambiato := True;
        end;
    until (not Cambiato) or (Giro > 50);

    Decorate := TList<TPair<Integer, TPair<string, TJSONObject>>>.Create;
    try
      for Coppia in Result do
        Decorate.Add(TPair<Integer, TPair<string, TJSONObject>>.Create(Profondita[Identita(Coppia.Key, Coppia.Value)], Coppia));
      Decorate.Sort(TComparer<TPair<Integer, TPair<string, TJSONObject>>>.Construct(
        function(const Sinistra, Destra: TPair<Integer, TPair<string, TJSONObject>>): Integer
        begin
          if DalBasso then
            Result := Destra.Key - Sinistra.Key
          else
            Result := Sinistra.Key - Destra.Key;
        end));
      Result.Clear;
      for Indice := 0 to Decorate.Count - 1 do
        Result.Add(Decorate[Indice].Value);
    finally
      Decorate.Free;
    end;
  finally
    Profondita.Free;
  end;
end;

{ TMetadataTransfer: esportazione }

class procedure TMetadataTransfer.AggiungiDataset(Scope: TDictionary<string, Boolean>; const Dataset: string);
begin
  if not Dataset.Trim.IsEmpty then
    Scope.AddOrSetValue(Dataset.Trim.ToUpper, True);
end;

class function TMetadataTransfer.Esporta(Connessione: TFDConnection; const Filtro: TFiltroEsportazione; const Origine: string): TJSONObject;
var
  Scope: TDictionary<string, Boolean>;
  LookupsScelti, PicklistScelte: TDictionary<string, Boolean>;
  Datasets, Lookups, Campi, Righe: TJSONArray;
  Elemento: TJSONValue;
  Riga: TJSONObject;
  T: TTabellaBaseWeb;
  Tabelle: TJSONObject;
  Ambito: TJSONObject;
  ElencoAmbito: TJSONArray;
  Nome, Modulo: string;
  Aggiunti: Integer;
  Giro: Integer;

  function InScope(R: TJSONObject; const Colonna: string): Boolean;
  begin
    Result := Scope.ContainsKey(Testo(R, Colonna).ToUpper);
  end;

  function RigaPulita(R: TJSONObject): TJSONObject;
  begin
    Result := TJSONObject(R.Clone);
    // colonne calcolate o rigenerate dai trigger: non si trasportano
    Result.RemovePair('DM').Free;
    Result.RemovePair('NAME').Free;
    Result.RemovePair('META').Free;
  end;

begin
  Scope := TDictionary<string, Boolean>.Create;
  LookupsScelti := TDictionary<string, Boolean>.Create;
  PicklistScelte := TDictionary<string, Boolean>.Create;
  Datasets := nil;
  Lookups := nil;
  Campi := nil;
  try
    Datasets := Carica(Connessione, Tabella('datasets'), ['']);
    Lookups := Carica(Connessione, Tabella('lookups'), ['']);
    Campi := Carica(Connessione, Tabella('fields'), ['', '']);

    // 1) i dataset che il filtro sceglie
    for Elemento in Datasets do
    begin
      Riga := TJSONObject(Elemento);
      Nome := Testo(Riga, 'DATASET');
      Modulo := Testo(Riga, 'DM');
      if (Length(Filtro.Datasets) > 0) and not Contiene(Filtro.Datasets, Nome) then
        Continue;
      if (Length(Filtro.Dm) > 0) and not Contiene(Filtro.Dm, Modulo) then
        Continue;
      if Contiene(Filtro.EscludiDm, Modulo) then
        Continue;
      AggiungiDataset(Scope, Nome);
    end;

    // 2) lookup e picklist usati dai campi dei dataset scelti, e i dataset
    //    sorgente di quei lookup, finche' l'insieme non cresce piu'
    Giro := 0;
    repeat
      Aggiunti := 0;
      Inc(Giro);
      for Elemento in Campi do
      begin
        Riga := TJSONObject(Elemento);
        if not InScope(Riga, 'DATASET') then
          Continue;
        Nome := Testo(Riga, 'LOOKUP');
        if not Nome.IsEmpty and not LookupsScelti.ContainsKey(Nome.ToUpper) then
        begin
          LookupsScelti.Add(Nome.ToUpper, True);
          Inc(Aggiunti);
        end;
        Nome := Testo(Riga, 'PICKLIST');
        if not Nome.IsEmpty and not PicklistScelte.ContainsKey(Nome.ToUpper) then
        begin
          PicklistScelte.Add(Nome.ToUpper, True);
          Inc(Aggiunti);
        end;
      end;
      for Elemento in Lookups do
      begin
        Riga := TJSONObject(Elemento);
        if LookupsScelti.ContainsKey(Testo(Riga, 'LOOKUP').ToUpper) and not InScope(Riga, 'DATASET') then
        begin
          AggiungiDataset(Scope, Testo(Riga, 'DATASET'));
          Inc(Aggiunti);
        end;
      end;
    until (Aggiunti = 0) or (Giro > 20);

    // 3) il pacchetto
    Result := TJSONObject.Create;
    Result.AddPair('formato', FormatoPacchetto);
    Result.AddPair('origine', TJSONObject.Create.AddPair('database', Origine).AddPair('data', DateToISO8601(Now, False)));
    Ambito := TJSONObject.Create;
    Ambito.AddPair('tutto', TJSONBool.Create(Filtro.Vuoto));
    ElencoAmbito := TJSONArray.Create;
    for Elemento in Datasets do
      if InScope(TJSONObject(Elemento), 'DATASET') then
        ElencoAmbito.Add(Testo(TJSONObject(Elemento), 'DATASET'));
    Ambito.AddPair('datasets', ElencoAmbito);
    Result.AddPair('ambito', Ambito);

    Tabelle := TJSONObject.Create;
    Result.AddPair('tabelle', Tabelle);
    for T in TMetadataTransfer.Tabelle do
    begin
      if T.Sezione = 'datasets' then
        Righe := TJSONArray(Datasets.Clone)
      else
        if T.Sezione = 'lookups' then
          Righe := TJSONArray(Lookups.Clone)
        else
          if T.Sezione = 'fields' then
            Righe := TJSONArray(Campi.Clone)
          else
            if Length(T.Chiavi) = 1 then
              Righe := Carica(Connessione, T, [''])
            else
              Righe := Carica(Connessione, T, ['', '']);
      try
        ElencoAmbito := TJSONArray.Create;
        Tabelle.AddPair(T.Sezione, ElencoAmbito);
        for Elemento in Righe do
        begin
          Riga := TJSONObject(Elemento);
          if Filtro.Vuoto then
            ElencoAmbito.AddElement(RigaPulita(Riga))
          else
            if T.Sezione = 'picklists' then
            begin
              if PicklistScelte.ContainsKey(Testo(Riga, 'PICKLIST').ToUpper) then
                ElencoAmbito.AddElement(RigaPulita(Riga));
            end
            else
              if (T.Sezione = 'lookups') or (T.Sezione = 'lookupColumns') then
              begin
                if LookupsScelti.ContainsKey(Testo(Riga, 'LOOKUP').ToUpper) then
                  ElencoAmbito.AddElement(RigaPulita(Riga));
              end
              else
                if InScope(Riga, 'DATASET') then
                  ElencoAmbito.AddElement(RigaPulita(Riga));
        end;
      finally
        Righe.Free;
      end;
    end;
  finally
    Campi.Free;
    Lookups.Free;
    Datasets.Free;
    PicklistScelte.Free;
    LookupsScelti.Free;
    Scope.Free;
  end;
end;

{ TMetadataTransfer: importazione }

class function TMetadataTransfer.RigheSezione(Pacchetto: TJSONObject; const Sezione: string): TJSONArray;
var
  Tabelle: TJSONValue;
  Valore: TJSONValue;
begin
  Result := nil;
  Tabelle := Pacchetto.GetValue('tabelle');
  if not(Tabelle is TJSONObject) then
    Exit;
  Valore := TJSONObject(Tabelle).GetValue(Sezione);
  if Valore is TJSONArray then
    Result := TJSONArray(Valore);
end;

class function TMetadataTransfer.Importa(Connessione: TFDConnection; Pacchetto: TJSONObject): TJSONObject;
var
  Tutto: Boolean;
  Scope: TDictionary<string, Boolean>;
  LookupsNelFile: TDictionary<string, Boolean>;
  Salvate, Eliminate: TJSONObject;
  Ambito: TJSONValue;
  Elemento: TJSONValue;
  T: TTabellaBaseWeb;
  Righe: TJSONArray;
  Ordinate: TList<TJSONObject>;
  Contenitori: TList<TPair<string, TJSONObject>>;
  Coppia: TPair<string, TJSONObject>;
  Riga: TJSONObject;
  Contatore: Integer;
  TransazioneMia: Boolean;

  procedure Conta(Oggetto: TJSONObject; const Sezione: string; Quanti: Integer);
  begin
    Oggetto.RemovePair(Sezione).Free;
    Oggetto.AddPair(Sezione, TJSONNumber.Create(Quanti));
  end;

  function InScope(R: TJSONObject): Boolean;
  begin
    Result := Tutto or Scope.ContainsKey(Testo(R, 'DATASET').ToUpper);
  end;

  // Cancella le righe di base della tabella che esistono sul database ma non
  // nel file, dentro l'ambito. Le _CUSTOM non si guardano: cadono in cascata
  // con la riga di base, e per il resto restano com'erano.
  function EliminaAssenti(const T: TTabellaBaseWeb; NelFile: TJSONArray; Candidati: TList<TJSONObject>): Integer;
  var
    ChiaviFile: TDictionary<string, Boolean>;
    Voce: TJSONValue;
    R: TJSONObject;
    Valori: TArray<string>;
    Indice: Integer;
  begin
    Result := 0;
    ChiaviFile := TDictionary<string, Boolean>.Create;
    try
      if Assigned(NelFile) then
        for Voce in NelFile do
          ChiaviFile.AddOrSetValue(ChiaveRiga(TJSONObject(Voce), T.Chiavi).ToUpper, True);
      for R in Candidati do
      begin
        if ChiaviFile.ContainsKey(ChiaveRiga(R, T.Chiavi).ToUpper) then
          Continue;
        SetLength(Valori, Length(T.Chiavi));
        for Indice := 0 to High(T.Chiavi) do
          Valori[Indice] := Testo(R, T.Chiavi[Indice]);
        Elimina(Connessione, T, Valori);
        Inc(Result);
      end;
    finally
      ChiaviFile.Free;
    end;
  end;

  function Esistenti(const T: TTabellaBaseWeb): TJSONArray;
  begin
    if Length(T.Chiavi) = 1 then
      Result := Carica(Connessione, T, [''])
    else
      Result := Carica(Connessione, T, ['', '']);
  end;

  function SoloInScope(RigheDate: TJSONArray; const Colonna: string; Insieme: TDictionary<string, Boolean>): TList<TJSONObject>;
  var
    Voce: TJSONValue;
  begin
    Result := TList<TJSONObject>.Create;
    for Voce in RigheDate do
      if Insieme.ContainsKey(Testo(TJSONObject(Voce), Colonna).ToUpper) then
        Result.Add(TJSONObject(Voce));
  end;

  function Tutte(RigheDate: TJSONArray): TList<TJSONObject>;
  var
    Voce: TJSONValue;
  begin
    Result := TList<TJSONObject>.Create;
    for Voce in RigheDate do
      Result.Add(TJSONObject(Voce));
  end;

  procedure EliminaSezione(const Sezione: string; SoloSeTutto: Boolean);
  var
    TabellaCorrente: TTabellaBaseWeb;
    RigheEsistenti: TJSONArray;
    Candidati: TList<TJSONObject>;
    Ordinate: TList<TJSONObject>;
    Indice: Integer;
  begin
    if SoloSeTutto and not Tutto then
      Exit;
    TabellaCorrente := Tabella(Sezione);
    RigheEsistenti := Esistenti(TabellaCorrente);
    try
      if Sezione = 'lookupColumns' then
        Candidati := SoloInScope(RigheEsistenti, 'LOOKUP', LookupsNelFile)
      else
        if TabellaCorrente.ColonnaDataset.IsEmpty or (Sezione = 'lookups') or Tutto then
          Candidati := Tutte(RigheEsistenti)
        else
          Candidati := SoloInScope(RigheEsistenti, 'DATASET', Scope);
      try
        if not TabellaCorrente.ColonnaPadre.IsEmpty then
        begin
          // figli prima dei padri: la _DELETE rifiuta una fascia con figli
          Ordinate := OrdinaPerPadre(RigheEsistenti, TabellaCorrente, True);
          try
            for Indice := Ordinate.Count - 1 downto 0 do
              if not Candidati.Contains(Ordinate[Indice]) then
                Ordinate.Delete(Indice);
            Conta(Eliminate, Sezione, EliminaAssenti(TabellaCorrente, RigheSezione(Pacchetto, Sezione), Ordinate));
          finally
            Ordinate.Free;
          end;
        end
        else
          Conta(Eliminate, Sezione, EliminaAssenti(TabellaCorrente, RigheSezione(Pacchetto, Sezione), Candidati));
      finally
        Candidati.Free;
      end;
    finally
      RigheEsistenti.Free;
    end;
  end;

  procedure EliminaContenitoriAssenti;
  var
    Gruppi, Pannelli, Schede: TJSONArray;
    ChiaviFile: TDictionary<string, Boolean>;
    Sezioni: array [0 .. 2] of string;
    Indice: Integer;
    TabellaCorrente: TTabellaBaseWeb;
    Quanti: array [0 .. 2] of Integer;
    Righe: TJSONArray;
    Elemento: TJSONValue;
    Contenitori: TList<TPair<string, TJSONObject>>;
    Coppia: TPair<string, TJSONObject>;
  begin
    Sezioni[0] := 'formGroups';
    Sezioni[1] := 'formTabbed';
    Sezioni[2] := 'formTabs';
    Gruppi := Esistenti(Tabella('formGroups'));
    Pannelli := Esistenti(Tabella('formTabbed'));
    Schede := Esistenti(Tabella('formTabs'));
    ChiaviFile := TDictionary<string, Boolean>.Create;
    try
      for Indice := 0 to 2 do
      begin
        Quanti[Indice] := 0;
        Righe := RigheSezione(Pacchetto, Sezioni[Indice]);
        if Assigned(Righe) then
          for Elemento in Righe do
            ChiaviFile.AddOrSetValue(Sezioni[Indice] + Separatore + ChiaveRiga(TJSONObject(Elemento), Tabella(Sezioni[Indice]).Chiavi).ToUpper, True);
      end;

      // un albero solo, dalle foglie alla radice, tre tabelle
      Contenitori := OrdinaContenitori([Gruppi, Pannelli, Schede], True);
      try
        for Coppia in Contenitori do
        begin
          if not InScope(Coppia.Value) then
            Continue;
          TabellaCorrente := Tabella(Coppia.Key);
          if ChiaviFile.ContainsKey(Coppia.Key + Separatore + ChiaveRiga(Coppia.Value, TabellaCorrente.Chiavi).ToUpper) then
            Continue;
          Elimina(Connessione, TabellaCorrente, [Testo(Coppia.Value, 'DATASET'), Testo(Coppia.Value, TabellaCorrente.ColonnaChiave)]);
          Indice := IndexStr(Coppia.Key, Sezioni);
          Inc(Quanti[Indice]);
        end;
      finally
        Contenitori.Free;
      end;
      for Indice := 0 to 2 do
        Conta(Eliminate, Sezioni[Indice], Quanti[Indice]);
    finally
      ChiaviFile.Free;
      Schede.Free;
      Pannelli.Free;
      Gruppi.Free;
    end;
  end;

begin
  if not SameText(Testo(Pacchetto, 'formato'), FormatoPacchetto) then
    raise Exception.CreateFmt('Il file non e'' un pacchetto di metadati BaseWeb (formato atteso %s)', [FormatoPacchetto]);

  Scope := TDictionary<string, Boolean>.Create;
  LookupsNelFile := TDictionary<string, Boolean>.Create;
  Result := TJSONObject.Create;
  Salvate := TJSONObject.Create;
  Eliminate := TJSONObject.Create;
  Result.AddPair('salvate', Salvate);
  Result.AddPair('eliminate', Eliminate);
  try
    // ambito: tutto il database, oppure i dataset elencati e quelli presenti nel file
    Tutto := False;
    Ambito := Pacchetto.GetValue('ambito');
    if Ambito is TJSONObject then
    begin
      Tutto := TJSONObject(Ambito).GetValue<Boolean>('tutto', False);
      Righe := TJSONObject(Ambito).GetValue('datasets') as TJSONArray;
      if Assigned(Righe) then
        for Elemento in Righe do
          AggiungiDataset(Scope, Elemento.Value);
    end;
    Righe := RigheSezione(Pacchetto, 'datasets');
    if Assigned(Righe) then
      for Elemento in Righe do
        AggiungiDataset(Scope, Testo(TJSONObject(Elemento), 'DATASET'));
    Righe := RigheSezione(Pacchetto, 'lookups');
    if Assigned(Righe) then
      for Elemento in Righe do
        LookupsNelFile.AddOrSetValue(Testo(TJSONObject(Elemento), 'LOOKUP').ToUpper, True);

    TransazioneMia := not Connessione.InTransaction;
    if TransazioneMia then
      Connessione.StartTransaction;
    try
      DisattivaRigenerazioneMeta(Connessione);
      try
        // 1) SAVE nell'ordine delle dipendenze
        for T in Tabelle do
        begin
          if T.Contenitore then
            Continue;
          Righe := RigheSezione(Pacchetto, T.Sezione);
          if not Assigned(Righe) then
            Continue;
          Contatore := 0;
          Ordinate := OrdinaPerPadre(Righe, T, False);
          try
            for Riga in Ordinate do
            begin
              Salva(Connessione, T, Riga);
              Inc(Contatore);
            end;
          finally
            Ordinate.Free;
          end;
          Conta(Salvate, T.Sezione, Contatore);

          // i contenitori vanno dopo le colonne della griglia e prima dei campi della form
          if T.Sezione = 'gridColumns' then
          begin
            Contenitori := OrdinaContenitori([RigheSezione(Pacchetto, 'formGroups'), RigheSezione(Pacchetto, 'formTabbed'), RigheSezione(Pacchetto, 'formTabs')], False);
            try
              for Coppia in Contenitori do
              begin
                Salva(Connessione, Tabella(Coppia.Key), Coppia.Value);
                Conta(Salvate, Coppia.Key, Salvate.GetValue<Integer>(Coppia.Key, 0) + 1);
              end;
            finally
              Contenitori.Free;
            end;
          end;
        end;

        // 2) DELETE delle righe di base assenti, dalle foglie alla radice
        EliminaSezione('formEmpty', False);
        EliminaSezione('formButtons', False);
        EliminaSezione('formFields', False);
        EliminaContenitoriAssenti;
        EliminaSezione('gridColumns', False);
        EliminaSezione('gridBands', False);
        EliminaSezione('fields', False);
        EliminaSezione('lookupColumns', False);
        // lookup, dataset e picklist si tolgono solo con un pacchetto completo:
        // con un ambito parziale potrebbero servire a dataset fuori ambito
        EliminaSezione('lookups', True);
        EliminaSezione('datasets', True);
        EliminaSezione('picklists', True);

        // 3) META di tutti i dataset, in un colpo solo
        RiattivaRigenerazioneMeta(Connessione);
        RigeneraTuttiIMeta(Connessione);
      except
        // la variabile di contesto sopravvive al rollback: va tolta comunque,
        // altrimenti la connessione torna nel pool con la rigenerazione spenta
        try
          RiattivaRigenerazioneMeta(Connessione);
        except
        end;
        raise;
      end;
      if TransazioneMia then
        Connessione.Commit;
    except
      if TransazioneMia and Connessione.InTransaction then
        Connessione.Rollback;
      raise;
    end;
  except
    Result.Free;
    LookupsNelFile.Free;
    Scope.Free;
    raise;
  end;
  LookupsNelFile.Free;
  Scope.Free;
end;

{ TMetadataTransfer: script SQL }

class function TMetadataTransfer.Letterale(Valore: TJSONValue): string;
begin
  if (Valore = nil) or (Valore is TJSONNull) then
    Result := 'NULL'
  else
    if Valore is TJSONBool then
      Result := IfThen(TJSONBool(Valore).AsBoolean, 'TRUE', 'FALSE')
    else
      if Valore is TJSONNumber then
        Result := TJSONNumber(Valore).ToString
      else
        if Valore.Value.IsEmpty then
          Result := 'NULL'
        else
          Result := QuotedStr(Valore.Value);
end;

class function TMetadataTransfer.ElencoLetterali(const Valori: TList<string>): string;
var
  Voce: string;
begin
  Result := '';
  for Voce in Valori do
    Result := Result + IfThen(Result <> '', ', ') + QuotedStr(Voce);
end;

class function TMetadataTransfer.ScriptSql(Pacchetto: TJSONObject): string;
var
  Script: TStringBuilder;
  Tutto: Boolean;
  Ambito: TJSONValue;
  DatasetsAmbito: TList<string>;
  LookupsNelFile: TList<string>;
  ChiaviGlobaliSezione: TList<string>;
  T: TTabellaBaseWeb;
  Righe: TJSONArray;
  Elemento: TJSONValue;
  Riga: TJSONObject;
  Ordinate: TList<TJSONObject>;
  Contenitori: TList<TPair<string, TJSONObject>>;
  Coppia: TPair<string, TJSONObject>;
  Dataset: string;
  Origine: TJSONValue;

  function Chiamata(const T: TTabellaBaseWeb; R: TJSONObject): string;
  var
    Parametro: string;
    Valori: string;
  begin
    Valori := '';
    for Parametro in T.ParametriSave do
      Valori := Valori + IfThen(Valori <> '', ', ') + Letterale(R.GetValue(Parametro));
    Result := Format('EXECUTE PROCEDURE %s(%s)^', [T.ProceduraSave, Valori]);
  end;

  // le chiavi presenti nel file per un dataset (o un lookup) e una sezione
  function ChiaviNelFile(const Sezione, Dataset: string; const ColonnaPadre: string = 'DATASET'): TList<string>;
  var
    TabellaCorrente: TTabellaBaseWeb;
    RigheSez: TJSONArray;
    Voce: TJSONValue;
  begin
    Result := TList<string>.Create;
    TabellaCorrente := Tabella(Sezione);
    RigheSez := RigheSezione(Pacchetto, Sezione);
    if Assigned(RigheSez) then
      for Voce in RigheSez do
        if SameText(Testo(TJSONObject(Voce), ColonnaPadre), Dataset) then
          Result.Add(Testo(TJSONObject(Voce), TabellaCorrente.ColonnaChiave));
  end;

  function ClausolaNotIn(const Colonna: string; Chiavi: TList<string>): string;
  begin
    if Chiavi.Count = 0 then
      Result := ''
    else
      Result := Format(' AND %s NOT IN (%s)', [Colonna, ElencoLetterali(Chiavi)]);
  end;

  // Toglie le righe piatte di una tabella del dataset che il file non ha piu'
  procedure PuliziaPiatta(const Sezione, Dataset: string);
  var
    TabellaCorrente: TTabellaBaseWeb;
    Chiavi: TList<string>;
    Colonna: string;
  begin
    TabellaCorrente := Tabella(Sezione);
    Colonna := TabellaCorrente.Tabella + '.' + TabellaCorrente.ColonnaChiave;
    Chiavi := ChiaviNelFile(Sezione, Dataset);
    try
      Script.AppendLine('EXECUTE BLOCK AS');
      Script.AppendLine('DECLARE VARIABLE CHIAVE BASE_WEB_IDENTIFIER;');
      Script.AppendLine('BEGIN');
      Script.AppendLine(Format('  FOR SELECT %s FROM %s WHERE %s.DATASET = %s%s INTO :CHIAVE DO', [Colonna, TabellaCorrente.Tabella, TabellaCorrente.Tabella, QuotedStr(Dataset), ClausolaNotIn(Colonna, Chiavi)]));
      Script.AppendLine(Format('    EXECUTE PROCEDURE %s(%s, :CHIAVE);', [TabellaCorrente.ProceduraDelete, QuotedStr(Dataset)]));
      Script.AppendLine('END^');
      Script.AppendLine;
    finally
      Chiavi.Free;
    end;
  end;

  // Le fasce formano un albero: dalle foglie alla radice con una CTE ricorsiva.
  // Gli alias sono ammessi perche' la stessa tabella compare due volte con
  // ruoli diversi (fascia figlia, fascia padre).
  procedure PuliziaFasce(const Dataset: string);
  var
    Chiavi: TList<string>;
  begin
    Chiavi := ChiaviNelFile('gridBands', Dataset);
    try
      Script.AppendLine('EXECUTE BLOCK AS');
      Script.AppendLine('DECLARE VARIABLE CHIAVE BASE_WEB_IDENTIFIER;');
      Script.AppendLine('BEGIN');
      Script.AppendLine('  FOR WITH RECURSIVE ALBERO AS (');
      Script.AppendLine('        SELECT BASE_WEB_GRID_BANDS.BAND_NAME, 0 AS LIVELLO');
      Script.AppendLine('        FROM BASE_WEB_GRID_BANDS');
      Script.AppendLine(Format('        WHERE BASE_WEB_GRID_BANDS.DATASET = %s AND BASE_WEB_GRID_BANDS.PARENT_BAND IS NULL', [QuotedStr(Dataset)]));
      Script.AppendLine('        UNION ALL');
      Script.AppendLine('        SELECT FASCIA_FIGLIA.BAND_NAME, FASCIA_PADRE.LIVELLO + 1');
      Script.AppendLine('        FROM BASE_WEB_GRID_BANDS FASCIA_FIGLIA');
      Script.AppendLine('        JOIN ALBERO FASCIA_PADRE ON FASCIA_FIGLIA.PARENT_BAND = FASCIA_PADRE.BAND_NAME');
      Script.AppendLine(Format('        WHERE FASCIA_FIGLIA.DATASET = %s)', [QuotedStr(Dataset)]));
      Script.AppendLine(Format('      SELECT ALBERO.BAND_NAME FROM ALBERO WHERE 1 = 1%s', [ClausolaNotIn('ALBERO.BAND_NAME', Chiavi)]));
      Script.AppendLine('      ORDER BY ALBERO.LIVELLO DESC');
      Script.AppendLine('      INTO :CHIAVE DO');
      Script.AppendLine(Format('    EXECUTE PROCEDURE %s(%s, :CHIAVE);', [Tabella('gridBands').ProceduraDelete, QuotedStr(Dataset)]));
      Script.AppendLine('END^');
      Script.AppendLine;
    finally
      Chiavi.Free;
    end;
  end;

  // I contenitori della form: un albero su tre tabelle, dalle foglie alla
  // radice, con la procedura di cancellazione scelta dal tipo.
  procedure PuliziaContenitori(const Dataset: string);
  var
    Gruppi, Pannelli, Schede: TList<string>;
    Esclusioni: string;

    function Esclusione(const Tipo: string; Chiavi: TList<string>): string;
    begin
      if Chiavi.Count = 0 then
        Result := ''
      else
        Result := Format(' AND NOT (ALBERO.CONTAINER_TYPE = %s AND ALBERO.CONTAINER_NAME IN (%s))', [QuotedStr(Tipo), ElencoLetterali(Chiavi)]);
    end;

  begin
    Gruppi := ChiaviNelFile('formGroups', Dataset);
    Pannelli := ChiaviNelFile('formTabbed', Dataset);
    Schede := ChiaviNelFile('formTabs', Dataset);
    try
      Esclusioni := Esclusione('group', Gruppi) + Esclusione('tabbed', Pannelli) + Esclusione('tab', Schede);
      Script.AppendLine('EXECUTE BLOCK AS');
      Script.AppendLine('DECLARE VARIABLE CHIAVE BASE_WEB_IDENTIFIER;');
      Script.AppendLine('DECLARE VARIABLE TIPO BASE_WEB_CONTAINER_TYPE;');
      Script.AppendLine('BEGIN');
      Script.AppendLine('  FOR WITH RECURSIVE ALBERO AS (');
      Script.AppendLine('        SELECT BASE_WEB_FORM_CONTAINER.CONTAINER_NAME, BASE_WEB_FORM_CONTAINER.CONTAINER_TYPE, 0 AS LIVELLO');
      Script.AppendLine('        FROM BASE_WEB_FORM_CONTAINER');
      Script.AppendLine(Format('        WHERE BASE_WEB_FORM_CONTAINER.DATASET = %s AND BASE_WEB_FORM_CONTAINER.PARENT_CONTAINER_NAME IS NULL', [QuotedStr(Dataset)]));
      Script.AppendLine('        UNION ALL');
      Script.AppendLine('        SELECT CONTENITORE_FIGLIO.CONTAINER_NAME, CONTENITORE_FIGLIO.CONTAINER_TYPE, CONTENITORE_PADRE.LIVELLO + 1');
      Script.AppendLine('        FROM BASE_WEB_FORM_CONTAINER CONTENITORE_FIGLIO');
      Script.AppendLine('        JOIN ALBERO CONTENITORE_PADRE ON CONTENITORE_FIGLIO.PARENT_CONTAINER_NAME = CONTENITORE_PADRE.CONTAINER_NAME AND CONTENITORE_FIGLIO.PARENT_CONTAINER_TYPE = CONTENITORE_PADRE.CONTAINER_TYPE');
      Script.AppendLine(Format('        WHERE CONTENITORE_FIGLIO.DATASET = %s)', [QuotedStr(Dataset)]));
      Script.AppendLine(Format('      SELECT ALBERO.CONTAINER_NAME, ALBERO.CONTAINER_TYPE FROM ALBERO WHERE 1 = 1%s', [Esclusioni]));
      Script.AppendLine('      ORDER BY ALBERO.LIVELLO DESC');
      Script.AppendLine('      INTO :CHIAVE, :TIPO DO');
      Script.AppendLine('  BEGIN');
      Script.AppendLine(Format('    IF (TIPO = ''group'') THEN EXECUTE PROCEDURE %s(%s, :CHIAVE);', [Tabella('formGroups').ProceduraDelete, QuotedStr(Dataset)]));
      Script.AppendLine(Format('    ELSE IF (TIPO = ''tabbed'') THEN EXECUTE PROCEDURE %s(%s, :CHIAVE);', [Tabella('formTabbed').ProceduraDelete, QuotedStr(Dataset)]));
      Script.AppendLine(Format('    ELSE EXECUTE PROCEDURE %s(%s, :CHIAVE);', [Tabella('formTabs').ProceduraDelete, QuotedStr(Dataset)]));
      Script.AppendLine('  END');
      Script.AppendLine('END^');
      Script.AppendLine;
    finally
      Schede.Free;
      Pannelli.Free;
      Gruppi.Free;
    end;
  end;

  // Righe di una tabella senza dataset (lookup, dataset, picklist) che il file non ha
  procedure PuliziaGlobale(const Sezione: string; Chiavi: TList<string>);
  var
    TabellaCorrente: TTabellaBaseWeb;
    Colonna: string;
  begin
    TabellaCorrente := Tabella(Sezione);
    Colonna := TabellaCorrente.Tabella + '.' + TabellaCorrente.ColonnaChiave;
    Script.AppendLine('EXECUTE BLOCK AS');
    Script.AppendLine('DECLARE VARIABLE CHIAVE BASE_WEB_IDENTIFIER;');
    Script.AppendLine('BEGIN');
    Script.AppendLine(Format('  FOR SELECT %s FROM %s WHERE 1 = 1%s INTO :CHIAVE DO', [Colonna, TabellaCorrente.Tabella, ClausolaNotIn(Colonna, Chiavi)]));
    Script.AppendLine(Format('    EXECUTE PROCEDURE %s(:CHIAVE);', [TabellaCorrente.ProceduraDelete]));
    Script.AppendLine('END^');
    Script.AppendLine;
  end;

  function ChiaviGlobali(const Sezione: string): TList<string>;
  var
    RigheSez: TJSONArray;
    Voce: TJSONValue;
  begin
    Result := TList<string>.Create;
    RigheSez := RigheSezione(Pacchetto, Sezione);
    if Assigned(RigheSez) then
      for Voce in RigheSez do
        Result.Add(Testo(TJSONObject(Voce), Tabella(Sezione).ColonnaChiave));
  end;

  // Toglie le colonne di un lookup presente nel file che il file non ha piu'
  procedure PuliziaColonneLookup(const Lookup: string);
  var
    Chiavi: TList<string>;
  begin
    Chiavi := ChiaviNelFile('lookupColumns', Lookup, 'LOOKUP');
    try
      Script.AppendLine('EXECUTE BLOCK AS');
      Script.AppendLine('DECLARE VARIABLE CHIAVE BASE_WEB_IDENTIFIER;');
      Script.AppendLine('BEGIN');
      Script.AppendLine(Format('  FOR SELECT BASE_WEB_LOOKUPS_COLUMNS.FIELD FROM BASE_WEB_LOOKUPS_COLUMNS WHERE BASE_WEB_LOOKUPS_COLUMNS.LOOKUP = %s%s INTO :CHIAVE DO',
        [QuotedStr(Lookup), ClausolaNotIn('BASE_WEB_LOOKUPS_COLUMNS.FIELD', Chiavi)]));
      Script.AppendLine(Format('    EXECUTE PROCEDURE %s(%s, :CHIAVE);', [Tabella('lookupColumns').ProceduraDelete, QuotedStr(Lookup)]));
      Script.AppendLine('END^');
      Script.AppendLine;
    finally
      Chiavi.Free;
    end;
  end;

begin
  if not SameText(Testo(Pacchetto, 'formato'), FormatoPacchetto) then
    raise Exception.CreateFmt('Il file non e'' un pacchetto di metadati BaseWeb (formato atteso %s)', [FormatoPacchetto]);

  Script := TStringBuilder.Create;
  DatasetsAmbito := TList<string>.Create;
  LookupsNelFile := TList<string>.Create;
  try
    Tutto := False;
    Ambito := Pacchetto.GetValue('ambito');
    if Ambito is TJSONObject then
    begin
      Tutto := TJSONObject(Ambito).GetValue<Boolean>('tutto', False);
      Righe := TJSONObject(Ambito).GetValue('datasets') as TJSONArray;
      if Assigned(Righe) then
        for Elemento in Righe do
          if not DatasetsAmbito.Contains(Elemento.Value) then
            DatasetsAmbito.Add(Elemento.Value);
    end;
    Righe := RigheSezione(Pacchetto, 'datasets');
    if Assigned(Righe) then
      for Elemento in Righe do
      begin
        Dataset := Testo(TJSONObject(Elemento), 'DATASET');
        if not DatasetsAmbito.Contains(Dataset) then
          DatasetsAmbito.Add(Dataset);
      end;
    Righe := RigheSezione(Pacchetto, 'lookups');
    if Assigned(Righe) then
      for Elemento in Righe do
        LookupsNelFile.Add(Testo(TJSONObject(Elemento), 'LOOKUP'));

    Script.AppendLine('-- ============================================================================');
    Script.AppendLine('-- Metadati BaseWeb: allineamento al master, scritto da zServer dal pacchetto JSON');
    Origine := Pacchetto.GetValue('origine');
    if Origine is TJSONObject then
      Script.AppendLine(Format('-- Origine: %s, %s', [Testo(TJSONObject(Origine), 'database'), Testo(TJSONObject(Origine), 'data')]));
    Script.AppendLine(Format('-- Ambito: %s', [IfThen(Tutto, 'tutto il database', String.Join(', ', DatasetsAmbito.ToArray))]));
    Script.AppendLine('-- Le _CUSTOM non vengono toccate. Richiede il pacchetto BASE_WEB_TABLE_IO con');
    Script.AppendLine('-- le procedure *_DELETE e BASE_WEB_DATASETS_SET_AUTHORIZATION.');
    Script.AppendLine('-- ============================================================================');
    Script.AppendLine;
    Script.AppendLine('SET TERM ^ ;');
    Script.AppendLine;
    Script.AppendLine('EXECUTE BLOCK AS');
    Script.AppendLine('DECLARE VARIABLE ESITO TRUE_FALSE;');
    Script.AppendLine('BEGIN');
    Script.AppendLine('  ESITO = BASE_WEB.META_UPDATE_DISABLE();');
    Script.AppendLine('END^');
    Script.AppendLine;

    // 1) SAVE nell'ordine delle dipendenze
    for T in Tabelle do
    begin
      if T.Contenitore then
        Continue;
      Righe := RigheSezione(Pacchetto, T.Sezione);
      if Assigned(Righe) and (Righe.Count > 0) then
      begin
        Script.AppendLine('-- ' + T.Tabella);
        Ordinate := OrdinaPerPadre(Righe, T, False);
        try
          for Riga in Ordinate do
          begin
            Script.AppendLine(Chiamata(T, Riga));
            if (T.Sezione = 'datasets') and (Riga.GetValue('AUTHORIZATION') <> nil) then
              Script.AppendLine(Format('EXECUTE PROCEDURE %s.BASE_WEB_DATASETS_SET_AUTHORIZATION(%s, %s)^', [NomePacchetto, QuotedStr(Testo(Riga, 'DATASET')), Letterale(Riga.GetValue('AUTHORIZATION'))]));
          end;
        finally
          Ordinate.Free;
        end;
        Script.AppendLine;
      end;

      if T.Sezione = 'gridColumns' then
      begin
        Contenitori := OrdinaContenitori([RigheSezione(Pacchetto, 'formGroups'), RigheSezione(Pacchetto, 'formTabbed'), RigheSezione(Pacchetto, 'formTabs')], False);
        try
          if Contenitori.Count > 0 then
          begin
            Script.AppendLine('-- BASE_WEB_FORM_GROUPS, BASE_WEB_FORM_TABBED, BASE_WEB_FORM_TABS (per profondita'')');
            for Coppia in Contenitori do
              Script.AppendLine(Chiamata(Tabella(Coppia.Key), Coppia.Value));
            Script.AppendLine;
          end;
        finally
          Contenitori.Free;
        end;
      end;
    end;

    // 2) DELETE delle righe di base assenti, dalle foglie alla radice
    Script.AppendLine('-- Righe di base che il master non ha piu''');
    for Dataset in DatasetsAmbito do
    begin
      PuliziaPiatta('formEmpty', Dataset);
      PuliziaPiatta('formButtons', Dataset);
      PuliziaPiatta('formFields', Dataset);
      PuliziaContenitori(Dataset);
      PuliziaPiatta('gridColumns', Dataset);
      PuliziaFasce(Dataset);
      PuliziaPiatta('fields', Dataset);
    end;
    // colonne dei lookup presenti nel file
    for Dataset in LookupsNelFile do
      PuliziaColonneLookup(Dataset);
    if Tutto then
    begin
      // prima i lookup (un dataset sorgente di un lookup non si cancella), poi i dataset, poi le picklist
      ChiaviGlobaliSezione := ChiaviGlobali('lookups');
      try
        PuliziaGlobale('lookups', ChiaviGlobaliSezione);
      finally
        ChiaviGlobaliSezione.Free;
      end;
      ChiaviGlobaliSezione := ChiaviGlobali('datasets');
      try
        PuliziaGlobale('datasets', ChiaviGlobaliSezione);
      finally
        ChiaviGlobaliSezione.Free;
      end;
      ChiaviGlobaliSezione := ChiaviGlobali('picklists');
      try
        PuliziaGlobale('picklists', ChiaviGlobaliSezione);
      finally
        ChiaviGlobaliSezione.Free;
      end;
    end;

    // 3) META di tutti i dataset
    Script.AppendLine('EXECUTE BLOCK AS');
    Script.AppendLine('DECLARE VARIABLE ESITO TRUE_FALSE;');
    Script.AppendLine('BEGIN');
    Script.AppendLine('  ESITO = BASE_WEB.META_UPDATE_ENABLE(NULL);');
    Script.AppendLine('  ESITO = BASE_WEB.DATASET_BUILD_ALL_META();');
    Script.AppendLine('END^');
    Script.AppendLine;
    Script.AppendLine('COMMIT^');
    Script.AppendLine;
    Script.AppendLine('SET TERM ; ^');

    Result := Script.ToString;
  finally
    LookupsNelFile.Free;
    DatasetsAmbito.Free;
    Script.Free;
  end;
end;

end.
