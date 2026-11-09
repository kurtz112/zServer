// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-02
// ---------------------------------------------------------------------------
unit Token.Service;

// Nomi dei claim e creazione dell'access token, in un posto solo.
//
// Prima il token nasceva in tre punti diversi con claim diversi: il login
// (dal middleware JWT, con i dati messi in ASessionData da
// Authentication.Service) scriveva user_id, id_sessione, nominativo; il
// rinnovo ne scriveva userid, username, displayname, role. Un token
// rinnovato non conteneva quindi user_id, e il logout-all leggeva un claim
// 'userid' che nessuno scriveva.
//
// Dopo il punto Z3 la cosa non e' piu' solo sgradevole: senza user_id nel
// token il raggruppamento non sa a nome di chi dichiarare il contesto, e la
// richiesta va rifiutata. Da qui l'unico punto di verita.
//
// DMVCFramework, quando ricarica un token, si aspetta due claim con nomi
// fissati da lui: 'username' e 'roles' (separati da virgola). Vanno scritti
// entrambi, altrimenti LoggedUser resta senza nome e senza ruoli e
// l'autorizzazione nega tutto.

interface

uses
  System.SysUtils,
  MVCFramework.JWT,
  App.Profile;

const
  // Claim del prodotto
  JWT_CLAIM_USER_ID = 'user_id';
  JWT_CLAIM_ID_SESSIONE = 'id_sessione';
  JWT_CLAIM_NOMINATIVO = 'nominativo';
  JWT_CLAIM_RUOLO = 'ruolo';
  // Sinonimo storico di 'ruolo': il portale di Gesty lo legge con questo
  // nome, quindi resta emesso per non rompere un front end in esercizio.
  JWT_CLAIM_TIPO_USER = 'tipo_user';
  JWT_CLAIM_DATA_SCADENZA_PASSWORD = 'data_scadenza_password';
  JWT_CLAIM_ADMIN_USER = 'admin_user';
  JWT_CLAIM_HOST_LDAP = 'host_ldap';
  JWT_CLAIM_OTP = 'otp';
  // Aree web (fase 0): codici separati da virgola, e area della sessione.
  // Solo informativi per il client: zServer decide sull'area leggendo
  // USR_SESSIONI.APP, cosi' un token emesso prima di un cambio d'area non
  // porta con se' l'area vecchia.
  JWT_CLAIM_AREE = 'aree';
  JWT_CLAIM_AREA = 'area';

  // Claim attesi da DMVCFramework
  JWT_CLAIM_USERNAME = 'username';
  JWT_CLAIM_ROLES = 'roles';

type
  TTokenService = class
  public
    /// <summary>
    /// Ruoli attribuiti a un utente: 'user' sempre, il ruolo del prodotto se
    /// c'e', 'admin' se e' amministratore. Usata sia al login sia al
    /// rinnovo, cosi' i due token non divergono.
    /// </summary>
    class function Ruoli(const Ruolo: string; const AdminUser: Boolean): TArray<string>;

    /// <summary>
    /// Access token con i claim standard di configurazione piu' quelli del
    /// prodotto. Usata dal rinnovo e dagli accessi che non passano dal
    /// middleware (per esempio SPID).
    /// </summary>
    class function CreaAccessToken(const Esito: TAuthResult; const UserName: string; const MinutiDiValidita: Integer = 0): string;
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils,
  MVCFramework.Commons,
  App.Config;

{ TTokenService }

class function TTokenService.Ruoli(const Ruolo: string; const AdminUser: Boolean): TArray<string>;
begin
  Result := ['user'];

  if not Ruolo.Trim.IsEmpty then
    Result := Result + [Ruolo];

  if AdminUser then
    Result := Result + ['admin'];
end;

class function TTokenService.CreaAccessToken(const Esito: TAuthResult; const UserName: string; const MinutiDiValidita: Integer = 0): string;
var
  Configurazione: TAppConfig;
  Token: TJWT;
  Minuti: Integer;
begin
  Configurazione := TAppConfig.Instance;

  // ZC 03.11.2026: validita' diversa da quella di configurazione, per il
  // cittadino (60 minuti, senza rinnovo). 0 = quella di configurazione.
  if MinutiDiValidita > 0 then
    Minuti := MinutiDiValidita
  else
    Minuti := Configurazione.JWT.ExpirationMinutes;

  Token := TJWT.Create(Configurazione.JWT.SecretKey);
  try
    Token.Claims.Issuer := Configurazione.JWT.Issuer;
    Token.Claims.Audience := Configurazione.JWT.Audience;
    Token.Claims.Subject := Esito.UserId.ToString;
    Token.Claims.IssuedAt := Now;
    Token.Claims.NotBefore := Now - (OneMinute * 5);
    Token.Claims.ExpirationTime := Now + (OneMinute * Minuti);

    Token.CustomClaims[JWT_CLAIM_USERNAME] := UserName;
    Token.CustomClaims[JWT_CLAIM_ROLES] := string.Join(',', Ruoli(Esito.Ruolo, Esito.AdminUser));

    Token.CustomClaims[JWT_CLAIM_USER_ID] := Esito.UserId.ToString;
    Token.CustomClaims[JWT_CLAIM_ID_SESSIONE] := Esito.IdSessione.ToString;
    Token.CustomClaims[JWT_CLAIM_NOMINATIVO] := Esito.Nominativo;
    Token.CustomClaims[JWT_CLAIM_RUOLO] := Esito.Ruolo;
    Token.CustomClaims[JWT_CLAIM_TIPO_USER] := Esito.Ruolo;
    Token.CustomClaims[JWT_CLAIM_DATA_SCADENZA_PASSWORD] := DateToISO8601(Esito.DataScadenzaPassword, False);
    Token.CustomClaims[JWT_CLAIM_ADMIN_USER] := BoolToStr(Esito.AdminUser, True);
    Token.CustomClaims[JWT_CLAIM_HOST_LDAP] := Esito.HostLDAP;
    Token.CustomClaims[JWT_CLAIM_OTP] := BoolToStr(Esito.RichiedeOtp, True);

    // Il prodotto senza aree non le scrive: il suo token resta quello di prima
    if not Esito.Area.IsEmpty then
    begin
      Token.CustomClaims[JWT_CLAIM_AREE] := string.Join(',', Esito.Aree);
      Token.CustomClaims[JWT_CLAIM_AREA] := Esito.Area;
    end;

    Result := Token.GetToken;
  finally
    FreeAndNil(Token);
  end;
end;

end.
