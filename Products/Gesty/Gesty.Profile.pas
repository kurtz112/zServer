// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-08
// ---------------------------------------------------------------------------
unit Gesty.Profile;

// Profilo applicativo di Gesty.
//
// Raccoglie cio' che prima era cablato nel nucleo: il codice applicativo
// 'Gesty', la firma a quattro parametri di USR_LOGIN e la lettura di
// TIPO_USER e HOST_LDAP.
//
// Firme verificate sul database GESTY il 2026-09-15:
// USR_LOGIN       ingresso: APP, USER_NAME, PASSWORD_, COMPUTER_NAME
// uscita:   USER_ID, ID_SESSIONE, NOMINATIVO, TIPO_USER,
// DATA_SCADENZA_PASSWORD, ADMIN_USER, HOST_LDAP, OTP
// USR_CONTEXT_SET ingresso: ID_SESSIONE, USER_ID, USER_NAME, COMPUTER_NAME

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  MVCFramework,
  App.Profile,
  App.Profile.Base;

type
  TGestyProfile = class(TAppProfileBase, IAppProfile)
  public
    function Codice: string;
    function CodiceApplicativo: string;
    function Autentica(const UserName, Password: string): TAuthResult;
    procedure ImpostaContesto(Connessione: TFDConnection; const UserId, IdSessione: Int64; const UserName: string);
    procedure AzzeraContesto(Connessione: TFDConnection);
    function ClausolaPerimetro(const NomeRelazione: string): string;
    function AmbitoAmmesso(const Belfiore: string; const IdAzienda: Int64): Boolean;
    function ClasseDocumentale(const NomeEntita: string): string;
    function PercorsoFile(const IdObjectFile, IdSessione: Int64): string;
    function ControllerDiDominio: TArray<TMVCControllerClazz>;
    function AzioniPubbliche: TArray<string>;
  end;

implementation

uses
  System.Variants,
  System.JSON,
  MVCFramework.Logger,
  Data.Service,
  Json.Values,
  Gesty.Capac.Controller,
  Gesty.Codebri.Controller,
  Gesty.Questionari.Controller,
  Gesty.Firma.Controller;

const
  // Nome con cui il server si presenta a USR_LOGIN e a USR_CONTEXT_SET:
  // in Gesty il quarto parametro del contesto e' COMPUTER_NAME, e questo
  // valore e' quello che compare in USR_SESSIONI.
  NOME_POSTAZIONE = 'zServer';

{ TGestyProfile }

function TGestyProfile.Codice: string;
begin
  Result := 'GESTY';
end;

function TGestyProfile.CodiceApplicativo: string;
begin
  Result := 'Gesty';
end;

function TGestyProfile.Autentica(const UserName, Password: string): TAuthResult;
var
  Parametri: TParamValues;
  Uscita: TJSONObject;
begin
  Result.Clear;

  try
    Parametri := TParamValues.Create;
    try
      Parametri.Add('APP', CodiceApplicativo);
      Parametri.Add('USER_NAME', UserName);
      Parametri.Add('PASSWORD_', Password);
      Parametri.Add('COMPUTER_NAME', NOME_POSTAZIONE);

      Uscita := EseguiLogin(Parametri);
      try
        if not Assigned(Uscita) then
        begin
          Result.ErrorMessage := 'USR_LOGIN non ha restituito alcun risultato';
          Exit;
        end;

        Result.UserId := JsonInt64(Uscita, 'USER_ID');

        if Result.UserId <= 0 then
        begin
          Result.CredenzialiNonValide := True;
          Result.ErrorMessage := 'Credenziali non valide';
          Exit;
        end;

        Result.Success := True;
        Result.IdSessione := JsonInt64(Uscita, 'ID_SESSIONE');
        Result.Nominativo := JsonStr(Uscita, 'NOMINATIVO');
        Result.Ruolo := JsonStr(Uscita, 'TIPO_USER');
        Result.DataScadenzaPassword := JsonDate(Uscita, 'DATA_SCADENZA_PASSWORD');
        Result.AdminUser := JsonBool(Uscita, 'ADMIN_USER');
        Result.HostLDAP := JsonStr(Uscita, 'HOST_LDAP');
        Result.RichiedeOtp := JsonBool(Uscita, 'OTP');

        LogI(Format('Accesso riuscito: %s (utente %d, sessione %d)', [Result.Nominativo, Result.UserId, Result.IdSessione]));
      finally
        FreeAndNil(Uscita);
      end;
    finally
      FreeAndNil(Parametri);
    end;
  except
    on E: Exception do
      Result := EsitoNegativo(E);
  end;
