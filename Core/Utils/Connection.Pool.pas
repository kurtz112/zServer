// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-28
// ---------------------------------------------------------------------------
unit Connection.Pool;

// Dal 2026-10-28 una richiesta HTTP usa una sola connessione.
//
// Prima ogni Acquire prendeva una connessione dal raggruppamento e le
// dichiarava il contesto (USR_CONTEXT_SET, che riempie le tabelle temporanee
// con USR_FILL_TABELLE_TMP). Una lettura di GetData ne fa cinque di fila
// (definizione del dataset, autorizzazione, perimetro, nomi dei campi, dati):
// cinque dichiarazioni del contesto per una lettura sola, e a raggruppamento
// vuoto, dopo un riavvio o una pausa, cinque aperture di connessione fisica
// per richiesta, in coda con quelle delle richieste parallele. Sulla macchina
// di prova la prima scheda di Agora' costava 1,1-1,8 s per lettura, le
// successive 0,07-0,25 s.
//
// Ora IniziaRichiesta e FineRichiesta (agganciate in WebModuleMain agli
// eventi di creazione e distruzione del contesto web di DMVC) delimitano la
// richiesta: dentro, Acquire restituisce sempre la stessa connessione e
// dichiara il contesto solo la prima volta o quando l'utente della richiesta
// cambia (rinnovo del token, logout). Release non la restituisce al
// raggruppamento: chiude solo la transazione rimasta aperta, come faceva la
// liberazione della connessione. La restituzione la fa FineRichiesta.
//
// Restano su una connessione propria, come prima:
// - le prese annidate, cioe' un Acquire mentre la connessione della richiesta
//   e' ancora in mano a qualcuno: condividerla metterebbe due transazioni
//   indipendenti sulla stessa connessione, e il Commit o il Rollback
//   dell'una chiuderebbe anche l'altra;
// - il login (ConContesto = False), dove e' USR_LOGIN a impostare il
//   contesto;
// - tutto cio' che gira fuori da una richiesta HTTP (coda, posta), che non
//   chiama IniziaRichiesta.
//
// Lo stato e' threadvar come quello di Session.Context: un thread serve una
// richiesta alla volta, e creazione e distruzione del contesto web avvengono
// sullo stesso thread. Contiene solo tipi non gestiti, quindi niente da
// finalizzare alla fine del thread.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  FireDAC.Comp.Client;

type
  TConnectionPool = class
  private
    class var FInstance: TConnectionPool;
    class var FLock: TCriticalSection;
    class procedure ChiudiConnessioneRichiesta; static;
    class procedure ChiudiTransazione(AConnection: TFDConnection); static;
    procedure DichiaraContesto(AConnection: TFDConnection);
    function NuovaConnessione: TFDConnection;
  public
    class function Instance: TConnectionPool;

    /// <summary>
    /// Apre l'ambito di una richiesta HTTP sul thread corrente: da qui a
    /// FineRichiesta Acquire riusa la stessa connessione. Se il thread ha
    /// ancora la connessione di una richiesta precedente, la restituisce.
    /// </summary>
    class procedure IniziaRichiesta; static;

    /// <summary>
    /// Chiude l'ambito della richiesta e restituisce la connessione al
    /// raggruppamento. Va chiamata anche quando la richiesta finisce in errore.
    /// </summary>
    class procedure FineRichiesta; static;

    /// <summary>
    /// Prende una connessione e le dichiara il contesto dell'utente della
    /// richiesta in corso (Z3); se la richiesta non ha un utente, il contesto
    /// viene svuotato (USR_CONTEXT_CLEAR). Con ConContesto = False la
    /// connessione resta com'e': serve al solo login, dove e' USR_LOGIN a
    /// impostare il contesto. Dentro una richiesta HTTP restituisce la
    /// connessione della richiesta, se non e' gia' in uso.
    /// </summary>
    function Acquire(const ConContesto: Boolean = True): TFDConnection;
    procedure Release(AConnection: TFDConnection);

    // Alternative syntax
    function GetConnection: TFDConnection; inline;
  end;

implementation

uses
  FireDAC.Stan.Option,
  MVCFramework.Logger,
  App.Config,
  App.Profile,
  Session.Context;

threadvar
  RichiestaAperta: Boolean;
  ConnessioneRichiesta: TFDConnection;
  ConnessioneInUso: Boolean;
  // Il contesto gia' dichiarato sulla connessione della richiesta
  ContestoDichiarato: Boolean;
  ContestoValorizzato: Boolean;
  ContestoUserId: Int64;
  ContestoIdSessione: Int64;

class function TConnectionPool.Instance: TConnectionPool;
begin
  if not Assigned(FInstance) then
  begin
    FLock.Enter;
    try
      if not Assigned(FInstance) then
        FInstance := TConnectionPool.Create;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

// Il raggruppamento di FireDAC ricicla la connessione fisica insieme al
// contenuto delle sue tabelle temporanee globali, che sono ON COMMIT PRESERVE
// ROWS e quindi appartengono alla connessione, non alla transazione. Senza
// questa dichiarazione a ogni presa, la richiesta di un utente puo' trovarsi
// in casa il perimetro di visibilita di un altro, e USR_LOG registrerebbe
// l'utente sbagliato.
procedure TConnectionPool.DichiaraContesto(AConnection: TFDConnection);
var
  Contesto: TSessionContext;
