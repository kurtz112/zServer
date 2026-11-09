// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-08
// ---------------------------------------------------------------------------
unit WT.Profile;

// Profilo applicativo di WinTarif.
//
// Firme verificate sul database WT il 2026-09-15:
// USR_LOGIN       ingresso: APP, USER_NAME, PASSWORD_, COMPUTER_NAME,
// COMPUTER_USER_NAME, SKIP_CREATE_SESSION
// uscita:   USER_ID, ID_SESSIONE, NOMINATIVO,
// DATA_SCADENZA_PASSWORD, RUOLO, ADMIN_USER, OTP
// USR_CONTEXT_SET ingresso: ID_SESSIONE, USER_ID, USER_NAME, ID_INTESTATARIO
//
// Due differenze rispetto a Gesty valgono la pena di essere scritte:
//
// 1. USR_LOGIN di WT verifica l'abilitazione all'applicativo con
// USR_GET_USER_APPS e solleva 'Utente non abilitato per questa
// applicazione.'. Senza la riga in USR_APPS e senza i gruppi, nessuno
// entra: vedi lo script db\06-wt-abilitazione-utenti.sql.
//
// 2. WT restituisce RUOLO dove Gesty restituisce TIPO_USER. Il nucleo li
// tratta come la stessa cosa (TAuthResult.Ruolo): prima il codice leggeva
// TIPO_USER con valore predefinito vuoto, quindi su WT non sollevava
// errori e semplicemente non assegnava nessun ruolo oltre a 'user'.
//
// Aree (2026-11-02, fase 0 di OUT\20261102-pipa-inizializzazione-progetto):
// ogni area web e' un'app di USR_APPS con TIPO_APP = 'W'. USR_LOGIN resta
// com'era e vuole l'app con cui si entra: la sceglie AutenticaInArea fra le
// aree dell'utente (USR_UTENTE_AREE_WEB), cosi' fascia oraria e secondo
// fattore valgono per l'area. Il cambio d'area passa da USR_SESSIONE_APP_SET,
// che ripete gli stessi controlli, e l'area attiva sta in USR_SESSIONI.APP.
//
// Moduli (2026-11-06, OUT\20261106-pipa-sportello-comuni-funzioni-per-comune):
// i moduli dell'utente vengono da USR_UTENTE_MODULI_WEB (script WT-MODULI-01),
// che forma la coppia modulo-comune dentro ogni gruppo prima di unire i gruppi.
// Per un dataset o una procedura con un modulo, USR_TMP_COMUNI della richiesta
// perde i comuni in cui l'utente non ha quel modulo: tutto cio' che gia' filtra
// su USR_TMP_COMUNI (ClausolaPerimetro, AmbitoAmmesso, le procedure web come
// WTWEB_SPORTELLO_PERIMETRO e WTWEB_SPORTELLO_RICHIESTA_*) resta cosi' ai comuni
// del modulo senza cambiare una riga.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  MVCFramework,
  App.Profile,
  App.Profile.Base;

type
  TWTProfile = class(TAppProfileBase, IAppProfile)
  private
    // Relazioni gia' interrogate: True se hanno la colonna BELFIORE. Il
    // dizionario e' condiviso fra i thread delle richieste, da cui il
    // lucchetto; una relazione si interroga una volta per processo.
    class var FRelazioniConBelfiore: TDictionary<string, Boolean>;
    class var FLucchetto: TCriticalSection;
    class constructor Create;
    class destructor Destroy;
    function LeggiIdIntestatario(Connessione: TFDConnection; const UserId, IdSessione: Int64): Int64;
    function RelazioneHaBelfiore(const NomeRelazione: string): Boolean;
    function AutenticaConApp(const UserName, Password, App: string): TAuthResult;
    function AreeWeb(const UserName: string): TArray<string>;
    function AreaDellaSessione(const IdSessione: Int64): string;
  public
    function Codice: string;
    function CodiceApplicativo: string;
    function Autentica(const UserName, Password: string): TAuthResult;
    function AutenticaInArea(const UserName, Password, Area: string): TAuthResult; override;
    procedure LeggiAree(const UserName: string; const IdSessione: Int64; out Aree: TArray<string>; out Area: string); override;
    procedure CambiaArea(const IdSessione: Int64; const Area: string); override;
    function AmmessoNellArea(const IdSessione: Int64; const Tipo, Nome: string): Boolean; override;
    procedure ImpostaContesto(Connessione: TFDConnection; const UserId, IdSessione: Int64; const UserName: string);
    procedure AzzeraContesto(Connessione: TFDConnection);
    function ClausolaPerimetro(const NomeRelazione: string): string;
    function AmbitoAmmesso(const Belfiore: string; const IdAzienda: Int64): Boolean;
    function ClasseDocumentale(const NomeEntita: string): string;
    function PercorsoFile(const IdObjectFile, IdSessione: Int64): string;
    function OggettoAmmesso(const Oid, IdSessione: Int64): Boolean; override;
    function ModuliUtente(const UserName: string): TModuliUtente; override;
    procedure RestringiComuniDellaRichiesta(const Comuni: TArray<string>); override;
    function ModuloAttivoPerAzienda(const UserName, Modulo: string): Boolean; override;
    function ModuloAttivoPerCittadino(const UserName, Modulo: string): Boolean; override;
    function ModuliCittadino(const UserName: string): TModuliUtente; override;
    function ModuloAttivoPerGruppo(const UserName, Modulo: string; const Scrittura: Boolean): Boolean; override;
    function ModuliGruppo(const UserName: string): TModuliUtente; override;
    function ControllerDiDominio: TArray<TMVCControllerClazz>;
    function AzioniPubbliche: TArray<string>;
  end;