end;

procedure TGestyProfile.ImpostaContesto(Connessione: TFDConnection; const UserId, IdSessione: Int64; const UserName: string);
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    if IdSessione > 0 then
      Parametri.Add('ID_SESSIONE', IdSessione)
    else
      Parametri.Add('ID_SESSIONE', Null);

    Parametri.Add('USER_ID', UserId);
    Parametri.Add('USER_NAME', UserName);
    Parametri.Add('COMPUTER_NAME', NOME_POSTAZIONE);

    EseguiContextSet(Connessione, Parametri);
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TGestyProfile.AzzeraContesto(Connessione: TFDConnection);
begin
  EseguiContextClear(Connessione);
end;

// In Gesty non esistono ne' USR_TMP_COMUNI ne' USR_TMP_AZIENDE: il perimetro
// di visibilita non e' per comune o per azienda, quindi non c'e' clausola da
// aggiungere. E' questo il motivo per cui il perimetro e' un metodo del
// profilo e non una regola scritta nel nucleo.
function TGestyProfile.ClausolaPerimetro(const NomeRelazione: string): string;
begin
  Result := '';
end;

function TGestyProfile.AmbitoAmmesso(const Belfiore: string; const IdAzienda: Int64): Boolean;
begin
  Result := True;
end;

function TGestyProfile.ClasseDocumentale(const NomeEntita: string): string;
begin
  // Nessuna corrispondenza cablata: la classe arriva dalla richiesta e viene
  // verificata su OBJ_CLASSES dal controller dei file.
  Result := '';
end;

function TGestyProfile.PercorsoFile(const IdObjectFile, IdSessione: Int64): string;
var
  Parametri: TParamValues;
  Riga: TJSONObject;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Parametri.Add('ID_OBJECT_FILE', IdObjectFile);
    // La funzione esiste solo nel package WEB, e da fuori un package si
    // chiama col nome completo: senza WEB. lo scarico falliva sempre.
    Riga := TDataService.ExecuteQuerySingleRow('SELECT WEB.FILE_GET_FULL_FILE_NAME(:ID_SESSIONE, :ID_OBJECT_FILE) AS FULL_FILE_NAME FROM RDB$DATABASE', Parametri, False);
    try
      Result := JsonStr(Riga, 'FULL_FILE_NAME');
    finally
      FreeAndNil(Riga);
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

function TGestyProfile.ControllerDiDominio: TArray<TMVCControllerClazz>;
begin
  Result := [TCapacController, TCodebriController, TQuestionariController, TGestyFirmaController];
end;

function TGestyProfile.AzioniPubbliche: TArray<string>;
begin
  // Moduli compilati dai visitatori del sito: arrivano senza token, e il
  // token non ci sarebbe modo di darglielo.
  Result := [
    'TCapacController.RichiestaInformazioni',
    'TCapacController.InserimentoCandidatura',
    'TCodebriController.RichiestaInformazioni',
    'TCodebriController.InserimentoCandidatura',
    'TQuestionariController.GetQuestionario',
    'TQuestionariController.SetRisposte'];
end;

initialization

TAppProfiles.Registra(TGestyProfile.Create);

end.