begin
  Contesto := TSessionContextManager.Corrente;

  // Le righe scritte nelle tabelle temporanee diventano visibili alle
  // transazioni successive solo dopo la conferma: senza questo commit la
  // query che segue non vedrebbe ne' il contesto ne' i comuni abilitati.
  if not AConnection.InTransaction then
    AConnection.StartTransaction;
  try
    if Contesto.Valorizzato then
      TAppProfiles.Corrente.ImpostaContesto(AConnection, Contesto.UserId, Contesto.IdSessione, Contesto.UserName)
    else
      // Richiesta senza utente (azione pubblica, rinnovo del token, logout):
      // la connessione puo' arrivare dal raggruppamento con il contesto di
      // chi l'ha usata prima, e USR_LOG attribuirebbe a lui le scritture.
      // Il contesto si svuota invece di lasciarlo com'e'.
      TAppProfiles.Corrente.AzzeraContesto(AConnection);

    AConnection.Commit;
  except
    on E: Exception do
    begin
      AConnection.Rollback;
      LogE(Format('Impossibile dichiarare il contesto utente %d: %s', [Contesto.UserId, E.Message]));
      raise;
    end;
  end;
end;

function TConnectionPool.NuovaConnessione: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.ConnectionDefName := TAppConfig.Instance.Database.ConnectionName;

    // Timeout
    Result.LoginPrompt := False;
    Result.TxOptions.AutoCommit := False;
    Result.TxOptions.AutoStart := True;
    Result.TxOptions.AutoStop := True;

    Result.FetchOptions.Items := Result.FetchOptions.Items + [fiMeta]; // per TDataService.ApplyParams

    Result.Connected := True;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

// La liberazione della connessione chiudeva la transazione rimasta aperta
// secondo DisconnectAction; la connessione della richiesta non viene liberata
// a ogni Release, quindi lo si fa qui, per lasciarla pulita alla presa dopo.
class procedure TConnectionPool.ChiudiTransazione(AConnection: TFDConnection);
begin
  if not(AConnection.Connected and AConnection.InTransaction) then
    Exit;

  case AConnection.TxOptions.DisconnectAction of
    xdCommit:
      AConnection.Commit;
    xdRollback:
      AConnection.Rollback;
  end;
end;

class procedure TConnectionPool.ChiudiConnessioneRichiesta;
begin
  ContestoDichiarato := False;
  ConnessioneInUso := False;

  if not Assigned(ConnessioneRichiesta) then
    Exit;

  try
    ConnessioneRichiesta.Free; // FireDAC pool si occupa del resto
  except
    on E: Exception do
      LogE('Impossibile restituire la connessione della richiesta: ' + E.Message);
  end;
  ConnessioneRichiesta := nil;
end;

class procedure TConnectionPool.IniziaRichiesta;
begin
  ChiudiConnessioneRichiesta;
  RichiestaAperta := True;
end;

class procedure TConnectionPool.FineRichiesta;
begin
  RichiestaAperta := False;
  ChiudiConnessioneRichiesta;
end;

function TConnectionPool.Acquire(const ConContesto: Boolean = True): TFDConnection;
var
  Contesto: TSessionContext;
begin
  if not(RichiestaAperta and ConContesto and not ConnessioneInUso) then
  begin
    Result := NuovaConnessione;
    try
      if ConContesto then
        DichiaraContesto(Result);
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise;
      end;
    end;
    Exit;
  end;

  if not Assigned(ConnessioneRichiesta) then
  begin
    ConnessioneRichiesta := NuovaConnessione;
    ContestoDichiarato := False;
  end;

  // Il contesto si dichiara di nuovo se l'utente della richiesta e' cambiato
  // dopo la prima presa: il middleware del token lo imposta o lo azzera
  // prima dell'instradamento, ma un controller puo' farlo anche dopo.
  Contesto := TSessionContextManager.Corrente;
  if (not ContestoDichiarato) or (ContestoValorizzato <> Contesto.Valorizzato) or (ContestoUserId <> Contesto.UserId) or (ContestoIdSessione <> Contesto.IdSessione) then
  begin
    try
      DichiaraContesto(ConnessioneRichiesta);
    except
      on E: Exception do
      begin
        ChiudiConnessioneRichiesta;
        raise;
      end;
    end;

    ContestoDichiarato := True;
    ContestoValorizzato := Contesto.Valorizzato;
    ContestoUserId := Contesto.UserId;
    ContestoIdSessione := Contesto.IdSessione;
  end;

  ConnessioneInUso := True;
  Result := ConnessioneRichiesta;
end;

procedure TConnectionPool.Release(AConnection: TFDConnection);
begin
  if not Assigned(AConnection) then
    Exit;

  if AConnection <> ConnessioneRichiesta then
  begin
    AConnection.Free; // FireDAC pool si occupa del resto
    Exit;
  end;

  ConnessioneInUso := False;
  try
    ChiudiTransazione(AConnection);
  except
    on E: Exception do
    begin
      // Una connessione che non riesce a chiudere la transazione non si
      // riusa: la prossima presa ne prende una nuova
      LogE('Impossibile chiudere la transazione della connessione della richiesta: ' + E.Message);
      ChiudiConnessioneRichiesta;
      Exit;
    end;
  end;

  // Connessione caduta durante l'uso: non si riusa
  if not AConnection.Connected then
    ChiudiConnessioneRichiesta;
end;

function TConnectionPool.GetConnection: TFDConnection;
begin
  Result := Acquire;
end;

initialization

TConnectionPool.FLock := TCriticalSection.Create;

finalization

FreeAndNil(TConnectionPool.FInstance);
FreeAndNil(TConnectionPool.FLock);

end.
