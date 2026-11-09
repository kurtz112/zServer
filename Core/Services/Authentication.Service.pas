// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-02
// ---------------------------------------------------------------------------
unit Authentication.Service;

// Gestore di autenticazione di DMVCFramework.
//
// Non sa piu' che cosa sia 'Gesty': l'accesso al database lo fa il profilo
// applicativo corrente (IAppProfile.Autentica), che incapsula la firma di
// USR_LOGIN del prodotto. Qui restano le sole cose comuni ai due prodotti:
// quali azioni non richiedono il token, come i dati dell'utente diventano
// claim del JWT, e la dichiarazione del contesto di sessione per la
// richiesta in corso.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  MVCFramework,
  MVCFramework.JWT,
  MVCFramework.Commons,
  App.Profile,
  Data.Service;

type
  TAuthenticationService = class(TInterfacedObject, IMVCAuthenticationHandler)
  private
    function AzionePubblica(const AControllerQualifiedClassName, AActionName: string): Boolean;
    function AreaRichiesta(const AContext: TWebContext): string;
  public
    function DoAuthenticate(const UserName, Password, Area: string): TAuthResult;
    // IMVCAuthenticationHandler
    procedure OnRequest(const AContext: TWebContext; const AControllerQualifiedClassName: string; const AActionName: string; var AAuthenticationRequired: Boolean);
    procedure OnAuthentication(const AContext: TWebContext; const AUserName: string; const APassword: string; AUserRoles: TList<string>; var IsValid: Boolean; const ASessionData: TDictionary<string, string>);
    procedure OnAuthorization(const AContext: TWebContext; AUserRoles: TList<string>; const AControllerQualifiedClassName: string; const AActionName: string; var IsAuthorized: Boolean);
  end;

// I nomi dei claim stanno in Token.Service: e' lo stesso elenco usato dal
// rinnovo del token, e tenerne due copie li ha gia' fatti divergere una volta.

implementation

uses
  System.JSON,
  System.StrUtils,
  System.DateUtils,
  MVCFramework.Logger,
  Token.Service,
  Session.Context;

function TAuthenticationService.DoAuthenticate(const UserName, Password, Area: string): TAuthResult;
begin
  Result := TAppProfiles.Corrente.AutenticaInArea(UserName, Password, Area);
end;

// Area chiesta dal client al login: voce facoltativa "area" nello stesso corpo
// JSON di jwtusername e jwtpassword. Il middleware JWT legge solo le
// credenziali, quindi la si prende qui; un corpo illeggibile vale come
// nessuna area, e a rifiutare le credenziali ci pensa il middleware.
function TAuthenticationService.AreaRichiesta(const AContext: TWebContext): string;
var
  Corpo: TJSONValue;
begin
  Result := '';

  try
    Corpo := TJSONObject.ParseJSONValue(AContext.Request.Body);
  except
    Exit;
  end;

  try
    if Corpo is TJSONObject then
      Result := TJSONObject(Corpo).GetValue<string>('area', '');
  finally
    FreeAndNil(Corpo);
  end;
end;

// Le azioni raggiungibili senza token sono elencate in un posto solo: qui per
// il nucleo, e in IAppProfile.AzioniPubbliche per i controller di dominio.
// Sostituisce l'attributo [SkipJWT] del vecchio server, che DMVCFramework
// non ha.
function TAuthenticationService.AzionePubblica(const AControllerQualifiedClassName, AActionName: string): Boolean;
var
  Azione: string;
  Pubblica: string;
begin
  // 'Unita.TNomeController' -> 'TNomeController.NomeAzione'
  Azione := AControllerQualifiedClassName;
  if Azione.Contains('.') then
    Azione := Azione.Substring(Azione.LastIndexOf('.') + 1);
  Azione := Azione + '.' + AActionName;

  for Pubblica in TAppProfiles.Corrente.AzioniPubbliche do
    if SameText(Pubblica, Azione) then
      Exit(True);

  Result := False;
end;

procedure TAuthenticationService.OnRequest(const AContext: TWebContext; const AControllerQualifiedClassName, AActionName: string; var AAuthenticationRequired: Boolean);
begin
  // Il contesto del thread appartiene alla richiesta precedente: va azzerato
  // prima di ogni richiesta, altrimenti una chiamata senza token
  // continuerebbe a lavorare con l'utente di quella prima.
  TSessionContextManager.Azzera;

  // Di default tutto richiede autenticazione
  AAuthenticationRequired := True;

  // Il login lo tratta il middleware in OnBeforeRouting e non arriva mai a
  // un controller: qui non serve nessuna deroga su un nome di azione, e una
  // deroga su 'Login' renderebbe pubblica senza volerlo la prima azione di
  // dominio che venisse chiamata cosi'.

  // Controller pubblici (stato, versione, ora del server)
  if AControllerQualifiedClassName.Contains('TPublicController') then
    AAuthenticationRequired := False;

  // Azioni pubbliche dei controller di dominio: registrazione, recupero
  // password, notifiche di ritorno dei servizi esterni.
  if AzionePubblica(AControllerQualifiedClassName, AActionName) then
    AAuthenticationRequired := False;

  // Z1 - Qui viveva una deroga che disattivava l'autenticazione per l'intero
  // TDynamicDatasetController: chiunque conoscesse l'indirizzo leggeva e
  // scriveva qualunque dataset registrato, senza token. Rimossa.
  // Se serve un punto d'ingresso in chiaro per il collaudo, va aggiunto a
  // AzioniPubbliche un singolo dataset dedicato, non il controller intero.
