// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit Firma.Gestore;

// Gestori FIRMA e FIRMA-STATO della coda ZZ_CODA, comuni a tutti i prodotti:
// firma remota di un documento di OBJ_FILES con il fornitore configurato per
// il tenant della registrazione (OBJ_FILES_FIRMA_CONFIGURAZIONE), sulle
// procedure OBJ_FILES_FIRMA_* che Gesty e WT hanno in comune.
//
// Nato il 2026-11-07 dal gestore di Gesty (Gesty.Firma.Gestore, che ne
// conserva la sequenza e le decisioni), per portare la firma con valore legale
// anche in WT (centri del riuso) senza duplicarlo. Le due cose che cambiano da
// un prodotto all'altro le dichiara il prodotto con TFirmaProdotti.Registra:
// - i firmatari al momento dell'invio (Gesty li ricava dal tipo di documento,
//   WT li rilegge da OBJ_FILES_FIRMA_REGISTRAZIONI_FIRMATARI);
// - il percorso del file da firmare (Gesty: procedura GET_FULL_FILE_NAME,
//   WT: funzione OBJ_FILES_GET_FULL_FILE_NAME).
// Il prodotto scelto e' quello del profilo corrente (TAppProfiles.Corrente):
// la coda e' unica, il database e' quello del prodotto in esecuzione.
//
// Il fornitore si sceglie per configurazione, senza ricompilare: e' quello
// di OBJ_FILES_FIRMA_CONFIGURAZIONE (FORNITORE con ATTIVO vero) e si crea con
// TzFirmaFactory. La coda accetta solo i fornitori che sanno ritrovare una
// busta gia' partita (IzFirmaRicercaBusta): la coda riprende "almeno una
// volta", e un fornitore che non lo sa fare rischierebbe il doppio invio.
//
// FIRMA {idFirmaRegistrazione, userId, idSessione, userName}
//   - registrazione non in stato A, o con la busta gia' assegnata: niente da
//     fare (un altro giro, o il programma desktop, l'ha gia' inviata);
//   - cerca per contrassegno FIRMA-<id> una busta gia' partita; se la trova
//     ne adotta l'identificativo;
//   - altrimenti firmatari dal prodotto, invio, REGISTRAZIONE_INVIATA;
//   - accoda FIRMA-STATO con attesa firma.intervalloStatoSecondi.
//
// FIRMA-STATO {idFirmaRegistrazione, userId, idSessione, userName, giro}
//   - registrazione non in stato D: niente da fare;
//   - chiede lo stato della busta; firmata: versioni FIR e RIC scaricate e
//     REGISTRAZIONE_FIRMATA; scaduta o respinta: REGISTRAZIONE_SCADUTA o
//     RESPINTA_FORNITORE; ancora aperta: STATO_ESTERNO e un nuovo lavoro
//     FIRMA-STATO con l'attesa, fino a firma.giriMassimi giri.
//
// Il gestore lavora sulla connessione dell'elaboratore e non conferma mai:
// le scritture di un lavoro si confermano insieme all'esito, oppure si
// annullano tutte. Fa eccezione il registro delle chiamate al fornitore,
// scritto in transazione autonoma (OBJ_FILES_FIRMA_LOG_*_ADD_AUTONOMA): resta
// anche quando il lavoro fallisce. Ciò che succede dopo la firma nel
// prodotto (in WT lo stato della liberatoria del centro del riuso) lo fanno
// i trigger del database su OBJ_FILES_FIRMA_REGISTRAZIONI, non questa unit.
//
// FirmaCollegamento (2026-11-07, firma al banco dei centri del riuso): non e'
// un lavoro della coda ma una lettura chiesta da un controller. Dato una
// registrazione gia' inviata (stato D con la busta), chiede al fornitore il
// collegamento alla pagina di firma del firmatario, se il fornitore lo sa
// dare (IzFirmaCollegamento). Usa la stessa configurazione e lo stesso
// registro delle chiamate dei lavori FIRMA e FIRMA-STATO, sulla connessione
// del chiamante, che porta gia' il contesto dell'utente.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  zDocumentale.Firma.Types;

