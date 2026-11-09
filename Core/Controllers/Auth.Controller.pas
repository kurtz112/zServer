// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-06
// ---------------------------------------------------------------------------
// 2026-11-06: /api/auth/moduli restituisce i moduli dell'utente collegato, comune per comune
// (moduli di Pipa per comune e per gruppo, OUT\20261106-pipa-sportello-comuni-funzioni-per-comune).
// 2026-11-05 (sera): le regole del secondo fattore stanno nel database (USR_APPS.OTP_MODALITA:
// N non previsto, F facoltativo, O obbligatorio; WT-AUTH-03 e GESTY-AUTH-01). /totp/stato le
// riporta con USR_TOTP_REGOLE, /totp/attiva imposta USR_UTENTI.OTP (lo fa la procedura) e la
// nuova /totp/disattiva toglie l'app con un codice valido, dove le regole lo consentono.
unit Auth.Controller;

// Restano qui solo i punti di ingresso che arrivano davvero a un controller.
//
// /api/auth/refresh, /api/auth/logout e /api/auth/logout-all li intercetta
// TMVCJWTRefreshMiddleware in OnBeforeRouting, prima dell'instradamento:
// le azioni con gli stessi percorsi che stavano qui non venivano mai
// eseguite, ed erano una seconda implementazione delle stesse tre operazioni,
// con claim diversi da quelli del middleware. Sono state eliminate e la
// correzione e' stata fatta dove il codice gira, cioe' nel middleware.
//
// /api/auth/password (2026-10-30) e' il cambio password comune a WT e Gesty:
// prima esisteva solo /api/wt/admin/password nel prodotto WT, e il portale di
// Gesty non aveva modo di cambiarla. USR_CAMBIA_PASSWORD ha la stessa firma e
// lo stesso corpo nei due database. La rotta di WT resta per i client che la
// usano gia'.
//
// /api/auth/area (2026-11-02, fase 0 delle aree) porta la sessione in
// un'altra area dell'utente senza rifare l'accesso. Non emette un token: il
// client chiama subito /api/auth/refresh, che rilegge l'area dalla sessione.
// Cosi' il token nasce sempre in un posto solo (TTokenService) e non serve
// un secondo modo di sostituirlo nel client.
//
// Secondo fattore (2026-11-05, WT e Gesty: serve USR_WEB_SESSIONE_ADOTTA, script
// WT-AUTH-01 per WT e GESTY-AUTH-01 per Gesty). Se USR_LOGIN risponde OTP vero il token nasce con la sessione
// "in attesa": ogni richiesta con contesto fallisce finche' il codice non e'
// verificato, e la procedura USR_TOTP_VERIFICA guarda la
// connessione che ha aperto la sessione, che a una richiesta successiva non e'
// piu' quella in mano. Le rotte /otp/* girano percio' su una connessione senza
// contesto (come il login), che adotta la sessione del token prima di chiamare
// la procedura, e la lascia a fine richiesta. Le rotte /totp/* (stato,
// registrazione, attivazione, codici di recupero) servono a sessione gia'
// valida e usano la connessione ordinaria.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  Base.Controller;