end;

procedure TAuthenticationService.OnAuthentication(const AContext: TWebContext; const AUserName, APassword: string; AUserRoles: TList<string>; var IsValid: Boolean; const ASessionData: TDictionary<string, string>);
var
  AuthResult: TAuthResult;
begin
  AuthResult := DoAuthenticate(AUserName, APassword, AreaRichiesta(AContext));

  IsValid := AuthResult.Success;

  if not IsValid then
  begin
    // Z13 - Le credenziali sbagliate diventano un 401 pulito: il middleware
    // JWT rende 401 quando IsValid e' False, mentre l'eccezione Firebird
    // lasciata risalire diventava un 500 con il messaggio grezzo del
    // database. Il messaggio d'origine resta nel registro, non nella risposta.
    if AuthResult.CredenzialiNonValide then
      LogW(Format('Accesso negato a %s: %s', [AUserName, AuthResult.ErrorMessage]))
    else
      LogE(Format('Autenticazione non riuscita per %s: %s', [AUserName, AuthResult.ErrorMessage]));
    Exit;
  end;

  // --- Ruoli ---
  // Stessa attribuzione usata dal rinnovo del token: se divergono, dopo un
  // rinnovo l'utente si ritrova con permessi diversi da quelli del login.
  AUserRoles.AddRange(TTokenService.Ruoli(AuthResult.Ruolo, AuthResult.AdminUser));

  // --- Custom Claims JWT ---
  // Tutto cio' che viene inserito in ASessionData diventa automaticamente
  // un custom claim nel token JWT generato dal middleware.
  // Nei controller si accede via: Context.LoggedUser.CustomData['chiave']
  ASessionData.AddOrSetValue(JWT_CLAIM_USER_ID, AuthResult.UserId.ToString);
  ASessionData.AddOrSetValue(JWT_CLAIM_ID_SESSIONE, AuthResult.IdSessione.ToString);
  ASessionData.AddOrSetValue(JWT_CLAIM_NOMINATIVO, AuthResult.Nominativo);
  ASessionData.AddOrSetValue(JWT_CLAIM_RUOLO, AuthResult.Ruolo);
  ASessionData.AddOrSetValue(JWT_CLAIM_TIPO_USER, AuthResult.Ruolo);
  ASessionData.AddOrSetValue(JWT_CLAIM_DATA_SCADENZA_PASSWORD, DateToISO8601(AuthResult.DataScadenzaPassword, False));
  ASessionData.AddOrSetValue(JWT_CLAIM_ADMIN_USER, BoolToStr(AuthResult.AdminUser, True));
  ASessionData.AddOrSetValue(JWT_CLAIM_HOST_LDAP, AuthResult.HostLDAP);
  ASessionData.AddOrSetValue(JWT_CLAIM_OTP, BoolToStr(AuthResult.RichiedeOtp, True));
  // Stessa regola di TTokenService.CreaAccessToken: senza area (prodotto
  // senza aree) i due claim non si scrivono
  if not AuthResult.Area.IsEmpty then
  begin
    ASessionData.AddOrSetValue(JWT_CLAIM_AREE, string.Join(',', AuthResult.Aree));
    ASessionData.AddOrSetValue(JWT_CLAIM_AREA, AuthResult.Area);
  end;

  // Il login ha creato la sessione su una connessione del raggruppamento:
  // dichiararla anche nel contesto del thread rende coerente l'eventuale
  // lavoro svolto nella stessa richiesta.
  TSessionContextManager.Imposta(AuthResult.UserId, AuthResult.IdSessione, AUserName);
end;

// Chiamata dal middleware JWT a ogni richiesta autenticata, dopo aver
// caricato i claim del token in LoggedUser. E' il punto in cui il livello
// web deposita l'identita per il livello dati (Z3): il raggruppamento di
// connessioni la legge in Connection.Pool e la dichiara al database.
procedure TAuthenticationService.OnAuthorization(const AContext: TWebContext; AUserRoles: TList<string>; const AControllerQualifiedClassName, AActionName: string; var IsAuthorized: Boolean);
var
  UserId: Int64;
  IdSessione: Int64;
begin
  IsAuthorized := AUserRoles.Count > 0;

  if not IsAuthorized then
    Exit;

  UserId := StrToInt64Def(AContext.LoggedUser.CustomData[JWT_CLAIM_USER_ID], 0);
  IdSessione := StrToInt64Def(AContext.LoggedUser.CustomData[JWT_CLAIM_ID_SESSIONE], 0);

  if UserId <= 0 then
  begin
    // Token valido ma senza identita utilizzabile: senza contesto la
    // tracciatura registrerebbe una scrittura senza autore.
    LogE('Token privo del claim user_id: richiesta rifiutata');
    IsAuthorized := False;
    Exit;
  end;

  TSessionContextManager.Imposta(UserId, IdSessione, AContext.LoggedUser.UserName);
end;

end.
