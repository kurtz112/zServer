// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-05
// ---------------------------------------------------------------------------
unit JWTRefresh.Middleware;

{
  Middleware JWT con Refresh Token per zServer.
  Deriva da TMVCJWTAuthenticationMiddleware e aggiunge:
  - Refresh token nella risposta del login (override di InternalRender)
  - Endpoint /auth/refresh per il rinnovo dei token
  - Endpoint /auth/logout per la revoca del refresh token e la chiusura
  della sessione sul database
  - Endpoint /auth/logout-all per la revoca di tutti i token utente

  Utilizza TRefreshTokenService per le operazioni sui token e Token.Service
  per creare l'access token.

  Due correzioni rispetto alla versione precedente, entrambe conseguenze del
  punto Z3:

  1. L'access token del rinnovo nasceva con claim diversi da quelli del
  login (userid, displayname, role) e senza i ruoli. Un token rinnovato
  non conteneva quindi user_id — che dopo Z3 serve a dichiarare il
  contesto al database — e non portava ruoli, quindi l'autorizzazione lo
  rifiutava. Ora il token lo crea Token.Service, lo stesso per tutti.

  2. Il logout revocava il refresh token ma non chiamava USR_LOGOUT: la
  sessione creata al login restava aperta in USR_SESSIONI.
}

interface

uses
  System.SysUtils,
  System.DateUtils,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.JWT,
  MVCFramework.Middleware.JWT,
  JsonDataObjects;

type
  TMVCJWTRefreshMiddleware = class(TMVCJWTAuthenticationMiddleware)
  private
    FRefreshURLSegment: string;
    FLogoutURLSegment: string;
    FLogoutAllURLSegment: string;
    FSecret: string;
    FSetupJWTClaims: TJWTClaimsSetup;
    FLoginURLSegment: string;

    procedure HandleRefreshRequest(context: TWebContext; var handled: Boolean);
    procedure HandleLogoutRequest(context: TWebContext; var handled: Boolean);
    procedure HandleLogoutAllRequest(context: TWebContext; var handled: Boolean);

    /// <summary>
    /// Legge un claim dall'access token presente nell'intestazione
    /// Authorization, senza pretendere che ci sia: al rinnovo e al logout il
    /// front end lo manda quasi sempre, ma non e' obbligato.
    /// </summary>
    function ClaimDellAccessToken(context: TWebContext; const NomeClaim: string): string;
  protected
    procedure InternalRender(AJSONObj: TJDOJsonObject; AContentType: string; AContentEncoding: string; AContext: TWebContext; AInstanceOwner: Boolean = True); override;

    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean); override;
  public
    constructor Create(authHandler: IMVCAuthenticationHandler; configClaims: TJWTClaimsSetup; const secret: string; const loginURLSegment: string; claimsToCheck: TJWTCheckableClaims; leewaySeconds: Cardinal; const hmacAlgorithm: string = 'HS256';
      const refreshURLSegment: string = '/api/auth/refresh'; const logoutURLSegment: string = '/api/auth/logout'; const logoutAllURLSegment: string = '/api/auth/logout-all');
  end;

implementation

uses
  System.JSON,
  System.NetEncoding,
  MVCFramework.Logger,
  App.Profile,
  Data.Service,
  Token.Service,
  RefreshToken.Service,
  Session.Context;

{ TMVCJWTRefreshMiddleware }

constructor TMVCJWTRefreshMiddleware.Create(authHandler: IMVCAuthenticationHandler; configClaims: TJWTClaimsSetup; const secret: string; const loginURLSegment: string; claimsToCheck: TJWTCheckableClaims; leewaySeconds: Cardinal;
  const hmacAlgorithm: string; const refreshURLSegment: string; const logoutURLSegment: string; const logoutAllURLSegment: string);
begin
  inherited Create(authHandler, configClaims, secret, loginURLSegment, claimsToCheck, leewaySeconds, hmacAlgorithm);
  FSecret := secret;
  FSetupJWTClaims := configClaims;
  FLoginURLSegment := loginURLSegment;
  FRefreshURLSegment := refreshURLSegment;
  FLogoutURLSegment := logoutURLSegment;
  FLogoutAllURLSegment := logoutAllURLSegment;