const
  TipoCodaFirma = 'FIRMA';
  TipoCodaFirmaStato = 'FIRMA-STATO';

  /// <summary>
  /// In testa al nome della busta, seguito dall'identificativo della
  /// registrazione: permette di ritrovare la busta presso il fornitore.
  /// </summary>
  PrefissoContrassegno = 'FIRMA-';

  /// <summary>Prefisso dell'esito di un lavoro FIRMA o FIRMA-STATO.</summary>
  PrefissoEsitoFirma = 'FIRMA_REGISTRAZIONE ';

type
  /// <summary>Riga di OBJ_FILES_FIRMA_REGISTRAZIONI letta dal gestore.</summary>
  TFirmaRegistrazione = record
    Trovata: Boolean;
    IdFirmaRegistrazione: Int64;
    IdTenant: Int64;
    Fornitore: string;
    Stato: string;
    Oid: Int64;
    IdObjectFile: Int64;
    IdDocumentoEsterno: string;
  end;

  TFirmaLeggiFirmatariFunc = reference to function(Connessione: TFDConnection; const Registrazione: TFirmaRegistrazione): TArray<TzFirmaFirmatario>;
  TFirmaPercorsoFileFunc = reference to function(Connessione: TFDConnection; const IdObjectFile: Int64): string;

  /// <summary>Le parti del gestore che dipendono dal prodotto.</summary>
  TFirmaProdotto = record
    LeggiFirmatari: TFirmaLeggiFirmatariFunc;
    PercorsoFile: TFirmaPercorsoFileFunc;
  end;

  TFirmaProdotti = class
  private
    class var FElenco: TDictionary<string, TFirmaProdotto>;
  public
    class destructor Destroy;

    /// <summary>
    /// Dichiara le parti di prodotto per il profilo con questo codice
    /// (IAppProfile.Codice: 'GESTY', 'WT'). Si chiama dall'initialization
    /// della unit del prodotto.
    /// </summary>
    class procedure Registra(const CodiceProfilo: string; const Prodotto: TFirmaProdotto);

    /// <summary>
    /// Parti di prodotto del profilo corrente; solleva EzFirmaErrore se il
    /// prodotto non gestisce la firma.
    /// </summary>
    class function Corrente: TFirmaProdotto;
  end;

  /// <summary>Esito di FirmaCollegamento.</summary>
  TFirmaCollegamento = record
    /// <summary>Stato della registrazione (A, D, F, R, S...).</summary>
    Stato: string;
    /// <summary>URL della pagina di firma; vuoto se non c'e' (ancora).</summary>
    Collegamento: string;
    /// <summary>Perche' il collegamento manca, per l'operatore.</summary>
    Messaggio: string;
  end;

/// <summary>
/// Collegamento alla pagina di firma della registrazione, per la firma in
/// presenza. In stato A (busta non ancora inviata dalla coda) torna vuoto con
/// il messaggio: chi chiama riprova. Solleva EzFirmaNonSupportato se il
/// fornitore non da' collegamenti, EzFirmaErrore per una registrazione
/// inesistente o per un errore del fornitore.
/// </summary>
function FirmaCollegamento(Connessione: TFDConnection; const IdFirmaRegistrazione: Int64; const IndirizzoRitorno: string): TFirmaCollegamento;

/// <summary>Esegue una query di una sola riga e restituisce il primo campo come testo.</summary>
function FirmaValoreTesto(Connessione: TFDConnection; const Testo, NomeParametro: string; const Valore: Int64): string;

implementation

uses
  System.JSON,
  Data.DB,
  FireDAC.Stan.Param,
  MVCFramework.Logger,
  App.Config,
  App.Profile,
  Json.Values,
  Queue.Service,
  zDocumentale.Firma.Intf,
  zDocumentale.Firma.ProviderBase,
  zDocumentale.Firma.Factory;

const
  // Finestra della ricerca per contrassegno: piu' lunga della ripresa di un
  // lavoro bloccato, e abbastanza corta da non chiedere al fornitore tutto
  // l'archivio.
  GiorniRicercaBusta = 30;

{ TFirmaProdotti }

class destructor TFirmaProdotti.Destroy;
begin
  FreeAndNil(FElenco);
end;

class procedure TFirmaProdotti.Registra(const CodiceProfilo: string; const Prodotto: TFirmaProdotto);
begin
  if not Assigned(FElenco) then
    FElenco := TDictionary<string, TFirmaProdotto>.Create;

  FElenco.AddOrSetValue(CodiceProfilo.Trim.ToUpper, Prodotto);
