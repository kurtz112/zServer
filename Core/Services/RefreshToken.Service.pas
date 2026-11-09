unit RefreshToken.Service;

// Refresh token: creazione, rotazione, revoca.
//
// Quattro correzioni rispetto alla versione precedente (revisione del
// 2026-09-21):
//
// 1. RevokeToken passava il gettone in chiaro a USR_REFRESH_TOKENS_REVOCA_PER_HASH,
// che confronta l'impronta: la revoca al logout non trovava mai la riga.
//
// 2. Il gettone nasceva da Random(256), un generatore prevedibile: ora viene
// dal generatore casuale del sistema operativo.
//
// 3. Il risultato di ExecuteStoredProc nelle due revoche non veniva liberato.
//
// 4. La validazione restituisce anche ID_SESSIONE e ADMIN_USER (colonna e
// parametri aggiunti dagli script db\03 per Gesty e db\05 per WT): il token
// rinnovato porta cosi' la stessa sessione e lo stesso ruolo del login.

interface

uses
  System.SysUtils,
  System.Hash;

type
  // OK                = K
  // Non trovato       = N
  // Utente non attivo = U
  // Scaduto           = S
  // Gia' revocato     = G
  TValidazioneResult = (vrOk, vrNonTrovato, vrUtenteNonAttivo, vrScaduto, vrGiaRevocato);

  TValidazioneResultHelper = record helper for TValidazioneResult
  public
    class function FromString(const Value: string): TValidazioneResult; static;
    function Description: string;
  end;

  TRefreshTokenResult = record
    Success: Boolean;
    ValidazioneResult: TValidazioneResult;
    NewExpiresAt: TDateTime;
    UserId: Integer;
    IdSessione: Int64;
    Username: string;
    DisplayName: string;
    Role: string;
    AdminUser: Boolean;
  end;

  TRefreshTokenService = class
  private
    function GenerateRandomToken: string;
    function HashToken(const token: string): string;
  public
    /// <summary>
    /// Genera un nuovo refresh token casuale (Base64URL, 32 byte dal
    /// generatore del sistema operativo)
    /// </summary>
    function GenerateToken: string;
    /// <summary>
    /// Salva il refresh token sul database dopo il login, insieme alla
    /// sessione creata da USR_LOGIN
    /// </summary>
    function CreateToken(UserId: Integer; const IdSessione: Int64; const rawToken, deviceInfo, ipAddress: string): TDateTime;
    /// <summary>
    /// Valida il refresh token e ne crea uno nuovo (rotazione).
    /// Restituisce i dati utente per generare un nuovo access token
    /// </summary>
    function ValidateAndRotate(const rawToken, newRawToken, deviceInfo, ipAddress: string): TRefreshTokenResult;
    /// <summary>
    /// Revoca un singolo refresh token (logout)
    /// </summary>
    procedure RevokeToken(const rawToken: string);
    /// <summary>
    /// Revoca tutti i refresh token di un utente (logout da tutti i dispositivi)
    /// </summary>
    procedure RevokeAllUserTokens(UserId: Integer);
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.NetEncoding,
  System.Classes,
  System.JSON,
  App.Config,
  Data.Service,
  Json.Values;

{$IFDEF MSWINDOWS}
// RtlGenRandom: il generatore casuale del sistema, esportato da advapi32
// con questo nome storico. E' lo stesso che usa CryptGenRandom.
function SystemFunction036(Buffer: Pointer; Length: ULONG): BOOL; stdcall; external 'advapi32.dll';
{$ENDIF}

// Riempie il vettore con byte del generatore casuale del sistema operativo:
// RtlGenRandom su Windows, /dev/urandom altrove. Random() della RTL e'
// prevedibile e un refresh token indovinabile vale quanto una password.
procedure RiempiCasuale(var Dati: TBytes);
{$IFDEF MSWINDOWS}
begin
  if Length(Dati) = 0 then
    Exit;

  if not SystemFunction036(@Dati[0], Length(Dati)) then
    raise Exception.Create('Generatore casuale di sistema non disponibile.');
end;
{$ELSE}
var
  Sorgente: TFileStream;
begin
  if Length(Dati) = 0 then
    Exit;

  Sorgente := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
  try
    Sorgente.ReadBuffer(Dati[0], Length(Dati));
  finally
    FreeAndNil(Sorgente);
  end;
end;
{$ENDIF}

{ TValidazioneResultHelper }

class function TValidazioneResultHelper.FromString(const Value: string): TValidazioneResult;
begin
  if Value = 'K' then
    Result := vrOk
  else
    if Value = 'N' then
      Result := vrNonTrovato
    else
      if Value = 'U' then
        Result := vrUtenteNonAttivo
      else
        if Value = 'S' then
          Result := vrScaduto
        else
          if Value = 'G' then
            Result := vrGiaRevocato
          else
            raise Exception.CreateFmt('Valore di validazione non valido: "%s"', [Value]);
end;

function TValidazioneResultHelper.Description: string;
begin
  case Self of
    vrOk:
      Result := 'OK';
    vrNonTrovato:
      Result := 'Non trovato';
    vrUtenteNonAttivo:
      Result := 'Utente non attivo';
    vrScaduto:
      Result := 'Scaduto';
    vrGiaRevocato:
      Result := 'Gia'' revocato';
  else
    Result := 'Sconosciuto';
  end;
end;

{ TRefreshTokenService }

function TRefreshTokenService.GenerateRandomToken: string;
var
  Dati: TBytes;
begin
  SetLength(Dati, 32);
  RiempiCasuale(Dati);
  Result := TNetEncoding.Base64URL.EncodeBytesToString(Dati);
end;