end;

// ═══════════════════════════════════════════════════════════════
// OnBeforeRouting
// Intercetta /auth/refresh, /auth/logout e /auth/logout-all
// PRIMA che il middleware base li tratti come richieste normali
// ═══════════════════════════════════════════════════════════════

procedure TMVCJWTRefreshMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  // Il contesto del thread appartiene alla richiesta precedente. Per le
  // azioni di controller lo azzera OnRequest, ma le tre rotte intercettate
  // qui sotto non ci arrivano: senza questa riga USR_LOGOUT verrebbe
  // eseguito dichiarando al database l'utente dell'ultima richiesta
  // servita da questo thread.
  TSessionContextManager.Azzera;

  // POST /auth/refresh — non richiede access token valido
  if SameText(AContext.Request.PathInfo, FRefreshURLSegment) and (AContext.Request.HTTPMethod = httpPOST) then
  begin
    HandleRefreshRequest(AContext, AHandled);
    Exit;
  end;

  // POST /auth/logout — non richiede access token valido
  if SameText(AContext.Request.PathInfo, FLogoutURLSegment) and (AContext.Request.HTTPMethod = httpPOST) then
  begin
    HandleLogoutRequest(AContext, AHandled);
    Exit;
  end;

  // POST /auth/logout-all — l'utente viene identificato dall'access token,
  // che qui viene letto e verificato a mano.
  if SameText(AContext.Request.PathInfo, FLogoutAllURLSegment) and (AContext.Request.HTTPMethod = httpPOST) then
  begin
    HandleLogoutAllRequest(AContext, AHandled);
    Exit;
  end;

  // Tutto il resto (login, richieste protette, ecc.) → middleware base
  inherited OnBeforeRouting(AContext, AHandled);
end;

function TMVCJWTRefreshMiddleware.ClaimDellAccessToken(context: TWebContext; const NomeClaim: string): string;
var
  Intestazione: string;
  Testo: string;
  Errore: string;
  Token: TJWT;
begin
  Result := '';

  Intestazione := context.Request.Headers['Authorization'];

  if not Intestazione.StartsWith('Bearer ', True) then
    Exit;

  Testo := Trim(TNetEncoding.URL.Decode(Intestazione.Substring(7).Trim));

  Token := TJWT.Create(FSecret);
  try
    // Il token puo' essere scaduto: e' proprio il caso del rinnovo. Qui
    // interessa solo cosa dichiara, e la firma resta comunque verificata.
    Token.RegClaimsToChecks := [];

    if Token.LoadToken(Testo, Errore) then
      Result := Token.CustomClaims[NomeClaim];
  finally
    Token.Free;
  end;
end;

// ═══════════════════════════════════════════════════════════════
// InternalRender (override)
// Chiamato dal middleware base per scrivere la risposta JSON del login.
// Iniettiamo il refresh_token nel JSON PRIMA di scrivere la response.
// ═══════════════════════════════════════════════════════════════

procedure TMVCJWTRefreshMiddleware.InternalRender(AJSONObj: TJDOJsonObject; AContentType: string; AContentEncoding: string; AContext: TWebContext; AInstanceOwner: Boolean);
var
  refreshService: TRefreshTokenService;
  rawRefreshToken: string;
  userId: Integer;
  idSessione: Int64;
  deviceInfo, ipAddress: string;
