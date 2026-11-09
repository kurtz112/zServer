// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit WT.Tvb.Controller;

// Portato da Moduli\WT\dmTVB.pas (classe TTVB, framework TRoute).
//
// Pagamento con carta tramite il gateway della banca. La sequenza e' quella
// del sorgente e non e' stata toccata, perche' ogni passo corrisponde a una
// procedura sul database che tiene la traccia della transazione:
//
// CCRED_TVB_01_START_TRANS      apre la transazione
// CCRED_TVB_02_ADD_SCADENZE     collega le scadenze da pagare
// CCRED_TVB_03_PAYMENT_INIT     legge le credenziali e i parametri
// (richiamo HTTP al gateway)
// CCRED_TVB_04_PAYMENT_INIT_RISP registra identificativo e indirizzo di pagamento
// CCRED_TVB_05_NOTIFICATION_MSG  esito, chiamato dalla banca
// CCRED_TVB_06_REDIRECTED        conferma della visualizzazione dell'esito
// CCRED_TVB_07_NOTIF_ERROR_URL   errore, chiamato dalla banca
//
// Due differenze rispetto al sorgente:
//
// 1. Il richiamo al gateway usava TIdHTTP con TIdSSLIOHandlerSocketOpenSSL.
// Qui usa THTTPClient della RTL, che sul canale sicuro si appoggia al
// fornitore del sistema operativo: la richiesta e' la stessa (POST con
// campi codificati), e zServer non acquisisce una dipendenza da OpenSSL.
//
// 2. La registrazione su file della richiesta (procedura Log, che scriveva
// in un .log_tvb accanto all'eseguibile) e' sostituita dal registratore
// condiviso: i due canali di diagnostica erano uno di troppo.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller,
  Data.Service;