end;

class function TFirmaProdotti.Corrente: TFirmaProdotto;
var
  Codice: string;
begin
  Codice := TAppProfiles.Corrente.Codice.Trim.ToUpper;

  if not Assigned(FElenco) or not FElenco.TryGetValue(Codice, Result) then
    raise EzFirmaErrore.CreateFmt('Il prodotto %s non gestisce la firma remota attraverso la coda.', [Codice]);
end;

function CreaProcedura(Connessione: TFDConnection; const Nome: string): TFDStoredProc;
begin
  Result := TFDStoredProc.Create(nil);
  try
    Result.Connection := Connessione;
    Result.StoredProcName := Nome;
    Result.Prepare;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function CreaQuery(Connessione: TFDConnection; const Testo: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := Connessione;
  Result.SQL.Text := Testo;
end;

function FirmaValoreTesto(Connessione: TFDConnection; const Testo, NomeParametro: string; const Valore: Int64): string;
var
  Query: TFDQuery;
begin
  Query := CreaQuery(Connessione, Testo);
  try
    Query.ParamByName(NomeParametro).AsLargeInt := Valore;
    Query.Open;

    if Query.IsEmpty then
      Result := ''
    else
      Result := Query.Fields[0].AsString;
  finally
    FreeAndNil(Query);
  end;
end;

// Solo le colonne che Gesty e WT hanno in comune: TIPO_DOCUMENTO c'e' solo in
// Gesty, e lo legge il suo adattatore.
function LeggiRegistrazione(Connessione: TFDConnection; const IdFirmaRegistrazione: Int64): TFirmaRegistrazione;
var
  Query: TFDQuery;
begin
  Result := Default(TFirmaRegistrazione);

  Query := CreaQuery(Connessione,
    'SELECT OBJ_FILES_FIRMA_REGISTRAZIONI.ID_TENANT, OBJ_FILES_FIRMA_REGISTRAZIONI.FORNITORE, ' +
    'OBJ_FILES_FIRMA_REGISTRAZIONI.STATO, OBJ_FILES_FIRMA_REGISTRAZIONI.OID, ' +
    'OBJ_FILES_FIRMA_REGISTRAZIONI.ID_OBJECT_FILE, OBJ_FILES_FIRMA_REGISTRAZIONI.ID_DOCUMENTO_ESTERNO ' +
    'FROM OBJ_FILES_FIRMA_REGISTRAZIONI ' +
    'WHERE OBJ_FILES_FIRMA_REGISTRAZIONI.ID_FIRMA_REGISTRAZIONE = :ID_FIRMA_REGISTRAZIONE');
  try
    Query.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
    Query.Open;

    if Query.IsEmpty then
      Exit;

    Result.Trovata := True;
    Result.IdFirmaRegistrazione := IdFirmaRegistrazione;
    Result.IdTenant := Query.FieldByName('ID_TENANT').AsLargeInt;
    Result.Fornitore := Query.FieldByName('FORNITORE').AsString;
    Result.Stato := Query.FieldByName('STATO').AsString;
    Result.Oid := Query.FieldByName('OID').AsLargeInt;
    Result.IdObjectFile := Query.FieldByName('ID_OBJECT_FILE').AsLargeInt;
    Result.IdDocumentoEsterno := Query.FieldByName('ID_DOCUMENTO_ESTERNO').AsString.Trim;
  finally
    FreeAndNil(Query);
  end;
end;

// Configurazione del fornitore per il tenant della registrazione. Chi la
// riceve la copia (TzFirmaProviderBase.Configura), quindi qui si libera subito.
procedure CaricaConfigurazione(Connessione: TFDConnection; const IdTenant: Int64; var Configurazione: TzFirmaConfigurazione);
var
  Procedura: TFDStoredProc;
  Query: TFDQuery;
begin
  Procedura := CreaProcedura(Connessione, 'OBJ_FILES_FIRMA_CONFIGURAZIONE_GET');
  try
    Procedura.ParamByName('ID_TENANT').AsLargeInt := IdTenant;
    Procedura.ExecProc;

    Configurazione.IdTenant := IdTenant;
    Configurazione.Fornitore := Procedura.ParamByName('FORNITORE').AsString;
    Configurazione.UrlBase := Procedura.ParamByName('URL_BASE').AsString;
    Configurazione.Utente := Procedura.ParamByName('UTENTE').AsString;
    Configurazione.Password := Procedura.ParamByName('PASSWORD_').AsString;

    if not Procedura.ParamByName('ATTIVO').AsBoolean then
      Configurazione.Fornitore := '';
  finally
    FreeAndNil(Procedura);
  end;

  if Configurazione.Fornitore.IsEmpty or SameText(Configurazione.Fornitore, FIRMA_FORNITORE_NESSUNO) then
    raise EzFirmaErrore.CreateFmt('Nessun fornitore di firma attivo per il tenant %d.', [IdTenant]);

  Query := CreaQuery(Connessione,
    'SELECT OBJ_FILES_FIRMA_CONFIG_PARAMETRI_GET.CHIAVE, OBJ_FILES_FIRMA_CONFIG_PARAMETRI_GET.VALORE ' +
    'FROM OBJ_FILES_FIRMA_CONFIG_PARAMETRI_GET(:ID_TENANT, :FORNITORE)');
  try
    Query.ParamByName('ID_TENANT').AsLargeInt := IdTenant;
    Query.ParamByName('FORNITORE').AsString := Configurazione.Fornitore;
    Query.Open;

    while not Query.Eof do
    begin
      Configurazione.Parametri.AddOrSetValue(Query.FieldByName('CHIAVE').AsString.ToUpper, Query.FieldByName('VALORE').AsString);
      Query.Next;
    end;
  finally
    FreeAndNil(Query);
  end;
end;

// Fornitore configurato e agganciato alla connessione del lavoro: registro
// in transazione autonoma, versioni nella transazione del lavoro.
function CreaFornitore(Connessione: TFDConnection; const Registrazione: TFirmaRegistrazione): IzFirmaProvider;
var
  Configurazione: TzFirmaConfigurazione;
  Base: TzFirmaProviderBase;
  IdTenant: Int64;
  IdFirmaRegistrazione: Int64;
  Fornitore: string;
begin
  Configurazione.Inizializza;
  try
    CaricaConfigurazione(Connessione, Registrazione.IdTenant, Configurazione);

    // Il fornitore della registrazione e' quello con cui e' nata: se nel
    // frattempo il tenant ne ha attivato un altro, la busta non va mandata a
    // chi non la conosce.
    if not SameText(Configurazione.Fornitore, Registrazione.Fornitore) then
      raise EzFirmaErrore.CreateFmt('La registrazione %d e'' del fornitore %s, ma per il tenant e'' attivo %s.',
        [Registrazione.IdFirmaRegistrazione, Registrazione.Fornitore, Configurazione.Fornitore]);

    Result := TzFirmaFactory.Crea(Configurazione.Fornitore);

    // La fabbrica ricade su NESSUNO per un nome sconosciuto: qui sarebbe un
    // fornitore che non sa firmare, meglio dirlo col suo nome.
    if not SameText(Result.Nome, Configurazione.Fornitore) then
      raise EzFirmaErrore.CreateFmt('Il fornitore di firma %s non e'' incluso in questo zServer.', [Configurazione.Fornitore]);

    Result.Configura(Configurazione);
    Fornitore := Configurazione.Fornitore;
  finally
    Configurazione.Finalizza;
  end;

  IdTenant := Registrazione.IdTenant;
  IdFirmaRegistrazione := Registrazione.IdFirmaRegistrazione;
  Base := Result as TzFirmaProviderBase;

  // Un registro che non si scrive non deve far fallire la firma: si annota
  // nel registro del server e si prosegue.
  Base.OnLogRequest :=
    function(const Operazione, Endpoint, Richiesta: string): Int64
    var
      Procedura: TFDStoredProc;
    begin
      Result := 0;
      try
        Procedura := CreaProcedura(Connessione, 'OBJ_FILES_FIRMA_LOG_REQUEST_ADD_AUTONOMA');
        try
          Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
          Procedura.ParamByName('ID_TENANT').AsLargeInt := IdTenant;
          Procedura.ParamByName('FORNITORE').AsString := Fornitore;
          Procedura.ParamByName('OPERAZIONE').AsString := Operazione;
          Procedura.ParamByName('ENDPOINT').AsString := Endpoint;
          Procedura.ParamByName('RICHIESTA').AsWideMemo := Richiesta;
          Procedura.ExecProc;
          Result := Procedura.ParamByName('ID_FIRMA_LOG_REQUEST').AsLargeInt;
        finally
          FreeAndNil(Procedura);
        end;
      except
        on E: Exception do
          LogW(Format('Firma %d: registro della richiesta %s non scritto: %s', [IdFirmaRegistrazione, Operazione, E.Message]));
      end;
    end;

  Base.OnLogResponse :=
    procedure(IdLogRequest: Int64; HttpStatus: Integer; const Risposta, Errore: string)
    var
      Procedura: TFDStoredProc;
    begin
      if IdLogRequest = 0 then
        Exit;

      try
        Procedura := CreaProcedura(Connessione, 'OBJ_FILES_FIRMA_LOG_RESPONSE_ADD_AUTONOMA');
        try
          Procedura.ParamByName('ID_FIRMA_LOG_REQUEST').AsLargeInt := IdLogRequest;
          Procedura.ParamByName('HTTP_STATUS').AsInteger := HttpStatus;
          Procedura.ParamByName('RISPOSTA').AsWideMemo := Risposta;
          Procedura.ParamByName('ERRORE').AsWideMemo := Errore;
          Procedura.ExecProc;
        finally
          FreeAndNil(Procedura);
        end;
      except
        on E: Exception do
          LogW(Format('Firma %d: registro della risposta non scritto: %s', [IdFirmaRegistrazione, E.Message]));
      end;
    end;

  Base.OnCreaVersione :=
    function(IdObjectFilePadre: Int64; const TipoVersione, NomeFileOriginale, FileSuffix: string): TzFirmaVersioneCreata
    var
      Procedura: TFDStoredProc;
    begin
      Result.Clear;
      Procedura := CreaProcedura(Connessione, 'OBJ_FILES_VERSIONE_ADD');
      try
        Procedura.ParamByName('ID_OBJECT_FILE_PADRE').AsLargeInt := IdObjectFilePadre;
        Procedura.ParamByName('TIPO_VERSIONE').AsString := TipoVersione;
        Procedura.ParamByName('NOME_FILE_ORIGINALE').AsString := NomeFileOriginale;
        Procedura.ParamByName('FILE_SUFFIX').AsString := FileSuffix;
        Procedura.ParamByName('FILE_SIZE').AsInteger := 0;
        Procedura.ExecProc;
        Result.IdObjectFile := Procedura.ParamByName('ID_OBJECT_FILE').AsLargeInt;
        Result.FullFileName := Procedura.ParamByName('FULL_FILE_NAME').AsString;
      finally
        FreeAndNil(Procedura);
      end;

      // La cartella di una versione nuova puo' non esistere ancora
      // (Mantis #87 in Gesty).
      ForceDirectories(ExtractFilePath(Result.FullFileName));
    end;
end;

procedure EseguiProcedura(Connessione: TFDConnection; const Nome: string; const IdFirmaRegistrazione: Int64; const StatoEsterno: string);
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaProcedura(Connessione, Nome);
  try
    Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
    Procedura.ParamByName('STATO_ESTERNO').AsString := StatoEsterno.Substring(0, 255);
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure SegnaInviata(Connessione: TFDConnection; const IdFirmaRegistrazione: Int64; const IdBusta, StatoEsterno: string);
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaProcedura(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_INVIATA');
  try
    Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
    Procedura.ParamByName('ID_DOCUMENTO_ESTERNO').AsString := IdBusta;
    Procedura.ParamByName('STATO_ESTERNO').AsString := StatoEsterno;
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure SegnaFirmata(Connessione: TFDConnection; const IdFirmaRegistrazione: Int64; const Esito: TzFirmaEsito);
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaProcedura(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_FIRMATA');
  try
    Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
    Procedura.ParamByName('ID_OBJECT_FILE_FIRMATO').AsLargeInt := Esito.IdObjectFileFirmato;

    if Esito.IdObjectFileAudit > 0 then
      Procedura.ParamByName('ID_OBJECT_FILE_AUDIT').AsLargeInt := Esito.IdObjectFileAudit
    else
      Procedura.ParamByName('ID_OBJECT_FILE_AUDIT').Clear;

    Procedura.ParamByName('STATO_ESTERNO').AsString := Esito.StatoEsterno.Substring(0, 255);
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

function ContenutoLavoro(Contenuto: TJSONObject; const Giro: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('idFirmaRegistrazione', TJSONNumber.Create(JsonInt64(Contenuto, 'idFirmaRegistrazione')));
  Result.AddPair('userId', TJSONNumber.Create(JsonInt64(Contenuto, 'userId')));
  Result.AddPair('idSessione', TJSONNumber.Create(JsonInt64(Contenuto, 'idSessione')));
  Result.AddPair('userName', JsonStr(Contenuto, 'userName'));
  Result.AddPair('giro', TJSONNumber.Create(Giro));
end;

// Accoda il controllo dello stato nella transazione del lavoro: parte solo
// se il lavoro che lo accoda si conferma.
procedure AccodaStato(Connessione: TFDConnection; Contenuto: TJSONObject; const Giro: Integer);
var
  Lavoro: TJSONObject;
begin
  Lavoro := ContenutoLavoro(Contenuto, Giro);
  try
    TCoda.Accoda(Connessione, TipoCodaFirmaStato, Lavoro, 0, TAppConfig.Instance.Firma.IntervalloStatoSecondi);
  finally
    FreeAndNil(Lavoro);
  end;
end;

function InviaRegistrazione(Connessione: TFDConnection; Contenuto: TJSONObject; const Registrazione: TFirmaRegistrazione; const Prodotto: TFirmaProdotto): string;
var
  Fornitore: IzFirmaProvider;
  Ricerca: IzFirmaRicercaBusta;
  Contrassegno: string;
  IdBusta: string;
  Documento: TzFirmaDocumento;
  Esito: TzFirmaEsito;
begin
  Fornitore := CreaFornitore(Connessione, Registrazione);
  Contrassegno := PrefissoContrassegno + Registrazione.IdFirmaRegistrazione.ToString;

  // Un fornitore che non sa ritrovare una busta per contrassegno non puo'
  // essere usato dalla coda, perche' rischierebbe il doppio invio.
  if not Supports(Fornitore, IzFirmaRicercaBusta, Ricerca) then
    raise EzFirmaErrore.CreateFmt('Il fornitore %s non e'' gestito dalla coda di firma.', [Fornitore.Nome]);

  Ricerca.ImpostaContrassegno(Contrassegno);
  IdBusta := Ricerca.CercaBusta(Contrassegno, GiorniRicercaBusta);

  if not IdBusta.IsEmpty then
  begin
    SegnaInviata(Connessione, Registrazione.IdFirmaRegistrazione, IdBusta, 'Sent');
    AccodaStato(Connessione, Contenuto, 1);
    Exit(Format('%s%d: busta %s gia'' inviata, ritrovata col contrassegno', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, IdBusta]));
  end;

  Documento.Clear;
  Documento.IdObjectFile := Registrazione.IdObjectFile;
  Documento.Oid := Registrazione.Oid;
  Documento.FullFileName := Prodotto.PercorsoFile(Connessione, Registrazione.IdObjectFile);
  Documento.Firmatari := Prodotto.LeggiFirmatari(Connessione, Registrazione);

  if Length(Documento.Firmatari) = 0 then
    raise EzFirmaErrore.CreateFmt('Nessun firmatario per l''oggetto %d.', [Registrazione.Oid]);

  Esito := Fornitore.Firma(Documento);

  SegnaInviata(Connessione, Registrazione.IdFirmaRegistrazione, Esito.IdDocumentoEsterno, Esito.StatoEsterno);
  AccodaStato(Connessione, Contenuto, 1);

  Result := Format('%s%d: busta %s inviata', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, Esito.IdDocumentoEsterno]);
end;

function AggiornaStato(Connessione: TFDConnection; Contenuto: TJSONObject; const Registrazione: TFirmaRegistrazione; const Prodotto: TFirmaProdotto): string;
var
  Fornitore: IzFirmaProvider;
  Documento: TzFirmaDocumento;
  Esito: TzFirmaEsito;
  Giro: Integer;
begin
  Fornitore := CreaFornitore(Connessione, Registrazione);

  Documento.Clear;
  Documento.IdObjectFile := Registrazione.IdObjectFile;
  Documento.Oid := Registrazione.Oid;
  Documento.FullFileName := Prodotto.PercorsoFile(Connessione, Registrazione.IdObjectFile);

  Esito := Fornitore.AggiornaEstremi(Documento, Registrazione.IdDocumentoEsterno);

  if Esito.Stato = FIRMA_STATO_FIRMATA then
  begin
    SegnaFirmata(Connessione, Registrazione.IdFirmaRegistrazione, Esito);
    Exit(Format('%s%d: firmata, versione firmata %d', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, Esito.IdObjectFileFirmato]));
  end;

  if Esito.Stato = FIRMA_STATO_SCADUTA then
  begin
    EseguiProcedura(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_SCADUTA', Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno);
    Exit(Format('%s%d: scaduta', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione]));
  end;

  if Esito.Stato = FIRMA_STATO_RESPINTA then
  begin
    EseguiProcedura(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_RESPINTA_FORNITORE', Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno);
    Exit(Format('%s%d: respinta (%s)', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno]));
  end;

  EseguiProcedura(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_STATO_ESTERNO', Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno);

  Giro := JsonInt(Contenuto, 'giro', 1);

  if Giro >= TAppConfig.Instance.Firma.GiriMassimi then
  begin
    // Oltre il tetto si smette di chiedere: la registrazione resta in D con
    // l'ultimo stato del fornitore, e il programma desktop puo' ancora
    // aggiornarla.
    LogW(Format('Firma %d: busta ancora aperta dopo %d controlli, la coda smette di seguirla', [Registrazione.IdFirmaRegistrazione, Giro]));
    Exit(Format('%s%d: ancora aperta (%s) dopo %d controlli, non piu'' seguita', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno, Giro]));
  end;

  AccodaStato(Connessione, Contenuto, Giro + 1);
  Result := Format('%s%d: ancora aperta (%s), controllo %d', [PrefissoEsitoFirma, Registrazione.IdFirmaRegistrazione, Esito.StatoEsterno, Giro]);
end;

// Parte comune dei due gestori: controlli sul lavoro, contesto utente,
// lettura della registrazione e contesto svuotato alla fine.
function Gestisci(const Tipo: string; Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
var
  IdFirmaRegistrazione: Int64;
  UserId: Int64;
  IdSessione: Int64;
  Registrazione: TFirmaRegistrazione;
  Prodotto: TFirmaProdotto;
begin
  IdFirmaRegistrazione := JsonInt64(Contenuto, 'idFirmaRegistrazione');
  UserId := JsonInt64(Contenuto, 'userId');
  IdSessione := JsonInt64(Contenuto, 'idSessione');

  if IdFirmaRegistrazione <= 0 then
  begin
    Messaggio := Format('Lavoro %s senza registrazione di firma.', [Tipo]);
    Exit(False);
  end;

  if UserId <= 0 then
  begin
    Messaggio := Format('Lavoro %s senza utente: va accodato da una richiesta autenticata.', [Tipo]);
    Exit(False);
  end;

  Prodotto := TFirmaProdotti.Corrente;

  TAppProfiles.Corrente.ImpostaContesto(Connessione, UserId, IdSessione, JsonStr(Contenuto, 'userName'));
  try
    Registrazione := LeggiRegistrazione(Connessione, IdFirmaRegistrazione);

    if not Registrazione.Trovata then
    begin
      Messaggio := Format('%s%d: registrazione inesistente.', [PrefissoEsitoFirma, IdFirmaRegistrazione]);
      Exit(False);
    end;

    if Tipo = TipoCodaFirma then
    begin
      // Si invia solo da A e senza busta assegnata: il programma desktop o
      // un giro precedente possono averla gia' inviata.
      if (Registrazione.Stato <> FIRMA_STATO_APPROVATA) or (not Registrazione.IdDocumentoEsterno.IsEmpty) then
      begin
        Messaggio := Format('%s%d: stato %s, busta %s, niente da inviare', [PrefissoEsitoFirma, IdFirmaRegistrazione, Registrazione.Stato, Registrazione.IdDocumentoEsterno]);
        Exit(True);
      end;

      Messaggio := InviaRegistrazione(Connessione, Contenuto, Registrazione, Prodotto);
    end
    else
    begin
      if (Registrazione.Stato <> FIRMA_STATO_IN_FIRMA) or Registrazione.IdDocumentoEsterno.IsEmpty then
      begin
        Messaggio := Format('%s%d: stato %s, niente da controllare', [PrefissoEsitoFirma, IdFirmaRegistrazione, Registrazione.Stato]);
        Exit(True);
      end;

      Messaggio := AggiornaStato(Connessione, Contenuto, Registrazione, Prodotto);
    end;
  finally
    // La variabile di contesto non segue le transazioni: va svuotata anche
    // quando il lavoro fallisce, la connessione serve gli altri lavori.
    try
      TAppProfiles.Corrente.AzzeraContesto(Connessione);
    except
      on E: Exception do
        LogE('Firma: contesto utente non svuotato sulla connessione della coda: ' + E.Message);
    end;
  end;

  Result := True;
end;

function FirmaCollegamento(Connessione: TFDConnection; const IdFirmaRegistrazione: Int64; const IndirizzoRitorno: string): TFirmaCollegamento;
var
  Registrazione: TFirmaRegistrazione;
  Fornitore: IzFirmaProvider;
  Collegamento: IzFirmaCollegamento;
  Firmatari: TArray<TzFirmaFirmatario>;
  Firmatario: TzFirmaFirmatario;
  Scelto: TzFirmaFirmatario;
  Trovato: Boolean;
begin
  Result := Default(TFirmaCollegamento);
  Scelto.Clear;

  Registrazione := LeggiRegistrazione(Connessione, IdFirmaRegistrazione);

  if not Registrazione.Trovata then
    raise EzFirmaErrore.CreateFmt('Registrazione di firma %d inesistente.', [IdFirmaRegistrazione]);

  Result.Stato := Registrazione.Stato;

  if Registrazione.Stato = FIRMA_STATO_APPROVATA then
  begin
    Result.Messaggio := 'Il documento si sta preparando per la firma: riprova fra qualche secondo.';
    Exit;
  end;

  if Registrazione.Stato = FIRMA_STATO_FIRMATA then
  begin
    Result.Messaggio := 'Il documento e'' gia'' firmato.';
    Exit;
  end;

  if (Registrazione.Stato <> FIRMA_STATO_IN_FIRMA) or Registrazione.IdDocumentoEsterno.IsEmpty then
  begin
    Result.Messaggio := Format('La richiesta di firma non e'' piu'' aperta (stato %s).', [Registrazione.Stato]);
    Exit;
  end;

  Fornitore := CreaFornitore(Connessione, Registrazione);

  if not Supports(Fornitore, IzFirmaCollegamento, Collegamento) then
    raise EzFirmaNonSupportato.CreateFmt('Il fornitore %s non gestisce la firma al banco.', [Fornitore.Nome]);

  // Il firmatario in presenza e' quello che firma con il codice (OTP): le
  // firme remote automatiche non hanno una pagina di firma.
  Firmatari := TFirmaProdotti.Corrente.LeggiFirmatari(Connessione, Registrazione);
  Trovato := False;

  for Firmatario in Firmatari do
    if Firmatario.IdentificativoFirmaRemota.IsEmpty then
    begin
      Scelto := Firmatario;
      Trovato := True;
      Break;
    end;

  if not Trovato then
    raise EzFirmaErrore.CreateFmt('La registrazione %d non ha un firmatario che firmi in presenza.', [IdFirmaRegistrazione]);

  Result.Collegamento := Collegamento.CollegamentoFirma(Registrazione.IdDocumentoEsterno, Scelto, IndirizzoRitorno);

  if Result.Collegamento.IsEmpty then
    Result.Messaggio := 'Il fornitore non ha ancora il collegamento di firma: riprova fra qualche secondo.';
end;

function GestisciFirma(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
begin
  Result := Gestisci(TipoCodaFirma, Contenuto, Connessione, Messaggio);
end;

function GestisciFirmaStato(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
begin
  Result := Gestisci(TipoCodaFirmaStato, Contenuto, Connessione, Messaggio);
end;

initialization

TCodaGestori.Registra(TipoCodaFirma, GestisciFirma);
TCodaGestori.Registra(TipoCodaFirmaStato, GestisciFirmaStato);

end.
