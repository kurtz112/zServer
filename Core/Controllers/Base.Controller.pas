// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-11
// ---------------------------------------------------------------------------
unit Base.Controller;

{ ===========================================================================
  Controller base. Nessun punto di ingresso.

  Due compiti:

  1. Gestione uniforme delle eccezioni (come prima).

  2. Le comodita che i controller di dominio portati dal vecchio server si
  aspettavano dalla classe TRoute: leggere un parametro senza sapere se
  arriva dalla riga dell'indirizzo o dal modulo, prendere una connessione
  che porta con se' il contesto dell'utente, creare una stored procedure,
  rispondere con un dataset.

  Cosi' i controller portati non prendono connessioni per conto proprio:
  passano da qui, e quindi dal contesto di sessione del punto Z3.
  =========================================================================== }

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.JSON,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Stan.Param,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Logger,
  LoggerPro;

type
  TBaseController = class(TMVCController)
  protected
    procedure OnException(const aContext: TWebContext; const aException: Exception; var aHandled: Boolean); override;
  protected
    // ── Registro ──
    /// <summary>
    /// Z7: il registratore e' uno per processo, creato alla prima richiesta.
    /// Prima ogni azione chiamava BuildLogWriter, quindi creava un
    /// registratore e apriva i file a ogni chiamata.
    /// </summary>
    function Registro: ILogWriter;

    // ── Parametri della richiesta ──
    /// <summary>
    /// Cerca il parametro, senza distinzione fra maiuscole e minuscole,
    /// nella riga dell'indirizzo, poi nei campi del modulo, poi nei segmenti
    /// del percorso. Sostituisce Request.ParamByName del vecchio server, che
    /// i moduli usavano con nomi scritti in tutti i modi.
    /// </summary>
    function ParamByName(const Nome: string): string;
    function ParamObbligatorio(const Nome: string): string;
    function ParamInt64(const Nome: string; const Predefinito: Int64 = 0): Int64;
    function ParamValuta(const Nome: string; const Predefinito: Currency = 0): Currency;
    function CorpoJson: TJSONObject;

    // ── Identita della richiesta ──
    // Prese dal contesto di sessione riempito dal servizio di autenticazione:
    // sono le stesse che il raggruppamento dichiara al database.
    function UserId: Int64;
    function IdSessione: Int64;
    function UserName: string;

    // ── Dati ──
    function PrendiConnessione: TFDConnection;
    procedure RilasciaConnessione(var Connessione: TFDConnection);
    function CreaStoredProc(Connessione: TFDConnection; const Nome: string): TFDStoredProc;
    function CreaQuery(Connessione: TFDConnection; const SQL: string): TFDQuery;
    /// <summary>Valore vuoto uguale NULL, come il SetParam del vecchio server.</summary>
    procedure ImpostaParametro(Parametro: TFDParam; const Valore: string);
    procedure ApriTransazione(Connessione: TFDConnection);
    procedure Conferma(Connessione: TFDConnection);
    procedure Annulla(Connessione: TFDConnection);

    // ── Risposte ──
    procedure RenderEsito(const Riuscito: Boolean = True);
    procedure RenderJson(Oggetto: TJSONObject);
    /// <summary>
    /// Rende un valore JSON con il codice di stato indicato. Il testo passa da
    /// una variabile di tipo string perche' TJSONValue.ToJSON ha piu' forme
    /// (con e senza opzioni, e una che scrive su un TJsonWriter): usata
    /// direttamente come argomento di Render, il compilatore non sceglie
    /// l'overload (E2250).
    /// </summary>
    procedure RenderTestoJson(const StatoHttp: Integer; Valore: TJSONValue);
    procedure RenderDataSet(DataSet: TFDAdaptedDataSet);
    procedure RenderRecord(DataSet: TFDAdaptedDataSet);
    procedure RenderStoredProc(Procedura: TFDStoredProc);
    /// <summary>Indirizzo di rimando, come il SetContentURL del vecchio server.</summary>
    procedure RenderUrl(const Url: string);
  end;

implementation