type
  /// <summary>
  /// Parametri che CCRED_TVB_03_PAYMENT_INIT restituisce e che vanno spediti
  /// al gateway. Sono tanti e tutti stringhe: un record evita una funzione
  /// con quindici parametri var, come nel sorgente d'origine.
  /// </summary>
  TParametriPagamento = record
    MerchantId: string;
    MerchantPassword: string;
    GatewayUrl: string;
    ActionType: string;
    CurrencyCode: string;
    LangId: string;
    ResponseUrl: string;
    ErrorUrl: string;
    TrackId: string;
    Udf1: string;
    Udf2: string;
    Udf3: string;
    Udf4: string;
    Udf5: string;
  end;

  [MVCPath('/api/wt/tvb')]
  [MVCDoc('Pagamenti con carta di credito tramite gateway bancario')]
  TWTTvbController = class(TBaseController)
  private
    function ElencoScadenze: TArray<Int64>;
    function InserisciTransazione(Connessione: TFDConnection; const IdContratto: Int64; const ImportoTotale: Currency): Int64;
    procedure CollegaScadenze(Connessione: TFDConnection; const IdTransazione: Int64; const Scadenze: TArray<Int64>);
    function LeggiParametriPagamento(Connessione: TFDConnection; const IdTransazione: Int64): TParametriPagamento;
    function ChiamaGateway(const Parametri: TParametriPagamento; const ImportoTotale: Currency): string;
    procedure RegistraEsitoPaymentInit(Connessione: TFDConnection; const IdTransazione: Int64; const PaymentId, PaymentUrl: string);
  public
    [MVCPath('/payment-init')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Apre la transazione, la registra e restituisce l''indirizzo di pagamento')]
    procedure PaymentInit;

    [MVCPath('/notification-message')]
    [MVCHTTPMethod([httpGET, httpPOST])]
    [MVCDoc('Esito del pagamento, chiamato dalla banca')]
    procedure NotificationMessage;

    [MVCPath('/redirected')]
    [MVCHTTPMethod([httpGET, httpPOST])]
    [MVCDoc('Conferma che l''esito e stato mostrato all''utente')]
    procedure Redirected;

    [MVCPath('/error-url')]
    [MVCHTTPMethod([httpGET, httpPOST])]
    [MVCDoc('Errore di pagamento, chiamato dalla banca')]
    procedure ErrorURL;

    [MVCPath('/stato-transazione')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Stato di una transazione')]
    procedure GetStatoTransazione;
  end;

implementation

uses
  System.StrUtils,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.URLClient,
  Json.Values;

{ TWTTvbController }

// Le scadenze arrivano nella forma [1, 2, 3]: si accettano solo numeri, e
// una voce non numerica ferma tutto invece di essere ignorata in silenzio.
function TWTTvbController.ElencoScadenze: TArray<Int64>;
var
  Testo: string;
  Voce: string;
  Scadenza: Int64;
begin
  Result := [];

  Testo := ParamByName('idScadenze').Replace('[', '', [rfReplaceAll]).Replace(']', '', [rfReplaceAll]).Trim;

  for Voce in SplitString(Testo, ',') do
  begin
    if Voce.Trim.IsEmpty then
      Continue;

    if not TryStrToInt64(Voce.Trim, Scadenza) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Identificativo di scadenza non corretto: %s', [Voce.Trim]));

    Result := Result + [Scadenza];
  end;
end;

function TWTTvbController.InserisciTransazione(Connessione: TFDConnection; const IdContratto: Int64; const ImportoTotale: Currency): Int64;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaStoredProc(Connessione, 'CCRED_TVB_01_START_TRANS');
  try
    Procedura.ParamByName('ID_SESSIONE_WEB').AsLargeInt := IdSessione;
    Procedura.ParamByName('ID_CONTRATTO').AsLargeInt := IdContratto;
    Procedura.ParamByName('IMPORTO_TOTALE').AsCurrency := ImportoTotale;
    Procedura.ExecProc;
    Result := Procedura.ParamByName('ID_CCRED_TVB_TRANSAZIONE').AsLargeInt;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TWTTvbController.CollegaScadenze(Connessione: TFDConnection; const IdTransazione: Int64; const Scadenze: TArray<Int64>);
var
  Procedura: TFDStoredProc;
  Scadenza: Int64;
begin
  Procedura := CreaStoredProc(Connessione, 'CCRED_TVB_02_ADD_SCADENZE');
  try
    for Scadenza in Scadenze do
    begin
      Procedura.ParamByName('ID_CCRED_TVB_TRANSAZIONE').AsLargeInt := IdTransazione;
      Procedura.ParamByName('ID_SCADENZA').AsLargeInt := Scadenza;
      Procedura.ExecProc;
    end;
  finally
    FreeAndNil(Procedura);
  end;
end;

function TWTTvbController.LeggiParametriPagamento(Connessione: TFDConnection; const IdTransazione: Int64): TParametriPagamento;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaStoredProc(Connessione, 'CCRED_TVB_03_PAYMENT_INIT');
  try
    Procedura.ParamByName('ID_CCRED_TVB_TRANSAZIONE').AsLargeInt := IdTransazione;
    Procedura.ExecProc;

    Result.MerchantId := Procedura.ParamByName('MERCHANT_ID').AsString;
    Result.MerchantPassword := Procedura.ParamByName('MERCHANT_PWD').AsString;
    Result.GatewayUrl := Procedura.ParamByName('GATEWAY_URL').AsString;
    Result.ActionType := Procedura.ParamByName('ACTION_TYPE').AsString;
    Result.CurrencyCode := Procedura.ParamByName('CURRENCY_CODE').AsString;
    Result.LangId := Procedura.ParamByName('LANG_ID').AsString;
    Result.ResponseUrl := Procedura.ParamByName('RESPONSE_URL').AsString;
    Result.ErrorUrl := Procedura.ParamByName('ERROR_URL').AsString;
    Result.TrackId := Procedura.ParamByName('TRACK_ID').AsString;
    Result.Udf1 := Procedura.ParamByName('UDF1').AsString;
    Result.Udf2 := Procedura.ParamByName('UDF2').AsString;
    Result.Udf3 := Procedura.ParamByName('UDF3').AsString;
    Result.Udf4 := Procedura.ParamByName('UDF4').AsString;
    Result.Udf5 := Procedura.ParamByName('UDF5').AsString;

    // Le credenziali del negoziante non finiscono nel registro.
    Registro.Debug(Format('PaymentInit - transazione %d, gateway %s, track %s', [IdTransazione, Result.GatewayUrl, Result.TrackId]), 'WTTvbController');
  finally
    FreeAndNil(Procedura);
  end;
end;

function TWTTvbController.ChiamaGateway(const Parametri: TParametriPagamento; const ImportoTotale: Currency): string;
var
  Client: THTTPClient;
  Campi: TStringList;
  Corpo: TStringStream;
  Risposta: IHTTPResponse;
  FormatoImporto: TFormatSettings;
  Testo: string;
  i: Integer;
begin
  // Il gateway vuole l'importo con il punto decimale e due cifre, senza
  // simbolo di valuta: con le impostazioni locali italiane arriverebbe con
  // la virgola e verrebbe rifiutato.
  FormatoImporto := TFormatSettings.Create;
  FormatoImporto.DecimalSeparator := '.';
  FormatoImporto.CurrencyString := '';
  FormatoImporto.CurrencyDecimals := 2;

  Campi := TStringList.Create;
  try
    Campi.Add('id=' + Parametri.MerchantId);
    Campi.Add('password=' + Parametri.MerchantPassword);
    Campi.Add('action=' + Parametri.ActionType);
    Campi.Add('currencycode=' + Parametri.CurrencyCode);
    Campi.Add('langid=' + Parametri.LangId);
    Campi.Add('responseURL=' + Parametri.ResponseUrl);
    Campi.Add('errorURL=' + Parametri.ErrorUrl);
    Campi.Add('amt=' + CurrToStr(ImportoTotale, FormatoImporto));
    Campi.Add('trackid=' + Parametri.TrackId);
    Campi.Add('udf1=' + Parametri.Udf1);
    Campi.Add('udf2=' + Parametri.Udf2);
    Campi.Add('udf3=' + Parametri.Udf3);
    Campi.Add('udf4=' + Parametri.Udf4);
    Campi.Add('udf5=' + Parametri.Udf5);

    Testo := '';
    for i := 0 to Campi.Count - 1 do
    begin
      if not Testo.IsEmpty then
        Testo := Testo + '&';

      Testo := Testo + Campi.Names[i] + '=' + TNetEncoding.URL.EncodeForm(Campi.ValueFromIndex[i]);
    end;
  finally
    FreeAndNil(Campi);
  end;

  Corpo := TStringStream.Create(Testo, TEncoding.ANSI);
  try
    Client := THTTPClient.Create;
    try
      Client.ContentType := 'application/x-www-form-urlencoded';
      Client.HandleRedirects := True;
      Client.Accept := 'text/html, */*';

      Risposta := Client.Post(Parametri.GatewayUrl, Corpo);
      Result := Risposta.ContentAsString(TEncoding.ANSI);
    finally
      FreeAndNil(Client);
    end;
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTTvbController.RegistraEsitoPaymentInit(Connessione: TFDConnection; const IdTransazione: Int64; const PaymentId, PaymentUrl: string);
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaStoredProc(Connessione, 'CCRED_TVB_04_PAYMENT_INIT_RISP');
  try
    Procedura.ParamByName('ID_CCRED_TVB_TRANSAZIONE').AsLargeInt := IdTransazione;
    Procedura.ParamByName('PAYMENT_ID').AsString := PaymentId;
    Procedura.ParamByName('PAYMENT_URL').AsString := PaymentUrl;
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TWTTvbController.PaymentInit;
var
  Connessione: TFDConnection;
  IdContratto: Int64;
  ImportoTotale: Currency;
  Scadenze: TArray<Int64>;
  IdTransazione: Int64;
  Parametri: TParametriPagamento;
  Risposta: string;
  Separatore: Integer;
  PaymentId: string;
  PaymentUrl: string;
  Messaggio: string;
begin
  IdContratto := ParamInt64('idContratto');

  if IdContratto <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Contratto non specificato.');

  ImportoTotale := ParamValuta('importoTotale');

  if ImportoTotale <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Importo non specificato.');

  Scadenze := ElencoScadenze;

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      IdTransazione := InserisciTransazione(Connessione, IdContratto, ImportoTotale);
      CollegaScadenze(Connessione, IdTransazione, Scadenze);
      Parametri := LeggiParametriPagamento(Connessione, IdTransazione);

      Risposta := ChiamaGateway(Parametri, ImportoTotale);

      // Il gateway risponde 'PaymentID:Url' se ha accettato, oppure
      // '!ERROR!-CODICE-Descrizione'.
      if StartsText('!ERROR!', Risposta) then
      begin
        Annulla(Connessione);
        Messaggio := Risposta.Replace('!ERROR!-', 'Errore ').Replace('!-', ': ');
        Registro.Warn(Format('PaymentInit - gateway ha rifiutato la transazione %d: %s', [IdTransazione, Risposta]), 'WTTvbController');
        raise EMVCException.Create(HTTP_STATUS.BadGateway, Messaggio);
      end;

      Separatore := Pos(':', Risposta);
      PaymentId := Copy(Risposta, 1, Separatore - 1);
      PaymentUrl := Copy(Risposta, Separatore + 1, Length(Risposta));

      RegistraEsitoPaymentInit(Connessione, IdTransazione, PaymentId, PaymentUrl);

      Conferma(Connessione);

      RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('ID_CCRED_TVB_TRANSAZIONE', TJSONNumber.Create(IdTransazione)).AddPair('PAYMENT_ID', PaymentId)
        .AddPair('PAYMENT_URL', PaymentUrl).AddPair('url', PaymentUrl + '?PaymentID=' + PaymentId));
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
end;

procedure TWTTvbController.NotificationMessage;
var
  Parametri: TParamValues;
  Esito: TJSONObject;
  CodiceErrore: string;
  TestoErrore: string;
  Indirizzo: string;
begin
  // Chiamata dalla banca, senza token: e' in AzioniPubbliche del profilo.
  Registro.Info(Format('NotificationMessage - pagamento %s, esito %s', [ParamByName('paymentid'), ParamByName('result')]), 'WTTvbController');

  CodiceErrore := ParamByName('ERROR');
  TestoErrore := ParamByName('ErrorText').Replace(CodiceErrore + '-', '');

  Parametri := TParamValues.Create;
  try
    Parametri.Add('PAYMENT_ID', ParamByName('paymentid'));
    Parametri.Add('TRAN_ID', ParamByName('tranid'));
    Parametri.Add('RESULT', ParamByName('result'));
    Parametri.Add('AUTH', ParamByName('auth'));
    Parametri.Add('POST_DATE', ParamByName('postdate'));
    Parametri.Add('TRACK_ID', ParamByName('trackid'));
    Parametri.Add('REF', ParamByName('ref'));
    Parametri.Add('UDF1', ParamByName('udf1'));
    Parametri.Add('UDF2', ParamByName('udf2'));
    Parametri.Add('UDF3', ParamByName('udf3'));
    Parametri.Add('UDF4', ParamByName('udf4'));
    Parametri.Add('UDF5', ParamByName('udf5'));
    Parametri.Add('RESP_CODE', ParamByName('responsecode'));
    Parametri.Add('ERROR_CODE', CodiceErrore);
    Parametri.Add('ERR_TEXT', TestoErrore);

    Esito := TDataService.ExecuteStoredProc('CCRED_TVB_05_NOTIFICATION_MSG', Parametri);
    try
      Indirizzo := JsonStr(Esito, 'REDIRECT_URL');
    finally
      FreeAndNil(Esito);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  RenderUrl(Indirizzo);
end;

procedure TWTTvbController.Redirected;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  IdTransazione: Int64;
  Incassata: string;
  Messaggio: string;
begin
  IdTransazione := ParamInt64('idTransazione');

  if IdTransazione <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Transazione non specificata.');

  Connessione := PrendiConnessione;
  try
    Procedura := CreaStoredProc(Connessione, 'CCRED_TVB_06_REDIRECTED');
    try
      Procedura.ParamByName('ID_CCRED_TVB_TRANSAZIONE').AsLargeInt := IdTransazione;
      Procedura.ExecProc;
      Incassata := Procedura.ParamByName('INCASSATA').AsString;
      Messaggio := Procedura.ParamByName('MESSAGGIO').AsString;
    finally
      FreeAndNil(Procedura);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('INCASSATA', Incassata).AddPair('MESSAGGIO', Messaggio));
