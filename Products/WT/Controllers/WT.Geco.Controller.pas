// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-08
// ---------------------------------------------------------------------------
unit WT.Geco.Controller;

// Portato da Moduli\WT\dmGeCo.pas (classe TGeCo, framework TRoute).
//
// Scambio dati con i dispositivi in campo (GeCo, WinEco, censimento):
//
// dal dispositivo al database  initImport, importDataSet, doneImport
// dal database al dispositivo  initExport, getDB / getDataBase, doneExport,
// afterDbDeleted, getStatus
// interrogazioni dirette       getTessera, getPratica, getContenitore
// centri del riuso             cdr/firme/{id}/collegamento (2026-11-07)
//
// Firma al banco delle liberatorie dei centri del riuso (2026-11-07):
// GET /api/wt/geco/cdr/firme/{idFirmaRegistrazione}/collegamento?ritorno=...
// restituisce il collegamento alla pagina di firma del cittadino, che Pipa
// apre sul tablet del centro. La richiesta di firma la crea il database
// (WTWEB_GECO_CDR_BENE_DOCUMENTO_FIRMA_AL_BANCO, chiamata da Pipa come le
// altre procedure), la busta la invia la coda (Firma.Gestore): finche' la
// busta non e' partita il collegamento e' vuoto e Pipa richiede. Solo le
// registrazioni dei documenti dei beni (CDR_BENI_DOCUMENTI) e nel perimetro
// dell'utente, la stessa verifica di GET /api/files.
//
// Database per il lavoro senza linea (2026-11-08): il server prepara un file
// SQLite cifrato SQLCipher 4 con la chiave del dispositivo e il telefono lo
// scarica e lo apre cosi' com'e'. Rotte:
// POST dispositivo/chiave        il telefono consegna la chiave alla registrazione
// POST fotografia                crea il lavoro (GERA_SYNC_JOBS) e lo prepara in
// un filo proprio, risponde subito col numero
// GET  fotografia/{id}           fase e avanzamento (dataset i di n, righe)
// POST fotografia/{id}/biglietto biglietto monouso di 10 minuti
// GET  fotografia/{id}/{b}/{nome}.db  il file, senza token: vale il biglietto,
// perche' il plugin del telefono non puo' inviare l'intestazione; il nome (lettere, cifre,
// trattino basso) lo sceglie il telefono, che lo usa come nome del database
// POST fotografia/{id}/scaricato conferma, il file si elimina
// Il contenuto lo descrive GERA_SYNC_SCHEMA_DATASET (EXPORT_SQL, INDEXES): ogni
// dataset si travasa con TFDBatchMove, poi INFO_TABELLE con i conteggi,
// PRAGMA user_version = 1 e cifratura. Non serve lo .zip: un file cifrato non
// si comprime. Il motore e' SQLite3 Multiple Ciphers, libreria esterna accanto
// all'eseguibile (sqlite3mc_x64.dll, sqlite3mc.dll o libsqlite3mc.so).
//
// Due cose da sapere sul porto:
//
// 1. I componenti (memoria, query, travaso, connessione SQLite) erano posati
// sul DataModule e alcuni avevano la connessione sbagliata assegnata a
// tempo di progetto — venivano riassegnati in esecuzione da InitDataSet.
// Qui nascono e muoiono dentro l'azione che li usa: un controller
// DMVCFramework vive una richiesta, e componenti condivisi fra richieste
// concorrenti sarebbero un guaio.
//
// 2. Le SQL erano nel DFM. Sono state riportate nel codice, identiche, cosi'
// si leggono dove si usano.
//
// La cifratura con password fissa di Geco.Common.Consts non si usa piu': la
// chiave e' una per dispositivo, custodita cifrata in GECO_DISPOSITIVI.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Data.DB,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Stan.StorageJSON,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Comp.BatchMove,
  FireDAC.Comp.BatchMove.SQL,
  Base.Controller,
  Data.Service;

