// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-06
// ---------------------------------------------------------------------------
unit WT.Agora.Controller;

// Ticket dello sportello Agora (front end OVOSODO) sul database WT.
//
// Le letture passano tutte dai dataset del nucleo (GET /api/data/Agora.*,
// registrati dallo script WT-AGORA-04-dataset.sql). Qui stanno solo le
// scritture che hanno una regola o una transazione (decisione 18 di
// OUT\20261006-zserver-agora-anpr-firma-file-pdf):
//
// POST /api/wt/agora/ticket
//   {"testata": {BELFIORE, TIPOLOGIA_TICKET, ...colonne di AGORA_TICKET...},
//    "rifiuti": [{...}], "contenitori": [{...}], "puntiStradali": [...],
//    "conferimenti": [...], "abbandoni": [...], "generico": {...},
//    "ecocentro": {...}, "tari": {...}, "tariRecapiti": [...],
//    "tariCatasto": [...], "tariUtenza": {...}, "tariVariazioni": [...],
//    "tariSconti": [...]}
//   Testata e blocchi nella stessa transazione: AGORA_TICKET_ADD per la
//   testata, un INSERT per ogni riga dei blocchi, poi
//   AGORA_TICKET_GENERA_LAVORO, che genera la richiesta di servizio GERA o
//   la pratica GECO della tipologia. 201 con identificativo, anno, numero e
//   tipo del ticket, piu' idRichiestaDiServizio, idPratica e avviso quando
//   ci sono. L'operatore di inserimento e' quello GERA dell'utente: un
//   utente senza operatore riceve l'errore della procedura.
//   Il lavoro nasce una volta sola: una PUT successiva che cambia i blocchi
//   non lo rigenera (va aggiornato da WT).
// GET  /api/wt/agora/ticket/{id}
//   il documento intero: testata (dalla vista AGORA_ELENCO_TICKET) e tutti i
//   blocchi, esiti compresi.
// PUT  /api/wt/agora/ticket/{id}
//   stesso corpo della POST, tutto facoltativo: i campi della testata
//   presenti vengono aggiornati (non comune, azienda, tipologia, stato e
//   date di ciclo di vita); ogni blocco presente sostituisce per intero le
//   sue righe. Un ticket chiuso o annullato non si modifica.
// POST /api/wt/agora/ticket/{id}/sollecito      {"note": "..."}
// POST /api/wt/agora/ticket/{id}/annullamento   {"motivo": "DUP", "note": "..."}
// POST /api/wt/agora/ticket/{id}/chiusura       {"note": "..."}
//   cambi di stato con AGORA_TICKET_SET_STATO; una transizione non ammessa
//   risponde 409.
// POST /api/wt/agora/ticket/{id}/esiti
//   {ESITO, DATA_ESITO, ORA_ESITO, TEMPO_ESECUZIONE, MOTIVAZIONE,
//    DESCRIZIONE_ESITO, ID_SQUADRA}: AGORA_TICKET_ESITI_ADD; un esito COM
//   porta il ticket in COM. Gli esiti dal campo (turno GERA rendicontato,
//   passaggio GECO) non passano di qui: li scrivono i trigger del database.
//
// I nomi dei campi sono quelli delle colonne, in maiuscolo, come nei dataset
// del nucleo: il client usa un solo vocabolario in lettura e in scrittura.
// Le colonne di una tabella si leggono una volta da RDB$RELATION_FIELDS, e
// un campo sconosciuto risponde 400 invece di finire in una SQL.
//
// Dal rilascio 006 (decisione 21) i codici dei campi collegati ai cataloghi
// di WT sono quelli dei cataloghi, verificati dalle chiavi esterne:
//   testata      FONTE_RICHIESTA (ZZ_RICHIESTE_FONTI_RICHIESTE, al posto di
//                MODALITA_SEGNALAZIONE), ID_STRADARIO (COM_STRADARIO),
//                ID_LOCALITA (COM_LOCALITA);
//   contenitori  SERVIZIO_RACCOLTA (ZZ_CALENDARI_RACCOLTA_RIFIUTI, al posto di
//                TIPOLOGIA_RACCOLTA), CODICE_CONTENITORE (ZZ_QTA_CONTENITORI,
//                senza TIPOLOGIA_CONTENITORE: tipologia e descrizione si
//                leggono dal catalogo);
//   tari         ID_SCADENZA (DOC_SCADENZE);
//   tariUtenza   ID_STRADARIO, ID_LOCALITA, CATEGORIA_OCCUPAZIONE
//                (ZZ_TIA_CATEGORIE_OCCUPAZIONE) e CODICE_ATECO
//                (ZZ_CODICI_ATECO), al posto di CATEGORIA_ATTIVITA;
//   tariSconti   COD_SCONTO (ZZ_TIA_SCONTI), senza DESC_SCONTO.
// Il codice qui non cambia: le colonne le legge dal database. Un codice che
// il catalogo non ha fa fallire la chiave esterna e annulla tutta la
// transazione.
//
// Perimetro e autorizzazione (decisioni 17 e 19): ogni azione passa da
// USR_AUTHORIZATION_CHECK('AGORA'); la creazione verifica comune e azienda
// con AmbitoAmmesso; le altre rileggono il ticket dalla vista con la clausola
// del profilo, e un ticket di un altro comune risponde 404, come per i file.
//
// Modulo (2026-11-06, OUT\20261106-pipa-sportello-comuni-funzioni-per-comune,
// script WT-MODULI-09): queste rotte non passano dal controller dei dataset,
// quindi il modulo per comune di Agora lo verifica VerificaAutorizzazione. Il
// modulo e' quello del dataset Agora.Ticket (BASE_WEB_DATASETS.MODULO), cosi'
// lettura e scrittura del ticket seguono la stessa riga: vuoto = nessun
// controllo. La lettura chiede il modulo in R, le scritture in W; poi
// USR_TMP_COMUNI della richiesta si restringe ai comuni del modulo, e da li'
// AmbitoAmmesso (creazione) e la clausola del profilo (rilettura del ticket)
// lasciano fuori i comuni in cui il modulo e' spento.
//
// Gli allegati non passano di qui: POST e GET /api/files con l'identificativo
// del ticket come oggetto (il ticket nasce con OBJECT_CREATE). La posta al
// referente non c'e' (decisione 20): il punto in cui accodarla e' CambiaStato.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller;

