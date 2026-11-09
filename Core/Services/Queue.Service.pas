// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-11
// ---------------------------------------------------------------------------
unit Queue.Service;

// Coda generica ZZ_CODA: chi mette i lavori in coda e chi li elabora.
//
// Una richiesta HTTP non puo' spedire una e-mail o chiamare un servizio
// esterno e aspettare: il servizio puo' essere lento o fermo, e la richiesta
// resterebbe appesa o fallirebbe a meta'. Con la coda la richiesta scrive
// una riga (TCoda.Accoda) nella stessa transazione del dato di dominio,
// quindi o c'e' tutto o non c'e' niente, e risponde subito. Un filo in
// sottofondo (TCodaElaboratore) prende le righe una alla volta e le passa al
// gestore del loro tipo, riprovando con attesa crescente se il gestore
// fallisce.
//
// I gestori si registrano per tipo (TCodaGestori.Registra), tipicamente
// nella sezione initialization della unit che li definisce. Un tipo senza
// gestore non viene mai prelevato: le righe restano in coda finche' non ne
// compare uno, che e' il comportamento voluto (meglio una riga in attesa
// che una riga persa).
//
// Il gestore riceve la connessione dell'elaboratore. Se scrive sul
// database lo fa li' e non conferma: se riesce, le sue scritture vengono
// confermate insieme all'esito del lavoro (ZZ_CODA_ESITO), se fallisce
// vengono annullate prima di scrivere l'esito. Cosi' un lavoro che passa il
// messaggio a un'altra tabella (WT e la sua EMAIL_OUTBOX) non puo'
// lasciarvi una riga e restare da rifare: o riga ed esito, o nessuno dei
// due. Un gestore che parla con l'esterno (SMTP) non ha questa garanzia: se
// la spedizione riesce e l'esito non si scrive, il lavoro viene ripreso e
// il messaggio parte due volte. E' il limite di ogni consegna "almeno una
// volta", preferito alla perdita del messaggio.
//
// Il prelievo usa SKIP LOCKED di Firebird 5 (procedura ZZ_CODA_PRELEVA):
// piu' elaboratori, sullo stesso server o su server diversi, non si
// aspettano e non prendono la stessa riga.
//
// L'elaboratore parte solo nell'eseguibile autonomo (zServer). I moduli per
// Apache e IIS mettono in coda e basta: un filo permanente dentro un
// processo che il server web puo' riciclare in qualunque momento non e' un
// posto affidabile, e lo stesso eseguibile autonomo puo' girare accanto.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  FireDAC.Comp.Client;