begin
  // Inietta il refresh token SOLO se:
  // 1. Siamo nell'URL di login
  // 2. Il JSON contiene "token" (login riuscito)
  if SameText(AContext.Request.PathInfo, FLoginURLSegment) and AJSONObj.Contains('token') then
  begin
    userId := StrToIntDef(AContext.LoggedUser.CustomData[JWT_CLAIM_USER_ID], 0);
    // La sessione creata dal login viaggia anche nel refresh token (colonna
    // ID_SESSIONE di USR_REFRESH_TOKENS): cosi' il rinnovo la restituisce
    // senza dipendere dall'access token scaduto.
    idSessione := StrToInt64Def(AContext.LoggedUser.CustomData[JWT_CLAIM_ID_SESSIONE], 0);
    deviceInfo := AContext.Request.Headers['User-Agent'];
    ipAddress := AContext.Request.ClientIp;

    if userId > 0 then
    begin
      refreshService := TRefreshTokenService.Create;
      try
        rawRefreshToken := refreshService.GenerateToken;
        try
          // ZC 05.11.2026: il login con secondo fattore lascia nel thread il contesto
          // dell'utente, con la sessione ancora in attesa del codice. Il pool di
          // connessioni lo dichiara al database con USR_CONTEXT_SET, che per una
          // sessione in attesa solleva un errore: CreateToken falliva, l'errore veniva
          // solo scritto nel log e il login rispondeva senza refresh_token. Dopo il
          // codice, la scelta dell'area chiede un rinnovo, non trova il token e riporta
          // al login. Il contesto si azzera: USR_REFRESH_TOKENS_CREA riceve utente e
          // sessione come parametri e non lo usa.
          TSessionContextManager.Azzera;
          refreshService.CreateToken(userId, idSessione, rawRefreshToken, deviceInfo, ipAddress);

          // Inietta nel JSON di risposta del middleware base
          AJSONObj.S['refresh_token'] := rawRefreshToken;

          LogI(Format('Login + refresh token generato per UserID:%d da IP:%s', [userId, ipAddress]));
        except
          on E: Exception do
            LogE('Errore creazione refresh token durante login: ' + E.Message);
          // Non blocchiamo il login: l'access token JWT è comunque valido
        end;
      finally
        refreshService.Free;
      end;
    end;
  end;

  // Scrive il JSON (con o senza refresh_token) nella response
  inherited InternalRender(AJSONObj, AContentType, AContentEncoding, AContext, AInstanceOwner);
end;

// ═══════════════════════════════════════════════════════════════
// POST /auth/refresh
// ═══════════════════════════════════════════════════════════════

procedure TMVCJWTRefreshMiddleware.HandleRefreshRequest(context: TWebContext; var handled: Boolean);
var
  body: TJDOJsonObject;
  oldRefreshToken, newRefreshToken: string;
  deviceInfo, ipAddress: string;
  refreshService: TRefreshTokenService;
  validateResult: TRefreshTokenResult;
  Esito: TAuthResult;
  accessToken: string;
  responseJson: TJDOJsonObject;