uses
  System.SyncObjs,
  System.StrUtils,
  FireDAC.Phys.IBWrapper,
  FireDAC.Stan.Option,
  LoggerPro.FileAppender,
  FirebirdExceptions,
  FiredacHelper,
  App.Config,
  Connection.Pool,
  Session.Context;

var
  RegistroCondiviso: ILogWriter;
  LucchettoRegistro: TCriticalSection;

procedure TBaseController.OnException(const aContext: TWebContext; const aException: Exception; var aHandled: Boolean);
var
  InDevelopment: Boolean;
  StatusCode: Integer;
  Message: string;
begin
  aHandled := True;
  InDevelopment := TAppConfig.Instance.Development;
  // Valori di default
  StatusCode := HTTP_STATUS.InternalServerError;
  Message := aException.Message;

  if aException is EIBNativeException then
  begin
    StatusCode := HTTP_STATUS.BadRequest;
    Message := TranslateFirebirdException(aException as EIBNativeException, InDevelopment);
  end
  else
    if aException is EMVCSessionExpiredException then
    begin
      StatusCode := HTTP_STATUS.Unauthorized;
      Message := 'Sessione scaduta, effettuare nuovamente il login';
    end
    else
      if aException is EMVCException then
      begin
        StatusCode := EMVCException(aException).HTTPStatusCode;
      end
      else
      begin
        Message := 'Si è verificato un errore imprevisto';
      end;

  Log.Error('Eccezione [%d %s] %s', [StatusCode, aException.ClassName, aException.Message], 'exceptions');

  // Rendering uniforme della risposta
  aContext.Response.StatusCode := StatusCode;
  aContext.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
  Render(TJSONObject.Create.AddPair('success', TJSONBool.Create(False)).AddPair('message', Message).AddPair('status', TJSONNumber.Create(StatusCode)));
end;

{ ── Registro ── }

function TBaseController.Registro: ILogWriter;
begin
  if not Assigned(RegistroCondiviso) then
  begin
    LucchettoRegistro.Enter;
    try
      if not Assigned(RegistroCondiviso) then
        // Numero e dimensione dei file da configurazione (logMaxFiles,
        // logMaxFileSizeKB): prima erano fissi a 10 file da 5 KB, il
        // secondo numero di LoggerPro e' in KB, non in MB.
        RegistroCondiviso := BuildLogWriter([TLoggerProFileAppender.Create(TAppConfig.Instance.LogMaxFiles, TAppConfig.Instance.LogMaxFileSizeKB, TAppConfig.Instance.LogPath)]);
    finally
      LucchettoRegistro.Leave;
    end;
  end;

  Result := RegistroCondiviso;
end;

{ ── Parametri della richiesta ── }

function TBaseController.ParamByName(const Nome: string): string;
var
  Voce: TPair<string, string>;
  Segmento: string;
begin
  for Voce in Context.Request.QueryParams do
    if SameText(Voce.Key, Nome) then
      Exit(Voce.Value);

  for Voce in Context.Request.ContentFields do
    if SameText(Voce.Key, Nome) then
      Exit(Voce.Value);

  if Context.Request.SegmentParam(Nome, Segmento) then
    Exit(Segmento);

  Result := '';
end;

function TBaseController.ParamObbligatorio(const Nome: string): string;
begin
  Result := ParamByName(Nome);

  if Result.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Parametro %s non specificato.', [Nome]));
end;

function TBaseController.ParamInt64(const Nome: string; const Predefinito: Int64 = 0): Int64;
begin
  Result := StrToInt64Def(ParamByName(Nome).Trim, Predefinito);
end;

function TBaseController.ParamValuta(const Nome: string; const Predefinito: Currency = 0): Currency;
begin
  if not TryStrToCurr(ParamByName(Nome).Trim, Result) then
    Result := Predefinito;
end;

function TBaseController.CorpoJson: TJSONObject;
var
  Valore: TJSONValue;
begin
  Valore := TJSONObject.ParseJSONValue(Context.Request.Body);

  if not(Valore is TJSONObject) then
  begin
    FreeAndNil(Valore);
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Corpo della richiesta non valido: atteso un oggetto JSON.');
  end;

  Result := TJSONObject(Valore);