implementation

uses
  System.Variants,
  System.StrUtils,
  System.JSON,
  MVCFramework.Logger,
  Data.Service,
  Connection.Pool,
  Json.Values,
  WT.Admin.Controller,
  WT.Geco.Controller,
  WT.Tvb.Controller,
  WT.Anpr.Controller,
  WT.Agora.Controller,
  WT.Cittadino.Controller,
  WT.CdrPubblico.Controller
{$IFDEF WT_CONTROLLER_NETA}
{$IFDEF MSWINDOWS}
  , WT.Neta.Controller
{$ENDIF}
{$ENDIF};

const
  // Applicativo registrato in USR_APPS. WTWEB_SPORTELLO esiste gia ed e' lo
  // sportello dell'operatore: si riusa quello invece di introdurre un codice
  // nuovo da abilitare a mano su ogni installazione.
  APPLICATIVO = 'WTWEB_SPORTELLO';

  NOME_POSTAZIONE = 'zServer';

  // La sessione sul database viene creata al login e il suo identificativo
  // viaggia nel token: a ogni richiesta successiva USR_CONTEXT_SET la
  // riassocia alla connessione presa dal raggruppamento.
  //
  // Il documento di intervento proponeva SKIP_CREATE_SESSION = TRUE, che
  // rende il server senza stato. Non si puo' fare qui: le procedure dei
  // moduli portati (WEB_CONFIG_GET, WEB_GET_FILE_NAME, WEB_ANPR_CONFIG_GET,
  // WEB_GET_INTESTATARIO_LOGIN e le altre) prendono ID_SESSIONE_WEB e senza
  // una sessione vera restituiscono niente. Con TRUE, inoltre, USR_LOGIN
  // esce prima di valorizzare ID_SESSIONE, che resterebbe nullo nel token.
  SALTA_CREAZIONE_SESSIONE = False;

{ TWTProfile }

class constructor TWTProfile.Create;
begin
  FRelazioniConBelfiore := TDictionary<string, Boolean>.Create;
  FLucchetto := TCriticalSection.Create;
end;

class destructor TWTProfile.Destroy;
begin
  FreeAndNil(FRelazioniConBelfiore);
  FreeAndNil(FLucchetto);
end;

function TWTProfile.Codice: string;
begin
  Result := 'WT';
end;

function TWTProfile.CodiceApplicativo: string;
begin
  Result := APPLICATIVO;
end;

function TWTProfile.Autentica(const UserName, Password: string): TAuthResult;
begin
  Result := AutenticaConApp(UserName, Password, CodiceApplicativo);
end;

// L'app con cui si entra: l'area chiesta se e' fra quelle dell'utente,
// altrimenti lo sportello (cosi' Agora', che non chiede aree, entra come
// prima), altrimenti la prima area dell'utente. Senza nessuna area si entra
// con lo sportello: USR_LOGIN rifiuta come oggi, con lo stesso messaggio e la
// stessa riga in USR_EVENTI_SICUREZZA.
//
// Le aree si leggono prima della password, ma restano qui dentro: chi
// sbaglia la password riceve lo stesso 401, abbia o no delle aree.
function TWTProfile.AutenticaInArea(const UserName, Password, Area: string): TAuthResult;
var
  Aree: TArray<string>;
  App: string;