type
  /// <summary>
  /// Elabora un lavoro. Restituisce True se e' riuscito; in caso contrario
  /// scrive in Messaggio il motivo, che finisce in ZZ_CODA.ESITO. Un'eccezione
  /// equivale a False con il testo dell'eccezione. Connessione e' quella
  /// dell'elaboratore, con una transazione aperta: il gestore ci scrive ma
  /// non conferma e non annulla, lo fa l'elaboratore secondo l'esito.
  /// </summary>
  TCodaGestore = reference to function(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;

  TCodaGestori = class
  private
    class var FElenco: TDictionary<string, TCodaGestore>;
    class var FLucchetto: TCriticalSection;
  public
    class procedure Registra(const Tipo: string; const Gestore: TCodaGestore);
    class function HaGestore(const Tipo: string): Boolean;
    class function Trova(const Tipo: string; out Gestore: TCodaGestore): Boolean;
    class function Tipi: TArray<string>;
  end;

  /// <summary>
  /// Fotografia di una riga di ZZ_CODA, per chi ha accodato un lavoro e ne
  /// vuole l'esito. Stato: A da elaborare, L in lavorazione, C completato,
  /// F fallito dopo l'ultimo tentativo (dominio ZZ_CODA_STATO).
  /// </summary>
  TCodaLavoro = record
    Trovato: Boolean;
    IdCoda: Int64;
    Tipo: string;
    Stato: string;
    Contenuto: string;
    Esito: string;
    Tentativi: Integer;
    function Concluso: Boolean;
  end;

  TCoda = class
  public
    /// <summary>
    /// Mette un lavoro in coda sulla connessione indicata, SENZA confermare:
    /// la conferma e' di chi chiama, insieme al dato di dominio. Restituisce
    /// l'identificativo della riga. TentativiMassimi e AttesaSecondi a zero
    /// lasciano i valori predefiniti della procedura (cinque tentativi,
    /// nessuna attesa).
    /// </summary>
    class function Accoda(Connessione: TFDConnection; const Tipo: string; Contenuto: TJSONObject;
      const TentativiMassimi: Integer = 0; const AttesaSecondi: Integer = 0): Int64; static;

    /// <summary>Legge una riga di ZZ_CODA sulla connessione indicata.</summary>
    class function Leggi(Connessione: TFDConnection; const IdCoda: Int64): TCodaLavoro; static;

    /// <summary>
    /// Aspetta che un lavoro gia' confermato si concluda (C o F), al massimo
    /// AttesaMs millisecondi, e restituisce l'ultima fotografia letta. Serve
    /// ai lavori brevi che il chiamante vorrebbe sincroni (ANPR, una
    /// ricevuta): se l'elaboratore fa in tempo si risponde con il risultato,
    /// altrimenti con l'identificativo da rileggere. Ogni lettura parte da
    /// una transazione nuova, altrimenti l'esito scritto dall'elaboratore
    /// non si vedrebbe.
    /// </summary>
    class function Attendi(Connessione: TFDConnection; const IdCoda: Int64; const AttesaMs: Cardinal): TCodaLavoro; static;
  end;

  TCodaElaboratore = class(TThread)
  private
    class var FIstanza: TCodaElaboratore;
  private
    FEvento: TEvent;
    FIntervalloMs: Cardinal;
    FMinutiBlocco: Integer;
    FUltimaRipresa: TDateTime;
    function ElaboraUno(Connessione: TFDConnection; const Tipo: string; const Gestore: TCodaGestore): Boolean;
    function ElaboraGiro: Boolean;
    procedure RiprendiBloccati(Connessione: TFDConnection);
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create; reintroduce;
    destructor Destroy; override;

    /// <summary>
    /// Avvia l'elaboratore, se la configurazione lo consente. Registra prima
    /// la definizione della connessione, cosi' il primo giro trova il
    /// database senza aspettare una richiesta HTTP.
    /// </summary>
    class procedure Avvia;
    /// <summary>Lo ferma e attende che il giro in corso finisca.</summary>
    class procedure Ferma;
    /// <summary>
    /// Interrompe l'attesa fra due giri, se l'elaboratore gira in questo
    /// processo: chi ha appena confermato un lavoro che qualcuno aspetta lo
    /// fa prelevare subito invece che al prossimo intervallo. Nei moduli per
    /// Apache e IIS non fa niente, e il lavoro parte al giro successivo
    /// dell'elaboratore che gira accanto.
    /// </summary>
    class procedure Sveglia;
  end;

implementation

uses
  System.DateUtils,
  Data.DB,
  FireDAC.Stan.Param,
  MVCFramework.Logger,
  App.Config,
  Connection.Definition,
  Connection.Pool,
  Data.Service,
  Json.Values;

{ TCodaGestori }

class procedure TCodaGestori.Registra(const Tipo: string; const Gestore: TCodaGestore);
begin
  FLucchetto.Enter;
  try
    FElenco.AddOrSetValue(UpperCase(Tipo), Gestore);
  finally
    FLucchetto.Leave;
  end;
end;

class function TCodaGestori.HaGestore(const Tipo: string): Boolean;
begin
  FLucchetto.Enter;
  try
    Result := FElenco.ContainsKey(UpperCase(Tipo));
  finally
    FLucchetto.Leave;
  end;
end;

class function TCodaGestori.Trova(const Tipo: string; out Gestore: TCodaGestore): Boolean;
begin
  FLucchetto.Enter;
  try
    Result := FElenco.TryGetValue(UpperCase(Tipo), Gestore);
  finally
    FLucchetto.Leave;
  end;
end;

class function TCodaGestori.Tipi: TArray<string>;
begin
  FLucchetto.Enter;
  try
    Result := FElenco.Keys.ToArray;
  finally
    FLucchetto.Leave;
  end;
end;

{ TCoda }

class function TCoda.Accoda(Connessione: TFDConnection; const Tipo: string; Contenuto: TJSONObject;
  const TentativiMassimi, AttesaSecondi: Integer): Int64;
var
  Procedura: TFDStoredProc;
  Testo: string;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := 'ZZ_CODA_ADD';
    Procedura.Prepare;

    Procedura.ParamByName('TIPO').AsString := UpperCase(Tipo);

    // Il testo passa da una variabile: TJSONValue.ToJSON ha piu' forme e,
    // usata come argomento di un metodo a sua volta sovraccaricato, il
    // compilatore non sceglie.
    if Assigned(Contenuto) then
    begin
      Testo := Contenuto.ToJSON;
      Procedura.ParamByName('CONTENUTO').AsString := Testo;
    end
    else
      Procedura.ParamByName('CONTENUTO').Clear;

    if TentativiMassimi > 0 then
      Procedura.ParamByName('TENTATIVI_MASSIMI').AsInteger := TentativiMassimi;

    if AttesaSecondi > 0 then
      Procedura.ParamByName('ATTESA_SECONDI').AsInteger := AttesaSecondi;

    Procedura.ExecProc;
    Result := Procedura.ParamByName('ID_CODA').AsLargeInt;
  finally
    FreeAndNil(Procedura);
  end;
end;

class function TCoda.Leggi(Connessione: TFDConnection; const IdCoda: Int64): TCodaLavoro;
var
  Query: TFDQuery;
begin
  Result := Default(TCodaLavoro);
  Result.IdCoda := IdCoda;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text :=
      'SELECT ZZ_CODA.TIPO, ZZ_CODA.STATO, ZZ_CODA.CONTENUTO, ZZ_CODA.ESITO, ZZ_CODA.TENTATIVI ' +
      'FROM ZZ_CODA WHERE ZZ_CODA.ID_CODA = :ID_CODA';
    Query.ParamByName('ID_CODA').AsLargeInt := IdCoda;
    Query.Open;

    if Query.IsEmpty then
      Exit;

    Result.Trovato := True;
    Result.Tipo := Query.FieldByName('TIPO').AsString;
    Result.Stato := Query.FieldByName('STATO').AsString;
    Result.Contenuto := Query.FieldByName('CONTENUTO').AsString;
    Result.Esito := Query.FieldByName('ESITO').AsString;
    Result.Tentativi := Query.FieldByName('TENTATIVI').AsInteger;
  finally
    FreeAndNil(Query);
  end;
end;

class function TCoda.Attendi(Connessione: TFDConnection; const IdCoda: Int64; const AttesaMs: Cardinal): TCodaLavoro;
var
  Scadenza: UInt64;
begin
  Scadenza := TThread.GetTickCount64 + AttesaMs;

  repeat
    // La lettura precedente ha lasciato aperta una transazione: chiudendola,
    // la prossima vede quello che l'elaboratore ha confermato nel frattempo.
    if Connessione.InTransaction then
      Connessione.Commit;

    Result := Leggi(Connessione, IdCoda);

    if (not Result.Trovato) or Result.Concluso or (TThread.GetTickCount64 >= Scadenza) then
      Exit;

    Sleep(250);
  until False;
end;

{ TCodaLavoro }

function TCodaLavoro.Concluso: Boolean;
begin
  Result := (Stato = 'C') or (Stato = 'F');
end;

{ TCodaElaboratore }

constructor TCodaElaboratore.Create;
begin
  FEvento := TEvent.Create(nil, True, False, '');
  FIntervalloMs := Cardinal(TAppConfig.Instance.Coda.IntervalloSecondi) * 1000;
  FMinutiBlocco := TAppConfig.Instance.Coda.MinutiBlocco;
  FUltimaRipresa := 0;
  inherited Create(False);
end;

destructor TCodaElaboratore.Destroy;
begin
  FreeAndNil(FEvento);
  inherited;
end;

procedure TCodaElaboratore.TerminatedSet;
begin
  inherited;
  // Sveglia l'attesa fra due giri: senza questo la chiusura aspetterebbe
  // fino a un intervallo intero.
  if Assigned(FEvento) then
    FEvento.SetEvent;
end;

class procedure TCodaElaboratore.Avvia;
begin
  if not TAppConfig.Instance.Coda.Attiva then
  begin
    LogI('Coda: elaboratore disattivato dalla configurazione (voce coda.attiva)');
    Exit;
  end;

  if Assigned(FIstanza) then
    Exit;

  // Senza definizione il primo giro non avrebbe database: prima del 2026-10-06
  // nasceva con il primo modulo web, cioe' alla prima richiesta HTTP.
  TConnectionDefinition.Registra;

  FIstanza := TCodaElaboratore.Create;
  LogI(Format('Coda: elaboratore avviato (controllo ogni %d s, tipi gestiti: %s)',
    [TAppConfig.Instance.Coda.IntervalloSecondi, string.Join(', ', TCodaGestori.Tipi)]));
end;

class procedure TCodaElaboratore.Ferma;
begin
  if not Assigned(FIstanza) then
    Exit;

  FIstanza.Terminate;
  FIstanza.WaitFor;
  FreeAndNil(FIstanza);
  LogI('Coda: elaboratore fermato');
end;

class procedure TCodaElaboratore.Sveglia;
var
  Istanza: TCodaElaboratore;
begin
  Istanza := FIstanza;

  if Assigned(Istanza) and Assigned(Istanza.FEvento) then
    Istanza.FEvento.SetEvent;
end;

procedure TCodaElaboratore.Execute;
var
  Lavorato: Boolean;
begin
  while not Terminated do
  begin
    Lavorato := False;

    // L'evento e' a riarmo manuale: va spento prima del giro, non dopo, cosi'
    // una Sveglia arrivata mentre il giro lavora non va persa e l'attesa che
    // segue finisce subito.
    FEvento.ResetEvent;

    try
      Lavorato := ElaboraGiro;
    except
      on E: Exception do
        // Il giro non deve mai uccidere il filo: database fermo, rete
        // caduta e simili passano da soli, al giro dopo.
        LogE('Coda: giro di elaborazione interrotto: ' + E.Message);
    end;

    // Dopo aver lavorato si rilegge subito: potrebbe esserci altro. Si
    // aspetta solo a coda vuota.
    if (not Lavorato) and (not Terminated) then
      FEvento.WaitFor(FIntervalloMs);
  end;
end;

function TCodaElaboratore.ElaboraGiro: Boolean;
var
  Connessione: TFDConnection;
  Tipo: string;
  Gestore: TCodaGestore;
begin
  Result := False;

  // Nessun gestore registrato: niente da fare, e niente connessione.
  if Length(TCodaGestori.Tipi) = 0 then
    Exit;

  Connessione := TConnectionPool.Instance.Acquire;
  try
    if MinutesBetween(Now, FUltimaRipresa) >= 5 then
    begin
      RiprendiBloccati(Connessione);
      FUltimaRipresa := Now;
    end;

    for Tipo in TCodaGestori.Tipi do
    begin
      if not TCodaGestori.Trova(Tipo, Gestore) then
        Continue;

      while (not Terminated) and ElaboraUno(Connessione, Tipo, Gestore) do
        Result := True;
    end;
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;
end;

procedure TCodaElaboratore.RiprendiBloccati(Connessione: TFDConnection);
var
  Parametri: TParamValues;
  Risultato: TJSONObject;
  Riprese: Int64;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('MINUTI', FMinutiBlocco);
    Risultato := TDataService.ExecuteStoredProc(Connessione, 'ZZ_CODA_RIPRENDI_BLOCCATI', Parametri);
    try
      Riprese := JsonInt64(Risultato, 'RIPRESI');
    finally
      FreeAndNil(Risultato);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  if Riprese > 0 then
    LogW(Format('Coda: %d lavori in lavorazione da oltre %d minuti sono stati ripresi', [Riprese, FMinutiBlocco]));
end;

function TCodaElaboratore.ElaboraUno(Connessione: TFDConnection; const Tipo: string; const Gestore: TCodaGestore): Boolean;
var
  Parametri: TParamValues;
  Prelievo: TJSONObject;
  Esito: TJSONObject;
  IdCoda: Int64;
  Testo: string;
  Valore: TJSONValue;
  Contenuto: TJSONObject;
  Riuscito: Boolean;
  Messaggio: string;
begin
  // Il prelievo conferma da se' (TDataService.ExecuteStoredProc): la riga
  // passa a "in lavorazione" e il blocco cade subito, quindi nessun altro
  // elaboratore l'aspetta mentre il gestore lavora.
  // Il prelievo gira a ogni giro per ogni tipo, quasi sempre a vuoto: la
  // riga di esito di ExecuteStoredProc copriva il resto del registro. Si
  // registra solo il prelievo che trova un lavoro, qui sotto.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('TIPO', Tipo);
    Prelievo := TDataService.ExecuteStoredProc(Connessione, 'ZZ_CODA_PRELEVA', Parametri, True, False);
  finally
    FreeAndNil(Parametri);
  end;

  try
    IdCoda := JsonInt64(Prelievo, 'ID_CODA');
    Testo := JsonStr(Prelievo, 'CONTENUTO');
  finally
    FreeAndNil(Prelievo);
  end;

  if IdCoda = 0 then
    Exit(False);

  LogD(Format('Coda: prelevato il lavoro %d di tipo %s', [IdCoda, Tipo]));

  Riuscito := False;
  Messaggio := '';
  Contenuto := nil;

  try
    if Testo.Trim.IsEmpty then
      Contenuto := TJSONObject.Create
    else
    begin
      Valore := TJSONObject.ParseJSONValue(Testo);

      if Valore is TJSONObject then
        Contenuto := TJSONObject(Valore)
      else
      begin
        FreeAndNil(Valore);
        Messaggio := 'Il contenuto del lavoro non e'' un oggetto JSON valido.';
      end;
    end;

    if Assigned(Contenuto) then
      Riuscito := Gestore(Contenuto, Connessione, Messaggio);
  except
    on E: Exception do
    begin
      Riuscito := False;
      Messaggio := E.Message;
      LogE(Format('Coda: il gestore di %s ha sollevato un errore sul lavoro %d: %s', [Tipo, IdCoda, E.Message]));
    end;
  end;

  FreeAndNil(Contenuto);

  // Un gestore fallito puo' aver scritto a meta' sulla connessione: quelle
  // scritture non devono partire insieme all'esito. Se l'annullamento
  // stesso fallisce (connessione caduta) anche l'esito fallira', e la riga
  // tornera' in coda con ZZ_CODA_RIPRENDI_BLOCCATI.
  if (not Riuscito) and Connessione.InTransaction then
  begin
    try
      Connessione.Rollback;
    except
      on E: Exception do
        LogE(Format('Coda: annullamento delle scritture del lavoro %d non riuscito: %s', [IdCoda, E.Message]));
    end;
  end;

  // ZZ_CODA_ESITO conferma la transazione: con l'esito di un lavoro riuscito
  // partono anche le scritture del gestore.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_CODA', IdCoda);
    Parametri.Add('RIUSCITO', Riuscito);
    Parametri.Add('MESSAGGIO', Copy(Messaggio, 1, 500));

    try
      Esito := TDataService.ExecuteStoredProc(Connessione, 'ZZ_CODA_ESITO', Parametri);
      FreeAndNil(Esito);
    except
      on E: Exception do
        // L'esito non e' stato scritto, e con lui sono state annullate le
        // scritture del gestore: la riga resta "in lavorazione" e
        // ZZ_CODA_RIPRENDI_BLOCCATI la riporta in coda fra qualche minuto.
        LogE(Format('Coda: esito del lavoro %d non scritto: %s', [IdCoda, E.Message]));
    end;
  finally
    FreeAndNil(Parametri);
  end;

  if Riuscito then
    LogD(Format('Coda: lavoro %d (%s) completato', [IdCoda, Tipo]))
  else
    LogW(Format('Coda: lavoro %d (%s) non riuscito: %s', [IdCoda, Tipo, Messaggio]));

  Result := True;
end;

initialization

TCodaGestori.FElenco := TDictionary<string, TCodaGestore>.Create;
TCodaGestori.FLucchetto := TCriticalSection.Create;

finalization

TCodaElaboratore.Ferma;
FreeAndNil(TCodaGestori.FElenco);
FreeAndNil(TCodaGestori.FLucchetto);

end.