end;

{ ── Identita della richiesta ── }

function TBaseController.UserId: Int64;
begin
  Result := TSessionContextManager.Corrente.UserId;
end;

function TBaseController.IdSessione: Int64;
begin
  Result := TSessionContextManager.Corrente.IdSessione;
end;

function TBaseController.UserName: string;
begin
  Result := TSessionContextManager.Corrente.UserName;
end;

{ ── Dati ── }

function TBaseController.PrendiConnessione: TFDConnection;
begin
  Result := TConnectionPool.Instance.Acquire;
end;

procedure TBaseController.RilasciaConnessione(var Connessione: TFDConnection);
begin
  if Assigned(Connessione) then
  begin
    TConnectionPool.Instance.Release(Connessione);
    Connessione := nil;
  end;
end;

function TBaseController.CreaStoredProc(Connessione: TFDConnection; const Nome: string): TFDStoredProc;
begin
  Result := TFDStoredProc.Create(nil);
  try
    Result.Connection := Connessione;
    Result.StoredProcName := Nome;
    Result.Prepare;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

function TBaseController.CreaQuery(Connessione: TFDConnection; const SQL: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := Connessione;
    Result.SQL.Text := SQL;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

procedure TBaseController.ImpostaParametro(Parametro: TFDParam; const Valore: string);
begin
  if not Assigned(Parametro) then
    Exit;

  if Valore.Trim.IsEmpty then
    Parametro.Clear
  else
    if Parametro.Size > 0 then
      Parametro.AsString := Valore.Substring(0, Parametro.Size)
    else
      Parametro.AsString := Valore;
end;

// Le connessioni del raggruppamento hanno AutoStart attivo: una transazione
// puo' essere gia' aperta, e riaprirla solleva.
procedure TBaseController.ApriTransazione(Connessione: TFDConnection);
begin
  if not Connessione.InTransaction then
    Connessione.StartTransaction;
end;

procedure TBaseController.Conferma(Connessione: TFDConnection);
begin
  if Connessione.InTransaction then
    Connessione.Commit;
end;

procedure TBaseController.Annulla(Connessione: TFDConnection);
begin
  if Connessione.InTransaction then
    Connessione.Rollback;
end;

{ ── Risposte ── }

procedure TBaseController.RenderEsito(const Riuscito: Boolean = True);
begin
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(Riuscito)));
end;

// Il JSON viene reso come testo, non affidato al serializzatore: il tipo di
// contenuto predefinito e' gia application/json (impostato in WebModuleMain)
// e cosi' la proprieta dell'oggetto resta qui, senza dipendere da quali
// serializzatori dei tipi di System.JSON risultano registrati.
procedure TBaseController.RenderJson(Oggetto: TJSONObject);
begin
  if not Assigned(Oggetto) then
  begin
    RenderEsito(False);
    Exit;
  end;

  try
    RenderTestoJson(HTTP_STATUS.OK, Oggetto);
  finally
    FreeAndNil(Oggetto);
  end;
end;

procedure TBaseController.RenderTestoJson(const StatoHttp: Integer; Valore: TJSONValue);
var
  Testo: string;
begin
  Testo := Valore.ToJSON;
  Render(StatoHttp, Testo);
end;

procedure TBaseController.RenderDataSet(DataSet: TFDAdaptedDataSet);
var
  Righe: TJSONArray;
begin
  Righe := DataSet.DataSetToJSON({ encodeBlobs } True);
  try
    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    FreeAndNil(Righe);
  end;
end;

procedure TBaseController.RenderRecord(DataSet: TFDAdaptedDataSet);
begin
  RenderJson(DataSet.RecordToJSON({ encodeBlobs } True));
end;

procedure TBaseController.RenderStoredProc(Procedura: TFDStoredProc);
begin
  RenderJson(Procedura.ToJSON({ encodeBlobs } True));
end;

procedure TBaseController.RenderUrl(const Url: string);
begin
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('url', Url));
end;

initialization

LucchettoRegistro := TCriticalSection.Create;

finalization

RegistroCondiviso := nil;
FreeAndNil(LucchettoRegistro);

end.