begin
  Aree := AreeWeb(UserName);

  if (not Area.Trim.IsEmpty) and MatchText(Area.Trim, Aree) then
    App := Area.Trim.ToUpper
  else
    if MatchText(CodiceApplicativo, Aree) or (Length(Aree) = 0) then
      App := CodiceApplicativo
    else
      App := Aree[0];

  Result := AutenticaConApp(UserName, Password, App);

  if Result.Success then
  begin
    Result.Aree := Aree;
    Result.Area := App;
  end;
end;

// Aree web dell'utente. Un errore (procedura assente perche' lo script della
// fase 0 non e' ancora passato) lascia l'elenco vuoto: si entra con lo
// sportello come prima delle aree.
function TWTProfile.AreeWeb(const UserName: string): TArray<string>;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
begin
  Result := [];

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    try
      Righe := TDataService.ExecuteQuery('SELECT USR_UTENTE_AREE_WEB.APP FROM USR_UTENTE_AREE_WEB(:USER_NAME)', Parametri, False);
      try
        for Riga in Righe do
          if Riga is TJSONObject then
            Result := Result + [JsonStr(TJSONObject(Riga), 'APP')];
      finally
        FreeAndNil(Righe);
      end;
    except
      on E: Exception do
        LogW('Aree web non lette, si entra con lo sportello: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTProfile.AreaDellaSessione(const IdSessione: Int64): string;
var
  Parametri: TParamValues;
  Riga: TJSONObject;
begin
  Result := '';

  if IdSessione <= 0 then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Riga := TDataService.ExecuteQuerySingleRow('SELECT USR_SESSIONI.APP FROM USR_SESSIONI WHERE USR_SESSIONI.ID_SESSIONE = :ID_SESSIONE', Parametri, False);
    try
      Result := JsonStr(Riga, 'APP');
    finally
      FreeAndNil(Riga);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTProfile.LeggiAree(const UserName: string; const IdSessione: Int64; out Aree: TArray<string>; out Area: string);
begin
  Aree := AreeWeb(UserName);
  Area := AreaDellaSessione(IdSessione);
end;

// I controlli (area dell'utente, fascia oraria, secondo fattore, sessione
// dell'utente collegato) li fa la procedura sulla connessione con il
// contesto dell'utente: un rifiuto e' un'eccezione di Firebird, che il
// controller trasforma in 400 con la frase della procedura.
procedure TWTProfile.CambiaArea(const IdSessione: Int64; const Area: string);
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Parametri.Add('APP', Area.Trim.ToUpper);
    Esito := TDataService.ExecuteStoredProc('USR_SESSIONE_APP_SET', Parametri);
    FreeAndNil(Esito);
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTProfile.AmmessoNellArea(const IdSessione: Int64; const Tipo, Nome: string): Boolean;
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Parametri.Add('TIPO', Tipo);
    Parametri.Add('NOME', Nome);
    Result := TDataService.ExecuteScalar('SELECT IIF(BASE_WEB_AREA_AMMESSO.AMMESSO, 1, 0) FROM BASE_WEB_AREA_AMMESSO(:ID_SESSIONE, :TIPO, :NOME)', Parametri) = 1;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTProfile.AutenticaConApp(const UserName, Password, App: string): TAuthResult;
var
  Parametri: TParamValues;
  Uscita: TJSONObject;
begin
  Result.Clear;

  try
    Parametri := TParamValues.Create;
    try
      Parametri.Add('APP', App);
      Parametri.Add('USER_NAME', UserName);
      Parametri.Add('PASSWORD_', Password);
      Parametri.Add('COMPUTER_NAME', NOME_POSTAZIONE);
      Parametri.Add('COMPUTER_USER_NAME', UserName);
      Parametri.Add('SKIP_CREATE_SESSION', SALTA_CREAZIONE_SESSIONE);

      Uscita := EseguiLogin(Parametri);
      try
        if not Assigned(Uscita) then
        begin
          Result.ErrorMessage := 'USR_LOGIN non ha restituito alcun risultato';
          Exit;
        end;

        Result.UserId := JsonInt64(Uscita, 'USER_ID');

        if Result.UserId <= 0 then
        begin
          Result.CredenzialiNonValide := True;
          Result.ErrorMessage := 'Credenziali non valide';
          Exit;
        end;

        Result.Success := True;
        Result.IdSessione := JsonInt64(Uscita, 'ID_SESSIONE');
        Result.Nominativo := JsonStr(Uscita, 'NOMINATIVO');
        Result.Ruolo := JsonStr(Uscita, 'RUOLO');
        Result.DataScadenzaPassword := JsonDate(Uscita, 'DATA_SCADENZA_PASSWORD');
        Result.AdminUser := JsonBool(Uscita, 'ADMIN_USER');
        Result.RichiedeOtp := JsonBool(Uscita, 'OTP');
        // HOST_LDAP non esiste in WT: resta vuoto.

        LogI(Format('Accesso riuscito: %s (utente %d, sessione %d, ruolo %s, app %s)', [Result.Nominativo, Result.UserId, Result.IdSessione, Result.Ruolo, App]));
      finally
        FreeAndNil(Uscita);
      end;
    finally
      FreeAndNil(Parametri);
    end;
  except
    on E: Exception do
      Result := EsitoNegativo(E);
  end;
end;

// USR_CONTEXT_SET di WT vuole ID_INTESTATARIO come quarto parametro: e' il
// contribuente collegato all'utente, e serve alle installazioni dove la
// stessa banca dati serve anche lo sportello del cittadino.
//
// La lettura usa la connessione che si sta dichiarando, passata dal
// raggruppamento. Chiederne una al raggruppamento sarebbe una chiamata
// ricorsiva: prendere una connessione dichiara il contesto, e dichiarare il
// contesto prenderebbe un'altra connessione, senza fine.
//
// Il cittadino entrato con SPID non ha un intestatario fisso sull'utente: lo sceglie
// (o gli viene assegnato se e' unico) e la scelta sta in USR_SPID_AUTHORIZATIONS,
// per sessione. Prima si leggeva solo USR_UTENTI.ID_INTESTATARIO, quindi per lui il
// contesto restava senza intestatario a ogni richiesta, anche dopo la scelta. Ora la
// scelta della sessione ha la precedenza; senza sessione o senza scelta vale
// l'intestatario dell'utente come prima (accesso a password invariato).
function TWTProfile.LeggiIdIntestatario(Connessione: TFDConnection; const UserId, IdSessione: Int64): Int64;
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('UID', UserId);
    Parametri.Add('SID', IdSessione);
    Result := TDataService.ExecuteScalar(Connessione,
      'SELECT COALESCE((SELECT USR_SPID_AUTHORIZATIONS.ID_INTESTATARIO_SELEZIONATO FROM USR_SPID_AUTHORIZATIONS ' +
      'WHERE USR_SPID_AUTHORIZATIONS.ID_SESSIONE = :SID), USR_UTENTI.ID_INTESTATARIO, -1) ' +
      'FROM USR_UTENTI WHERE USR_UTENTI.USER_ID = :UID', Parametri);
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTProfile.ImpostaContesto(Connessione: TFDConnection; const UserId, IdSessione: Int64; const UserName: string);
var
  IdIntestatario: Int64;
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    if IdSessione > 0 then
      Parametri.Add('ID_SESSIONE', IdSessione)
    else
      Parametri.Add('ID_SESSIONE', Null);

    Parametri.Add('USER_ID', UserId);
    Parametri.Add('USER_NAME', UserName);

    IdIntestatario := LeggiIdIntestatario(Connessione, UserId, IdSessione);

    if IdIntestatario > 0 then
      Parametri.Add('ID_INTESTATARIO', IdIntestatario)
    else
      Parametri.Add('ID_INTESTATARIO', Null);

    EseguiContextSet(Connessione, Parametri);
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTProfile.AzzeraContesto(Connessione: TFDConnection);
begin
  EseguiContextClear(Connessione);
end;

// Il perimetro non si fida di quello che arriva dal browser: USR_TMP_COMUNI
// e' riempita da USR_FILL_TABELLE_TMP a partire dai gruppi dell'utente, ed
// e' quindi per utente e non falsificabile. Il comune scelto dall'operatore
// serve solo a restringere ulteriormente la vista (segnaposto :##BELFIORE).
//
// La clausola si applica solo alle relazioni che hanno la colonna BELFIORE
// (decisione 17 di OUT\20261006-zserver-agora-anpr-firma-file-pdf): prima
// veniva aggiunta a qualunque dataset, e su una relazione senza quella
// colonna, come un elenco di tipologie o di operatori, la SELECT falliva
// con "column unknown". Le viste per comune (contribuenti, ticket e i loro
// dettagli) devono quindi esporre BELFIORE, altrimenti escono dal perimetro.
function TWTProfile.ClausolaPerimetro(const NomeRelazione: string): string;
begin
  if NomeRelazione.Trim.IsEmpty then
    Exit('');

  if not RelazioneHaBelfiore(NomeRelazione) then
    Exit('');

  Result := Format('%s.BELFIORE IN (SELECT USR_TMP_COMUNI.BELFIORE FROM USR_TMP_COMUNI)', [NomeRelazione]);
end;

// Moduli dell'utente comune per comune. Un errore (procedura assente perche'
// lo script WT-MODULI-01 non e' ancora passato) lascia l'elenco vuoto: senza
// lo script nessun dataset ha un modulo, quindi non si nega niente a nessuno.
function TWTProfile.ModuliUtente(const UserName: string): TModuliUtente;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Modulo: TModuloUtente;
begin
  Result := [];

  if UserName.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    try
      Righe := TDataService.ExecuteQuery(
        'SELECT USR_UTENTE_MODULI_WEB.MODULO, USR_UTENTE_MODULI_WEB.BELFIORE, USR_UTENTE_MODULI_WEB.ACCESS ' +
        'FROM USR_UTENTE_MODULI_WEB(:USER_NAME)', Parametri, False);
      try
        for Riga in Righe do
          if Riga is TJSONObject then
          begin
            Modulo.Modulo := JsonStr(TJSONObject(Riga), 'MODULO').Trim;
            Modulo.Belfiore := JsonStr(TJSONObject(Riga), 'BELFIORE').Trim;
            Modulo.Scrittura := SameText(JsonStr(TJSONObject(Riga), 'ACCESS').Trim, 'W');
            Result := Result + [Modulo];
          end;
      finally
        FreeAndNil(Righe);
      end;
    except
      on E: Exception do
        LogW('Moduli web non letti, l''utente resta senza moduli: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Moduli per azienda (GeCo, script WT-MODULI-05 del rilascio 010): la
// procedura USR_UTENTE_MODULI_AZIENDE_WEB dice quali moduli l'utente ha attivi
// nelle aziende dei suoi gruppi. Un errore (procedura assente perche' lo
// script non e' ancora passato) nega: i dataset con il modulo di GeCo nascono
// con lo stesso script, quindi non si trovano mai da una parte senza l'altra.
function TWTProfile.ModuloAttivoPerAzienda(const UserName, Modulo: string): Boolean;
var
  Parametri: TParamValues;
begin
  Result := False;

  if UserName.Trim.IsEmpty or Modulo.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    Parametri.Add('MODULO', Modulo);
    try
      Result := TDataService.ExecuteScalar(
        'SELECT COUNT(*) FROM USR_UTENTE_MODULI_AZIENDE_WEB(:USER_NAME) ' +
        'WHERE USR_UTENTE_MODULI_AZIENDE_WEB.MODULO = :MODULO', Parametri) > 0;
    except
      on E: Exception do
        LogW('Moduli per azienda non letti, modulo ' + Modulo + ' negato: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Moduli del cittadino (Riciclario, script WT-MODULI-07 del rilascio 012): la
// procedura USR_UTENTE_MODULI_CITTADINO_WEB dice in quali comuni delle sue
// utenze e del suo intestatario il modulo e' attivo. Un errore (procedura
// assente perche' lo script non e' ancora passato) nega: i dataset con il
// modulo del cittadino nascono con lo stesso script.
function TWTProfile.ModuloAttivoPerCittadino(const UserName, Modulo: string): Boolean;
var
  Parametri: TParamValues;
begin
  Result := False;

  if UserName.Trim.IsEmpty or Modulo.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    Parametri.Add('MODULO', Modulo);
    try
      Result := TDataService.ExecuteScalar(
        'SELECT COUNT(*) FROM USR_UTENTE_MODULI_CITTADINO_WEB(:USER_NAME) ' +
        'WHERE USR_UTENTE_MODULI_CITTADINO_WEB.MODULO = :MODULO', Parametri) > 0;
    except
      on E: Exception do
        LogW('Moduli del cittadino non letti, modulo ' + Modulo + ' negato: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Moduli del portale del cittadino per /auth/moduli (2026-11-06, rilascio 013):
// i soli moduli Cittadino.* della procedura, che restituisce anche quelli per
// comune. Un errore lascia l'elenco vuoto e Pipa nasconde le voci con modulo.
function TWTProfile.ModuliCittadino(const UserName: string): TModuliUtente;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Modulo: TModuloUtente;
begin
  Result := [];

  if UserName.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    try
      Righe := TDataService.ExecuteQuery(
        'SELECT USR_UTENTE_MODULI_CITTADINO_WEB.MODULO, USR_UTENTE_MODULI_CITTADINO_WEB.BELFIORE ' +
        'FROM USR_UTENTE_MODULI_CITTADINO_WEB(:USER_NAME) ' +
        'WHERE USR_UTENTE_MODULI_CITTADINO_WEB.MODULO STARTING WITH ''Cittadino.''', Parametri, False);
      try
        for Riga in Righe do
          if Riga is TJSONObject then
          begin
            Modulo.Modulo := JsonStr(TJSONObject(Riga), 'MODULO').Trim;
            Modulo.Belfiore := JsonStr(TJSONObject(Riga), 'BELFIORE').Trim;
            Modulo.Scrittura := False;
            Result := Result + [Modulo];
          end;
      finally
        FreeAndNil(Righe);
      end;
    except
      on E: Exception do
        LogW('Moduli del cittadino non letti per il menu: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Moduli di GERA (script WT-MODULI-08 del rilascio 014): la procedura
// USR_UTENTE_MODULI_GRUPPO_WEB dice quali moduli senza comune i gruppi
// dell'utente gli danno, con l'accesso piu' ampio. Con Scrittura serve W.
// Un errore (procedura assente perche' lo script non e' ancora passato)
// nega: i dataset di GERA con il modulo nascono con lo stesso script.
function TWTProfile.ModuloAttivoPerGruppo(const UserName, Modulo: string; const Scrittura: Boolean): Boolean;
var
  Parametri: TParamValues;
  Condizione: string;
begin
  Result := False;

  if UserName.Trim.IsEmpty or Modulo.Trim.IsEmpty then
    Exit;

  Condizione := '';
  if Scrittura then
    Condizione := ' AND USR_UTENTE_MODULI_GRUPPO_WEB.ACCESS = ''W''';

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    Parametri.Add('MODULO', Modulo);
    try
      Result := TDataService.ExecuteScalar(
        'SELECT COUNT(*) FROM USR_UTENTE_MODULI_GRUPPO_WEB(:USER_NAME) ' +
        'WHERE USR_UTENTE_MODULI_GRUPPO_WEB.MODULO = :MODULO' + Condizione, Parametri) > 0;
    except
      on E: Exception do
        LogW('Moduli per gruppo non letti, modulo ' + Modulo + ' negato: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Moduli di GERA per /auth/moduli (2026-11-07, rilascio 014): una riga per
// modulo, senza comune. Un errore lascia l'elenco vuoto e Pipa nasconde le
// voci con modulo.
function TWTProfile.ModuliGruppo(const UserName: string): TModuliUtente;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Modulo: TModuloUtente;
begin
  Result := [];

  if UserName.Trim.IsEmpty then
    Exit;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', UserName);
    try
      Righe := TDataService.ExecuteQuery(
        'SELECT USR_UTENTE_MODULI_GRUPPO_WEB.MODULO, USR_UTENTE_MODULI_GRUPPO_WEB.ACCESS ' +
        'FROM USR_UTENTE_MODULI_GRUPPO_WEB(:USER_NAME)', Parametri, False);
      try
        for Riga in Righe do
          if Riga is TJSONObject then
          begin
            Modulo.Modulo := JsonStr(TJSONObject(Riga), 'MODULO').Trim;
            Modulo.Belfiore := '';
            Modulo.Scrittura := SameText(JsonStr(TJSONObject(Riga), 'ACCESS').Trim, 'W');
            Result := Result + [Modulo];
          end;
      finally
        FreeAndNil(Righe);
      end;
    except
      on E: Exception do
        LogW('Moduli per gruppo non letti per il menu: ' + E.Message);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Il filtro dei dataset dello sportello non sta in una colonna BELFIORE della
// relazione (sono quasi tutti procedure selezionabili): sta dentro le procedure,
// che guardano USR_TMP_COMUNI. Per questo il modulo restringe USR_TMP_COMUNI e
// non aggiunge una condizione alla SQL. La tabella e' temporanea della
// connessione (ON COMMIT PRESERVE ROWS) e la svuota e riempie
// USR_FILL_TABELLE_TMP a ogni dichiarazione del contesto: la richiesta
// successiva, anche sulla stessa connessione fisica, riparte dal perimetro
// intero (Connection.Pool dichiara il contesto alla prima presa di ogni
// richiesta). Si toglie soltanto: un comune del modulo che non fosse fra
// quelli dell'utente non entra.
//
// I comuni vengono da USR_UTENTE_MODULI_WEB, non dal browser; gli apici si
// raddoppiano comunque. La conferma serve perche' le righe tolte siano
// invisibili anche alle transazioni successive della stessa connessione, come
// in TConnectionPool.DichiaraContesto.
procedure TWTProfile.RestringiComuniDellaRichiesta(const Comuni: TArray<string>);
var
  Elenco: TArray<string>;
  Comune: string;
  SQL: string;
  Connessione: TFDConnection;
  Esito: TJSONObject;
begin
  if Length(Comuni) = 0 then
    SQL := 'DELETE FROM USR_TMP_COMUNI WHERE 1 = 1'
  else
  begin
    Elenco := [];
    for Comune in Comuni do
      Elenco := Elenco + [QuotedStr(Comune)];

    SQL := Format('DELETE FROM USR_TMP_COMUNI WHERE USR_TMP_COMUNI.BELFIORE NOT IN (%s)', [string.Join(', ', Elenco)]);
  end;

  Connessione := TConnectionPool.Instance.Acquire;
  try
    if not Connessione.InTransaction then
      Connessione.StartTransaction;
    try
      Esito := TDataService.ExecuteSQL(Connessione, SQL, nil, False);
      FreeAndNil(Esito);
      Connessione.Commit;
    except
      Connessione.Rollback;
      raise;
    end;
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;
end;

function TWTProfile.RelazioneHaBelfiore(const NomeRelazione: string): Boolean;
var
  Nome: string;
  Parametri: TParamValues;
begin
  Nome := NomeRelazione.Trim.Replace('"', '').ToUpper;

  FLucchetto.Enter;
  try
    if FRelazioniConBelfiore.TryGetValue(Nome, Result) then
      Exit;
  finally
    FLucchetto.Leave;
  end;

  // Fuori dal lucchetto: la lettura passa dal raggruppamento delle
  // connessioni e non deve tenere fermi gli altri thread.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('NOME_RELAZIONE', Nome);
    Result := TDataService.ExecuteScalar('SELECT COUNT(*) FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_FIELDS.RDB$RELATION_NAME = :NOME_RELAZIONE AND RDB$RELATION_FIELDS.RDB$FIELD_NAME = ''BELFIORE''', Parametri) > 0;
  finally
    FreeAndNil(Parametri);
  end;

  FLucchetto.Enter;
  try
    FRelazioniConBelfiore.AddOrSetValue(Nome, Result);
  finally
    FLucchetto.Leave;
  end;
end;

// USR_TMP_COMUNI e USR_TMP_AZIENDE sono riempite per utente da
// USR_FILL_TABELLE_TMP sulla connessione corrente: la verifica si fa quindi
// sulle stesse righe che il database usera' poi per filtrare, e non su un
// elenco ricostruito qui.
function TWTProfile.AmbitoAmmesso(const Belfiore: string; const IdAzienda: Int64): Boolean;
var
  Parametri: TParamValues;
begin
  Result := True;

  if not Belfiore.Trim.IsEmpty then
  begin
    Parametri := TParamValues.Create;
    try
      Parametri.Add('B', Belfiore);
      Result := TDataService.ExecuteScalar('SELECT COUNT(*) FROM USR_TMP_COMUNI WHERE USR_TMP_COMUNI.BELFIORE = :B', Parametri) > 0;
    finally
      FreeAndNil(Parametri);
    end;

    if not Result then
      Exit;
  end;

  if IdAzienda > 0 then
  begin
    Parametri := TParamValues.Create;
    try
      Parametri.Add('A', IdAzienda);
      Result := TDataService.ExecuteScalar('SELECT COUNT(*) FROM USR_TMP_AZIENDE WHERE USR_TMP_AZIENDE.ID_AZIENDA = :A', Parametri) > 0;
    finally
      FreeAndNil(Parametri);
    end;
  end;
end;

function TWTProfile.ClasseDocumentale(const NomeEntita: string): string;
begin
  Result := '';
end;

function TWTProfile.PercorsoFile(const IdObjectFile, IdSessione: Int64): string;
var
  Parametri: TParamValues;
  Riga: TJSONObject;
begin
  // OBJ_FILES_GET_FULL_FILE_NAME, usata fino al 2026-10-06, non riceve la
  // sessione: chiunque fosse autenticato scaricava qualunque file di
  // qualunque comune. WEB_OBJ_FILES_GET_FULL_FILE_NAME applica le regole del
  // GeDo (WEB_GET_FILE_NAME) e delle richieste, e restituisce NULL per un
  // file fuori perimetro o di una classe senza regola.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE_WEB', IdSessione);
    Parametri.Add('ID_OBJECT_FILE', IdObjectFile);
    Riga := TDataService.ExecuteQuerySingleRow('SELECT WEB_OBJ_FILES_GET_FULL_FILE_NAME(:ID_SESSIONE_WEB, :ID_OBJECT_FILE) AS FULL_FILE_NAME FROM RDB$DATABASE', Parametri, False);
    try
      Result := JsonStr(Riga, 'FULL_FILE_NAME');
    finally
      FreeAndNil(Riga);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTProfile.OggettoAmmesso(const Oid, IdSessione: Int64): Boolean;
var
  Parametri: TParamValues;
begin
  // Solo il cittadino e' ristretto: nel suo portale l'oggetto a cui allegare
  // e' una richiesta (OID = ID_RICHIESTA, come in
  // WEB_CITTADINI_ALLEGATI_RICHIESTA_ADD) e deve essere una richiesta sua.
  // Gli operatori allegano a oggetti di molte classi diverse e restano come
  // prima. Un cittadino senza intestatario nella sessione non ammette niente.
  // 2026-11-07: anche il Riciclario (WTWEB_RICICLARIO) e' un'area del cittadino, che
  // vi allega la foto delle segnalazioni. Prima la regola valeva solo per
  // WTWEB_CITTADINO e nel Riciclario ogni OID era ammesso: un cittadino avrebbe potuto
  // allegare file a oggetti di altri. Ora vale per entrambe; un operatore che entra
  // nel Riciclario non ha intestatario e non allega niente, come nel portale.
  if not MatchText(AreaDellaSessione(IdSessione), ['WTWEB_CITTADINO', 'WTWEB_RICICLARIO']) then
    Exit(True);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Parametri.Add('OID', Oid);
    Result := TDataService.ExecuteScalar('SELECT COUNT(*) FROM RICHIESTE WHERE RICHIESTE.ID_RICHIESTA = :OID AND RICHIESTE.ID_INTESTATARIO = (SELECT WEB_CIT_LOGIN_DATI_INTESTATARIO.ID_INTESTATARIO FROM WEB_CIT_LOGIN_DATI_INTESTATARIO(:ID_SESSIONE))', Parametri) > 0;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTProfile.ControllerDiDominio: TArray<TMVCControllerClazz>;
begin
  Result := [TWTAdminController, TWTGecoController, TWTTvbController, TWTAnprController, TWTAgoraController, TWTCittadinoController, TWTCdrPubblicoController];

  // Neta e' sospeso finche' mancano Neta_Proxy e Neta_StreamServer: rientra
  // definendo WT_CONTROLLER_NETA nel progetto.
  // Neta parla con un servizio DataSnap e con uno StreamServer raggiungibili
  // dai soli nodi Windows: sull'eseguibile Linux il controller non esiste.
{$IFDEF WT_CONTROLLER_NETA}
{$IFDEF MSWINDOWS}
  Result := Result + [TWTNetaController];
{$ENDIF}
{$ENDIF}
end;

function TWTProfile.AzioniPubbliche: TArray<string>;
begin
  // Tre famiglie, e nessuna puo' portare un token:
  // - registrazione e recupero credenziali: chi le chiede non e' ancora entrato;
  // - ritorni del gateway di pagamento: li chiama la banca, non il browser;
  // - diagnostica minima (Ping, Ver) usata dai controlli di disponibilita.
  // Piu' la bacheca pubblica dei centri del riuso (2026-11-07): solo beni
  // pubblicati, senza dati di persone, perimetro nelle procedure CDR_BACHECA_*.
  // ComuniAbilitati non e' fra queste: USR_COMUNI_ABILITATI filtra per
  // utente corrente, quindi senza token restituirebbe un elenco vuoto.
  // Piu' lo scaricamento del database GeCo preparato dal server (2026-11-08):
  // il plugin del telefono non puo' inviare l'intestazione di autorizzazione,
  // vale il biglietto monouso di 10 minuti rilasciato a chi ha il token. Il file
  // e' comunque cifrato con la chiave del dispositivo.
  // Piu' l'invio del database del palmare dalla pagina di accesso dell'app (2026-11-08): il telefono
  // che non riesce ad accedere non ha il gettone; vale il telefono registrato con la sua chiave,
  // il file e' cifrato e la risposta non lo descrive, con limite di dimensione e di frequenza.
  Result := [
    'TWTGecoController.ScaricaFotografia',
    'TWTGecoController.RiceviDatabasePalmareSenzaAccesso',
    'TWTAdminController.Ping',
    'TWTAdminController.Ver',
    'TWTAdminController.VerificaToken',
    'TWTAdminController.RichiestaRegistrazione',
    'TWTAdminController.ConfermaRegistrazione',
    'TWTAdminController.RecuperaUsername',
    'TWTAdminController.RecuperaPassword',
    'TWTCittadinoController.LoginCittadino',
    'TWTCittadinoController.LoginSpid',
    'TWTCittadinoController.LoginSpidGateway',
    'TWTCdrPubblicoController.Comuni',
    'TWTCdrPubblicoController.Bacheca',
    'TWTCdrPubblicoController.Bene',
    'TWTTvbController.NotificationMessage',
    'TWTTvbController.ErrorURL',
    'TWTTvbController.GetStatoTransazione'];
end;

initialization

TAppProfiles.Registra(TWTProfile.Create);

end.