type

  [MVCPath('/api/auth')]
  [MVCDoc('Stato dell''autenticazione')]
  TAuthController = class(TBaseController)
  public
    [MVCPath('/validate')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Verifica che il token sia valido e restituisce l''identita che porta')]
    [MVCSwagSummary('Autenticazione', 'Verifica il token', 'default')]
    [MVCSwagResponses(200, 'Token valido')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure ValidateToken;

    [MVCPath('/password')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Cambio della password dell''utente collegato: corpo { "oldPassword": "...", "newPassword": "..." }')]
    [MVCSwagSummary('Autenticazione', 'Cambia la password dell''utente collegato', 'default')]
    [MVCSwagResponses(200, 'Password cambiata')]
    [MVCSwagResponses(400, 'Password attuale errata, nuova password mancante o utente non valido')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure CambiaPassword;

    [MVCPath('/area')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Cambio d''area della sessione: corpo { "area": "WTWEB_GERA" }; poi il client rinnova il token')]
    [MVCSwagSummary('Autenticazione', 'Porta la sessione in un''altra area dell''utente', 'default')]
    [MVCSwagResponses(200, 'Area cambiata')]
    [MVCSwagResponses(400, 'Area mancante, non abilitata, fuori fascia oraria o con secondo fattore da verificare')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure CambiaArea;

    [MVCPath('/moduli')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Moduli dell''utente collegato, ciascuno con i comuni in cui e'' attivo per lui e l''accesso (consulta o lavora)')]
    [MVCSwagSummary('Autenticazione', 'Moduli dell''utente collegato', 'default')]
    [MVCSwagResponses(200, 'Moduli letti; elenco vuoto se il prodotto non ha moduli o l''utente non ne ha')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure Moduli;

    [MVCPath('/otp/stato')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Secondo fattore da completare: dice se l''utente ha l''app di autenticazione attiva e se il codice via mail e'' disponibile')]
    [MVCSwagSummary('Secondo fattore', 'Stato del secondo fattore della sessione in attesa', 'default')]
    [MVCSwagResponses(200, 'Stato letto')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure OtpStato;

    [MVCPath('/otp/totp')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Verifica il codice dell''app di autenticazione (o un codice di recupero) e completa la sessione: corpo { "codice": "123456" }')]
    [MVCSwagSummary('Secondo fattore', 'Verifica il codice dell''app', 'default')]
    [MVCSwagResponses(200, 'Sessione completata')]
    [MVCSwagResponses(400, 'Codice mancante, errato, gia'' usato o utente bloccato')]
    [MVCSwagResponses(401, 'Token assente, scaduto o non valido')]
    procedure OtpVerificaTotp;

    [MVCPath('/otp/mail')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Genera un codice e lo spedisce alla mail dell''utente (alternativa all''app, e primo accesso prima di registrarla)')]
    [MVCSwagSummary('Secondo fattore', 'Invia il codice via mail', 'default')]
    [MVCSwagResponses(200, 'Codice inviato')]
    [MVCSwagResponses(400, 'Utente senza mail o invio del codice non configurato')]
    [MVCSwagResponses(503, 'Posta non configurata su questo server')]
    procedure OtpInviaMail;

    [MVCPath('/otp/mail/verifica')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Verifica il codice ricevuto via mail e completa la sessione: corpo { "codice": "123456" }')]
    [MVCSwagSummary('Secondo fattore', 'Verifica il codice ricevuto via mail', 'default')]
    [MVCSwagResponses(200, 'Sessione completata')]
    [MVCSwagResponses(400, 'Codice errato, scaduto o troppi tentativi')]
    procedure OtpVerificaMail;

    [MVCPath('/totp/stato')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Stato dell''app di autenticazione dell''utente collegato')]
    [MVCSwagSummary('Secondo fattore', 'Stato dell''app di autenticazione', 'default')]
    [MVCSwagResponses(200, 'Stato letto')]
    procedure TotpStato;

    [MVCPath('/totp/registra')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Registra un segreto nuovo per l''utente collegato e restituisce l''indirizzo otpauth per il codice QR; l''app resta in sospeso finche'' non si conferma un codice con /totp/attiva')]
    [MVCSwagSummary('Secondo fattore', 'Registra l''app di autenticazione', 'default')]
    [MVCSwagResponses(200, 'Segreto registrato')]
    [MVCSwagResponses(400, 'App gia'' attiva o non disponibile su questo database')]
    procedure TotpRegistra;

    [MVCPath('/totp/attiva')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Attiva l''app con il primo codice e restituisce i codici di recupero (una volta sola): corpo { "codice": "123456" }')]
    [MVCSwagSummary('Secondo fattore', 'Attiva l''app di autenticazione', 'default')]
    [MVCSwagResponses(200, 'App attivata')]
    [MVCSwagResponses(400, 'Codice errato, app gia'' attiva o nessuna registrazione in sospeso')]
    procedure TotpAttiva;

    [MVCPath('/totp/codici-recupero')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Rigenera i codici di recupero (quelli di prima non valgono piu'') e li restituisce una volta sola')]
    [MVCSwagSummary('Secondo fattore', 'Rigenera i codici di recupero', 'default')]
    [MVCSwagResponses(200, 'Codici generati')]
    [MVCSwagResponses(400, 'App di autenticazione non attiva')]
    procedure TotpCodiciRecupero;

    [MVCPath('/totp/disattiva')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Disattiva l''app di autenticazione dell''utente collegato con un codice valido (app o recupero): corpo { "codice": "123456" }. Non e'' consentito nelle aree dove il secondo fattore e'' obbligatorio')]
    [MVCSwagSummary('Secondo fattore', 'Disattiva l''app di autenticazione', 'default')]
    [MVCSwagResponses(200, 'App disattivata')]
    [MVCSwagResponses(400, 'Codice errato o gia'' usato, utente bloccato, app non attiva o disattivazione non consentita')]
    procedure TotpDisattiva;
  private
    function PrendiConnessioneInAttesa: TFDConnection;
    procedure RilasciaConnessioneInAttesa(var Connessione: TFDConnection);
    procedure ImpostaCodiciRecupero(Connessione: TFDConnection; const Codici: TArray<string>);
    function CodiceDelCorpo: string;
    function LeggiRegole(Connessione: TFDConnection): Boolean;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  Data.DB,
  FireDAC.Stan.Param,
  Json.Values,
  App.Profile,
  Connection.Pool,
  Mail.Sender,
  Token.Service;

{$IFDEF MSWINDOWS}
const
  // Chiede al sistema il generatore casuale preferito, senza aprire un algoritmo
  BCRYPT_USA_GENERATORE_DI_SISTEMA = 2;

function BCryptGenRandom(Algoritmo: Pointer; Buffer: PByte; Lunghezza: Cardinal; Opzioni: Cardinal): Integer; stdcall; external 'bcrypt.dll' name 'BCryptGenRandom';
{$ENDIF}

const
  LUNGHEZZA_SEGRETO_BYTE = 20;
  NUMERO_CODICI_RECUPERO = 10;
  LUNGHEZZA_CODICE_RECUPERO = 16;
  ALFABETO_BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  // Senza 0, O, 1, I, L: si confondono su carta. 31 simboli, come nel client desktop.
  ALFABETO_CODICI_RECUPERO = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

// Byte casuali dal generatore del sistema. Se non risponde si solleva l'eccezione:
// un segreto debole non si genera mai al suo posto.
function ByteCasuali(const Quanti: Integer): TBytes;
{$IFNDEF MSWINDOWS}
var
  Sorgente: TFileStream;
{$ENDIF}
begin
  SetLength(Result, Quanti);
{$IFDEF MSWINDOWS}
  if BCryptGenRandom(nil, PByte(Result), Quanti, BCRYPT_USA_GENERATORE_DI_SISTEMA) <> 0 then
    raise Exception.Create('Il generatore casuale del sistema non risponde.');
{$ELSE}
  Sorgente := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
  try
    if Sorgente.Read(Result[0], Quanti) <> Quanti then
      raise Exception.Create('Il generatore casuale del sistema non risponde.');
  finally
    FreeAndNil(Sorgente);
  end;
{$ENDIF}
end;

// Base32 della RFC 4648 senza il riempimento, la forma che le app chiedono nel parametro secret
function CodificaBase32(const Dati: TBytes): string;
var
  Posizione: Integer;
  Accumulo: Cardinal;
  BitDisponibili: Integer;
begin
  Result := '';
  Accumulo := 0;
  BitDisponibili := 0;
  for Posizione := 0 to High(Dati) do
  begin
    Accumulo := (Accumulo shl 8) or Dati[Posizione];
    Inc(BitDisponibili, 8);
    while BitDisponibili >= 5 do
    begin
      Dec(BitDisponibili, 5);
      Result := Result + ALFABETO_BASE32[((Accumulo shr BitDisponibili) and 31) + 1];
    end;
    Accumulo := Accumulo and ((Cardinal(1) shl BitDisponibili) - 1);
  end;
  if BitDisponibili > 0 then
    Result := Result + ALFABETO_BASE32[((Accumulo shl (5 - BitDisponibili)) and 31) + 1];
end;

// Dieci codici XXXX-XXXX-XXXX-XXXX. Il byte casuale oltre il multiplo piu' alto della
// lunghezza dell'alfabeto si scarta, cosi' nessun simbolo esce piu' spesso degli altri.
function GeneraCodiciRecupero: TArray<string>;
var
  Limite: Integer;
  Indice: Integer;
  Carattere: Integer;
  Dati: TBytes;
  Posizione: Integer;
  Codice: string;
begin
  Limite := 256 - (256 mod Length(ALFABETO_CODICI_RECUPERO));
  SetLength(Result, NUMERO_CODICI_RECUPERO);
  Dati := nil;
  Posizione := 0;
  for Indice := 0 to NUMERO_CODICI_RECUPERO - 1 do
  begin
    Codice := '';
    while Length(Codice) < LUNGHEZZA_CODICE_RECUPERO do
    begin
      if Posizione >= Length(Dati) then
      begin
        Dati := ByteCasuali(64);
        Posizione := 0;
      end;
      Carattere := Dati[Posizione];
      Inc(Posizione);
      if Carattere >= Limite then
        Continue;
      Codice := Codice + ALFABETO_CODICI_RECUPERO[(Carattere mod Length(ALFABETO_CODICI_RECUPERO)) + 1];
    end;
    Result[Indice] := Codice.Substring(0, 4) + '-' + Codice.Substring(4, 4) + '-' + Codice.Substring(8, 4) + '-' + Codice.Substring(12, 4);
  end;
end;

// Frase da mostrare all'utente per i rifiuti previsti delle procedure del secondo fattore,
// vuota se l'errore non lo e': il messaggio di Firebird porta anche il nome dell'eccezione
// e la riga della procedura.
function RifiutoSecondoFattore(const Messaggio: string): string;
begin
  if Messaggio.Contains('non si puo'' disattivare') then
    Result := 'Il secondo fattore e'' obbligatorio per le aree a cui hai accesso: non si puo'' disattivare.'
  else
    if Messaggio.Contains('Codice gia'' usato') then
      Result := 'Codice gia'' usato: attendi il codice successivo dell''app e riprova.'
    else
      if Messaggio.Contains('azzerare l''app') then
        Result := 'L''app non si puo'' leggere: chiedi all''amministratore di azzerarla.'
      else
        if Messaggio.Contains('Nessuna app di autenticazione attiva') then
          Result := 'Nessuna app di autenticazione attiva.'
        else
  if Messaggio.Contains('gia'' attiva') then
    Result := 'L''app di autenticazione e'' gia'' attiva: per registrarne una nuova serve l''amministratore.'
  else
    if Messaggio.Contains('Codice non valido') then
      Result := 'Codice non valido: controlla che data e ora del telefono siano automatiche e riprova con il codice successivo.'
    else
      if Messaggio.Contains('Utente bloccato') then
        Result := 'Utente bloccato per troppi tentativi errati: riprova fra qualche minuto.'
      else
        if Messaggio.Contains('Nessuna app di autenticazione registrata') then
          Result := 'Nessuna registrazione in sospeso: avvia prima la registrazione dell''app.'
        else
          if Messaggio.Contains('chiave di cifratura') or Messaggio.Contains('non e'' disponibile') then
            Result := 'L''app di autenticazione non e'' disponibile su questo database.'
          else
            if Messaggio.Contains('solo con l''app di autenticazione attiva') then
              Result := 'I codici di recupero si generano solo con l''app di autenticazione attiva.'
            else
              Result := '';
end;

// Testo da mostrare all'utente per i rifiuti di USR_CAMBIA_PASSWORD, vuoto se
// l'errore non e' un rifiuto previsto. Il messaggio di Firebird contiene anche
// il nome dell'eccezione e la riga della procedura, e in WT la procedura
// aggiunge l'identificativo della sessione al testo della password errata:
// all'utente si riporta solo la frase.
function MotivoRifiuto(const Messaggio: string): string;
begin
  if Messaggio.Contains('Password attuale non valida') then
    Result := 'La password attuale non e'' corretta.'
  else
    if Messaggio.Contains('Utente/password non validi') or Messaggio.Contains('Utente non valido') then
      Result := 'Utente non valido o non attivo.'
    else
      Result := '';
end;

procedure TAuthController.ValidateToken;
begin
  // Se si arriva qui il middleware ha gia' verificato firma e scadenza:
  // basta restituire cosa dice il token, che e' quello che il front end usa
  // per decidere cosa mostrare.
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair(JWT_CLAIM_USER_ID, TJSONNumber.Create(UserId)).AddPair(JWT_CLAIM_ID_SESSIONE, TJSONNumber.Create(IdSessione))
    .AddPair(JWT_CLAIM_USERNAME, UserName).AddPair(JWT_CLAIM_NOMINATIVO, Context.LoggedUser.CustomData[JWT_CLAIM_NOMINATIVO]).AddPair(JWT_CLAIM_RUOLO, Context.LoggedUser.CustomData[JWT_CLAIM_RUOLO]));
end;

procedure TAuthController.CambiaPassword;
var
  Corpo: TJSONObject;
  PasswordAttuale: string;
  PasswordNuova: string;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Lettura: TFDQuery;
  MetodoVerifica: string;
  Motivo: string;
begin
  Corpo := CorpoJson;
  try
    PasswordAttuale := JsonStr(Corpo, 'oldPassword');
    PasswordNuova := JsonStr(Corpo, 'newPassword');
  finally
    FreeAndNil(Corpo);
  end;

  if PasswordAttuale.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Password attuale non indicata.');
  if PasswordNuova.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Nuova password non indicata.');

  // L'utente e la sessione arrivano dal token, mai dal corpo: chi chiama puo'
  // cambiare solo la propria password, e solo conoscendo quella attuale.
  Connessione := PrendiConnessione;
  try
    // 2026-10-30: USR_VERIFICA_PASSWORD da' sempre ragione agli utenti con
    // PWD_METODO_VERIFICA 'D' (dominio) e 'N' (nessuna verifica), quindi per
    // loro USR_CAMBIA_PASSWORD accettava qualunque password attuale e il
    // portale diceva "Password cambiata" anche se la password scritta non
    // conta: per 'D' vale quella del dominio, per 'N' il login non la guarda.
    // Visto alla prova sullo zServer di Gesty con l'utente luca ('N').
    Lettura := CreaQuery(Connessione, 'SELECT USR_UTENTI.PWD_METODO_VERIFICA FROM USR_UTENTI WHERE USR_UTENTI.USER_ID = :USER_ID');
    try
      Lettura.ParamByName('USER_ID').AsLargeInt := UserId;
      Lettura.Open;
      MetodoVerifica := Lettura.Fields[0].AsString;
      Lettura.Close;
    finally
      FreeAndNil(Lettura);
    end;

    if MetodoVerifica = 'D' then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La tua password e'' quella del dominio aziendale: si cambia dal computer o con l''amministratore di rete, non dal portale.');
    if MetodoVerifica = 'N' then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Per il tuo utente la password non viene controllata: chiedi al tuo ente di attivarne la verifica prima di cambiarla.');

    Procedura := CreaStoredProc(Connessione, 'USR_CAMBIA_PASSWORD');
    try
      ApriTransazione(Connessione);
      try
        Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione;
        Procedura.ParamByName('USER_ID').AsLargeInt := UserId;
        Procedura.ParamByName('OLD_PASSWORD').AsString := PasswordAttuale;
        Procedura.ParamByName('NEW_PASSWORD').AsString := PasswordNuova;
        Procedura.ExecProc;
        Conferma(Connessione);
      except
        on E: Exception do
        begin
          Annulla(Connessione);
          Motivo := MotivoRifiuto(E.Message);
          if Motivo.IsEmpty then
            raise;
          Registro.Warn(Format('Cambio password rifiutato per utente %d: %s', [UserId, Motivo]), 'AuthController');
          raise EMVCException.Create(HTTP_STATUS.BadRequest, Motivo);
        end;
      end;
    finally
      FreeAndNil(Procedura);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('Password cambiata da utente %d', [UserId]), 'AuthController');
  RenderEsito(True);
end;

procedure TAuthController.CambiaArea;
var
  Corpo: TJSONObject;
  Area: string;
begin
  Corpo := CorpoJson;
  try
    Area := JsonStr(Corpo, 'area').Trim.ToUpper;
  finally
    FreeAndNil(Corpo);
  end;

  if Area.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Area non indicata.');

  // La sessione e' quella del token: si cambia solo la propria. I controlli
  // (area dei gruppi, fascia oraria, secondo fattore) li fa il profilo.
  TAppProfiles.Corrente.CambiaArea(IdSessione, Area);

  Registro.Info(Format('Utente %d, sessione %d: area %s', [UserId, IdSessione, Area]), 'AuthController');
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair(JWT_CLAIM_AREA, Area));
end;

// Moduli dell'utente del token, raggruppati per modulo:
// { "success": true, "moduli": [ { "modulo": "Comune.Giri", "scrittura": true,
//   "comuni": [ { "belfiore": "A123", "scrittura": true } ] } ] }
// "scrittura" del modulo e' vero se l'utente lo lavora in almeno un comune.
// Servono a Pipa per il menu: la protezione vera la fanno le rotte dei dati,
// che rileggono i moduli a ogni richiesta. Non stanno nel token perche' con
// molti comuni lo allungherebbero a ogni rinnovo, e perche' una modifica di
// gruppi o contratti vale subito senza aspettare il token successivo.
procedure TAuthController.Moduli;
var
  Riga: TModuloUtente;
  Elenco: TJSONArray;
  PerModulo: TDictionary<string, TJSONObject>;
  Modulo: TJSONObject;
  Risposta: TJSONObject;
begin
  Risposta := TJSONObject.Create;
  try
    Elenco := TJSONArray.Create;
    Risposta.AddPair('success', TJSONBool.Create(True)).AddPair('moduli', Elenco);

    // Il dizionario non possiede gli oggetti: stanno in Elenco
    PerModulo := TDictionary<string, TJSONObject>.Create;
    try
      // Prima i moduli dell'operatore, poi quelli del portale del cittadino
      // (Cittadino.*, sola lettura, rilascio 013): i due insiemi non hanno
      // moduli in comune
      // e i moduli senza comune dati dai gruppi (Gera.*, rilascio 014: elenco
      // "comuni" vuoto)
      for Riga in TAppProfiles.Corrente.ModuliUtente(UserName) + TAppProfiles.Corrente.ModuliCittadino(UserName) + TAppProfiles.Corrente.ModuliGruppo(UserName) do
      begin
        if not PerModulo.TryGetValue(Riga.Modulo.ToUpper, Modulo) then
        begin
          Modulo := TJSONObject.Create;
          Modulo.AddPair('modulo', Riga.Modulo).AddPair('scrittura', TJSONBool.Create(False)).AddPair('comuni', TJSONArray.Create);
          Elenco.AddElement(Modulo);
          PerModulo.Add(Riga.Modulo.ToUpper, Modulo);
        end;

        TJSONArray(Modulo.GetValue('comuni')).AddElement(TJSONObject.Create.AddPair('belfiore', Riga.Belfiore).AddPair('scrittura', TJSONBool.Create(Riga.Scrittura)));

        if Riga.Scrittura then
        begin
          Modulo.RemovePair('scrittura').Free;
          Modulo.AddPair('scrittura', TJSONBool.Create(True));
        end;
      end;
    finally
      FreeAndNil(PerModulo);
    end;
  except
    FreeAndNil(Risposta);
    raise;
  end;

  RenderJson(Risposta);
end;

{ Secondo fattore }

// Connessione senza contesto con la sessione del token adottata: le procedure del
// secondo fattore la riconoscono come "la sessione in attesa di questa connessione".
// Il chiamante la restituisce con RilasciaConnessioneInAttesa.
function TAuthController.PrendiConnessioneInAttesa: TFDConnection;
var
  Procedura: TFDStoredProc;
begin
  Result := TConnectionPool.Instance.Acquire(False);
  try
    ApriTransazione(Result);
    Procedura := CreaStoredProc(Result, 'USR_WEB_SESSIONE_ADOTTA');
    try
      Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione;
      Procedura.ExecProc;
    finally
      FreeAndNil(Procedura);
    end;
  except
    on E: Exception do
    begin
      Annulla(Result);
      TConnectionPool.Instance.Release(Result);
      Result := nil;
      if E.Message.Contains('non in attesa') then
        raise EMVCException.Create(HTTP_STATUS.BadRequest, 'La sessione non e'' in attesa del secondo fattore.');
      raise;
    end;
  end;
end;

// La connessione torna al raggruppamento: l'attesa adottata non deve restarle addosso
procedure TAuthController.RilasciaConnessioneInAttesa(var Connessione: TFDConnection);
var
  Procedura: TFDStoredProc;
begin
  if not Assigned(Connessione) then
    Exit;

  try
    ApriTransazione(Connessione);
    Procedura := CreaStoredProc(Connessione, 'USR_WEB_SESSIONE_ADOTTA');
    try
      Procedura.ParamByName('ID_SESSIONE').Clear;
      Procedura.ExecProc;
    finally
      FreeAndNil(Procedura);
    end;
    Conferma(Connessione);
  except
    on E: Exception do
    begin
      Annulla(Connessione);
      Registro.Warn('Attesa del secondo fattore non tolta dalla connessione: ' + E.Message, 'AuthController');
    end;
  end;

  TConnectionPool.Instance.Release(Connessione);
  Connessione := nil;
end;

function TAuthController.CodiceDelCorpo: string;
var
  Corpo: TJSONObject;
begin
  Corpo := CorpoJson;
  try
    Result := JsonStr(Corpo, 'codice').Trim;
  finally
    FreeAndNil(Corpo);
  end;

  if Result.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Digitare il codice.');
end;

// Vero se il database ha le regole del secondo fattore (USR_TOTP_REGOLE, script WT-AUTH-03 e
// GESTY-AUTH-01): un server aggiornato prima dello script continua a rispondere come prima
function TAuthController.LeggiRegole(Connessione: TFDConnection): Boolean;
var
  Lettura: TFDQuery;
begin
  Lettura := CreaQuery(Connessione, 'SELECT COUNT(*) FROM RDB$PROCEDURES WHERE RDB$PROCEDURES.RDB$PROCEDURE_NAME = ''USR_TOTP_REGOLE''');
  try
    Lettura.Open;
    Result := Lettura.Fields[0].AsInteger > 0;
    Lettura.Close;
  finally
    FreeAndNil(Lettura);
  end;
end;

// Salva i codici di recupero (la procedura conserva solo l'impronta) nella transazione in corso
procedure TAuthController.ImpostaCodiciRecupero(Connessione: TFDConnection; const Codici: TArray<string>);
var
  Procedura: TFDStoredProc;
  Elenco: string;
begin
  Elenco := string.Join(sLineBreak, Codici);
  Procedura := CreaStoredProc(Connessione, 'USR_TOTP_CODICI_RECUPERO_IMPOSTA');
  try
    Procedura.ParamByName('CODICI').AsString := Elenco;
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TAuthController.OtpStato;
var
  Connessione: TFDConnection;
  Lettura: TFDQuery;
  TotpAttivo: Boolean;
  MailUtente: Boolean;
begin
  // Qui basta l'utente del token: nessuna procedura che guardi la connessione
  Connessione := TConnectionPool.Instance.Acquire(False);
  try
    ApriTransazione(Connessione);
    try
      Lettura := CreaQuery(Connessione, 'SELECT COALESCE(USR_UTENTI_TOTP.ATTIVO, FALSE) AS TOTP_ATTIVO, ' +
        '(USR_UTENTI.OTP_MAIL IS NOT NULL) AS MAIL_UTENTE ' +
        'FROM USR_UTENTI LEFT JOIN USR_UTENTI_TOTP ON USR_UTENTI_TOTP.USER_ID = USR_UTENTI.USER_ID ' +
        'WHERE USR_UTENTI.USER_ID = :USER_ID');
      try
        Lettura.ParamByName('USER_ID').AsLargeInt := UserId;
        Lettura.Open;
        TotpAttivo := (not Lettura.IsEmpty) and Lettura.FieldByName('TOTP_ATTIVO').AsBoolean;
        MailUtente := (not Lettura.IsEmpty) and Lettura.FieldByName('MAIL_UTENTE').AsBoolean;
        Lettura.Close;
      finally
        FreeAndNil(Lettura);
      end;
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        raise;
      end;
    end;
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;

  RenderJson(TJSONObject.Create.AddPair('totpAttivo', TJSONBool.Create(TotpAttivo))
    .AddPair('mailDisponibile', TJSONBool.Create(MailUtente and TMailSenders.Disponibile)));
end;

procedure TAuthController.OtpVerificaTotp;
var
  Codice: string;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Riuscito: Boolean;
  Messaggio: string;
  CodiceRecuperoUsato: Boolean;
  CodiciRestanti: Integer;
begin
  Codice := CodiceDelCorpo;
  Riuscito := False;
  Messaggio := '';
  CodiceRecuperoUsato := False;
  CodiciRestanti := 0;

  Connessione := PrendiConnessioneInAttesa;
  try
    try
      Procedura := CreaStoredProc(Connessione, 'USR_TOTP_VERIFICA');
      try
        Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione;
        Procedura.ParamByName('CODICE').AsString := Codice;
        Procedura.ParamByName('RAISE_ERROR').AsBoolean := False;
        Procedura.ExecProc;
        Riuscito := Procedura.ParamByName('OK').AsBoolean;
        Messaggio := Procedura.ParamByName('ERROR_MESSAGE').AsString;
        CodiceRecuperoUsato := Procedura.ParamByName('CODICE_RECUPERO_USATO').AsBoolean;
        CodiciRestanti := Procedura.ParamByName('CODICI_RECUPERO_RESTANTI').AsInteger;
      finally
        FreeAndNil(Procedura);
      end;
      // Si conferma anche il rifiuto: il blocco dopo troppi errori conta i tentativi scritti
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        raise;
      end;
    end;
  finally
    RilasciaConnessioneInAttesa(Connessione);
  end;

  if not Riuscito then
  begin
    Registro.Warn(Format('Secondo fattore: codice rifiutato per utente %d (%s)', [UserId, Messaggio]), 'AuthController');
    if Messaggio.IsEmpty then
      Messaggio := 'Codice non valido.';
    raise EMVCException.Create(HTTP_STATUS.BadRequest, Messaggio);
  end;

  Registro.Info(Format('Secondo fattore completato con l''app: utente %d, sessione %d', [UserId, IdSessione]), 'AuthController');
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True))
    .AddPair('codiceRecuperoUsato', TJSONBool.Create(CodiceRecuperoUsato))
    .AddPair('codiciRecuperoRestanti', TJSONNumber.Create(CodiciRestanti)));
end;

procedure TAuthController.OtpInviaMail;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Messaggio: TMailMessage;
begin
  if not TMailSenders.Disponibile then
    raise EMVCException.Create(HTTP_STATUS.ServiceUnavailable, 'Invio della posta non configurato su questo server: usa l''app di autenticazione.');

  Connessione := TConnectionPool.Instance.Acquire(False);
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'USR_GENERA_TOKEN_OTP');
      try
        Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione;
        Procedura.ExecProc;
        Messaggio.Destinatario := Procedura.ParamByName('MAIL_UTENTE').AsString;
        Messaggio.Mittente := Procedura.ParamByName('EMAIL_INVIO_OTP').AsString;
        Messaggio.Oggetto := Procedura.ParamByName('MAIL_INVIO_OTP_OGGETTO').AsString;
        Messaggio.CorpoTesto := Procedura.ParamByName('MAIL_INVIO_OTP_CORPO').AsString;
        Messaggio.CorpoHtml := Procedura.ParamByName('MAIL_INVIO_OTP_CORPO_HTML').AsString;
      finally
        FreeAndNil(Procedura);
      end;

      // Il codice nasce nella transazione e si conferma solo se la mail parte (o e' in coda)
      if not TMailSenders.Invia(Messaggio, Connessione) then
      begin
        Annulla(Connessione);
        raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Impossibile inviare il codice: riprova fra poco.');
      end;
      Conferma(Connessione);
    except
      on E: EMVCException do
      begin
        Annulla(Connessione);
        raise;
      end;
      on E: Exception do
      begin
        Annulla(Connessione);
        if E.Message.Contains('Errore configurazione') then
        begin
          Registro.Warn(Format('Codice via mail non inviabile per utente %d: %s', [UserId, E.Message]), 'AuthController');
          raise EMVCException.Create(HTTP_STATUS.BadRequest, 'L''invio del codice via mail non e'' configurato per questo utente: usa l''app di autenticazione o chiedi all''amministratore.');
        end;
        raise;
      end;
    end;
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;

  Registro.Info(Format('Codice via mail inviato: utente %d, sessione %d', [UserId, IdSessione]), 'AuthController');
  RenderEsito(True);
end;

procedure TAuthController.OtpVerificaMail;
var
  Codice: string;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Riuscito: Boolean;
  Messaggio: string;
begin
  Codice := CodiceDelCorpo;
  Riuscito := False;
  Messaggio := '';

  Connessione := TConnectionPool.Instance.Acquire(False);
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'USR_VERIFICA_TOKEN_OTP');
      try
        Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione;
        Procedura.ParamByName('TOKEN_OTP').AsString := Codice;
        Procedura.ParamByName('REMOTE_ADDRESS').AsString := Context.Request.ClientIp;
        Procedura.ParamByName('RAISE_ERROR').AsBoolean := False;
        Procedura.ExecProc;
        Riuscito := Procedura.ParamByName('OK').AsBoolean;
        Messaggio := Procedura.ParamByName('ERROR_MESSAGE').AsString;
      finally
        FreeAndNil(Procedura);
      end;
      // Anche il rifiuto si conferma: il numero di tentativi sta nella riga del codice
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        raise;
      end;
    end;
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;

  if not Riuscito then
  begin
    Registro.Warn(Format('Codice via mail rifiutato per utente %d (%s)', [UserId, Messaggio]), 'AuthController');
    // Il messaggio della procedura porta anche gli identificativi interni: all'utente la sola frase
    if Messaggio.Contains('scaduto') then
      Messaggio := 'Codice scaduto: chiedine uno nuovo.'
    else
      if Messaggio.Contains('Eccessivo') then
        Messaggio := 'Troppi tentativi: chiedi un nuovo codice.'
      else
        Messaggio := 'Codice non valido.';
    raise EMVCException.Create(HTTP_STATUS.BadRequest, Messaggio);
  end;

  Registro.Info(Format('Secondo fattore completato con la mail: utente %d, sessione %d', [UserId, IdSessione]), 'AuthController');
  RenderEsito(True);
end;

procedure TAuthController.TotpStato;
var
  Connessione: TFDConnection;
  Lettura: TFDQuery;
  Disponibile: Boolean;
  Registrato: Boolean;
  Attivo: Boolean;
  CodiciRestanti: Integer;
  SecondiBlocco: Integer;
  Modalita: string;
  AttivazioneConsentita: Boolean;
  DisattivazioneConsentita: Boolean;
  RegistrazioneObbligatoria: Boolean;
  OtpUtente: Boolean;
begin
  // Senza lo script delle regole (WT-AUTH-03, GESTY-AUTH-01) si comporta come prima:
  // modalita' vuota, attivazione consentita, mai disattivazione ne' obbligo
  Modalita := '';
  AttivazioneConsentita := True;
  DisattivazioneConsentita := False;
  RegistrazioneObbligatoria := False;
  OtpUtente := False;

  Connessione := PrendiConnessione;
  try
    try
      Lettura := CreaQuery(Connessione, 'SELECT USR_TOTP_DISPONIBILE() AS DISPONIBILE, USR_TOTP_STATO.REGISTRATO, ' +
        'USR_TOTP_STATO.ATTIVO, USR_TOTP_STATO.CODICI_RECUPERO_RESTANTI, USR_TOTP_STATO.SECONDI_BLOCCO ' +
        'FROM USR_TOTP_STATO');
      try
        Lettura.Open;
        Disponibile := Lettura.FieldByName('DISPONIBILE').AsBoolean;
        Registrato := Lettura.FieldByName('REGISTRATO').AsBoolean;
        Attivo := Lettura.FieldByName('ATTIVO').AsBoolean;
        CodiciRestanti := Lettura.FieldByName('CODICI_RECUPERO_RESTANTI').AsInteger;
        SecondiBlocco := Lettura.FieldByName('SECONDI_BLOCCO').AsInteger;
        Lettura.Close;
      finally
        FreeAndNil(Lettura);
      end;

      if LeggiRegole(Connessione) then
      begin
        Lettura := CreaQuery(Connessione, 'SELECT USR_TOTP_REGOLE.MODALITA, USR_TOTP_REGOLE.OTP_UTENTE, USR_TOTP_REGOLE.ATTIVAZIONE_CONSENTITA, ' +
          'USR_TOTP_REGOLE.DISATTIVAZIONE_CONSENTITA, USR_TOTP_REGOLE.REGISTRAZIONE_OBBLIGATORIA FROM USR_TOTP_REGOLE');
        try
          Lettura.Open;
          Modalita := Lettura.FieldByName('MODALITA').AsString;
          OtpUtente := Lettura.FieldByName('OTP_UTENTE').AsBoolean;
          AttivazioneConsentita := Lettura.FieldByName('ATTIVAZIONE_CONSENTITA').AsBoolean;
          DisattivazioneConsentita := Lettura.FieldByName('DISATTIVAZIONE_CONSENTITA').AsBoolean;
          RegistrazioneObbligatoria := Lettura.FieldByName('REGISTRAZIONE_OBBLIGATORIA').AsBoolean;
          Lettura.Close;
        finally
          FreeAndNil(Lettura);
        end;
      end;
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

  RenderJson(TJSONObject.Create.AddPair('disponibile', TJSONBool.Create(Disponibile))
    .AddPair('registrato', TJSONBool.Create(Registrato))
    .AddPair('attivo', TJSONBool.Create(Attivo))
    .AddPair('codiciRecuperoRestanti', TJSONNumber.Create(CodiciRestanti))
    .AddPair('secondiBlocco', TJSONNumber.Create(SecondiBlocco))
    .AddPair('modalita', Modalita)
    .AddPair('otpUtente', TJSONBool.Create(OtpUtente))
    .AddPair('attivazioneConsentita', TJSONBool.Create(AttivazioneConsentita))
    .AddPair('disattivazioneConsentita', TJSONBool.Create(DisattivazioneConsentita))
    .AddPair('registrazioneObbligatoria', TJSONBool.Create(RegistrazioneObbligatoria)));
end;

procedure TAuthController.TotpDisattiva;
var
  Codice: string;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Motivo: string;
begin
  Codice := CodiceDelCorpo;

  // Utente e sessione arrivano dal token: chi chiama puo' togliere solo la propria app,
  // e solo con un codice valido (la procedura conta i rifiuti per il blocco)
  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'USR_TOTP_DISATTIVA');
      try
        Procedura.ParamByName('CODICE').AsString := Codice;
        Procedura.ExecProc;
      finally
        FreeAndNil(Procedura);
      end;
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        Motivo := RifiutoSecondoFattore(E.Message);
        if Motivo.IsEmpty then
          raise;
        Registro.Warn(Format('Disattivazione dell''app rifiutata per utente %d: %s', [UserId, Motivo]), 'AuthController');
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Motivo);
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('App di autenticazione disattivata: utente %d', [UserId]), 'AuthController');
  RenderEsito(True);
end;

procedure TAuthController.TotpRegistra;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Segreto: string;
  IndirizzoOtpauth: string;
  Motivo: string;
begin
  // Il segreto nasce qui, dal generatore del sistema: la procedura lo cifra e lo conserva
  Segreto := CodificaBase32(ByteCasuali(LUNGHEZZA_SEGRETO_BYTE));

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'USR_TOTP_REGISTRA');
      try
        Procedura.ParamByName('SEGRETO_BASE32').AsString := Segreto;
        Procedura.ExecProc;
        IndirizzoOtpauth := Procedura.ParamByName('INDIRIZZO_OTPAUTH').AsString;
      finally
        FreeAndNil(Procedura);
      end;
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        Motivo := RifiutoSecondoFattore(E.Message);
        if Motivo.IsEmpty then
          raise;
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Motivo);
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('App di autenticazione registrata (in sospeso): utente %d', [UserId]), 'AuthController');
  RenderJson(TJSONObject.Create.AddPair('otpauth', IndirizzoOtpauth).AddPair('segreto', Segreto));
end;

procedure TAuthController.TotpAttiva;
var
  Codice: string;
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Codici: TArray<string>;
  Motivo: string;
  Elenco: TJSONArray;
  Voce: string;
begin
  Codice := CodiceDelCorpo;
  Codici := GeneraCodiciRecupero;

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'USR_TOTP_ATTIVA');
      try
        Procedura.ParamByName('CODICE').AsString := Codice;
        Procedura.ExecProc;
      finally
        FreeAndNil(Procedura);
      end;
      // Attivazione e codici di recupero insieme: senza i secondi l'utente non ha una via d'uscita
      ImpostaCodiciRecupero(Connessione, Codici);
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        Motivo := RifiutoSecondoFattore(E.Message);
        if Motivo.IsEmpty then
          raise;
        Registro.Warn(Format('Attivazione dell''app rifiutata per utente %d: %s', [UserId, Motivo]), 'AuthController');
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Motivo);
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('App di autenticazione attivata: utente %d', [UserId]), 'AuthController');
  Elenco := TJSONArray.Create;
  for Voce in Codici do
    Elenco.Add(Voce);
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('codiciRecupero', Elenco));
end;

procedure TAuthController.TotpCodiciRecupero;
var
  Connessione: TFDConnection;
  Codici: TArray<string>;
  Motivo: string;
  Elenco: TJSONArray;
  Voce: string;
begin
  Codici := GeneraCodiciRecupero;

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      ImpostaCodiciRecupero(Connessione, Codici);
      Conferma(Connessione);
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        Motivo := RifiutoSecondoFattore(E.Message);
        if Motivo.IsEmpty then
          raise;
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Motivo);
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  Registro.Info(Format('Codici di recupero rigenerati: utente %d', [UserId]), 'AuthController');
  Elenco := TJSONArray.Create;
  for Voce in Codici do
    Elenco.Add(Voce);
  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('codiciRecupero', Elenco));
end;

end.