end;

procedure TWTTvbController.ErrorURL;
var
  Parametri: TParamValues;
  Esito: TJSONObject;
  Indirizzo: string;
begin
  Registro.Warn(Format('ErrorURL - track %s', [ParamByName('TRACK_ID')]), 'WTTvbController');

  Parametri := TParamValues.Create;
  try
    Parametri.Add('TRACK_ID', ParamByName('TRACK_ID'));

    Esito := TDataService.ExecuteStoredProc('CCRED_TVB_07_NOTIF_ERROR_URL', Parametri);
    try
      Indirizzo := JsonStr(Esito, 'REDIRECT_URL');
    finally
      FreeAndNil(Esito);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  RenderUrl(Indirizzo);
end;

procedure TWTTvbController.GetStatoTransazione;
var
  Parametri: TParamValues;
  Esito: TJSONObject;
  Stato: string;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_CCRED_TVB_TRANSAZIONE', ParamInt64('idTransazione'));

    Esito := TDataService.ExecuteStoredProc('CCRED_TVB_GET_STATO_TRANSAZIONE', Parametri);
    try
      Stato := JsonStr(Esito, 'STATO_TRANSAZIONE');
    finally
      FreeAndNil(Esito);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('STATO_TRANSAZIONE', Stato));
end;

end.