type
  [MVCPath('/api/wt/agora')]
  [MVCDoc('Ticket dello sportello Agora: creazione, lettura, modifica, stato ed esiti')]
  TWTAgoraController = class(TBaseController)
  private
    procedure VerificaAutorizzazione(const Scrittura: Boolean);
    procedure VerificaModulo(const Scrittura: Boolean);
    function ColonneDiTabella(Connessione: TFDConnection; const Tabella: string): TArray<string>;
    function LeggiTestata(Connessione: TFDConnection; const IdTicket: Int64): TJSONObject;
    function LeggiDocumento(Connessione: TFDConnection; const IdTicket: Int64): TJSONObject;
    function LeggiStato(Connessione: TFDConnection; const IdTicket: Int64): string;
    procedure AssegnaParametri(Procedura: TFDStoredProc; Valori: TJSONObject; const Riservate: array of string);
    function CreaTestata(Connessione: TFDConnection; Testata: TJSONObject): TJSONObject;
    procedure GeneraLavoro(Connessione: TFDConnection; const IdTicket: Int64; Esito: TJSONObject);
    procedure AggiornaTestata(Connessione: TFDConnection; Testata: TJSONObject; const IdTicket: Int64);
    procedure InserisciRiga(Connessione: TFDConnection; const Tabella: string; Riga: TJSONObject; const IdTicket: Int64);
    procedure ScriviBlocchi(Connessione: TFDConnection; Corpo: TJSONObject; const IdTicket: Int64; const Sostituisci: Boolean);
    procedure CambiaStato(const IdTicket: Int64; const StatoNuovo, Testo, MotivoAnnullamento: string);
  public
    [MVCPath('/ticket')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Crea un ticket con i suoi blocchi di dettaglio in una transazione')]
    procedure Crea;

    [MVCPath('/ticket/($idTicket)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Il ticket intero: testata, blocchi di dettaglio ed esiti')]
    procedure Leggi(const idTicket: Int64);

    [MVCPath('/ticket/($idTicket)')]
    [MVCHTTPMethod([httpPUT])]
    [MVCDoc('Aggiorna i campi liberi della testata e sostituisce i blocchi presenti nel corpo')]
    procedure Modifica(const idTicket: Int64);

    [MVCPath('/ticket/($idTicket)/sollecito')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Registra un sollecito')]
    procedure Sollecito(const idTicket: Int64);

    [MVCPath('/ticket/($idTicket)/annullamento')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Annulla il ticket con il motivo indicato')]
    procedure Annullamento(const idTicket: Int64);

    [MVCPath('/ticket/($idTicket)/chiusura')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Chiude il ticket')]
    procedure Chiusura(const idTicket: Int64);

    [MVCPath('/ticket/($idTicket)/esiti')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Registra un esito di intervento')]
    procedure AggiungiEsito(const idTicket: Int64);
  end;

implementation

uses
  System.Variants,
  System.StrUtils,
  System.SyncObjs,
  Data.DB,
  FireDAC.Stan.Param,
  FireDAC.Stan.Error,
  App.Profile,
  Data.Service,
  DevExtremeHelper,
  Json.Values;

const
  AutorizzazioneAgora = 'AGORA';
  // Dataset da cui si legge il modulo delle rotte dei ticket
  DatasetDelModulo = 'Agora.Ticket';
  VistaTestata = 'AGORA_ELENCO_TICKET';
  TabellaTestata = 'AGORA_TICKET';

  StatoSollecito = 'SOL';
  StatoCompletato = 'COM';
  StatoChiuso = 'CHI';
  StatoAnnullato = 'ANN';

type
  TBlocco = record
    Chiave: string;
    Tabella: string;
    UnaRiga: Boolean;
    SoloLettura: Boolean;
  end;

const
  // I blocchi del documento: chiave nel JSON, tabella, una riga sola o un
  // elenco, e se il client puo' scriverlo (gli esiti hanno la loro rotta).
  Blocchi: array [0 .. 13] of TBlocco = (
    (Chiave: 'esiti'; Tabella: 'AGORA_TICKET_ESITI'; UnaRiga: False; SoloLettura: True),
    (Chiave: 'rifiuti'; Tabella: 'AGORA_TICKET_RIFIUTI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'contenitori'; Tabella: 'AGORA_TICKET_CONTENITORI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'puntiStradali'; Tabella: 'AGORA_TICKET_PUNTI_STRADALI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'conferimenti'; Tabella: 'AGORA_TICKET_CONFERIMENTI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'abbandoni'; Tabella: 'AGORA_TICKET_ABBANDONI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'generico'; Tabella: 'AGORA_TICKET_GENERICO'; UnaRiga: True; SoloLettura: False),
    (Chiave: 'ecocentro'; Tabella: 'AGORA_TICKET_ECOCENTRO'; UnaRiga: True; SoloLettura: False),
    (Chiave: 'tari'; Tabella: 'AGORA_TICKET_TARI'; UnaRiga: True; SoloLettura: False),
    (Chiave: 'tariRecapiti'; Tabella: 'AGORA_TICKET_TARI_RECAPITI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'tariCatasto'; Tabella: 'AGORA_TICKET_TARI_CATASTO'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'tariUtenza'; Tabella: 'AGORA_TICKET_TARI_UTENZA'; UnaRiga: True; SoloLettura: False),
    (Chiave: 'tariVariazioni'; Tabella: 'AGORA_TICKET_TARI_VARIAZIONI'; UnaRiga: False; SoloLettura: False),
    (Chiave: 'tariSconti'; Tabella: 'AGORA_TICKET_TARI_SCONTI'; UnaRiga: False; SoloLettura: False));

  // Colonne della testata che il client non scrive mai: le assegna il
  // server, il trigger o una rotta di stato. Le USR_* sono escluse a parte.
  // Dal rilascio OUT/20261009-ovosodo-alimentazione-gera-geco/001 anche
  // l'operatore di inserimento (dall'utente della sessione) e il lavoro
  // generato in GERA e GECO (AGORA_TICKET_GENERA_LAVORO).
  ColonneRiservate: array [0 .. 15] of string = ('ID_TICKET', 'ANNO_TICKET', 'NUMERO_TICKET', 'TIPO_TICKET', 'STATO_TICKET', 'DATA_CREAZIONE', 'ORA_CREAZIONE', 'DATA_CHIUSURA', 'DATA_SOLLECITO', 'NOTE_SOLLECITO',
    'DATA_ANNULLAMENTO', 'MOTIVO_ANNULLAMENTO', 'ID_RICHIESTA', 'ID_RICHIESTA_DI_SERVIZIO', 'ID_PRATICA', 'ID_OPERATORE_INSERIMENTO');

  // In modifica non cambiano nemmeno comune, azienda e tipologia: un ticket
  // non si sposta di comune, e cambiare tipologia e' un ticket nuovo.
  ColonneFisse: array [0 .. 2] of string = ('BELFIORE', 'ID_AZIENDA', 'TIPOLOGIA_TICKET');

var
  ColonneLucchetto: TCriticalSection;
  ColonnePerTabella: TDictionary<string, TArray<string>>;

function Contiene(const Elenco: array of string; const Nome: string): Boolean;
var
  Voce: string;
begin
  for Voce in Elenco do
    if SameText(Voce, Nome) then
      Exit(True);

  Result := False;
end;

function ColonnaRiservata(const Nome: string): Boolean;
begin
  Result := Nome.ToUpper.StartsWith('USR_') or Contiene(ColonneRiservate, Nome);
end;

function StatoFinale(const Stato: string): Boolean;
begin
  Result := (Stato = StatoChiuso) or (Stato = StatoAnnullato);
end;

// Matrice degli stati (analisi, § "Agora (passo 6)"): la stessa che
// AGORA_TICKET_SET_STATO fa rispettare sul database. Qui serve a rispondere
// 409 prima di chiamarla.
function TransizioneAmmessa(const Da, A: string): Boolean;
begin
  if StatoFinale(Da) then
    Exit(False);

  if Da = StatoCompletato then
    Exit((A = StatoSollecito) or (A = StatoChiuso) or (A = StatoAnnullato));

  // NUO e SOL
  Result := (A = StatoSollecito) or (A = StatoCompletato) or (A = StatoChiuso) or (A = StatoAnnullato);
end;

{ TWTAgoraController }

procedure TWTAgoraController.VerificaAutorizzazione(const Scrittura: Boolean);
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('AUTHORIZATION', AutorizzazioneAgora);
    Parametri.Add('ERROR_MSG', '');

    try
      Esito := TDataService.ExecuteStoredProc('USR_AUTHORIZATION_CHECK', Parametri);
      FreeAndNil(Esito);
    except
      on E: Exception do
      begin
        Registro.Warn(Format('Agora: autorizzazione %s negata a utente %d: %s', [AutorizzazioneAgora, UserId, E.Message]), 'WTAgoraController');
        raise EMVCException.Create(HTTP_STATUS.Forbidden, E.Message);
      end;
    end;
  finally
    FreeAndNil(Parametri);
  end;

  VerificaModulo(Scrittura);
end;

// Stessa regola dei dataset (TDynamicDatasetController.VerificaModulo), ridotta
// ai moduli per comune: Agora lavora sempre sui dati di un comune. Un errore
// nel leggere il modulo (colonna MODULO assente perche' lo script WT-MODULI-01
// non e' passato) vale come nessun modulo, come in ModuliUtente.
procedure TWTAgoraController.VerificaModulo(const Scrittura: Boolean);
var
  Parametri: TParamValues;
  Riga: TJSONObject;
  Modulo: string;
  ModuloUtente: TModuloUtente;
  Comuni: TArray<string>;
  Comune: string;
  GiaPresente: Boolean;
begin
  Modulo := '';

  Parametri := TParamValues.Create;
  try
    Parametri.Add('DATASET', DatasetDelModulo);

    try
      Riga := TDataService.ExecuteQuerySingleRow('SELECT BASE_WEB_DATASETS.MODULO FROM BASE_WEB_DATASETS WHERE BASE_WEB_DATASETS.DATASET = :DATASET', Parametri, False);
      try
        if Assigned(Riga) then
          Modulo := JsonStr(Riga, 'MODULO').Trim;
      finally
        FreeAndNil(Riga);
      end;
    except
      on E: Exception do
        Registro.Warn(Format('Agora: modulo di %s non letto: %s', [DatasetDelModulo, E.Message]), 'WTAgoraController');
    end;
  finally
    FreeAndNil(Parametri);
  end;

  if Modulo.IsEmpty then
    Exit;

  Comuni := [];
  for ModuloUtente in TAppProfiles.Corrente.ModuliUtente(UserName) do
  begin
    if not SameText(ModuloUtente.Modulo, Modulo) then
      Continue;

    if Scrittura and not ModuloUtente.Scrittura then
      Continue;

    GiaPresente := False;
    for Comune in Comuni do
      if SameText(Comune, ModuloUtente.Belfiore) then
        GiaPresente := True;

    if not GiaPresente then
      Comuni := Comuni + [ModuloUtente.Belfiore];
  end;

  // Come per i dataset, il rifiuto e' un 403 che non dice quale modulo manca
  if Length(Comuni) = 0 then
  begin
    Registro.Warn(Format('Agora: modulo %s %s non disponibile per utente %d', [Modulo, IfThen(Scrittura, 'in scrittura', 'in lettura'), UserId]), 'WTAgoraController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Funzione non disponibile per questo utente.');
  end;

  TAppProfiles.Corrente.RestringiComuniDellaRichiesta(Comuni);
end;

function TWTAgoraController.ColonneDiTabella(Connessione: TFDConnection; const Tabella: string): TArray<string>;
var
  Query: TFDQuery;
  Elenco: TList<string>;
begin
  ColonneLucchetto.Enter;
  try
    if ColonnePerTabella.TryGetValue(Tabella, Result) then
      Exit;
  finally
    ColonneLucchetto.Leave;
  end;

  Elenco := TList<string>.Create;
  try
    Query := CreaQuery(Connessione, 'SELECT TRIM(RDB$RELATION_FIELDS.RDB$FIELD_NAME) AS CAMPO FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_FIELDS.RDB$RELATION_NAME = :TABELLA ORDER BY RDB$RELATION_FIELDS.RDB$FIELD_POSITION');
    try
      Query.ParamByName('TABELLA').AsString := Tabella;
      Query.Open;

      while not Query.Eof do
      begin
        Elenco.Add(Query.FieldByName('CAMPO').AsString);
        Query.Next;
      end;
    finally
      FreeAndNil(Query);
    end;

    Result := Elenco.ToArray;
  finally
    FreeAndNil(Elenco);
  end;

  if Length(Result) = 0 then
    raise EMVCException.Create(HTTP_STATUS.InternalServerError, Format('Tabella %s non trovata sul database: eseguire gli script WT-AGORA.', [Tabella]));

  ColonneLucchetto.Enter;
  try
    ColonnePerTabella.AddOrSetValue(Tabella, Result);
  finally
    ColonneLucchetto.Leave;
  end;
end;

// La testata si legge dalla vista con la clausola di perimetro del profilo:
// un ticket di un altro comune non esiste, per chi chiede.
// Senza righe risponde nil: ExecuteQuerySingleRow restituisce comunque un
// oggetto, con tutte le colonne a null, e senza questo controllo un ticket
// inesistente arrivava al client come un ticket vuoto invece che come 404.
function TWTAgoraController.LeggiTestata(Connessione: TFDConnection; const IdTicket: Int64): TJSONObject;
var
  SQL: string;
  Perimetro: string;
  Parametri: TParamValues;
begin
  SQL := Format('SELECT %s.* FROM %s WHERE %s.ID_TICKET = :ID_TICKET', [VistaTestata, VistaTestata, VistaTestata]);
  Perimetro := TAppProfiles.Corrente.ClausolaPerimetro(VistaTestata);

  if not Perimetro.Trim.IsEmpty then
    SQL := SQL + ' AND ' + Perimetro;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_TICKET', IdTicket);
    Result := TDataService.ExecuteQuerySingleRow(Connessione, SQL, Parametri, False);
  finally
    FreeAndNil(Parametri);
  end;

  if Assigned(Result) and (JsonInt64(Result, 'ID_TICKET') = 0) then
    FreeAndNil(Result);
end;

function TWTAgoraController.LeggiStato(Connessione: TFDConnection; const IdTicket: Int64): string;
var
  Testata: TJSONObject;
begin
  Testata := LeggiTestata(Connessione, IdTicket);

  if not Assigned(Testata) then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Ticket non trovato.');

  try
    Result := JsonStr(Testata, 'STATO_TICKET');
  finally
    FreeAndNil(Testata);
  end;
end;

function TWTAgoraController.LeggiDocumento(Connessione: TFDConnection; const IdTicket: Int64): TJSONObject;
var
  Testata: TJSONObject;
  Blocco: TBlocco;
  Righe: TJSONArray;
  Parametri: TParamValues;
  SQL: string;
begin
  Testata := LeggiTestata(Connessione, IdTicket);

  if not Assigned(Testata) then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Ticket non trovato.');

  Result := TJSONObject.Create;
  try
    Result.AddPair('testata', Testata);

    for Blocco in Blocchi do
    begin
      SQL := Format('SELECT %s.* FROM %s WHERE %s.ID_TICKET = :ID_TICKET ORDER BY 1', [Blocco.Tabella, Blocco.Tabella, Blocco.Tabella]);

      Parametri := TParamValues.Create;
      try
        Parametri.Add('ID_TICKET', IdTicket);
        Righe := TDataService.ExecuteQuery(Connessione, SQL, Parametri, False);
      finally
        FreeAndNil(Parametri);
      end;

      if Blocco.UnaRiga then
      begin
        try
          if Righe.Count > 0 then
            Result.AddPair(Blocco.Chiave, Righe.Remove(0))
          else
            Result.AddPair(Blocco.Chiave, TJSONNull.Create);
        finally
          FreeAndNil(Righe);
        end;
      end
      else
        Result.AddPair(Blocco.Chiave, Righe);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// Porta i valori di un oggetto JSON nei parametri di ingresso di una
// procedura, per nome. La conversione in Variant tipizzati e' quella del
// nucleo (BuildInsertSQL con una configurazione fittizia: la SQL che produce
// non si usa). Un campo riservato o sconosciuto risponde 400.
procedure TWTAgoraController.AssegnaParametri(Procedura: TFDStoredProc; Valori: TJSONObject; const Riservate: array of string);
var
  Helper: TDevExtremeHelper;
  Configurazione: TDatasetConfig;
  SqlIgnorata: string;
  Parametri: TParamValues;
  Coppia: TPair<string, Variant>;
  Parametro: TFDParam;
begin
  Helper := TDevExtremeHelper.Create;
  try
    Configurazione := Default (TDatasetConfig);
    Configurazione.TableName := Procedura.StoredProcName;
    Helper.BuildInsertSQL(Configurazione, Valori, SqlIgnorata, Parametri);
  finally
    FreeAndNil(Helper);
  end;

  try
    for Coppia in Parametri do
    begin
      if Coppia.Key.ToUpper.StartsWith('USR_') or Contiene(Riservate, Coppia.Key) then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il campo %s non si puo'' impostare dal client.', [Coppia.Key]));

      Parametro := Procedura.Params.FindParam(Coppia.Key);

      if (not Assigned(Parametro)) or (not(Parametro.ParamType in [ptInput, ptInputOutput])) then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Campo sconosciuto: %s. I nomi dei campi sono quelli delle colonne, in maiuscolo.', [Coppia.Key]));

      if VarIsNull(Coppia.Value) or VarIsEmpty(Coppia.Value) then
        Parametro.Clear
      else
        Parametro.Value := Coppia.Value;
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TWTAgoraController.CreaTestata(Connessione: TFDConnection; Testata: TJSONObject): TJSONObject;
var
  Belfiore: string;
  IdAzienda: Int64;
  Procedura: TFDStoredProc;
  Tentativo: Integer;
begin
  Belfiore := JsonStr(Testata, 'BELFIORE').Trim.ToUpper;
  IdAzienda := JsonInt64(Testata, 'ID_AZIENDA');

  if Belfiore.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Il comune del ticket (BELFIORE) e'' obbligatorio.');

  if JsonStr(Testata, 'TIPOLOGIA_TICKET').Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La tipologia del ticket (TIPOLOGIA_TICKET) e'' obbligatoria.');

  // Il controllo si fa qui e non nella procedura: il perimetro e' del server,
  // e la procedura deve restare usabile dalla form di WT, che il perimetro lo
  // ha gia' applicato a monte.
  if not TAppProfiles.Corrente.AmbitoAmmesso(Belfiore, IdAzienda) then
  begin
    Registro.Warn(Format('Agora: creazione fuori ambito da utente %d (comune %s, azienda %d)', [UserId, Belfiore, IdAzienda]), 'WTAgoraController');
    raise EMVCException.Create(HTTP_STATUS.Forbidden, Format('Il comune %s o l''azienda non sono fra quelli abilitati per l''utente.', [Belfiore]));
  end;

  Procedura := CreaStoredProc(Connessione, 'AGORA_TICKET_ADD');
  try
    AssegnaParametri(Procedura, Testata, ColonneRiservate);

    // Il numero progressivo lo calcola il trigger con MAX + 1: due creazioni
    // nello stesso istante sullo stesso comune si scontrano sull'indice
    // univoco, e la seconda si riprova una volta con il numero successivo.
    Tentativo := 0;

    repeat
      Inc(Tentativo);
      try
        Procedura.ExecProc;
        Break;
      except
        on E: EFDDBEngineException do
          if (E.Kind = ekUKViolated) and (Tentativo < 2) then
            Registro.Warn('Agora: numero del ticket gia'' assegnato da un''altra richiesta, si riprova', 'WTAgoraController')
          else
            raise;
      end;
    until False;

    Result := TJSONObject.Create;
    Result.AddPair('idTicket', TJSONNumber.Create(Procedura.ParamByName('ID_TICKET').AsLargeInt));
    Result.AddPair('annoTicket', TJSONNumber.Create(Procedura.ParamByName('ANNO_TICKET').AsLargeInt));
    Result.AddPair('numeroTicket', TJSONNumber.Create(Procedura.ParamByName('NUMERO_TICKET').AsLargeInt));
    Result.AddPair('tipoTicket', Procedura.ParamByName('TIPO_TICKET').AsString);
  finally
    FreeAndNil(Procedura);
  end;
end;

// Lavoro operativo del ticket appena creato, dopo testata e blocchi e nella
// stessa transazione: richiesta di servizio GERA e/o pratica GECO secondo la
// tipologia. Un servizio GERA mancante o ambiguo non blocca la creazione: la
// procedura restituisce un avviso, che arriva allo sportello nella risposta.
procedure TWTAgoraController.GeneraLavoro(Connessione: TFDConnection; const IdTicket: Int64; Esito: TJSONObject);
var
  Procedura: TFDStoredProc;
  Avviso: string;
begin
  Procedura := CreaStoredProc(Connessione, 'AGORA_TICKET_GENERA_LAVORO');
  try
    Procedura.ParamByName('ID_TICKET').AsLargeInt := IdTicket;
    Procedura.ExecProc;

    if not Procedura.ParamByName('ID_RICHIESTA_DI_SERVIZIO').IsNull then
      Esito.AddPair('idRichiestaDiServizio', TJSONNumber.Create(Procedura.ParamByName('ID_RICHIESTA_DI_SERVIZIO').AsLargeInt));

    if not Procedura.ParamByName('ID_PRATICA').IsNull then
      Esito.AddPair('idPratica', TJSONNumber.Create(Procedura.ParamByName('ID_PRATICA').AsLargeInt));

    Avviso := Procedura.ParamByName('AVVISO').AsString.Trim;

    if not Avviso.IsEmpty then
    begin
      Esito.AddPair('avviso', Avviso);
      Registro.Warn(Format('Agora: ticket %d creato senza tutto il lavoro operativo: %s', [IdTicket, Avviso]), 'WTAgoraController');
    end;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TWTAgoraController.AggiornaTestata(Connessione: TFDConnection; Testata: TJSONObject; const IdTicket: Int64);
var
  Colonne: TArray<string>;
  Coppia: TJSONPair;
  Nome: string;
  Helper: TDevExtremeHelper;
  Configurazione: TDatasetConfig;
  SQL: string;
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  if Testata.Count = 0 then
    Exit;

  Colonne := ColonneDiTabella(Connessione, TabellaTestata);

  for Coppia in Testata do
  begin
    Nome := Coppia.JsonString.Value;

    if ColonnaRiservata(Nome) or Contiene(ColonneFisse, Nome) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il campo %s non si modifica da questa rotta.', [Nome]));

    if not Contiene(Colonne, Nome) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Campo sconosciuto nella testata: %s.', [Nome]));

    if Nome <> Nome.ToUpper then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il campo %s va scritto come la colonna, in maiuscolo.', [Nome]));
  end;

  Helper := TDevExtremeHelper.Create;
  try
    Configurazione := Default (TDatasetConfig);
    Configurazione.TableName := TabellaTestata;
    Configurazione.PrimaryKeyField := 'ID_TICKET';
    Helper.BuildUpdateSQL(Configurazione, Testata, IdTicket.ToString, SQL, Parametri);
  finally
    FreeAndNil(Helper);
  end;

  try
    Esito := TDataService.ExecuteUpdate(Connessione, SQL, Parametri);
    FreeAndNil(Esito);
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTAgoraController.InserisciRiga(Connessione: TFDConnection; const Tabella: string; Riga: TJSONObject; const IdTicket: Int64);
var
  Colonne: TArray<string>;
  Coppia: TJSONPair;
  Nome: string;
  RigaDaScrivere: TJSONObject;
  Helper: TDevExtremeHelper;
  Configurazione: TDatasetConfig;
  SQL: string;
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  Colonne := ColonneDiTabella(Connessione, Tabella);

  RigaDaScrivere := TJSONObject.Create;
  try
    for Coppia in Riga do
    begin
      Nome := Coppia.JsonString.Value;

      // Il legame col ticket lo mette il server; i campi di audit il trigger.
      if SameText(Nome, 'ID_TICKET') or Nome.ToUpper.StartsWith('USR_') then
        Continue;

      if not Contiene(Colonne, Nome) then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Campo sconosciuto nel blocco %s: %s.', [Tabella, Nome]));

      if Nome <> Nome.ToUpper then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il campo %s va scritto come la colonna, in maiuscolo.', [Nome]));

      RigaDaScrivere.AddPair(Nome, Coppia.JsonValue.Clone as TJSONValue);
    end;

    RigaDaScrivere.AddPair('ID_TICKET', TJSONNumber.Create(IdTicket));

    Helper := TDevExtremeHelper.Create;
    try
      Configurazione := Default (TDatasetConfig);
      Configurazione.TableName := Tabella;
      Helper.BuildInsertSQL(Configurazione, RigaDaScrivere, SQL, Parametri);
    finally
      FreeAndNil(Helper);
    end;

    try
      Esito := TDataService.ExecuteInsert(Connessione, SQL, Parametri);
      FreeAndNil(Esito);
    finally
      FreeAndNil(Parametri);
    end;
  finally
    FreeAndNil(RigaDaScrivere);
  end;
end;

// Scrive i blocchi presenti nel corpo. Con Sostituisci le righe esistenti
// del blocco vengono cancellate prima: il client manda il blocco intero, come
// lo ha in memoria, e non deve ricordarsi quali righe ha tolto. Un blocco
// assente nel corpo resta com'e'; un blocco a null si svuota.
procedure TWTAgoraController.ScriviBlocchi(Connessione: TFDConnection; Corpo: TJSONObject; const IdTicket: Int64; const Sostituisci: Boolean);
var
  Blocco: TBlocco;
  Valore: TJSONValue;
  Elemento: TJSONValue;
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  for Blocco in Blocchi do
  begin
    if Blocco.SoloLettura then
      Continue;

    Valore := Corpo.GetValue(Blocco.Chiave);

    if not Assigned(Valore) then
      Continue;

    if Sostituisci then
    begin
      Parametri := TParamValues.Create;
      try
        Parametri.Add('ID_TICKET', IdTicket);
        Esito := TDataService.ExecuteDelete(Connessione, Format('DELETE FROM %s WHERE %s.ID_TICKET = :ID_TICKET', [Blocco.Tabella, Blocco.Tabella]), Parametri);
        FreeAndNil(Esito);
      finally
        FreeAndNil(Parametri);
      end;
    end;

    if Valore is TJSONNull then
      Continue;

    if Blocco.UnaRiga then
    begin
      if not(Valore is TJSONObject) then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il blocco %s deve essere un oggetto.', [Blocco.Chiave]));

      InserisciRiga(Connessione, Blocco.Tabella, TJSONObject(Valore), IdTicket);
    end
    else
    begin
      if not(Valore is TJSONArray) then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il blocco %s deve essere un elenco.', [Blocco.Chiave]));

      for Elemento in TJSONArray(Valore) do
      begin
        if not(Elemento is TJSONObject) then
          raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Ogni riga del blocco %s deve essere un oggetto.', [Blocco.Chiave]));

        InserisciRiga(Connessione, Blocco.Tabella, TJSONObject(Elemento), IdTicket);
      end;
    end;
  end;
end;

procedure TWTAgoraController.CambiaStato(const IdTicket: Int64; const StatoNuovo, Testo, MotivoAnnullamento: string);
var
  Connessione: TFDConnection;
  StatoAttuale: string;
  StatoPrecedente: string;
  Procedura: TFDStoredProc;
  Risposta: TJSONObject;
begin
  VerificaAutorizzazione(True);

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      StatoAttuale := LeggiStato(Connessione, IdTicket);

      if not TransizioneAmmessa(StatoAttuale, StatoNuovo) then
        raise EMVCException.Create(HTTP_STATUS.Conflict, Format('Transizione non ammessa dallo stato %s a %s.', [StatoAttuale, StatoNuovo]));

      Procedura := CreaStoredProc(Connessione, 'AGORA_TICKET_SET_STATO');
      try
        Procedura.ParamByName('ID_TICKET').AsLargeInt := IdTicket;
        Procedura.ParamByName('STATO_NUOVO').AsString := StatoNuovo;
        ImpostaParametro(Procedura.ParamByName('TESTO'), Testo);
        ImpostaParametro(Procedura.ParamByName('MOTIVO_ANNULLAMENTO'), MotivoAnnullamento);
        Procedura.ExecProc;
        StatoPrecedente := Procedura.ParamByName('STATO_PRECEDENTE').AsString;
      finally
        FreeAndNil(Procedura);
      end;

      // Decisione 20: qui andra' accodata la posta al referente, nella stessa
      // transazione del cambio di stato, quando testo e modello saranno decisi.
      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;

    Registro.Info(Format('Agora: ticket %d da %s a %s (utente %d)', [IdTicket, StatoPrecedente, StatoNuovo, UserId]), 'WTAgoraController');

    Risposta := TJSONObject.Create;
    try
      Risposta.AddPair('idTicket', TJSONNumber.Create(IdTicket));
      Risposta.AddPair('statoPrecedente', StatoPrecedente);
      Risposta.AddPair('stato', StatoNuovo);
      RenderTestoJson(HTTP_STATUS.OK, Risposta);
    finally
      FreeAndNil(Risposta);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TWTAgoraController.Crea;
var
  Corpo: TJSONObject;
  Testata: TJSONValue;
  Connessione: TFDConnection;
  Esito: TJSONObject;
  IdTicket: Int64;
begin
  VerificaAutorizzazione(True);

  Corpo := CorpoJson;
  try
    Testata := Corpo.GetValue('testata');

    if not(Testata is TJSONObject) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Atteso l''oggetto "testata" con i campi del ticket.');

    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        Esito := CreaTestata(Connessione, TJSONObject(Testata));
        try
          IdTicket := JsonInt64(Esito, 'idTicket');
          ScriviBlocchi(Connessione, Corpo, IdTicket, False);
          GeneraLavoro(Connessione, IdTicket, Esito);
          Conferma(Connessione);

          Registro.Info(Format('Agora: creato il ticket %d (%s %d/%d) da utente %d', [IdTicket, JsonStr(Esito, 'tipoTicket'), JsonInt64(Esito, 'annoTicket'), JsonInt64(Esito, 'numeroTicket'), UserId]), 'WTAgoraController');

          Context.Response.CustomHeaders.Values['Location'] := Format('/api/wt/agora/ticket/%d', [IdTicket]);
          RenderTestoJson(HTTP_STATUS.Created, Esito);
        finally
          FreeAndNil(Esito);
        end;
      except
        Annulla(Connessione);
        raise;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTAgoraController.Leggi(const idTicket: Int64);
var
  Connessione: TFDConnection;
  Documento: TJSONObject;
begin
  VerificaAutorizzazione(False);

  Connessione := PrendiConnessione;
  try
    Documento := LeggiDocumento(Connessione, idTicket);
    try
      RenderTestoJson(HTTP_STATUS.OK, Documento);
    finally
      FreeAndNil(Documento);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TWTAgoraController.Modifica(const idTicket: Int64);
var
  Corpo: TJSONObject;
  Testata: TJSONValue;
  Connessione: TFDConnection;
  Documento: TJSONObject;
begin
  VerificaAutorizzazione(True);

  Corpo := CorpoJson;
  try
    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        if StatoFinale(LeggiStato(Connessione, idTicket)) then
          raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il ticket e'' chiuso o annullato e non si modifica.');

        Testata := Corpo.GetValue('testata');

        if Testata is TJSONObject then
          AggiornaTestata(Connessione, TJSONObject(Testata), idTicket);

        ScriviBlocchi(Connessione, Corpo, idTicket, True);
        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;

      Registro.Info(Format('Agora: modificato il ticket %d da utente %d', [idTicket, UserId]), 'WTAgoraController');

      Documento := LeggiDocumento(Connessione, idTicket);
      try
        RenderTestoJson(HTTP_STATUS.OK, Documento);
      finally
        FreeAndNil(Documento);
      end;
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTAgoraController.Sollecito(const idTicket: Int64);
var
  Corpo: TJSONObject;
begin
  Corpo := CorpoJson;
  try
    CambiaStato(idTicket, StatoSollecito, JsonStr(Corpo, 'note'), '');
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTAgoraController.Annullamento(const idTicket: Int64);
var
  Corpo: TJSONObject;
  Motivo: string;
begin
  Corpo := CorpoJson;
  try
    Motivo := JsonStr(Corpo, 'motivo').Trim.ToUpper;

    if Motivo.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Il motivo dell''annullamento e'' obbligatorio (ERR, DUP, NPN, GEN).');

    CambiaStato(idTicket, StatoAnnullato, JsonStr(Corpo, 'note'), Motivo);
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTAgoraController.Chiusura(const idTicket: Int64);
var
  Corpo: TJSONObject;
  Note: string;
begin
  // La chiusura puo' arrivare senza corpo.
  Note := '';

  if not Context.Request.Body.Trim.IsEmpty then
  begin
    Corpo := CorpoJson;
    try
      Note := JsonStr(Corpo, 'note');
    finally
      FreeAndNil(Corpo);
    end;
  end;

  CambiaStato(idTicket, StatoChiuso, Note, '');
end;

procedure TWTAgoraController.AggiungiEsito(const idTicket: Int64);
var
  Corpo: TJSONObject;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  IdEsito: Int64;
  Stato: string;
  Risposta: TJSONObject;
begin
  VerificaAutorizzazione(True);

  Corpo := CorpoJson;
  try
    if JsonStr(Corpo, 'ESITO').Trim.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Il campo ESITO e'' obbligatorio (NEG, COM, COR).');

    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        if StatoFinale(LeggiStato(Connessione, idTicket)) then
          raise EMVCException.Create(HTTP_STATUS.Conflict, 'Il ticket e'' chiuso o annullato: non si registrano esiti.');

        Procedura := CreaStoredProc(Connessione, 'AGORA_TICKET_ESITI_ADD');
        try
          // Operatore e origine dell'esito non vengono dal client: allo
          // sportello l'operatore e' quello della sessione, turno e
          // pianificazione GECO li scrivono i trigger del database.
          AssegnaParametri(Procedura, Corpo, ['ID_TICKET', 'ID_TICKET_ESITO', 'ID_OPERATORE', 'ID_TURNO', 'ID_PIANIFICAZIONE_PRATICA']);
          Procedura.ParamByName('ID_TICKET').AsLargeInt := idTicket;
          Procedura.ExecProc;
          IdEsito := Procedura.ParamByName('ID_TICKET_ESITO').AsLargeInt;
          Stato := Procedura.ParamByName('STATO_TICKET').AsString;
        finally
          FreeAndNil(Procedura);
        end;

        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;

    Registro.Info(Format('Agora: esito %d sul ticket %d, stato %s (utente %d)', [IdEsito, idTicket, Stato, UserId]), 'WTAgoraController');

    Risposta := TJSONObject.Create;
    try
      Risposta.AddPair('idTicketEsito', TJSONNumber.Create(IdEsito));
      Risposta.AddPair('idTicket', TJSONNumber.Create(idTicket));
      Risposta.AddPair('stato', Stato);
      RenderTestoJson(HTTP_STATUS.Created, Risposta);
    finally
      FreeAndNil(Risposta);
    end;
  finally
    FreeAndNil(Corpo);
  end;
end;

initialization

ColonneLucchetto := TCriticalSection.Create;
ColonnePerTabella := TDictionary<string, TArray<string>>.Create;

finalization

FreeAndNil(ColonnePerTabella);
FreeAndNil(ColonneLucchetto);

end.