begin
  handled := True;

  // Parse body
  try
    body := TJDOJsonObject.Parse(context.Request.body) as TJDOJsonObject;
  except
    context.Response.StatusCode := HTTP_STATUS.BadRequest;
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
    context.Response.Content := '{"error":"Body JSON non valido"}';
    Exit;
  end;

  try
    oldRefreshToken := body.S['refresh_token'];
  finally
    body.Free;
  end;

  if oldRefreshToken.IsEmpty then
  begin
    context.Response.StatusCode := HTTP_STATUS.BadRequest;
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
    context.Response.Content := '{"error":"refresh_token obbligatorio"}';
    Exit;
  end;

  deviceInfo := context.Request.Headers['User-Agent'];
  ipAddress := context.Request.ClientIp;

  refreshService := TRefreshTokenService.Create;
  try
    // Genera il nuovo refresh token PRIMA della validazione
    newRefreshToken := refreshService.GenerateToken;

    // Validazione e rotazione atomica (via stored procedure)
    validateResult := refreshService.ValidateAndRotate(oldRefreshToken, newRefreshToken, deviceInfo, ipAddress);
  finally
    refreshService.Free;
  end;

  if not validateResult.Success then
  begin
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;

    case validateResult.ValidazioneResult of
      vrNonTrovato:
        begin
          LogW(Format('Refresh token non trovato da IP %s', [ipAddress]));
          context.Response.StatusCode := HTTP_STATUS.Unauthorized;
          context.Response.Content := '{"error":"Refresh token non valido"}';
        end;

      vrUtenteNonAttivo:
        begin
          LogW(Format('Refresh tentato da utente non attivo, IP %s', [ipAddress]));
          context.Response.StatusCode := HTTP_STATUS.Forbidden;
          context.Response.Content := '{"error":"Utente non attivo"}';
        end;

      vrScaduto:
        begin
          LogW(Format('Refresh token scaduto da IP %s', [ipAddress]));
          context.Response.StatusCode := HTTP_STATUS.Unauthorized;
          context.Response.Content := '{"error":"Sessione scaduta, effettua nuovamente il login"}';
        end;

      vrGiaRevocato:
        begin
          // ALERT: possibile furto token! La SP ha già revocato tutti i token dell'utente
          LogE(Format('!!! TOKEN REUSE DETECTED da IP %s — tutti i token revocati', [ipAddress]));
          context.Response.StatusCode := HTTP_STATUS.Unauthorized;
          context.Response.Content := '{"error":"Sessione invalidata per motivi di sicurezza, effettua nuovamente il login"}';
        end;
    else
      context.Response.StatusCode := HTTP_STATUS.InternalServerError;
      context.Response.Content := '{"error":"Errore interno di autenticazione"}';
    end;
    Exit;
  end;

  // Il nuovo access token porta gli stessi claim del login.
  Esito.Clear;
  Esito.Success := True;
  Esito.UserId := validateResult.UserId;
  // La sessione la restituisce USR_REFRESH_TOKENS_VALIDAZIONE (colonna
  // ID_SESSIONE su USR_REFRESH_TOKENS, script db\03 per Gesty e db\05 per
  // WT). L'access token scaduto, che il front end manda ancora
  // nell'intestazione, resta come ripiego per un'installazione non ancora
  // aggiornata: se manca anche quello, il token rinnovato resta senza
  // sessione e le procedure che vogliono ID_SESSIONE_WEB non funzionano.
  Esito.IdSessione := validateResult.IdSessione;
  if Esito.IdSessione <= 0 then
    Esito.IdSessione := StrToInt64Def(ClaimDellAccessToken(context, JWT_CLAIM_ID_SESSIONE), 0);
  Esito.Nominativo := validateResult.DisplayName;
  Esito.Ruolo := validateResult.Role;
  // ADMIN_USER arriva dalla procedura. Prima si confrontava il ruolo con
  // 'admin': il confronto era sempre falso e dopo il primo rinnovo
  // l'amministratore perdeva il ruolo.
  Esito.AdminUser := validateResult.AdminUser;

  // Aree (fase 0): l'area si rilegge dalla sessione, cosi' il rinnovo dopo un
  // cambio d'area (POST /api/auth/area) porta l'area nuova. Un errore qui non
  // ferma il rinnovo: il token esce senza aree, come prima della fase 0.
  try
    TAppProfiles.Corrente.LeggiAree(validateResult.Username, Esito.IdSessione, Esito.Aree, Esito.Area);
  except
    on E: Exception do
      LogW(Format('Aree non lette al rinnovo per UserID:%d: %s', [validateResult.UserId, E.Message]));
  end;

  if Esito.IdSessione <= 0 then
    LogW(Format('Rinnovo senza sessione per UserID:%d: le chiamate che richiedono ID_SESSIONE_WEB non funzioneranno', [validateResult.UserId]));

  accessToken := TTokenService.CreaAccessToken(Esito, validateResult.Username);

  LogI(Format('Token refreshed per %s (ID:%d) da IP %s', [validateResult.Username, validateResult.UserId, ipAddress]));

  // Risposta
  responseJson := TJDOJsonObject.Create;
  try
    responseJson.S['token'] := accessToken;
    responseJson.S['refresh_token'] := newRefreshToken;

    context.Response.StatusCode := HTTP_STATUS.OK;
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
    context.Response.Content := responseJson.ToJSON;
  finally
    responseJson.Free;
  end;
end;

// ═══════════════════════════════════════════════════════════════
// POST /auth/logout
// ═══════════════════════════════════════════════════════════════

procedure TMVCJWTRefreshMiddleware.HandleLogoutRequest(context: TWebContext; var handled: Boolean);
var
  body: TJDOJsonObject;
  RefreshToken: string;
  refreshService: TRefreshTokenService;
  IdSessione: Int64;
  Parametri: TParamValues;
  EsitoLogout: TJSONObject;