function TRefreshTokenService.HashToken(const token: string): string;
begin
  // SHA-256 in esadecimale: 64 caratteri, compatibile con il dominio
  // USR_REFRESH_TOKEN_HASH (VARCHAR(64))
  Result := THashSHA2.GetHashString(token, SHA256);
end;

function TRefreshTokenService.GenerateToken: string;
begin
  Result := GenerateRandomToken;
end;

function TRefreshTokenService.CreateToken(UserId: Integer; const IdSessione: Int64; const rawToken, deviceInfo, ipAddress: string): TDateTime;
var
  Params: TParamValues;
  ResultData: TJSONObject;
begin
  // EXECUTE PROCEDURE USR_REFRESH_TOKENS_CREA(:USER_ID, :TOKEN_HASH,
  //   :DEVICE_INFO, :IP_ADDRESS, :GIORNI_MAX, :ID_SESSIONE)
  //   RETURNING_VALUES :ID_TOKEN, :SCADE_IL
  //
  // ID_SESSIONE e' l'ultimo parametro e ha un valore predefinito: su un
  // database non ancora aggiornato TDataService lo ignora, perche' applica
  // solo i parametri che la procedura dichiara.
  Params := TParamValues.Create;
  try
    Params.Add('USER_ID', UserId);
    Params.Add('TOKEN_HASH', HashToken(rawToken));
    Params.Add('DEVICE_INFO', Copy(deviceInfo, 1, 500));
    Params.Add('IP_ADDRESS', ipAddress);
    Params.Add('GIORNI_MAX', TAppConfig.Instance.JWT.RefreshTokenDays);

    if IdSessione > 0 then
      Params.Add('ID_SESSIONE', IdSessione);

    ResultData := TDataService.ExecuteStoredProc('USR_REFRESH_TOKENS_CREA', Params);
    try
      Result := JsonDate(ResultData, 'SCADE_IL', 0);
    finally
      FreeAndNil(ResultData);
    end;
  finally
    FreeAndNil(Params);
  end;
end;

function TRefreshTokenService.ValidateAndRotate(const rawToken, newRawToken, deviceInfo, ipAddress: string): TRefreshTokenResult;
var
  Params: TParamValues;
  ResultData: TJSONObject;
begin
  // EXECUTE PROCEDURE USR_REFRESH_TOKENS_VALIDAZIONE(:TOKEN_HASH, :NEW_TOKEN_HASH,
  //   :DEVICE_INFO, :IP_ADDRESS, :GIORNI_MAX)
  //   RETURNING_VALUES :RESULT, :NUOVA_SCADENZA, :USER_ID, :USER_NAME,
  //   :NOMINATIVO, :RUOLO, :ID_SESSIONE, :ADMIN_USER
  Result := Default(TRefreshTokenResult);
  Params := TParamValues.Create;
  try
    Params.Add('TOKEN_HASH', HashToken(rawToken));
    Params.Add('NEW_TOKEN_HASH', HashToken(newRawToken));
    Params.Add('DEVICE_INFO', Copy(deviceInfo, 1, 500));
    Params.Add('IP_ADDRESS', ipAddress);
    Params.Add('GIORNI_MAX', TAppConfig.Instance.JWT.RefreshTokenDays);
    ResultData := TDataService.ExecuteStoredProc('USR_REFRESH_TOKENS_VALIDAZIONE', Params);
    try
      Result.ValidazioneResult := TValidazioneResult.FromString(JsonStr(ResultData, 'RESULT'));
      Result.Success := Result.ValidazioneResult = vrOk;
      Result.NewExpiresAt := JsonDate(ResultData, 'NUOVA_SCADENZA', Now);
      Result.UserId := JsonInt(ResultData, 'USER_ID', -1);
      // Assenti su un database non ancora aggiornato: restano 0 e False, e il
      // middleware ripiega sull'access token scaduto per la sessione.
      Result.IdSessione := JsonInt64(ResultData, 'ID_SESSIONE', 0);
      Result.Username := JsonStr(ResultData, 'USER_NAME');
      Result.DisplayName := JsonStr(ResultData, 'NOMINATIVO');
      Result.Role := JsonStr(ResultData, 'RUOLO');
      Result.AdminUser := JsonBool(ResultData, 'ADMIN_USER', False);
    finally
      FreeAndNil(ResultData);
    end;
  finally
    FreeAndNil(Params);
  end;
end;

procedure TRefreshTokenService.RevokeToken(const rawToken: string);
var
  Params: TParamValues;
  Esito: TJSONObject;
begin
  // EXECUTE PROCEDURE USR_REFRESH_TOKENS_REVOCA_PER_HASH(:TOKEN_HASH)
  // La tabella conserva l'impronta, non il gettone: va passata l'impronta.
  Params := TParamValues.Create;
  try
    Params.Add('TOKEN_HASH', HashToken(rawToken));
    Esito := TDataService.ExecuteStoredProc('USR_REFRESH_TOKENS_REVOCA_PER_HASH', Params);
    FreeAndNil(Esito);
  finally
    FreeAndNil(Params);
  end;
end;

procedure TRefreshTokenService.RevokeAllUserTokens(UserId: Integer);
var
  Params: TParamValues;
  Esito: TJSONObject;
begin
  // EXECUTE PROCEDURE USR_REFRESH_TOKENS_REVOCA_PER_UTENTE(:USER_ID)
  Params := TParamValues.Create;
  try
    Params.Add('USER_ID', UserId);
    Esito := TDataService.ExecuteStoredProc('USR_REFRESH_TOKENS_REVOCA_PER_UTENTE', Params);
    FreeAndNil(Esito);
  finally
    FreeAndNil(Params);
  end;
end;

end.