type

  [MVCPath('/api/wt/geco')]
  [MVCDoc('Scambio dati con i dispositivi in campo')]
  TWTGecoController = class(TBaseController)
  private
    function EseguiProceduraDiLavoro(const NomeProcedura: string): TJSONObject;
    function LeggiValore(const Nome: string): string;
    function TrovaDispositivo(Connessione: TFDConnection; const Crea: Boolean; out Attivo, HaChiave: Boolean): Int64;
    procedure VerificaOperatore(Connessione: TFDConnection);
    procedure ElaboraDatabasePalmare(const SenzaAccesso: Boolean);
    function VerificaAmministratore(Connessione: TFDConnection): Int64;
    function CreaQueryLavoro(Connessione: TFDConnection; const IdLavoro: Int64): TFDQuery;
    procedure PulisciFotografieScadute(Connessione: TFDConnection);
  public
    // ── dal dispositivo al database ──
    [MVCPath('/import-dataset')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Importa un dataset inviato dal dispositivo')]
    procedure ImportDataSet;

    [MVCPath('/done-import')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Chiude il lavoro di importazione')]
    procedure DoneImport;

    // ── dal database al dispositivo ──
    // Database SQLite cifrato preparato dal server (2026-11-08)
    [MVCPath('/dispositivo/chiave')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Registra la chiave di cifratura del telefono (modello, seriale, chiave)')]
    procedure RegistraChiaveDispositivo;

    [MVCPath('/fotografia')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Avvia la preparazione del database SQLite cifrato (modello, seriale) e risponde con il numero del lavoro')]
    procedure AvviaFotografia;

    [MVCPath('/fotografia/($idLavoro)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Fase e avanzamento della preparazione')]
    procedure StatoFotografia(const idLavoro: Int64);

    [MVCPath('/fotografia/($idLavoro)/biglietto')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Biglietto monouso per scaricare il file pronto')]
    procedure BigliettoFotografia(const idLavoro: Int64);

    [MVCPath('/fotografia/($idLavoro)/($biglietto)/($nomeFile)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Scarica il database SQLite cifrato (senza token: vale il biglietto)')]
    procedure ScaricaFotografia(const idLavoro: Int64; const biglietto: string; const nomeFile: string);

    [MVCPath('/fotografia/($idLavoro)/scaricato')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Il telefono conferma lo scaricamento: il file si elimina')]
    procedure FotografiaScaricata(const idLavoro: Int64);

    // Recupero del database del palmare (2026-11-08): il telefono invia il proprio database
    // `geco_<UTENTE>` (coda e mappe) cosi' com'e', cifrato; zServer lo conserva, lo apre con la
    // chiave del dispositivo e descrive la coda. L'integrazione delle operazioni non c'e' ancora.
    [MVCPath('/recupero')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Riceve il database cifrato del palmare (multipart, campo file; modello e seriale nel modulo o nell''indirizzo), lo apre con la chiave del dispositivo e descrive la coda')]
    procedure RiceviDatabasePalmare;

    // Stesso invio dalla pagina di accesso dell'app, quando il telefono non riesce piu' ad accedere:
    // niente gettone, vale il telefono registrato (modello, seriale); la risposta non descrive il file.
    [MVCPath('/recupero-assistenza')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Riceve il database cifrato del palmare senza accesso (multipart, campo file con nome geco_<UTENTE>.db, modello e seriale); un file ogni dieci minuti per telefono')]
    procedure RiceviDatabasePalmareSenzaAccesso;

    // Integrazione del recupero (2026-11-08): l'amministratore di GeCo rilancia le operazioni della
    // coda del palmare, con le stesse procedure e nello stesso ordine, a nome dell'operatore del
    // palmare; il resoconto sta in GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.
    [MVCPath('/recupero/($idRecupero)/integra')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Integra nel database le operazioni della coda del palmare (solo amministratori di GeCo; uuid facoltativo per rilanciarne una sola) e restituisce il resoconto')]
    procedure IntegraRecupero(const idRecupero: Int64);

    [MVCPath('/recupero/($idRecupero)/operazioni/($uuid)/scarta')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Scarta un''operazione rifiutata o da integrare, lasciandone traccia (solo amministratori di GeCo)')]
    procedure ScartaOperazioneRecupero(const idRecupero: Int64; const uuid: string);

    [MVCPath('/recupero/($idRecupero)/file')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Scarica il database cifrato ricevuto dal palmare (solo amministratori di GeCo)')]
    procedure ScaricaFileRecupero(const idRecupero: Int64);

    [MVCPath('/done-export')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Chiude il lavoro di esportazione')]
    procedure DoneExport;

    [MVCPath('/db-eliminato')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Il dispositivo dichiara di aver eliminato il database ricevuto')]
    procedure AfterDbDeleted;

    [MVCPath('/errore')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Registra un errore segnalato dal dispositivo')]
    procedure SetErrorMsg;

    // ── interrogazioni dirette ──
    [MVCPath('/tessera')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Cerca una tessera su una isola ecologica')]
    procedure GetTessera;

    [MVCPath('/pratica')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Cerca una pratica e i suoi contenitori')]
    procedure GetPratica;

    [MVCPath('/contenitore')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Cerca un contenitore per matricola, RFID o numero di serie')]
    procedure GetContenitore;

    // ── centri del riuso ──
    [MVCPath('/cdr/firme/($idFirmaRegistrazione)/collegamento')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Collegamento alla pagina di firma di un documento di un bene, per la firma al banco')]
    procedure GetCollegamentoFirmaCdr(const idFirmaRegistrazione: Int64);
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.SyncObjs,
  Web.HTTPApp,
  System.Variants,
  System.DateUtils,
  FireDAC.Phys.SQLiteWrapper,
  MVCFramework.Logger,
  FiredacHelper,
  Json.Values,
  App.Profile,
  Queue.Service,
  Connection.Pool,
  Session.Context,
  zDocumentale.Firma.Types,
  Firma.Gestore;

const
  SQL_DATASET_DA_ESPORTARE = 'SELECT' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.ID_GERA_SYNC_SCHEMA,' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.DATASET_NAME,' + sLineBreak +
    '    GERA_SYNC_SCHEMA_DATASET.EXPORT_SQL,' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.INDEXES' + sLineBreak + 'FROM' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET' + sLineBreak +
    '          INNER JOIN GERA_SYNC_JOBS ON GERA_SYNC_SCHEMA_DATASET.ID_GERA_SYNC_SCHEMA = GERA_SYNC_JOBS.ID_GERA_SYNC_SCHEMA' + sLineBreak + 'WHERE' + sLineBreak +
    '    GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB AND' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.ATTIVO = ''S''' + sLineBreak + 'ORDER BY' + sLineBreak +
    '    GERA_SYNC_SCHEMA_DATASET.ORDINE_EXPORT,' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.DATASET_NAME';

  SQL_PROCEDURA_DI_IMPORTAZIONE = 'SELECT' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.IMPORT_PROC' + sLineBreak + 'FROM' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET' + sLineBreak +
    '              INNER JOIN GERA_SYNC_JOBS ON GERA_SYNC_SCHEMA_DATASET.ID_GERA_SYNC_SCHEMA = GERA_SYNC_JOBS.ID_GERA_SYNC_SCHEMA' + sLineBreak + 'WHERE' + sLineBreak +
    '    GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB AND' + sLineBreak + '    GERA_SYNC_SCHEMA_DATASET.DATASET_NAME = :DATASET_NAME';

  SQL_CERCA_TESSERA = 'SELECT * FROM ISOLE_CERCA_TESSERA(:CODICE_ISOLA, :CODICE_TESSERA)';
  SQL_CERCA_PRATICA = 'SELECT * FROM GERA_SYNC_CERCA_PRATICA(:ID_OPERATORE, :ID_PRATICA)';
  SQL_CERCA_PRATICA_CONTENITORI = 'SELECT * FROM GERA_SYNC_CERCA_PRATICA_CONTEN(:ID_PRATICA)';

const
  // Il motore SQLite con la cifratura SQLCipher (SQLite3 Multiple Ciphers) e'
  // una libreria esterna accanto all'eseguibile: il motore incorporato di
  // FireDAC non sa scrivere il formato che il telefono apre.
{$IFDEF MSWINDOWS}
{$IFDEF CPUX64}
  NomeLibreriaSQLite = 'sqlite3mc_x64.dll';
{$ELSE}
  NomeLibreriaSQLite = 'sqlite3mc.dll';
{$ENDIF}
{$ELSE}
  NomeLibreriaSQLite = 'libsqlite3mc.so';
{$ENDIF}
  NomeCartellaFotografie = 'zServerGeco';

  // Quante preparazioni possono leggere Firebird insieme: ognuna legge
  // centinaia di migliaia di righe.
  PreparazioniContemporaneeMassime = 3;
  MinutiValiditaBiglietto = 10;
  OreValiditaFile = 6;
  OreConservazioneFile = 24;
  MinutiPreparazioneMassima = 120;
  LunghezzaBiglietto = 40;
  // Il plugin del telefono apre i database con questa versione
  VersioneFormatoDatabase = 1;

  StatoNonPiuDisponibile = 410;
  StatoTroppeRichieste = 429;

  // Fasi di GERA_SYNC_JOBS.FASE (dominio GERA_FASE_JOB)
  FasePronto = 'P';
  FaseScaricato = 'S';

  SQL_LAVORO_DELL_UTENTE = 'SELECT GERA_SYNC_JOBS.FASE, GERA_SYNC_JOBS.DATASET_CORRENTE, GERA_SYNC_JOBS.DATASET_NUMERO, GERA_SYNC_JOBS.DATASET_TOTALE, ' +
    'GERA_SYNC_JOBS.RIGHE, GERA_SYNC_JOBS.FILE_BYTE, GERA_SYNC_JOBS.DATA_ORA_SCADENZA_FILE, GERA_SYNC_JOBS.ERRORE ' +
    'FROM GERA_SYNC_JOBS WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB AND ' +
    'GERA_SYNC_JOBS.ID_OPERATORE IN (SELECT GERA_OPERATORI.ID_OPERATORE FROM GERA_OPERATORI WHERE GERA_OPERATORI.USER_ID = :USER_ID)';

var
  // Lo stato condiviso fra richieste e fili di preparazione: i lavori in
  // corso (numero del lavoro e utente) e il collegamento al motore SQLite,
  // che e' uno per processo e vive fino alla chiusura.
  CollegamentoSQLite: TFDPhysSQLiteDriverLink;
  LucchettoPreparazioni: TCriticalSection;
  PreparazioniAttive: TDictionary<Int64, string>;

function CartellaFotografie: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetTempPath, NomeCartellaFotografie));
  ForceDirectories(Result);
end;

function PercorsoFileFotografia(const IdLavoro: Int64; const Definitivo: Boolean): string;
begin
  if Definitivo then
    Result := CartellaFotografie + IdLavoro.ToString + '.db'
  else
    Result := CartellaFotografie + IdLavoro.ToString + '.tmp';
end;

procedure EliminaFile(const NomeFile: string);
begin
  try
    if TFile.Exists(NomeFile) then
      TFile.Delete(NomeFile);
  except
    on E: Exception do
      LogW('Impossibile eliminare ' + NomeFile + ': ' + E.Message);
  end;
end;

function DimensioneFile(const NomeFile: string): Int64;
var
  Flusso: TFileStream;
begin
  Flusso := TFileStream.Create(NomeFile, fmOpenRead or fmShareDenyNone);
  try
    Result := Flusso.Size;
  finally
    FreeAndNil(Flusso);
  end;
end;

// Raddoppia gli apici: PRAGMA e ATTACH non accettano parametri legati.
function TestoSql(const Valore: string): string;
begin
  Result := Valore.Replace('''', '''''');
end;

procedure AssicuraCollegamentoSQLite;
var
  Libreria: string;
begin
  LucchettoPreparazioni.Enter;
  try
    if Assigned(CollegamentoSQLite) then
      Exit;

    Libreria := TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), NomeLibreriaSQLite);

    if not TFile.Exists(Libreria) then
      raise EMVCException.Create(HTTP_STATUS.ServiceUnavailable, 'Libreria SQLite con cifratura non trovata: ' + NomeLibreriaSQLite);

    CollegamentoSQLite := TFDPhysSQLiteDriverLink.Create(nil);
    CollegamentoSQLite.DriverID := 'SQLite';
    CollegamentoSQLite.EngineLinkage := slDynamic;
    CollegamentoSQLite.VendorLib := Libreria;
  finally
    LucchettoPreparazioni.Leave;
  end;
end;

// Scrive sul lavoro con una connessione propria e conferma subito: chi
// interroga lo stato deve vedere l'avanzamento mentre la preparazione gira.
procedure ScriviLavoro(Connessione: TFDConnection; const SQL: string; const Valori: array of Variant);
begin
  Connessione.ExecSQL(SQL, Valori);

  if Connessione.InTransaction then
    Connessione.Commit;
end;

// Travasa i dataset dello schema in un file SQLite, crea gli indici, scrive
// INFO_TABELLE con i conteggi e cifra il file in formato SQLCipher 4. La
// cifratura avviene a file finito, sulla stessa connessione: FireDAC non
// lascia impostare cipher e legacy fra l'apertura e la chiave.
procedure CostruisciDatabase(const IdLavoro: Int64; Lettura, Avanzamento: TFDConnection; const NomeFileLavoro, Chiave: string;
  out TabelleScritte: Integer; out RigheTotali: Int64);
var
  ConnessioneSQLite: TFDConnection;
  Lettore: TFDBatchMoveSQLReader;
  Scrittore: TFDBatchMoveSQLWriter;
  Travaso: TFDBatchMove;
  Elenco: TFDQuery;
  Indici: TStringList;
  Conteggi: TStringList;
  Nome: string;
  Indice: string;
  Carattere: Char;
  Numero: Integer;
  Totale: Integer;
  Righe: Int64;
  Posizione: Integer;
begin
  RigheTotali := 0;
  TabelleScritte := 0;
  AssicuraCollegamentoSQLite;

  ConnessioneSQLite := TFDConnection.Create(nil);
  Lettore := TFDBatchMoveSQLReader.Create(nil);
  Scrittore := TFDBatchMoveSQLWriter.Create(nil);
  Travaso := TFDBatchMove.Create(nil);
  Elenco := TFDQuery.Create(nil);
  Indici := TStringList.Create;
  Conteggi := TStringList.Create;
  try
    ConnessioneSQLite.Params.Clear;
    ConnessioneSQLite.Params.Add('DriverID=SQLite');
    ConnessioneSQLite.Params.Add('Database=' + NomeFileLavoro);
    ConnessioneSQLite.Params.Add('Synchronous=Off');
    ConnessioneSQLite.Params.Add('LockingMode=Exclusive');
    ConnessioneSQLite.LoginPrompt := False;
    ConnessioneSQLite.Connected := True;

    Lettore.Connection := Lettura;
    Scrittore.Connection := ConnessioneSQLite;
    Travaso.Reader := Lettore;
    Travaso.Writer := Scrittore;

    Elenco.Connection := Lettura;
    Elenco.SQL.Text := SQL_DATASET_DA_ESPORTARE;
    Elenco.ParamByName('ID_GERA_SYNC_JOB').AsLargeInt := IdLavoro;
    Elenco.Open;
    Elenco.FetchAll;

    if Elenco.IsEmpty then
      raise Exception.CreateFmt('Nessun dataset da esportare per il lavoro %d.', [IdLavoro]);

    Totale := Elenco.RecordCount;
    Numero := 0;
    Elenco.First;

    while not Elenco.Eof do
    begin
      Inc(Numero);
      Nome := Elenco.FieldByName('DATASET_NAME').AsString;

      // Il nome finisce in istruzioni SQL: solo lettere, cifre e trattino basso.
      for Carattere in Nome do
        if not CharInSet(Carattere, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
          raise Exception.CreateFmt('Nome di dataset non valido: %s', [Nome]);

      ScriviLavoro(Avanzamento,
        'UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.DATASET_CORRENTE = :DATASET_CORRENTE, GERA_SYNC_JOBS.DATASET_NUMERO = :DATASET_NUMERO, ' +
        'GERA_SYNC_JOBS.DATASET_TOTALE = :DATASET_TOTALE, GERA_SYNC_JOBS.RIGHE = :RIGHE WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB',
        [Nome, Numero, Totale, RigheTotali, IdLavoro]);

      // Il segnaposto del lavoro si sostituisce nel testo: la SQL arriva dal
      // database e il travaso non accetta parametri legati.
      Lettore.ReadSQL := Elenco.FieldByName('EXPORT_SQL').AsString.Replace(':ID_GERA_SYNC_JOB', IdLavoro.ToString, [rfReplaceAll, rfIgnoreCase]);
      Scrittore.TableName := Nome;

      try
        Travaso.Execute;
      except
        on E: Exception do
          raise Exception.CreateFmt('Errore esportazione tabella %s: %s', [Nome, E.Message]);
      end;

      Righe := ConnessioneSQLite.ExecSQLScalar('select count(*) from "' + Nome + '"');
      RigheTotali := RigheTotali + Righe;
      Conteggi.Add(Nome + '=' + Righe.ToString);

      Indici.Text := Elenco.FieldByName('INDEXES').AsString;

      for Indice in Indici do
      begin
        if Indice.Trim.IsEmpty then
          Continue;

        try
          ConnessioneSQLite.ExecSQL(Indice);
        except
          on E: Exception do
            raise Exception.CreateFmt('Errore indicizzazione tabella %s: %s', [Nome, E.Message]);
        end;
      end;

      Elenco.Next;
    end;

    // I conteggi servono al telefono per verificare di aver ricevuto tutto.
    ConnessioneSQLite.ExecSQL('CREATE TABLE INFO_TABELLE (TABELLA TEXT NOT NULL PRIMARY KEY, RIGHE INTEGER NOT NULL)');

    for Posizione := 0 to Conteggi.Count - 1 do
      ConnessioneSQLite.ExecSQL('INSERT INTO INFO_TABELLE (TABELLA, RIGHE) VALUES (:TABELLA, :RIGHE)',
        [Conteggi.Names[Posizione], StrToInt64(Conteggi.ValueFromIndex[Posizione])]);

    TabelleScritte := Conteggi.Count;

    ConnessioneSQLite.ExecSQL('PRAGMA user_version = ' + VersioneFormatoDatabase.ToString);
    ConnessioneSQLite.ExecSQL('PRAGMA cipher = ''sqlcipher''');
    ConnessioneSQLite.ExecSQL('PRAGMA legacy = 4');
    ConnessioneSQLite.ExecSQL('PRAGMA rekey = ''' + TestoSql(Chiave) + '''');
    ConnessioneSQLite.Connected := False;
  finally
    FreeAndNil(Conteggi);
    FreeAndNil(Indici);
    FreeAndNil(Elenco);
    FreeAndNil(Travaso);
    FreeAndNil(Scrittore);
    FreeAndNil(Lettore);
    FreeAndNil(ConnessioneSQLite);
  end;
end;

// Riapre il file con la chiave, come fa il telefono: se la cifratura non e'
// quella attesa il file non parte.
procedure VerificaCifratura(const NomeFile, Chiave: string; const TabelleAttese: Integer);
var
  Connessione: TFDConnection;
  Trovate: Integer;
  Versione: Integer;
begin
  Connessione := TFDConnection.Create(nil);
  try
    Connessione.Params.Clear;
    Connessione.Params.Add('DriverID=SQLite');
    Connessione.Params.Add('Database=:memory:');
    Connessione.LoginPrompt := False;
    Connessione.Connected := True;

    Connessione.ExecSQL('PRAGMA cipher = ''sqlcipher''');
    Connessione.ExecSQL('PRAGMA legacy = 4');
    Connessione.ExecSQL('ATTACH DATABASE ''' + TestoSql(NomeFile) + ''' AS verifica KEY ''' + TestoSql(Chiave) + '''');

    Trovate := Connessione.ExecSQLScalar('select count(*) from verifica.INFO_TABELLE');
    Versione := Connessione.ExecSQLScalar('PRAGMA verifica.user_version');

    if Trovate <> TabelleAttese then
      raise Exception.CreateFmt('Verifica del file: %d tabelle lette, %d attese.', [Trovate, TabelleAttese]);

    if Versione <> VersioneFormatoDatabase then
      raise Exception.CreateFmt('Verifica del file: versione %d, attesa %d.', [Versione, VersioneFormatoDatabase]);
  finally
    FreeAndNil(Connessione);
  end;
end;

// Apre il database di un palmare ricevuto (cifrato con la chiave del dispositivo) e ne descrive la
// coda: quante operazioni, quali, con quale stato e ultimo errore. Come VerificaCifratura, apre un
// database vuoto in memoria e ci collega il file con ATTACH ... KEY. Le operazioni escono come le ha
// scritte il telefono (uuid, ordine, descrizione, procedura, stato, tentativi, errore); i parametri,
// che possono contenere foto, non si restituiscono. Se la chiave e' sbagliata o il file non e' un
// database GeCo, solleva un'eccezione.
function LeggiDatabasePalmare(const NomeFile, Chiave: string; out OperazioniInCoda, Mappe: Integer): TJSONArray;
const
  OperazioniMassime = 500;
var
  Connessione: TFDConnection;
  Elenco: TFDQuery;
  Voce: TJSONValue;
  Riga: TJSONObject;
begin
  AssicuraCollegamentoSQLite;
  Result := TJSONArray.Create;
  Connessione := TFDConnection.Create(nil);
  try
    try
      Connessione.Params.Clear;
      Connessione.Params.Add('DriverID=SQLite');
      Connessione.Params.Add('Database=:memory:');
      Connessione.LoginPrompt := False;
      Connessione.Connected := True;

      Connessione.ExecSQL('PRAGMA cipher = ''sqlcipher''');
      Connessione.ExecSQL('PRAGMA legacy = 4');
      Connessione.ExecSQL('ATTACH DATABASE ''' + TestoSql(NomeFile) + ''' AS palmare KEY ''' + TestoSql(Chiave) + '''');

      OperazioniInCoda := Connessione.ExecSQLScalar('select count(*) from palmare.coda');
      Mappe := Connessione.ExecSQLScalar('select count(*) from palmare.mappe');

      Elenco := TFDQuery.Create(nil);
      try
        Elenco.Connection := Connessione;
        Elenco.SQL.Text := 'select uuid, ordine, operazione from palmare.coda order by ordine limit ' + OperazioniMassime.ToString;
        Elenco.Open;

        while not Elenco.Eof do
        begin
          Riga := TJSONObject.Create;
          Riga.AddPair('uuid', Elenco.FieldByName('uuid').AsString);
          Riga.AddPair('ordine', TJSONNumber.Create(Elenco.FieldByName('ordine').AsLargeInt));

          Voce := TJSONObject.ParseJSONValue(Elenco.FieldByName('operazione').AsString);
          try
            if Voce is TJSONObject then
            begin
              Riga.AddPair('descrizione', TJSONObject(Voce).GetValue<string>('descrizione', ''));
              Riga.AddPair('procedura', TJSONObject(Voce).GetValue<string>('procedura', ''));
              Riga.AddPair('stato', TJSONObject(Voce).GetValue<string>('stato', ''));
              Riga.AddPair('versione', TJSONNumber.Create(TJSONObject(Voce).GetValue<Integer>('versione', 0)));
              Riga.AddPair('tentativi', TJSONNumber.Create(TJSONObject(Voce).GetValue<Integer>('tentativi', 0)));
              Riga.AddPair('errore', TJSONObject(Voce).GetValue<string>('errore', ''));
            end;
          finally
            FreeAndNil(Voce);
          end;

          Result.AddElement(Riga);
          Elenco.Next;
        end;
      finally
        FreeAndNil(Elenco);
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise;
      end;
    end;
  finally
    FreeAndNil(Connessione);
  end;
end;

type
  // Un'operazione della coda di un palmare recuperato, com'e' scritta nel suo database.
  TOperazionePalmare = class
  public
    Uuid: string;
    Ordine: Int64;
    Versione: Integer;
    Procedura: string;
    Descrizione: string;
    Parametri: TJSONArray;
    Prodotti: TJSONArray;
    destructor Destroy; override;
  end;

  // Esito dell'integrazione di una operazione, da scrivere nel resoconto.
  TEsitoOperazioneRecupero = record
    Uuid: string;
    Stato: string;
    Messaggio: string;
    Prodotti: string;
  end;

const
  // Le sole procedure che il file di un palmare puo' far eseguire al recupero: quelle che la coda
  // di Pipa invia (GecoCodaService). Il nome arriva dal file, che e' un dato del telefono: senza
  // questo elenco chi possiede la chiave di un telefono potrebbe far girare qualunque procedura
  // con i diritti dell'operatore.
  ProcedureRecuperabili: array[0..13] of string = (
    'WTWEB_GECO_ISOLE_ACCESSO_APRI',
    'WTWEB_GECO_ISOLE_CONFERIMENTO_ADD',
    'WTWEB_GECO_ISOLE_CONFERIMENTO_ANNULLA',
    'WTWEB_GECO_ISOLE_ACCESSO_DETTAGLI',
    'WTWEB_GECO_ISOLE_ACCESSO_CHIUDI',
    'WTWEB_GECO_CONSEGNE_PASSAGGIO_APRI',
    'WTWEB_GECO_CONSEGNE_CONTENITORE_AGGIUNGI',
    'WTWEB_GECO_ANAGRAFICA_NUOVA',
    'WTWEB_GECO_CONSEGNE_CONTENITORE_IMPOSTA',
    'WTWEB_GECO_CONSEGNE_FOTO_IMPOSTA',
    'WTWEB_GECO_CONSEGNE_FIRMA_POSIZIONE_IMPOSTA',
    'WTWEB_GECO_CONSEGNE_PASSAGGIO_CHIUDI',
    'WTWEB_GECO_CDR_BENE_PRENDI_IN_CARICO',
    'WTWEB_GECO_CDR_BENE_FOTO_AGGIUNGI');

var
  // Recuperi con un'integrazione in corso: due amministratori non integrano lo stesso file insieme.
  RecuperiInCorso: TDictionary<Int64, Boolean>;

destructor TOperazionePalmare.Destroy;
begin
  FreeAndNil(Parametri);
  FreeAndNil(Prodotti);
  inherited;
end;

// Valore di un campo del JSON come testo, vuoto se manca o e' null (un numero esce con le sue cifre).
function TestoDelCampo(Oggetto: TJSONObject; const Nome: string): string;
var
  Valore: TJSONValue;
begin
  Result := '';
  Valore := Oggetto.GetValue(Nome);

  if Assigned(Valore) and not (Valore is TJSONNull) then
    Result := Valore.Value;
end;

// Il testo di un RAISE_ERROR arriva da Firebird come "... exception N / E / <testo> / At ...":
// si tiene la riga del testo, come fa l'app del telefono.
function MotivoDelRifiuto(const Messaggio: string): string;
var
  Righe: TArray<string>;
  Indice: Integer;
begin
  Result := Messaggio.Trim;
  Righe := Messaggio.Replace(#13, '').Split([#10]);

  for Indice := 0 to Length(Righe) - 3 do
    // La riga comincia con "[FireDAC][Phys][FB]exception N": il prefisso del driver non conta.
    if Pos('exception ', Righe[Indice]) > 0 then
    begin
      Result := Righe[Indice + 2].Trim;
      Exit;
    end;
end;

// Una riga del resoconto per ogni operazione del file, creata una volta sola: se esiste gia'
// ne cambia la descrizione ma non lo stato.
procedure AssicuraRigaOperazione(Connessione: TFDConnection; const IdRecupero, Ordine: Int64; const Uuid, Procedura, Descrizione: string;
  const Versione: Integer);
begin
  Connessione.ExecSQL('UPDATE OR INSERT INTO GECO_DISPOSITIVI_RECUPERI_OPERAZIONI (ID_RECUPERO, UUID_OPERAZIONE, ORDINE, PROCEDURA, DESCRIZIONE, VERSIONE_FORMATO) ' +
    'VALUES (:ID_RECUPERO, :UUID_OPERAZIONE, :ORDINE, :PROCEDURA, :DESCRIZIONE, :VERSIONE_FORMATO) MATCHING (ID_RECUPERO, UUID_OPERAZIONE)',
    [IdRecupero, Uuid, Ordine, Copy(Procedura, 1, 255), Copy(Descrizione, 1, 255), Versione]);
end;

// Apre il database di un palmare (come LeggiDatabasePalmare) e ne legge la coda per intero, con i
// parametri di ogni operazione, e le mappe degli identificativi provvisori gia' accettati dal server.
function LeggiCodaCompletaPalmare(const NomeFile, Chiave: string; Mappe: TDictionary<Int64, Int64>): TObjectList<TOperazionePalmare>;
const
  OperazioniMassime = 5000;
var
  Connessione: TFDConnection;
  Elenco: TFDQuery;
  Voce: TJSONValue;
  Valore: TJSONValue;
  Operazione: TOperazionePalmare;
begin
  AssicuraCollegamentoSQLite;
  Result := TObjectList<TOperazionePalmare>.Create(True);
  Connessione := TFDConnection.Create(nil);
  try
    try
      Connessione.Params.Clear;
      Connessione.Params.Add('DriverID=SQLite');
      Connessione.Params.Add('Database=:memory:');
      Connessione.LoginPrompt := False;
      Connessione.Connected := True;

      Connessione.ExecSQL('PRAGMA cipher = ''sqlcipher''');
      Connessione.ExecSQL('PRAGMA legacy = 4');
      Connessione.ExecSQL('ATTACH DATABASE ''' + TestoSql(NomeFile) + ''' AS palmare KEY ''' + TestoSql(Chiave) + '''');

      Elenco := TFDQuery.Create(nil);
      try
        Elenco.Connection := Connessione;
        Elenco.SQL.Text := 'select locale, server from palmare.mappe';
        Elenco.Open;

        while not Elenco.Eof do
        begin
          Mappe.AddOrSetValue(Elenco.FieldByName('locale').AsLargeInt, Elenco.FieldByName('server').AsLargeInt);
          Elenco.Next;
        end;

        Elenco.Close;
        Elenco.SQL.Text := 'select uuid, ordine, operazione from palmare.coda order by ordine limit ' + OperazioniMassime.ToString;
        Elenco.Open;

        while not Elenco.Eof do
        begin
          Voce := TJSONObject.ParseJSONValue(Elenco.FieldByName('operazione').AsString);
          try
            if Voce is TJSONObject then
            begin
              Operazione := TOperazionePalmare.Create;
              try
                Operazione.Uuid := Elenco.FieldByName('uuid').AsString;
                Operazione.Ordine := Elenco.FieldByName('ordine').AsLargeInt;
                Operazione.Procedura := TestoDelCampo(TJSONObject(Voce), 'procedura');
                Operazione.Descrizione := TestoDelCampo(TJSONObject(Voce), 'descrizione');
                Operazione.Versione := StrToIntDef(TestoDelCampo(TJSONObject(Voce), 'versione'), 0);

                Valore := TJSONObject(Voce).GetValue('parametri');

                if Valore is TJSONArray then
                  Operazione.Parametri := TJSONArray(Valore.Clone)
                else
                  Operazione.Parametri := TJSONArray.Create;

                Valore := TJSONObject(Voce).GetValue('prodotti');

                if Valore is TJSONArray then
                  Operazione.Prodotti := TJSONArray(Valore.Clone)
                else
                  Operazione.Prodotti := TJSONArray.Create;
              except
                FreeAndNil(Operazione);
                raise;
              end;

              Result.Add(Operazione);
            end;
          finally
            FreeAndNil(Voce);
          end;

          Elenco.Next;
        end;
      finally
        FreeAndNil(Elenco);
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise;
      end;
    end;
  finally
    FreeAndNil(Connessione);
  end;
end;

// Esegue una operazione del palmare con la connessione dell'operatore (contesto gia' impostato).
// Un identificativo negativo (nato sul telefono) si traduce con le mappe; l'operazione che non si
// puo' tradurre non parte. Ogni operazione e' una transazione a se': un rifiuto non ferma le altre.
// Gli identificativi che l'operazione produce entrano nelle mappe, per le operazioni successive.
function EseguiOperazioneRecuperata(Connessione: TFDConnection; Operazione: TOperazionePalmare; Mappe: TDictionary<Int64, Int64>;
  const IdSessione: Int64): TEsitoOperazioneRecupero;
var
  Parametri: TParamValues;
  Elemento: TJSONValue;
  Voce: TJSONObject;
  Valore: TJSONValue;
  Risultato: TJSONObject;
  ProdottiScritti: TJSONArray;
  Coppia: TJSONObject;
  Nome: string;
  TipoDato: string;
  Note: string;
  Campo: string;
  NumeroLetto: Int64;
  IdServer: Int64;
  Provvisorio: Int64;
  DecimaleLetto: Double;
begin
  Result.Uuid := Operazione.Uuid;
  Result.Stato := 'R';
  Result.Messaggio := '';
  Result.Prodotti := '';

  if not MatchText(Operazione.Procedura, ProcedureRecuperabili) then
  begin
    Result.Messaggio := 'Procedura non ammessa nel recupero: ' + Copy(Operazione.Procedura, 1, 100);
    Exit;
  end;

  Parametri := TParamValues.Create;
  try
    for Elemento in Operazione.Parametri do
    begin
      if not (Elemento is TJSONObject) then
        Continue;

      Voce := TJSONObject(Elemento);
      Nome := UpperCase(TestoDelCampo(Voce, 'name'));
      TipoDato := TestoDelCampo(Voce, 'dataType');
      Valore := Voce.GetValue('value');

      if Nome.IsEmpty then
        Continue;

      if (Valore = nil) or (Valore is TJSONNull) then
      begin
        Parametri.AddOrSetValue(Nome, Null);
        Continue;
      end;

      if TipoDato = 'integer' then
      begin
        if not TryStrToInt64(Valore.Value, NumeroLetto) then
        begin
          Result.Messaggio := Format('Parametro %s non numerico.', [Nome]);
          Exit;
        end;

        // Un ID_* intero negativo e' un identificativo nato sul telefono (stessa regola dell'app).
        if Nome.StartsWith('ID_') and (NumeroLetto < 0) then
        begin
          Provvisorio := NumeroLetto;

          if not Mappe.TryGetValue(Provvisorio, IdServer) then
          begin
            Result.Messaggio := Format('Dipende da un''operazione non integrata (identificativo provvisorio %d senza corrispondenza).', [Provvisorio]);
            Exit;
          end;

          NumeroLetto := IdServer;
        end;

        Parametri.AddOrSetValue(Nome, NumeroLetto);
      end
      else if TipoDato = 'float' then
      begin
        if not TryStrToFloat(Valore.Value, DecimaleLetto, TFormatSettings.Invariant) then
        begin
          Result.Messaggio := Format('Parametro %s non numerico.', [Nome]);
          Exit;
        end;

        Parametri.AddOrSetValue(Nome, DecimaleLetto);
      end
      else
        Parametri.AddOrSetValue(Nome, Valore.Value);
    end;

    // La sessione e' quella del contesto impostato (CURRENT_SESSION_ID): la procedura la riconosce
    // senza cambiare utente. Il codice dell'operazione e' quello della voce, come nell'invio dell'app.
    Parametri.AddOrSetValue('ID_SESSIONE', IdSessione);

    if not Parametri.ContainsKey('UUID_OPERAZIONE') then
      Parametri.Add('UUID_OPERAZIONE', Operazione.Uuid);

    try
      Risultato := TDataService.ExecuteStoredProc(Connessione, Operazione.Procedura, Parametri, False, False);
    except
      on E: Exception do
      begin
        Result.Messaggio := Copy(MotivoDelRifiuto(E.Message), 1, 1000);
        Exit;
      end;
    end;
  finally
    FreeAndNil(Parametri);
  end;

  try
    Note := TestoDelCampo(Risultato, 'NOTE_ESITO').Trim;

    if TestoDelCampo(Risultato, 'ESITO') <> 'S' then
    begin
      Result.Messaggio := Copy(IfThen(Note.IsEmpty, 'Il server non l''ha registrata.', Note), 1, 1000);
      Exit;
    end;

    // Tutti i messaggi di "gia' fatto" delle procedure contengono "gia'".
    if Pos('gia''', Note) > 0 then
      Result.Stato := 'G'
    else
      Result.Stato := 'I';

    Result.Messaggio := Copy(Note, 1, 1000);

    ProdottiScritti := TJSONArray.Create;
    try
      for Elemento in Operazione.Prodotti do
      begin
        if not (Elemento is TJSONObject) then
          Continue;

        Campo := TestoDelCampo(TJSONObject(Elemento), 'campo');

        if TryStrToInt64(TestoDelCampo(TJSONObject(Elemento), 'locale'), Provvisorio) and TryStrToInt64(TestoDelCampo(Risultato, Campo), IdServer) and
          (Provvisorio <> 0) and (IdServer > 0) then
        begin
          Mappe.AddOrSetValue(Provvisorio, IdServer);
          Coppia := TJSONObject.Create;
          Coppia.AddPair('locale', TJSONNumber.Create(Provvisorio));
          Coppia.AddPair('server', TJSONNumber.Create(IdServer));
          ProdottiScritti.AddElement(Coppia);
        end;
      end;

      Result.Prodotti := ProdottiScritti.ToJSON;
    finally
      FreeAndNil(ProdottiScritti);
    end;
  finally
    FreeAndNil(Risultato);
  end;
end;

// Corpo del filo di preparazione. Fuori da una richiesta HTTP il contesto
// dell'utente non c'e': lo si deposita nel filo, cosi' la connessione di
// lettura dichiara USR_CONTEXT_SET come per una richiesta e le SQL dei dataset
// vedono il perimetro dell'operatore (USR_TMP_COMUNI).
procedure EseguiPreparazione(const IdLavoro, IdDispositivo, IdUtente, IdSessioneUtente: Int64; const NomeUtente: string);
var
  Lettura: TFDConnection;
  Avanzamento: TFDConnection;
  NomeLavoro: string;
  NomeFinale: string;
  Chiave: string;
  TabelleScritte: Integer;
  RigheTotali: Int64;
begin
  Lettura := nil;
  Avanzamento := nil;
  NomeLavoro := PercorsoFileFotografia(IdLavoro, False);
  NomeFinale := PercorsoFileFotografia(IdLavoro, True);

  try
    try
      TSessionContextManager.Imposta(IdUtente, IdSessioneUtente, NomeUtente);

      Avanzamento := TConnectionPool.Instance.Acquire({ ConContesto } False);
      ScriviLavoro(Avanzamento, 'UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''G'' WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB', [IdLavoro]);

      Chiave := VarToStr(Avanzamento.ExecSQLScalar('SELECT GECO_DISPOSITIVI_GET_CHIAVE.CHIAVE_IN_CHIARO FROM GECO_DISPOSITIVI_GET_CHIAVE(:ID_DISPOSITIVO_MOBILE)', [IdDispositivo]));

      if Avanzamento.InTransaction then
        Avanzamento.Commit;

      if Chiave.IsEmpty then
        raise Exception.Create('Chiave del dispositivo non disponibile.');

      EliminaFile(NomeLavoro);
      Lettura := TConnectionPool.Instance.Acquire;
      CostruisciDatabase(IdLavoro, Lettura, Avanzamento, NomeLavoro, Chiave, TabelleScritte, RigheTotali);
      VerificaCifratura(NomeLavoro, Chiave, TabelleScritte);

      EliminaFile(NomeFinale);
      TFile.Move(NomeLavoro, NomeFinale);

      ScriviLavoro(Avanzamento,
        'UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''P'', GERA_SYNC_JOBS.DATASET_CORRENTE = NULL, GERA_SYNC_JOBS.RIGHE = :RIGHE, ' +
        'GERA_SYNC_JOBS.FILE_BYTE = :FILE_BYTE, GERA_SYNC_JOBS.DATA_ORA_SCADENZA_FILE = DATEADD(HOUR, ' + OreValiditaFile.ToString + ', CURRENT_TIMESTAMP) ' +
        'WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB',
        [RigheTotali, DimensioneFile(NomeFinale), IdLavoro]);

      LogI(Format('Preparazione GeCo %d completata: %d tabelle, %d righe', [IdLavoro, TabelleScritte, RigheTotali]));
    except
      on E: Exception do
      begin
        LogE(Format('Preparazione GeCo %d fallita: %s', [IdLavoro, E.Message]));
        EliminaFile(NomeLavoro);
        EliminaFile(NomeFinale);

        try
          if not Assigned(Avanzamento) then
            Avanzamento := TConnectionPool.Instance.Acquire({ ConContesto } False);

          if Avanzamento.InTransaction then
            Avanzamento.Rollback;

          ScriviLavoro(Avanzamento,
            'UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''E'', GERA_SYNC_JOBS.ERRORE = :ERRORE WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB',
            [E.Message, IdLavoro]);
        except
          on E2: Exception do
            LogE(Format('Preparazione GeCo %d: errore non registrato sul lavoro: %s', [IdLavoro, E2.Message]));
        end;
      end;
    end;
  finally
    if Assigned(Lettura) then
      TConnectionPool.Instance.Release(Lettura);

    if Assigned(Avanzamento) then
      TConnectionPool.Instance.Release(Avanzamento);

    LucchettoPreparazioni.Enter;
    try
      PreparazioniAttive.Remove(IdLavoro);
    finally
      LucchettoPreparazioni.Leave;
    end;

    TSessionContextManager.Azzera;
  end;
end;

{ TWTGecoController }

// Le procedure di apertura e chiusura dei lavori prendono tutte gli stessi
// parametri dalla richiesta: nel vecchio server c'era un ExecSP generico che
// faceva questo, qui i parametri li passa TDataService.
function TWTGecoController.EseguiProceduraDiLavoro(const NomeProcedura: string): TJSONObject;
var
  Parametri: TParamValues;
  Nome: string;
begin
  Parametri := TParamValues.Create;
  try
    // Tutti i parametri della richiesta: la procedura prende quelli che
    // riconosce e ignora gli altri.
    for Nome in Context.Request.QueryParams.Keys do
      Parametri.AddOrSetValue(UpperCase(Nome), Context.Request.QueryParams[Nome]);

    for Nome in Context.Request.ContentFields.Keys do
      Parametri.AddOrSetValue(UpperCase(Nome), Context.Request.ContentFields[Nome]);

    Result := TDataService.ExecuteStoredProc(NomeProcedura, Parametri);
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTGecoController.DoneImport;
begin
  RenderJson(EseguiProceduraDiLavoro('GERA_SYNC_JOBS_DONE_IMPORT'));
end;

procedure TWTGecoController.DoneExport;
begin
  RenderJson(EseguiProceduraDiLavoro('GERA_SYNC_JOBS_DONE_EXPORT'));
end;

procedure TWTGecoController.AfterDbDeleted;
begin
  RenderJson(EseguiProceduraDiLavoro('GERA_SYNC_JOBS_SQLLITE_DELETED'));
end;

procedure TWTGecoController.SetErrorMsg;
begin
  RenderJson(EseguiProceduraDiLavoro('GERA_SYNC_JOBS_SET_ERROR_MSG'));
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Importazione di un dataset inviato dal dispositivo
  ────────────────────────────────────────────────────────────────────────────── }

procedure TWTGecoController.ImportDataSet;
var
  Connessione: TFDConnection;
  DatiRicevuti: TFDMemTable;
  Collegamento: TFDStanStorageJSONLink;
  LetturaProcedura: TFDQuery;
  Procedura: TFDStoredProc;
  NomeDataset: string;
  IdJob: Int64;
  NomeProcedura: string;
  Campo: TField;
  Parametro: TFDParam;
  Testo: string;
  Contenuto: TStringStream;
begin
  NomeDataset := ParamObbligatorio('dataset');
  IdJob := ParamInt64('ID_GERA_SYNC_JOB');

  if IdJob <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Lavoro di importazione non specificato.');

  Registro.Info(Format('ImportDataSet - lavoro %d, dataset %s', [IdJob, NomeDataset]), 'WTGecoController');

  Collegamento := TFDStanStorageJSONLink.Create(nil);
  try
    DatiRicevuti := TFDMemTable.Create(nil);
    try
      Contenuto := TStringStream.Create(Context.Request.Body, TEncoding.UTF8);
      try
        Contenuto.Position := 0;
        DatiRicevuti.LoadFromStream(Contenuto, sfJSON);
      finally
        FreeAndNil(Contenuto);
      end;

      if DatiRicevuti.IsEmpty then
      begin
        RenderEsito(True);
        Exit;
      end;

      Connessione := PrendiConnessione;
      try
        ApriTransazione(Connessione);
        try
          LetturaProcedura := CreaQuery(Connessione, SQL_PROCEDURA_DI_IMPORTAZIONE);
          try
            LetturaProcedura.ParamByName('ID_GERA_SYNC_JOB').AsLargeInt := IdJob;
            LetturaProcedura.ParamByName('DATASET_NAME').AsString := NomeDataset;
            LetturaProcedura.Open;
            try
              NomeProcedura := LetturaProcedura.FieldByName('IMPORT_PROC').AsString;
            finally
              LetturaProcedura.Close;
            end;
          finally
            FreeAndNil(LetturaProcedura);
          end;

          if NomeProcedura.IsEmpty then
            raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Procedura di importazione non specificata per il dataset: ' + NomeDataset);

          Procedura := CreaStoredProc(Connessione, NomeProcedura);
          try
            if Procedura.ParamExists('ID_GERA_SYNC_JOB') then
              Procedura.ParamByName('ID_GERA_SYNC_JOB').AsLargeInt := IdJob;

            DatiRicevuti.First;
            while not DatiRicevuti.Eof do
            begin
              for Campo in DatiRicevuti.Fields do
              begin
                Parametro := Procedura.Params.FindParam(Campo.FieldName);

                if not Assigned(Parametro) then
                  Continue;

                if Campo.IsNull then
                begin
                  Parametro.Clear;
                  Continue;
                end;

                // Il troncamento alla lunghezza del parametro e la
                // distinzione fra BLOB e campi semplici vengono dal sorgente
                // d'origine: assegnare Value a un intero con la dimensione
                // sbagliata faceva fallire l'importazione (Mantis 1554).
                if Parametro.DataType in [ftString, ftFixedChar, ftWideString, ftFixedWideChar] then
                begin
                  Testo := Campo.Text;

                  if (Parametro.Size > 0) and (Testo.Length > Parametro.Size) then
                    Testo := Testo.Substring(0, Parametro.Size);

                  Parametro.AsString := Testo;
                end
                else
                  if Campo is TBlobField then
                    Parametro.Value := Campo.Value
                  else
                    Parametro.Text := Campo.Value;
              end;

              Procedura.ExecProc;
              DatiRicevuti.Next;
            end;
          finally
            FreeAndNil(Procedura);
          end;

          Conferma(Connessione);
        except
          on E: Exception do
          begin
            Annulla(Connessione);
            Registro.Error(Format('ImportDataSet - lavoro %d, dataset %s: %s', [IdJob, NomeDataset, E.Message]), 'WTGecoController');
            raise;
          end;
        end;
      finally
        RilasciaConnessione(Connessione);
      end;
    finally
      FreeAndNil(DatiRicevuti);
    end;
  finally
    FreeAndNil(Collegamento);
  end;

  RenderEsito(True);
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Chiave del dispositivo e database SQLite cifrato (dal 2026-11-08)
  ────────────────────────────────────────────────────────────────────────────── }

// Il valore puo' arrivare dalla riga dell'indirizzo, dal modulo o da un corpo
// JSON: il telefono invia JSON, i collaudi da riga di comando un modulo.
function TWTGecoController.LeggiValore(const Nome: string): string;
var
  Corpo: TJSONValue;
  Coppia: TJSONPair;
begin
  Result := ParamByName(Nome);

  if not Result.IsEmpty then
    Exit;

  if not Context.Request.Body.TrimLeft.StartsWith('{') then
    Exit;

  Corpo := TJSONObject.ParseJSONValue(Context.Request.Body);
  try
    if Corpo is TJSONObject then
      for Coppia in TJSONObject(Corpo) do
        if SameText(Coppia.JsonString.Value, Nome) then
        begin
          Result := Coppia.JsonValue.Value;
          Exit;
        end;
  finally
    FreeAndNil(Corpo);
  end;
end;

// Solo chi e' un operatore GeCo registra chiavi e chiede i dati.
procedure TWTGecoController.VerificaOperatore(Connessione: TFDConnection);
var
  Ricerca: TFDQuery;
  Trovato: Boolean;
begin
  Ricerca := CreaQuery(Connessione, 'SELECT FIRST 1 GERA_OPERATORI.ID_OPERATORE FROM GERA_OPERATORI WHERE GERA_OPERATORI.USER_ID = :USER_ID');
  try
    Ricerca.ParamByName('USER_ID').AsLargeInt := UserId;
    Ricerca.Open;
    Trovato := not Ricerca.IsEmpty;
  finally
    FreeAndNil(Ricerca);
  end;

  if not Trovato then
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Utente non abilitato a GeCo.');
end;

// Il lavoro si legge solo se e' di un operatore dell'utente della richiesta:
// il numero del lavoro e' progressivo e non si deve poter indovinare.
function TWTGecoController.CreaQueryLavoro(Connessione: TFDConnection; const IdLavoro: Int64): TFDQuery;
begin
  Result := CreaQuery(Connessione, SQL_LAVORO_DELL_UTENTE);
  try
    Result.ParamByName('ID_GERA_SYNC_JOB').AsLargeInt := IdLavoro;
    Result.ParamByName('USER_ID').AsLargeInt := UserId;
    Result.Open;

    if Result.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Lavoro non trovato.');
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

// Pulizia delle tracce lasciate dai lavori non conclusi: file pronti e mai
// scaricati, lavori rimasti a meta' per un riavvio del server.
procedure TWTGecoController.PulisciFotografieScadute(Connessione: TFDConnection);
var
  NomeFile: string;
begin
  Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''X'', GERA_SYNC_JOBS.BIGLIETTO = NULL ' +
    'WHERE GERA_SYNC_JOBS.FASE = ''P'' AND GERA_SYNC_JOBS.DATA_ORA_SCADENZA_FILE < CURRENT_TIMESTAMP');
  Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''E'', GERA_SYNC_JOBS.ERRORE = ''Preparazione interrotta: riavvio del server.'' ' +
    'WHERE GERA_SYNC_JOBS.FASE IN (''A'', ''G'') AND GERA_SYNC_JOBS.DATA_ORA_INIZIO_EXPORT < DATEADD(MINUTE, -' + MinutiPreparazioneMassima.ToString + ', CURRENT_TIMESTAMP)');
  Conferma(Connessione);

  for NomeFile in TDirectory.GetFiles(CartellaFotografie) do
    if TFile.GetLastWriteTime(NomeFile) < IncHour(Now, -OreConservazioneFile) then
      EliminaFile(NomeFile);
end;

// Il telefono si presenta con modello e seriale, gli stessi con cui si registra in
// GECO_DISPOSITIVI (WTWEB_GECO_ALLINEAMENTO_REGISTRA). Con Crea la riga si crea se manca
// (la registrazione della chiave puo' precedere il primo allineamento); senza, un telefono
// sconosciuto restituisce 0. Attivo e' vero se l'amministrazione ha abilitato il telefono.
function TWTGecoController.TrovaDispositivo(Connessione: TFDConnection; const Crea: Boolean; out Attivo, HaChiave: Boolean): Int64;
const
  RicercaDispositivo =
    'SELECT FIRST 1 GECO_DISPOSITIVI.ID_DISPOSITIVO_MOBILE, GECO_DISPOSITIVI.ATTIVO, ' +
    'IIF(GECO_DISPOSITIVI.CHIAVE_CIFRATURA IS NULL, FALSE, TRUE) HA_CHIAVE ' +
    'FROM GECO_DISPOSITIVI ' +
    'WHERE GECO_DISPOSITIVI.MODELLO = :MODELLO AND GECO_DISPOSITIVI.SERIALE = :SERIALE ' +
    'ORDER BY GECO_DISPOSITIVI.ID_DISPOSITIVO_MOBILE';
var
  Modello: string;
  Seriale: string;
  Ricerca: TFDQuery;
  Procedura: TFDStoredProc;
  Tentativo: Integer;
begin
  Result := 0;
  Attivo := False;
  HaChiave := False;
  Modello := LeggiValore('modello').Trim;
  Seriale := LeggiValore('seriale').Trim;

  if Modello.IsEmpty or Seriale.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Dispositivo non specificato: servono modello e seriale.');

  for Tentativo := 1 to 2 do
  begin
    Ricerca := CreaQuery(Connessione, RicercaDispositivo);
    try
      Ricerca.ParamByName('MODELLO').AsString := Modello;
      Ricerca.ParamByName('SERIALE').AsString := Seriale;
      Ricerca.Open;

      if not Ricerca.IsEmpty then
      begin
        Result := Ricerca.FieldByName('ID_DISPOSITIVO_MOBILE').AsLargeInt;
        Attivo := Ricerca.FieldByName('ATTIVO').AsString = 'S';
        HaChiave := Ricerca.FieldByName('HA_CHIAVE').AsBoolean;
        Exit;
      end;
    finally
      FreeAndNil(Ricerca);
    end;

    if (not Crea) or (Tentativo = 2) then
      Exit;

    // Telefono mai visto: la procedura crea la riga (non abilitata) e la ricerca si ripete.
    Procedura := CreaStoredProc(Connessione, 'GECO_GET_ID_DISPOSITIVO');
    try
      Procedura.ParamByName('MODELLO').AsString := Modello;
      Procedura.ParamByName('SERIALE').AsString := Seriale;
      Procedura.ExecProc;
    finally
      FreeAndNil(Procedura);
    end;
  end;
end;

procedure TWTGecoController.RegistraChiaveDispositivo;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  IdDispositivo: Int64;
  Attivo: Boolean;
  HaChiave: Boolean;
  Chiave: string;
  ChiaveEsistente: string;
  Carattere: Char;
begin
  Chiave := LeggiValore('chiave').Trim;

  if (Chiave.Length < 32) or (Chiave.Length > 128) then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Chiave non valida: lunghezza da 32 a 128 caratteri.');

  for Carattere in Chiave do
    if (Carattere <= ' ') or (Carattere >= #127) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Chiave non valida: caratteri non ammessi.');

  Connessione := PrendiConnessione;
  try
    VerificaOperatore(Connessione);

    IdDispositivo := TrovaDispositivo(Connessione, True, Attivo, HaChiave);

    if IdDispositivo <= 0 then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dispositivo non trovato.');

    // La chiave di un telefono gia' registrato e abilitato non si sostituisce: chi conosce modello
    // e seriale (che non sono segreti) potrebbe altrimenti renderne inutilizzabile il database.
    // Lo stesso telefono che ripete la stessa chiave (conferma andata persa) passa; per una chiave
    // diversa (app reinstallata) l'amministrazione prima disabilita il telefono (ATTIVO = N).
    if HaChiave and Attivo then
    begin
      ChiaveEsistente := VarToStr(Connessione.ExecSQLScalar('SELECT GECO_DISPOSITIVI_GET_CHIAVE.CHIAVE_IN_CHIARO FROM GECO_DISPOSITIVI_GET_CHIAVE(:ID_DISPOSITIVO_MOBILE)',
        [IdDispositivo]));

      if ChiaveEsistente <> Chiave then
        raise EMVCException.Create(HTTP_STATUS.Conflict,
          'Telefono gia'' registrato con un''altra chiave: l''amministrazione deve disabilitarlo prima di registrarlo di nuovo.');
    end
    else
    begin
      Procedura := CreaStoredProc(Connessione, 'GECO_DISPOSITIVI_IMPOSTA_CHIAVE');
      try
        Procedura.ParamByName('ID_DISPOSITIVO_MOBILE').AsLargeInt := IdDispositivo;
        Procedura.ParamByName('CHIAVE_IN_CHIARO').AsString := Chiave;
        Procedura.ExecProc;
      finally
        FreeAndNil(Procedura);
      end;

      Conferma(Connessione);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  // La chiave non entra mai nel registro.
  Registro.Info(Format('RegistraChiaveDispositivo - dispositivo %d, utente %s', [IdDispositivo, UserName]), 'WTGecoController');
  RenderEsito(True);
end;

procedure TWTGecoController.AvviaFotografia;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Voce: TPair<Int64, string>;
  IdDispositivo: Int64;
  IdLavoro: Int64;
  IdEsistente: Int64;
  PreparazioniInCorso: Integer;
  Attivo: Boolean;
  HaChiave: Boolean;
  DispositivoTrovato: Boolean;
  IdUtente: Int64;
  IdSessioneUtente: Int64;
  NomeUtente: string;
  Risposta: TJSONObject;
begin
  AssicuraCollegamentoSQLite;

  IdUtente := UserId;
  IdSessioneUtente := IdSessione;
  NomeUtente := UserName;

  // Un utente prepara un file alla volta: se ce n'e' gia' uno in corso si
  // restituisce quello, cosi' un doppio tocco non carica due volte Firebird.
  IdEsistente := 0;
  LucchettoPreparazioni.Enter;
  try
    PreparazioniInCorso := PreparazioniAttive.Count;

    for Voce in PreparazioniAttive do
      if SameText(Voce.Value, NomeUtente) then
        IdEsistente := Voce.Key;
  finally
    LucchettoPreparazioni.Leave;
  end;

  if IdEsistente > 0 then
  begin
    Risposta := TJSONObject.Create;
    Risposta.AddPair('success', TJSONBool.Create(True));
    Risposta.AddPair('idLavoro', TJSONNumber.Create(IdEsistente));
    Risposta.AddPair('giaInCorso', TJSONBool.Create(True));
    RenderJson(Risposta);
    Exit;
  end;

  if PreparazioniInCorso >= PreparazioniContemporaneeMassime then
    raise EMVCException.Create(StatoTroppeRichieste, 'Server occupato con altre preparazioni: riprovare fra qualche minuto.');

  Connessione := PrendiConnessione;
  try
    VerificaOperatore(Connessione);

    try
      PulisciFotografieScadute(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        Registro.Warn('AvviaFotografia - pulizia non riuscita: ' + E.Message, 'WTGecoController');
      end;
    end;

    // Il telefono e' quello di GECO_DISPOSITIVI con il modello e il seriale della richiesta.
    IdDispositivo := TrovaDispositivo(Connessione, False, Attivo, HaChiave);
    DispositivoTrovato := IdDispositivo > 0;

    if not DispositivoTrovato then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dispositivo non trovato.');

    if not Attivo then
      raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Dispositivo non abilitato.');

    if not HaChiave then
      raise EMVCException.Create(HTTP_STATUS.Conflict, 'Chiave del dispositivo non registrata.');

    try
      // Lo schema dei dati lo sceglie la procedura dall'utente: l'utente e'
      // quello del gettone, mai uno scritto nella richiesta.
      Procedura := CreaStoredProc(Connessione, 'GERA_SYNC_JOBS_INIT_EXPORT_MOBILE');
      try
        Procedura.ParamByName('USER_NAME').AsString := NomeUtente;
        Procedura.ParamByName('ID_DISPOSITIVO_MOBILE').AsLargeInt := IdDispositivo;
        Procedura.ExecProc;
        IdLavoro := Procedura.ParamByName('ID_GERA_SYNC_JOB_RESULT').AsLargeInt;
      finally
        FreeAndNil(Procedura);
      end;

      Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''A'' WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB', [IdLavoro]);
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        raise;
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  LucchettoPreparazioni.Enter;
  try
    PreparazioniAttive.AddOrSetValue(IdLavoro, NomeUtente);
  finally
    LucchettoPreparazioni.Leave;
  end;

  Registro.Info(Format('AvviaFotografia - lavoro %d, dispositivo %d, utente %s', [IdLavoro, IdDispositivo, NomeUtente]), 'WTGecoController');

  // La preparazione gira in un filo proprio: la richiesta risponde subito e
  // il telefono segue l'avanzamento con StatoFotografia.
  TThread.CreateAnonymousThread(
    procedure
    begin
      EseguiPreparazione(IdLavoro, IdDispositivo, IdUtente, IdSessioneUtente, NomeUtente);
    end).Start;

  Risposta := TJSONObject.Create;
  Risposta.AddPair('success', TJSONBool.Create(True));
  Risposta.AddPair('idLavoro', TJSONNumber.Create(IdLavoro));
  Risposta.AddPair('giaInCorso', TJSONBool.Create(False));
  RenderJson(Risposta);
end;

procedure TWTGecoController.StatoFotografia(const idLavoro: Int64);
var
  Connessione: TFDConnection;
  Lavoro: TFDQuery;
  Risposta: TJSONObject;

  procedure AggiungiNumero(const Nome: string);
  begin
    if Lavoro.FieldByName(Nome).IsNull then
      Risposta.AddPair(Nome, TJSONNull.Create)
    else
      Risposta.AddPair(Nome, TJSONNumber.Create(Lavoro.FieldByName(Nome).AsLargeInt));
  end;

  procedure AggiungiTesto(const Nome: string);
  begin
    if Lavoro.FieldByName(Nome).IsNull then
      Risposta.AddPair(Nome, TJSONNull.Create)
    else
      Risposta.AddPair(Nome, Lavoro.FieldByName(Nome).AsString);
  end;

begin
  Connessione := PrendiConnessione;
  try
    Lavoro := CreaQueryLavoro(Connessione, idLavoro);
    try
      Risposta := TJSONObject.Create;
      try
        Risposta.AddPair('success', TJSONBool.Create(True));
        Risposta.AddPair('idLavoro', TJSONNumber.Create(idLavoro));
        AggiungiTesto('FASE');
        AggiungiTesto('DATASET_CORRENTE');
        AggiungiNumero('DATASET_NUMERO');
        AggiungiNumero('DATASET_TOTALE');
        AggiungiNumero('RIGHE');
        AggiungiNumero('FILE_BYTE');
        AggiungiTesto('ERRORE');

        if Lavoro.FieldByName('DATA_ORA_SCADENZA_FILE').IsNull then
          Risposta.AddPair('DATA_ORA_SCADENZA_FILE', TJSONNull.Create)
        else
          Risposta.AddPair('DATA_ORA_SCADENZA_FILE', DateToISO8601(Lavoro.FieldByName('DATA_ORA_SCADENZA_FILE').AsDateTime, False));
      except
        FreeAndNil(Risposta);
        raise;
      end;
    finally
      FreeAndNil(Lavoro);
    end;

    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  RenderJson(Risposta);
end;

// Il plugin del telefono scarica con una richiesta che non porta l'intestazione
// di autorizzazione: il file si prende con un biglietto, a parte e monouso. Il
// biglietto e' 32 cifre casuali piu' 8 cifre con la scadenza in secondi (UTC),
// e il database lo conserva intero: chi lo modifica non corrisponde piu'.
procedure TWTGecoController.BigliettoFotografia(const idLavoro: Int64);
var
  Connessione: TFDConnection;
  Lavoro: TFDQuery;
  Fase: string;
  Biglietto: string;
  Scadenza: Int64;
  Risposta: TJSONObject;
begin
  Connessione := PrendiConnessione;
  try
    Lavoro := CreaQueryLavoro(Connessione, idLavoro);
    try
      Fase := Lavoro.FieldByName('FASE').AsString;
    finally
      FreeAndNil(Lavoro);
    end;

    if Fase <> FasePronto then
      raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il file non e'' pronto.');

    if not TFile.Exists(PercorsoFileFotografia(idLavoro, True)) then
      raise EMVCException.Create(StatoNonPiuDisponibile, 'Il file non e'' piu'' disponibile: richiedere una nuova preparazione.');

    Scadenza := DateTimeToUnix(Now, False) + MinutiValiditaBiglietto * 60;
    Biglietto := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '').Substring(0, 16).ToLower +
      TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '').Substring(0, 16).ToLower + IntToHex(Scadenza, 8).ToLower;

    Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.BIGLIETTO = :BIGLIETTO WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB',
      [Biglietto, idLavoro]);
    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  Risposta := TJSONObject.Create;
  Risposta.AddPair('success', TJSONBool.Create(True));
  Risposta.AddPair('biglietto', Biglietto);
  Risposta.AddPair('percorso', Format('/api/wt/geco/fotografia/%d/%s/gecodati.db', [idLavoro, Biglietto]));
  Risposta.AddPair('validitaSecondi', TJSONNumber.Create(MinutiValiditaBiglietto * 60));
  RenderJson(Risposta);
end;

procedure TWTGecoController.ScaricaFotografia(const idLavoro: Int64; const biglietto: string; const nomeFile: string);
var
  Connessione: TFDConnection;
  Consumati: Integer;
  Scadenza: Int64;
  PercorsoFile: string;
  Carattere: Char;
  Flusso: TFileStream;
begin
  // Rotta senza token (AzioniPubbliche): il biglietto e' l'unica prova.
  if biglietto.Length <> LunghezzaBiglietto then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  // L'ultimo segmento dell'indirizzo e' il nome che il plugin del telefono da' al file scaricato:
  // il telefono lo sceglie (una copia A e una B per utente), il contenuto e' sempre lo stesso.
  // Solo lettere, cifre e trattino basso, con estensione .db: il nome non entra mai in un percorso.
  if (nomeFile.Length < 4) or (nomeFile.Length > 80) or not nomeFile.EndsWith('.db') then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  for Carattere in nomeFile.Substring(0, nomeFile.Length - 3) do
    if not CharInSet(Carattere, ['0'..'9', 'a'..'z', 'A'..'Z', '_']) then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  for Carattere in biglietto do
    if not CharInSet(Carattere, ['0'..'9', 'a'..'f', 'A'..'F']) then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  Scadenza := StrToInt64Def('$' + biglietto.Substring(32), 0);

  if Scadenza < DateTimeToUnix(Now, False) then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  Connessione := PrendiConnessione;
  try
    // Il biglietto si consuma prima dell'invio: se lo scaricamento si
    // interrompe il telefono ne chiede uno nuovo, il file e' ancora li'.
    Consumati := Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.BIGLIETTO = NULL WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB ' +
      'AND GERA_SYNC_JOBS.BIGLIETTO = :BIGLIETTO AND GERA_SYNC_JOBS.FASE = ''P''', [idLavoro, biglietto]);
    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  if Consumati <> 1 then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Biglietto non valido o scaduto.');

  PercorsoFile := PercorsoFileFotografia(idLavoro, True);

  if not TFile.Exists(PercorsoFile) then
    raise EMVCException.Create(StatoNonPiuDisponibile, 'Il file non e'' piu'' disponibile: richiedere una nuova preparazione.');

  Registro.Info(Format('ScaricaFotografia - lavoro %d', [idLavoro]), 'WTGecoController');

  Flusso := TFileStream.Create(PercorsoFile, fmOpenRead or fmShareDenyNone);
  ContentType := 'application/octet-stream';

  // La proprieta del flusso passa al framework, che lo libera dopo l'invio.
  SendStream(Flusso, True, False);
end;

procedure TWTGecoController.FotografiaScaricata(const idLavoro: Int64);
var
  Connessione: TFDConnection;
  Lavoro: TFDQuery;
  Procedura: TFDStoredProc;
  Fase: string;
begin
  Connessione := PrendiConnessione;
  try
    Lavoro := CreaQueryLavoro(Connessione, idLavoro);
    try
      Fase := Lavoro.FieldByName('FASE').AsString;
    finally
      FreeAndNil(Lavoro);
    end;

    // Una conferma ripetuta non e' un errore.
    if Fase <> FaseScaricato then
    begin
      if Fase <> FasePronto then
        raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il lavoro non e'' in una fase che ammette la conferma.');

      try
        Procedura := CreaStoredProc(Connessione, 'GERA_SYNC_JOBS_DONE_EXPORT');
        try
          Procedura.ParamByName('ID_GERA_SYNC_JOB').AsLargeInt := idLavoro;
          Procedura.ExecProc;
        finally
          FreeAndNil(Procedura);
        end;

        Connessione.ExecSQL('UPDATE GERA_SYNC_JOBS SET GERA_SYNC_JOBS.FASE = ''S'', GERA_SYNC_JOBS.BIGLIETTO = NULL WHERE GERA_SYNC_JOBS.ID_GERA_SYNC_JOB = :ID_GERA_SYNC_JOB',
          [idLavoro]);
        Conferma(Connessione);
      except
        on E: Exception do
        begin
          Annulla(Connessione);
          raise;
        end;
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  EliminaFile(PercorsoFileFotografia(idLavoro, True));
  RenderEsito(True);
end;

procedure TWTGecoController.RiceviDatabasePalmare;
begin
  ElaboraDatabasePalmare(False);
end;

procedure TWTGecoController.RiceviDatabasePalmareSenzaAccesso;
begin
  ElaboraDatabasePalmare(True);
end;

// Ricezione del database di un palmare. Con SenzaAccesso (dalla pagina di accesso dell'app, quando
// il telefono non riesce piu' ad accedere) non c'e' il gettone: il telefono e' riconosciuto da
// modello e seriale, che devono essere gia' registrati con una chiave, e l'operatore si ricava dal
// nome del file (geco_<UTENTE>.db). Il file e' cifrato con la chiave del telefono, che non esce mai
// da zServer; la risposta non descrive il contenuto. Limiti: dimensione massima e un file ogni
// dieci minuti per telefono, perche' una rotta aperta che salva file non sia un punto d'abuso.
procedure TWTGecoController.ElaboraDatabasePalmare(const SenzaAccesso: Boolean);
const
  DimensioneMinimaByte = 4096;
  DimensioneMassimaByte = 100 * 1024 * 1024;
  MinutiFraDueInvii = 10;
  SQL_REGISTRA_RICEZIONE =
    'INSERT INTO GECO_DISPOSITIVI_RECUPERI (ID_DISPOSITIVO_MOBILE, ID_OPERATORE, NOME_FILE, DIMENSIONE_BYTE, CONTENUTO) ' +
    'VALUES (:ID_DISPOSITIVO_MOBILE, (SELECT FIRST 1 GERA_OPERATORI.ID_OPERATORE FROM GERA_OPERATORI WHERE GERA_OPERATORI.USER_ID = :USER_ID), ' +
    ':NOME_FILE, :DIMENSIONE_BYTE, :CONTENUTO) RETURNING ID_RECUPERO';
var
  Connessione: TFDConnection;
  Inserimento: TFDQuery;
  FileRicevuto: TAbstractWebRequestFile;
  Contenuto: TStream;
  Copia: TFileStream;
  IdDispositivo: Int64;
  IdRecupero: Int64;
  Attivo: Boolean;
  HaChiave: Boolean;
  Chiave: string;
  NomeOriginale: string;
  PercorsoTemporaneo: string;
  Operazioni: TJSONArray;
  Elemento: TJSONValue;
  Riga: TJSONObject;
  OperazioniInCoda: Integer;
  Mappe: Integer;
  MotivoErrore: string;
  Risposta: TJSONObject;
  IdUtenteRecupero: Int64;
  NomeUtenteFile: string;
begin
  if Context.Request.Files.Count = 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Nessun file nella richiesta: attesa una richiesta a piu'' parti (multipart/form-data).');

  FileRicevuto := Context.Request.Files[0];
  Contenuto := FileRicevuto.Stream;
  NomeOriginale := ExtractFileName(FileRicevuto.FileName);

  if Contenuto.Size < DimensioneMinimaByte then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'File non valido: troppo piccolo per essere un database.');

  if SenzaAccesso and (Contenuto.Size > DimensioneMassimaByte) then
    raise EMVCException.Create(413, 'File troppo grande.');

  Connessione := PrendiConnessione;
  try
    if not SenzaAccesso then
      VerificaOperatore(Connessione);

    IdDispositivo := TrovaDispositivo(Connessione, False, Attivo, HaChiave);

    // Senza accesso non si dice se il telefono e' sconosciuto o senza chiave: un'unica risposta.
    if SenzaAccesso and ((IdDispositivo <= 0) or not HaChiave) then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Telefono non riconosciuto.');

    if IdDispositivo <= 0 then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Dispositivo non trovato.');

    if not HaChiave then
      raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il telefono non ha una chiave registrata: il file non si puo'' aprire.');

    IdUtenteRecupero := UserId;
    NomeUtenteFile := '';

    if SenzaAccesso then
    begin
      if StrToIntDef(VarToStr(Connessione.ExecSQLScalar('SELECT COUNT(*) FROM GECO_DISPOSITIVI_RECUPERI WHERE GECO_DISPOSITIVI_RECUPERI.ID_DISPOSITIVO_MOBILE = :ID_DISPOSITIVO_MOBILE ' +
        'AND GECO_DISPOSITIVI_RECUPERI.DATA_RICEZIONE > DATEADD(MINUTE, -' + MinutiFraDueInvii.ToString + ', CURRENT_TIMESTAMP)', [IdDispositivo])), 0) > 0 then
        raise EMVCException.Create(StatoTroppeRichieste, 'Da questo telefono e'' arrivato un file da pochi minuti: riprova fra poco.');

      // L'operatore si ricava dal nome del file (geco_<UTENTE>.db): senza accesso non c'e' altro modo
      if NomeOriginale.ToLower.StartsWith('geco_') and NomeOriginale.ToLower.EndsWith('.db') then
        NomeUtenteFile := Copy(NomeOriginale, 6, Length(NomeOriginale) - 8);

      IdUtenteRecupero := StrToInt64Def(VarToStr(Connessione.ExecSQLScalar('SELECT FIRST 1 USR_UTENTI.USER_ID FROM USR_UTENTI WHERE UPPER(USR_UTENTI.USER_NAME) = :USER_NAME',
        [UpperCase(NomeUtenteFile)])), 0);
    end;

    Chiave := VarToStr(Connessione.ExecSQLScalar('SELECT GECO_DISPOSITIVI_GET_CHIAVE.CHIAVE_IN_CHIARO FROM GECO_DISPOSITIVI_GET_CHIAVE(:ID_DISPOSITIVO_MOBILE)',
      [IdDispositivo]));

    // Il file si conserva subito, cosi' com'e' arrivato: se la lettura fallisce resta comunque
    // all'assistenza, con lo stato E e il motivo.
    Inserimento := CreaQuery(Connessione, SQL_REGISTRA_RICEZIONE);
    try
      Inserimento.ParamByName('ID_DISPOSITIVO_MOBILE').AsLargeInt := IdDispositivo;
      Inserimento.ParamByName('USER_ID').AsLargeInt := IdUtenteRecupero;
      Inserimento.ParamByName('NOME_FILE').AsString := Copy(NomeOriginale, 1, 255);
      Inserimento.ParamByName('DIMENSIONE_BYTE').AsLargeInt := Contenuto.Size;
      Contenuto.Position := 0;
      Inserimento.ParamByName('CONTENUTO').LoadFromStream(Contenuto, ftBlob);
      Inserimento.Open;
      IdRecupero := Inserimento.FieldByName('ID_RECUPERO').AsLargeInt;
    finally
      FreeAndNil(Inserimento);
    end;

    Conferma(Connessione);

    // Lettura dalla copia temporanea (SQLite apre solo file su disco), eliminata alla fine.
    PercorsoTemporaneo := CartellaFotografie + 'recupero_' + IdRecupero.ToString + '.db';
    Operazioni := nil;
    OperazioniInCoda := 0;
    Mappe := 0;
    MotivoErrore := '';
    try
      try
        Copia := TFileStream.Create(PercorsoTemporaneo, fmCreate);
        try
          Contenuto.Position := 0;
          Copia.CopyFrom(Contenuto, Contenuto.Size);
        finally
          FreeAndNil(Copia);
        end;

        Operazioni := LeggiDatabasePalmare(PercorsoTemporaneo, Chiave, OperazioniInCoda, Mappe);
      except
        on E: Exception do
          MotivoErrore := Copy(E.Message, 1, 1000);
      end;
    finally
      EliminaFile(PercorsoTemporaneo);
    end;

    if MotivoErrore.IsEmpty then
    begin
      Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI SET STATO = ''L'', OPERAZIONI_IN_CODA = :OPERAZIONI, MAPPE = :MAPPE, ERRORE = NULL ' +
        'WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO', [OperazioniInCoda, Mappe, IdRecupero]);

      // Il resoconto dell'integrazione parte da qui: una riga "da integrare" per ogni operazione letta
      // (le prime 500; l'integrazione completa le altre).
      for Elemento in Operazioni do
        if Elemento is TJSONObject then
        begin
          Riga := TJSONObject(Elemento);
          AssicuraRigaOperazione(Connessione, IdRecupero, StrToInt64Def(TestoDelCampo(Riga, 'ordine'), 0), TestoDelCampo(Riga, 'uuid'),
            TestoDelCampo(Riga, 'procedura'), TestoDelCampo(Riga, 'descrizione'), StrToIntDef(TestoDelCampo(Riga, 'versione'), 0));
        end;
    end
    else
      Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI SET STATO = ''E'', ERRORE = :ERRORE WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO',
        [MotivoErrore, IdRecupero]);

    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('RiceviDatabasePalmare - dispositivo %d, recupero %d, %d byte, utente %s, esito %s',
    [IdDispositivo, IdRecupero, Contenuto.Size, IfThen(SenzaAccesso, 'senza accesso (' + NomeUtenteFile + ')', UserName),
    IfThen(MotivoErrore.IsEmpty, 'letto', 'errore')]), 'WTGecoController');

  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('success', TJSONBool.Create(MotivoErrore.IsEmpty));
    Risposta.AddPair('idRecupero', TJSONNumber.Create(IdRecupero));

    if SenzaAccesso then
    begin
      // Senza accesso non si descrive il contenuto del file: solo l'esito.
      FreeAndNil(Operazioni);
      Risposta.AddPair('stato', IfThen(MotivoErrore.IsEmpty, 'L', 'E'));
    end
    else if MotivoErrore.IsEmpty then
    begin
      Risposta.AddPair('stato', 'L');
      Risposta.AddPair('operazioniInCoda', TJSONNumber.Create(OperazioniInCoda));
      Risposta.AddPair('mappe', TJSONNumber.Create(Mappe));
      Risposta.AddPair('operazioni', Operazioni);
      Operazioni := nil;
    end
    else
    begin
      Risposta.AddPair('stato', 'E');
      Risposta.AddPair('message', 'File ricevuto e conservato, ma non si e'' potuto leggere: ' + MotivoErrore);
    end;

    RenderJson(Risposta);
  except
    FreeAndNil(Operazioni);
    FreeAndNil(Risposta);
    raise;
  end;
end;

// Solo un amministratore attivo di GeCo integra, scarica o scarta: e' lo stesso criterio dei dataset
// Geco.Amm*. Restituisce l'operatore amministratore.
function TWTGecoController.VerificaAmministratore(Connessione: TFDConnection): Int64;
var
  Ricerca: TFDQuery;
begin
  Result := 0;
  Ricerca := CreaQuery(Connessione, 'SELECT FIRST 1 GERA_OPERATORI.ID_OPERATORE FROM GERA_OPERATORI ' +
    'INNER JOIN GERA_OPERATORI_SYNC_APP ON GERA_OPERATORI_SYNC_APP.ID_OPERATORE = GERA_OPERATORI.ID_OPERATORE ' +
    'WHERE GERA_OPERATORI.USER_ID = :USER_ID AND GERA_OPERATORI_SYNC_APP.AMMINISTRATORE = ''S'' AND GERA_OPERATORI_SYNC_APP.ATTIVO = ''S''');
  try
    Ricerca.ParamByName('USER_ID').AsLargeInt := UserId;
    Ricerca.Open;

    if not Ricerca.IsEmpty then
      Result := Ricerca.Fields[0].AsLargeInt;
  finally
    FreeAndNil(Ricerca);
  end;

  if Result = 0 then
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Serve un amministratore di GeCo.');
end;

// Il recupero e' integrato se non resta nessuna operazione da integrare o rifiutata; altrimenti e' parziale.
procedure AggiornaStatoRecupero(Connessione: TFDConnection; const IdRecupero, IdOperatoreAmministratore: Int64; const Integrazione: Boolean);
var
  Pendenti: Integer;
  NuovoStato: string;
begin
  Pendenti := Connessione.ExecSQLScalar('SELECT COUNT(*) FROM GECO_DISPOSITIVI_RECUPERI_OPERAZIONI WHERE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ID_RECUPERO = :ID_RECUPERO ' +
    'AND GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.STATO IN (''A'', ''R'')', [IdRecupero]);

  if Pendenti > 0 then
    NuovoStato := 'P'
  else
    NuovoStato := 'I';

  if Integrazione then
    Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI SET STATO = :STATO, DATA_INTEGRAZIONE = CURRENT_TIMESTAMP, ID_OPERATORE_INTEGRAZIONE = :ID_OPERATORE ' +
      'WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO', [NuovoStato, IdOperatoreAmministratore, IdRecupero])
  else
    Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI SET STATO = :STATO WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO', [NuovoStato, IdRecupero]);
end;

// Integra le operazioni della coda di un palmare. L'amministratore chiede, il server rilancia le
// operazioni con le procedure della coda, nello stesso ordine e a nome dell'operatore del palmare
// (le procedure controllano l'operatore e le assegnazioni di quella persona). Un'operazione gia'
// eseguita prima del guasto si riconosce dal suo codice (UUID_OPERAZIONE) e risulta "gia' presente".
// Il rifiuto di una operazione non ferma le altre; quelle che ne dipendono non partono.
procedure TWTGecoController.IntegraRecupero(const idRecupero: Int64);
const
  SQL_RECUPERO = 'SELECT GECO_DISPOSITIVI_RECUPERI.ID_OPERATORE, GECO_DISPOSITIVI_RECUPERI.ID_DISPOSITIVO_MOBILE, GECO_DISPOSITIVI_RECUPERI.STATO, ' +
    'GECO_DISPOSITIVI_RECUPERI.CONTENUTO FROM GECO_DISPOSITIVI_RECUPERI WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO';
  SQL_UTENTE_OPERATORE = 'SELECT GERA_OPERATORI.USER_ID, USR_UTENTI.USER_NAME FROM GERA_OPERATORI ' +
    'INNER JOIN USR_UTENTI ON USR_UTENTI.USER_ID = GERA_OPERATORI.USER_ID WHERE GERA_OPERATORI.ID_OPERATORE = :ID_OPERATORE';
  SQL_RIGHE = 'SELECT GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.UUID_OPERAZIONE, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.STATO, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.PRODOTTI ' +
    'FROM GECO_DISPOSITIVI_RECUPERI_OPERAZIONI WHERE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ID_RECUPERO = :ID_RECUPERO';
  SQL_RESOCONTO = 'SELECT GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ORDINE, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.UUID_OPERAZIONE, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.PROCEDURA, ' +
    'GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.DESCRIZIONE, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.STATO, GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.MESSAGGIO ' +
    'FROM GECO_DISPOSITIVI_RECUPERI_OPERAZIONI WHERE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ID_RECUPERO = :ID_RECUPERO ORDER BY GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ORDINE';
var
  Connessione: TFDConnection;
  Ricerca: TFDQuery;
  Operazioni: TObjectList<TOperazionePalmare>;
  Operazione: TOperazionePalmare;
  Mappe: TDictionary<Int64, Int64>;
  StatiPrecedenti: TDictionary<string, string>;
  Esiti: TList<TEsitoOperazioneRecupero>;
  Esito: TEsitoOperazioneRecupero;
  ContestoAmministratore: TSessionContext;
  IdAmministratore: Int64;
  IdOperatorePalmare: Int64;
  IdDispositivo: Int64;
  IdUtentePalmare: Int64;
  NomeUtentePalmare: string;
  StatoRecupero: string;
  Chiave: string;
  PercorsoTemporaneo: string;
  UuidSingolo: string;
  Prodotti: TJSONValue;
  Coppia: TJSONValue;
  Elemento: TJSONValue;
  Provvisorio: Int64;
  IdServer: Int64;
  Risposta: TJSONObject;
  Righe: TJSONArray;
  Riga: TJSONObject;
  Integrate: Integer;
  GiaPresenti: Integer;
  Rifiutate: Integer;
  Scartate: Integer;
  DaIntegrare: Integer;
  StatoOperazione: string;
begin
  UuidSingolo := LeggiValore('uuid').Trim;
  Operazioni := nil;
  Mappe := TDictionary<Int64, Int64>.Create;
  StatiPrecedenti := TDictionary<string, string>.Create;
  Esiti := TList<TEsitoOperazioneRecupero>.Create;
  try
    LucchettoPreparazioni.Enter;
    try
      if RecuperiInCorso.ContainsKey(idRecupero) then
        raise EMVCException.Create(HTTP_STATUS.Conflict, 'Questo recupero e'' gia'' in corso di integrazione.');

      RecuperiInCorso.Add(idRecupero, True);
    finally
      LucchettoPreparazioni.Leave;
    end;

    try
      // 1. Con l'utente della richiesta: permesso, file ricevuto, chiave, dati dell'operatore del palmare.
      Connessione := PrendiConnessione;
      try
        IdAmministratore := VerificaAmministratore(Connessione);

        Ricerca := CreaQuery(Connessione, SQL_RECUPERO);
        try
          Ricerca.ParamByName('ID_RECUPERO').AsLargeInt := idRecupero;
          Ricerca.Open;

          if Ricerca.IsEmpty then
            raise EMVCException.Create(HTTP_STATUS.NotFound, 'Recupero non trovato.');

          StatoRecupero := Ricerca.FieldByName('STATO').AsString;
          IdOperatorePalmare := Ricerca.FieldByName('ID_OPERATORE').AsLargeInt;
          IdDispositivo := Ricerca.FieldByName('ID_DISPOSITIVO_MOBILE').AsLargeInt;

          if not MatchText(StatoRecupero, ['L', 'I', 'P']) then
            raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il file ricevuto non si e'' potuto leggere: non si puo'' integrare.');

          if IdOperatorePalmare = 0 then
            raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il file non ha un operatore associato: non si sa a nome di chi integrare.');

          if Ricerca.FieldByName('CONTENUTO').IsNull then
            raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il file ricevuto e'' vuoto.');

          PercorsoTemporaneo := CartellaFotografie + 'integra_' + idRecupero.ToString + '.db';
          (Ricerca.FieldByName('CONTENUTO') as TBlobField).SaveToFile(PercorsoTemporaneo);
        finally
          FreeAndNil(Ricerca);
        end;

        Ricerca := CreaQuery(Connessione, SQL_UTENTE_OPERATORE);
        try
          Ricerca.ParamByName('ID_OPERATORE').AsLargeInt := IdOperatorePalmare;
          Ricerca.Open;

          if Ricerca.IsEmpty then
            raise EMVCException.Create(HTTP_STATUS.Conflict, 'L''operatore del palmare non ha un utente: non si puo'' integrare a suo nome.');

          IdUtentePalmare := Ricerca.FieldByName('USER_ID').AsLargeInt;
          NomeUtentePalmare := Ricerca.FieldByName('USER_NAME').AsString;
        finally
          FreeAndNil(Ricerca);
        end;

        Chiave := VarToStr(Connessione.ExecSQLScalar('SELECT GECO_DISPOSITIVI_GET_CHIAVE.CHIAVE_IN_CHIARO FROM GECO_DISPOSITIVI_GET_CHIAVE(:ID_DISPOSITIVO_MOBILE)',
          [IdDispositivo]));

        if Chiave.IsEmpty then
          raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il telefono non ha una chiave registrata: il file non si puo'' aprire.');

        // 2. Il file si legge una volta e si cancella subito; il resoconto parte da una riga per operazione.
        try
          Operazioni := LeggiCodaCompletaPalmare(PercorsoTemporaneo, Chiave, Mappe);
        finally
          EliminaFile(PercorsoTemporaneo);
        end;

        for Operazione in Operazioni do
          AssicuraRigaOperazione(Connessione, idRecupero, Operazione.Ordine, Operazione.Uuid, Operazione.Procedura, Operazione.Descrizione, Operazione.Versione);

        Conferma(Connessione);

        // Le operazioni gia' chiuse prima non si rifanno; i loro identificativi servono alle successive.
        Ricerca := CreaQuery(Connessione, SQL_RIGHE);
        try
          Ricerca.ParamByName('ID_RECUPERO').AsLargeInt := idRecupero;
          Ricerca.Open;

          while not Ricerca.Eof do
          begin
            StatiPrecedenti.AddOrSetValue(Ricerca.FieldByName('UUID_OPERAZIONE').AsString, Ricerca.FieldByName('STATO').AsString);
            Prodotti := TJSONObject.ParseJSONValue(Ricerca.FieldByName('PRODOTTI').AsString);
            try
              if Prodotti is TJSONArray then
                for Coppia in TJSONArray(Prodotti) do
                  if (Coppia is TJSONObject) and TryStrToInt64(TestoDelCampo(TJSONObject(Coppia), 'locale'), Provvisorio) and
                    TryStrToInt64(TestoDelCampo(TJSONObject(Coppia), 'server'), IdServer) then
                    Mappe.AddOrSetValue(Provvisorio, IdServer);
            finally
              FreeAndNil(Prodotti);
            end;

            Ricerca.Next;
          end;
        finally
          FreeAndNil(Ricerca);
        end;
      finally
        RilasciaConnessione(Connessione);
      end;

      // 3. Con l'utente del palmare: ogni procedura verifica "operatore GERA associato all'utente di login"
      // e che le pratiche siano del suo gruppo. Il contesto dell'amministratore si ripristina sempre.
      ContestoAmministratore := TSessionContextManager.Corrente;
      TSessionContextManager.Imposta(IdUtentePalmare, ContestoAmministratore.IdSessione, NomeUtentePalmare);
      try
        Connessione := PrendiConnessione;
        try
          for Operazione in Operazioni do
          begin
            if StatiPrecedenti.TryGetValue(Operazione.Uuid, StatoOperazione) and MatchText(StatoOperazione, ['I', 'G', 'S']) then
              Continue;

            if (not UuidSingolo.IsEmpty) and not SameText(UuidSingolo, Operazione.Uuid) then
              Continue;

            Esito := EseguiOperazioneRecuperata(Connessione, Operazione, Mappe, ContestoAmministratore.IdSessione);
            Esiti.Add(Esito);
          end;
        finally
          RilasciaConnessione(Connessione);
        end;
      finally
        TSessionContextManager.Imposta(ContestoAmministratore.UserId, ContestoAmministratore.IdSessione, ContestoAmministratore.UserName);
        TSessionContextManager.ImpostaAmbito(ContestoAmministratore.Belfiore, ContestoAmministratore.IdAzienda);
      end;

      // 4. Di nuovo con l'utente della richiesta: esiti, stato del recupero e resoconto.
      Connessione := PrendiConnessione;
      try
        for Esito in Esiti do
          Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI SET STATO = :STATO, MESSAGGIO = :MESSAGGIO, PRODOTTI = :PRODOTTI, ' +
            'TENTATIVI = TENTATIVI + 1, DATA_ESECUZIONE = CURRENT_TIMESTAMP WHERE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ID_RECUPERO = :ID_RECUPERO ' +
            'AND GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.UUID_OPERAZIONE = :UUID_OPERAZIONE',
            [Esito.Stato, Esito.Messaggio, Esito.Prodotti, idRecupero, Esito.Uuid]);

        AggiornaStatoRecupero(Connessione, idRecupero, IdAmministratore, True);
        Conferma(Connessione);

        Risposta := TJSONObject.Create;
        try
          Righe := TJSONArray.Create;
          Risposta.AddPair('operazioni', Righe);
          Integrate := 0;
          GiaPresenti := 0;
          Rifiutate := 0;
          Scartate := 0;
          DaIntegrare := 0;

          Ricerca := CreaQuery(Connessione, SQL_RESOCONTO);
          try
            Ricerca.ParamByName('ID_RECUPERO').AsLargeInt := idRecupero;
            Ricerca.Open;

            while not Ricerca.Eof do
            begin
              StatoOperazione := Ricerca.FieldByName('STATO').AsString;

              if StatoOperazione = 'I' then
                Inc(Integrate)
              else if StatoOperazione = 'G' then
                Inc(GiaPresenti)
              else if StatoOperazione = 'R' then
                Inc(Rifiutate)
              else if StatoOperazione = 'S' then
                Inc(Scartate)
              else
                Inc(DaIntegrare);

              Riga := TJSONObject.Create;
              Riga.AddPair('ordine', TJSONNumber.Create(Ricerca.FieldByName('ORDINE').AsLargeInt));
              Riga.AddPair('uuid', Ricerca.FieldByName('UUID_OPERAZIONE').AsString);
              Riga.AddPair('procedura', Ricerca.FieldByName('PROCEDURA').AsString);
              Riga.AddPair('descrizione', Ricerca.FieldByName('DESCRIZIONE').AsString);
              Riga.AddPair('stato', StatoOperazione);
              Riga.AddPair('messaggio', Ricerca.FieldByName('MESSAGGIO').AsString);
              Righe.AddElement(Riga);
              Ricerca.Next;
            end;
          finally
            FreeAndNil(Ricerca);
          end;

          Risposta.AddPair('success', TJSONBool.Create(True));
          Risposta.AddPair('idRecupero', TJSONNumber.Create(idRecupero));
          Risposta.AddPair('stato', IfThen((Rifiutate + DaIntegrare) > 0, 'P', 'I'));
          Risposta.AddPair('integrate', TJSONNumber.Create(Integrate));
          Risposta.AddPair('giaPresenti', TJSONNumber.Create(GiaPresenti));
          Risposta.AddPair('rifiutate', TJSONNumber.Create(Rifiutate));
          Risposta.AddPair('scartate', TJSONNumber.Create(Scartate));
          Risposta.AddPair('daIntegrare', TJSONNumber.Create(DaIntegrare));
        except
          FreeAndNil(Risposta);
          raise;
        end;
      finally
        RilasciaConnessione(Connessione);
      end;

      Registro.Info(Format('IntegraRecupero - recupero %d, operatore del palmare %d, %d integrate, %d gia'' presenti, %d rifiutate, %d scartate, da %s',
        [idRecupero, IdOperatorePalmare, Integrate, GiaPresenti, Rifiutate, Scartate, UserName]), 'WTGecoController');

      RenderJson(Risposta);
    finally
      LucchettoPreparazioni.Enter;
      try
        RecuperiInCorso.Remove(idRecupero);
      finally
        LucchettoPreparazioni.Leave;
      end;
    end;
  finally
    // Il file del palmare e' cifrato ma e' un dato dell'operatore: non resta in giro se qualcosa e' andato storto
    if not PercorsoTemporaneo.IsEmpty then
      EliminaFile(PercorsoTemporaneo);

    FreeAndNil(Operazioni);
    FreeAndNil(Esiti);
    FreeAndNil(StatiPrecedenti);
    FreeAndNil(Mappe);
  end;
end;

procedure TWTGecoController.ScartaOperazioneRecupero(const idRecupero: Int64; const uuid: string);
var
  Connessione: TFDConnection;
  IdAmministratore: Int64;
  Modificate: Integer;
begin
  Connessione := PrendiConnessione;
  try
    IdAmministratore := VerificaAmministratore(Connessione);

    Modificate := Connessione.ExecSQL('UPDATE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI SET STATO = ''S'', MESSAGGIO = :MESSAGGIO, DATA_ESECUZIONE = CURRENT_TIMESTAMP ' +
      'WHERE GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.ID_RECUPERO = :ID_RECUPERO AND GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.UUID_OPERAZIONE = :UUID_OPERAZIONE ' +
      'AND GECO_DISPOSITIVI_RECUPERI_OPERAZIONI.STATO IN (''A'', ''R'')',
      [Copy('Scartata da ' + UserName + '.', 1, 1000), idRecupero, uuid]);

    if Modificate = 0 then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Operazione non trovata, oppure gia'' chiusa.');

    AggiornaStatoRecupero(Connessione, idRecupero, IdAmministratore, False);
    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('ScartaOperazioneRecupero - recupero %d, operazione %s, da %s', [idRecupero, uuid, UserName]), 'WTGecoController');
  RenderEsito(True);
end;

procedure TWTGecoController.ScaricaFileRecupero(const idRecupero: Int64);
var
  Connessione: TFDConnection;
  Ricerca: TFDQuery;
  Flusso: TMemoryStream;
begin
  Flusso := TMemoryStream.Create;
  try
    Connessione := PrendiConnessione;
    try
      VerificaAmministratore(Connessione);

      Ricerca := CreaQuery(Connessione, 'SELECT GECO_DISPOSITIVI_RECUPERI.CONTENUTO FROM GECO_DISPOSITIVI_RECUPERI WHERE GECO_DISPOSITIVI_RECUPERI.ID_RECUPERO = :ID_RECUPERO');
      try
        Ricerca.ParamByName('ID_RECUPERO').AsLargeInt := idRecupero;
        Ricerca.Open;

        if Ricerca.IsEmpty or Ricerca.FieldByName('CONTENUTO').IsNull then
          raise EMVCException.Create(HTTP_STATUS.NotFound, 'File non trovato.');

        (Ricerca.FieldByName('CONTENUTO') as TBlobField).SaveToStream(Flusso);
      finally
        FreeAndNil(Ricerca);
      end;
    finally
      RilasciaConnessione(Connessione);
    end;

    Flusso.Position := 0;
  except
    FreeAndNil(Flusso);
    raise;
  end;

  Registro.Info(Format('ScaricaFileRecupero - recupero %d, %d byte, da %s', [idRecupero, Flusso.Size, UserName]), 'WTGecoController');
  ContentType := 'application/octet-stream';
  Context.Response.SetCustomHeader('Content-Disposition', Format('attachment; filename="recupero_%d.db"', [idRecupero]));

  // La proprieta del flusso passa al framework, che lo libera dopo l'invio.
  SendStream(Flusso, True, False);
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Interrogazioni dirette
  ────────────────────────────────────────────────────────────────────────────── }

procedure TWTGecoController.GetTessera;
var
  Connessione: TFDConnection;
  Ricerca: TFDQuery;
begin
  Connessione := PrendiConnessione;
  try
    Ricerca := CreaQuery(Connessione, SQL_CERCA_TESSERA);
    try
      ImpostaParametro(Ricerca.ParamByName('CODICE_ISOLA'), ParamByName('CODICE_ISOLA'));
      ImpostaParametro(Ricerca.ParamByName('CODICE_TESSERA'), ParamByName('CODICE_TESSERA'));
      Ricerca.Open;
      try
        RenderRecord(Ricerca);
      finally
        Ricerca.Close;
      end;
    finally
      FreeAndNil(Ricerca);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TWTGecoController.GetPratica;
var
  Connessione: TFDConnection;
  Pratica: TFDQuery;
  Contenitori: TFDQuery;
  Risposta: TJSONObject;
  Trovata: Boolean;
begin
  Risposta := TJSONObject.Create;
  try
    Connessione := PrendiConnessione;
    try
      Pratica := CreaQuery(Connessione, SQL_CERCA_PRATICA);
      try
        Pratica.ParamByName('ID_OPERATORE').AsLargeInt := ParamInt64('ID_OPERATORE');
        Pratica.ParamByName('ID_PRATICA').AsLargeInt := ParamInt64('ID_PRATICA');
        Pratica.Open;
        try
          Trovata := not Pratica.IsEmpty;

          if Trovata then
            Risposta.AddPair('Pratica', Pratica.RecordToJSON(True));
        finally
          Pratica.Close;
        end;
      finally
        FreeAndNil(Pratica);
      end;

      if Trovata then
      begin
        Contenitori := CreaQuery(Connessione, SQL_CERCA_PRATICA_CONTENITORI);
        try
          Contenitori.ParamByName('ID_PRATICA').AsLargeInt := ParamInt64('ID_PRATICA');
          Contenitori.Open;
          try
            if not Contenitori.IsEmpty then
              Risposta.AddPair('Contenitori', Contenitori.DataSetToJSON(True));
          finally
            Contenitori.Close;
          end;
        finally
          FreeAndNil(Contenitori);
        end;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;

    Risposta.AddPair('success', TJSONBool.Create(Trovata));
  except
    on E: Exception do
    begin
      FreeAndNil(Risposta);
      raise;
    end;
  end;

  RenderJson(Risposta);
end;

procedure TWTGecoController.GetContenitore;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Risultato: string;
begin
  Connessione := PrendiConnessione;
  try
    Procedura := CreaStoredProc(Connessione, 'GECO_CONTENITORI_CERCA');
    try
      ImpostaParametro(Procedura.ParamByName('MATRICOLA'), ParamByName('Matricola'));
      ImpostaParametro(Procedura.ParamByName('RFID'), ParamByName('RFID'));
      ImpostaParametro(Procedura.ParamByName('NUMERO_DI_SERIE'), ParamByName('NumeroDiSerie'));
      Procedura.ExecProc;
      Risultato := Procedura.ParamByName('RESULT').AsString;
    finally
      FreeAndNil(Procedura);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('contenitore', Risultato));
end;

{ ──────────────────────────────────────────────────────────────────────────────
  Centri del riuso: firma al banco
  ────────────────────────────────────────────────────────────────────────────── }

procedure TWTGecoController.GetCollegamentoFirmaCdr(const idFirmaRegistrazione: Int64);
const
  // Richiesta corretta ma non eseguibile: il fornitore non da' collegamenti.
  StatoNonEseguibile = 422;
  // Il fornitore ha risposto con un errore.
  StatoFornitore = 502;
var
  Connessione: TFDConnection;
  Query: TFDQuery;
  IdObjectFile: Int64;
  Esito: TFirmaCollegamento;
  Risposta: TJSONObject;
begin
  Connessione := PrendiConnessione;
  try
    // Solo le registrazioni dei documenti dei beni: la rotta non apre le
    // pagine di firma di altri documenti del documentale.
    Query := CreaQuery(Connessione,
      'SELECT CDR_BENI_DOCUMENTI.ID_OBJECT_FILE FROM CDR_BENI_DOCUMENTI ' +
      'WHERE CDR_BENI_DOCUMENTI.ID_FIRMA_REGISTRAZIONE = :ID_FIRMA_REGISTRAZIONE');
    try
      Query.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := idFirmaRegistrazione;
      Query.Open;

      if Query.IsEmpty then
        IdObjectFile := 0
      else
        IdObjectFile := Query.FieldByName('ID_OBJECT_FILE').AsLargeInt;
    finally
      FreeAndNil(Query);
    end;

    // Fuori perimetro e inesistente rispondono allo stesso modo: il numero
    // della registrazione e' progressivo.
    if (IdObjectFile <= 0) or TAppProfiles.Corrente.PercorsoFile(IdObjectFile, IdSessione).IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Richiesta di firma non trovata.');

    try
      Esito := FirmaCollegamento(Connessione, idFirmaRegistrazione, ParamByName('ritorno'));
    except
      on E: EzFirmaNonSupportato do
        raise EMVCException.Create(StatoNonEseguibile, E.Message);
      on E: EzFirmaErrore do
        raise EMVCException.Create(StatoFornitore, E.Message);
    end;

    // Sola lettura: chiude la transazione aperta in automatico.
    Conferma(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;

  // Busta ancora da inviare: la coda la invia al prossimo giro, qui la si
  // sveglia perche' l'operatore sta aspettando al banco.
  if Esito.Stato = FIRMA_STATO_APPROVATA then
    TCodaElaboratore.Sveglia;

  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('idFirmaRegistrazione', TJSONNumber.Create(idFirmaRegistrazione));
    Risposta.AddPair('stato', Esito.Stato);
    Risposta.AddPair('collegamento', Esito.Collegamento);
    Risposta.AddPair('messaggio', Esito.Messaggio);
    RenderTestoJson(HTTP_STATUS.OK, Risposta);
  finally
    FreeAndNil(Risposta);
  end;
end;

initialization

PreparazioniAttive := TDictionary<Int64, string>.Create;
RecuperiInCorso := TDictionary<Int64, Boolean>.Create;
LucchettoPreparazioni := TCriticalSection.Create;

finalization

FreeAndNil(PreparazioniAttive);
FreeAndNil(RecuperiInCorso);
FreeAndNil(CollegamentoSQLite);
FreeAndNil(LucchettoPreparazioni);

end.