begin
  handled := True;
  body := nil;

  try
    body := TJDOJsonObject.Parse(context.Request.body) as TJDOJsonObject;
  except
    // Body vuoto o non JSON — logout locale comunque
  end;

  if Assigned(body) then
    try
      RefreshToken := body.S['refresh_token'];
      if not RefreshToken.IsEmpty then
      begin
        refreshService := TRefreshTokenService.Create;
        try
          refreshService.RevokeToken(RefreshToken);
          LogI(Format('Logout: refresh token revocato, IP %s', [context.Request.ClientIp]));
        finally
          refreshService.Free;
        end;
      end;
    finally
      body.Free;
    end;

  // Chiusura della sessione sul database: la creava il login, e senza questa
  // chiamata restava aperta in USR_SESSIONI per sempre. USR_LOGOUT ha la
  // stessa firma nei due prodotti, quindi non serve passare dal profilo.
  IdSessione := StrToInt64Def(ClaimDellAccessToken(context, JWT_CLAIM_ID_SESSIONE), 0);

  if IdSessione > 0 then
  begin
    Parametri := TParamValues.Create;
    try
      Parametri.Add('ID_SESSIONE', IdSessione);
      try
        EsitoLogout := TDataService.ExecuteStoredProc('USR_LOGOUT', Parametri);
        FreeAndNil(EsitoLogout);
      except
        on E: Exception do
          // Un logout non deve fallire per questo: il token e' comunque revocato.
          LogE(Format('Logout: USR_LOGOUT per sessione %d non riuscito: %s', [IdSessione, E.Message]));
      end;
    finally
      Parametri.Free;
    end;
  end;

  context.Response.StatusCode := HTTP_STATUS.OK;
  context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
  context.Response.Content := '{"message":"Logout effettuato"}';
end;

// ═══════════════════════════════════════════════════════════════
// POST /auth/logout-all
// Nota: questo endpoint richiede l'access token valido per
// identificare l'utente. Lo gestiamo qui estraendo il JWT
// manualmente dall'header Authorization.
// ═══════════════════════════════════════════════════════════════

procedure TMVCJWTRefreshMiddleware.HandleLogoutAllRequest(context: TWebContext; var handled: Boolean);
var
  authHeader, tokenStr: string;
  err: string;
  JWT: TJWT;
  userId: Integer;
  refreshService: TRefreshTokenService;
begin
  handled := True;

  // Estrai e valida il JWT dall'header
  authHeader := context.Request.Headers['Authorization'];
  if not authHeader.StartsWith('Bearer ', True) then
  begin
    context.Response.StatusCode := HTTP_STATUS.Unauthorized;
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
    context.Response.Content := '{"error":"Token di accesso richiesto"}';
    Exit;
  end;

  tokenStr := authHeader.Substring(7).Trim;

  JWT := TJWT.Create(FSecret);
  try
    if not JWT.LoadToken(tokenStr, err) then
    begin
      LogE(err);
      context.Response.StatusCode := HTTP_STATUS.Unauthorized;
      context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
      context.Response.Content := '{"error":"Token di accesso non valido"}';
      Exit;
    end;

    // Il claim si chiama user_id, non userid: con il nome sbagliato questo
    // punto di ingresso rispondeva sempre 401.
    userId := StrToIntDef(JWT.CustomClaims[JWT_CLAIM_USER_ID], 0);
  finally
    JWT.Free;
  end;

  if userId <= 0 then
  begin
    context.Response.StatusCode := HTTP_STATUS.Unauthorized;
    context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
    context.Response.Content := '{"error":"Utente non identificabile dal token"}';
    Exit;
  end;

  refreshService := TRefreshTokenService.Create;
  try
    refreshService.RevokeAllUserTokens(userId);
    LogI(Format('Logout-all per UserID:%d da IP %s', [userId, context.Request.ClientIp]));
  finally
    refreshService.Free;
  end;

  context.Response.StatusCode := HTTP_STATUS.OK;
  context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
  context.Response.Content := '{"message":"Logout da tutti i dispositivi effettuato"}';
end;

end.
