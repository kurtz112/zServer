// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-06
// ---------------------------------------------------------------------------
unit App.Profile.Base;

// Parte comune dei profili applicativi: il meccanismo con cui si chiamano
// USR_LOGIN e USR_CONTEXT_SET. Cambia solo l'elenco dei parametri, e quello
// vive nel profilo del prodotto.
//
// Questa unit non nomina ne' WT ne' Gesty.

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  MVCFramework,
  App.Profile,
  Data.Service;

type
  TAppProfileBase = class(TInterfacedObject)
  protected
    /// <summary>
    /// Esegue USR_LOGIN su una connessione presa senza contesto: al login il
    /// contesto non esiste ancora, ed e' proprio la procedura a crearlo.
    /// La conferma la fa TDataService, cosi' la sessione appena creata e'
    /// visibile alle richieste successive, che useranno un'altra connessione.
    /// Il chiamante e' proprietario del TJSONObject restituito.
    /// </summary>
    function EseguiLogin(const Parametri: TParamValues): TJSONObject;

    /// <summary>
    /// Esegue USR_CONTEXT_SET sulla connessione data, senza aprire ne'
    /// confermare transazioni: la transazione la governa chi ha preso la
    /// connessione (Connection.Pool), perche' le righe delle tabelle
    /// temporanee servono confermate.
    /// </summary>
    procedure EseguiContextSet(Connessione: TFDConnection; const Parametri: TParamValues);

    /// <summary>
    /// Esegue USR_CONTEXT_CLEAR sulla connessione data: stessa firma nei due
    /// prodotti (nessun parametro), stessa disciplina di transazione di
    /// EseguiContextSet.
    /// </summary>
    procedure EseguiContextClear(Connessione: TFDConnection);

    /// <summary>
    /// Traduce l'esito di USR_LOGIN in un TAuthResult non riuscito,
    /// distinguendo l'accesso negato da un guasto (Z13).
    /// </summary>
    function EsitoNegativo(const E: Exception): TAuthResult;
  public
    // Aree (fase 0) per i prodotti che non le hanno: l'accesso resta quello
    // di Autentica, nessuna area nel token, nessun cambio d'area, ogni
    // procedura e dataset ammesso come prima. Il prodotto con le aree le
    // ridefinisce.
    function AutenticaInArea(const UserName, Password, Area: string): TAuthResult; virtual;
    procedure LeggiAree(const UserName: string; const IdSessione: Int64; out Aree: TArray<string>; out Area: string); virtual;
    procedure CambiaArea(const IdSessione: Int64; const Area: string); virtual;
    function AmmessoNellArea(const IdSessione: Int64; const Tipo, Nome: string): Boolean; virtual;
    function OggettoAmmesso(const Oid, IdSessione: Int64): Boolean; virtual;
    // Moduli (2026-11-06) per i prodotti che non li hanno: nessun modulo e
    // nessun perimetro per comune da restringere. In Gesty BASE_WEB_DATASETS e
    // BASE_WEB_PROCEDURE non hanno la colonna MODULO, quindi nessun oggetto
    // chiede un modulo e niente cambia.
    function ModuliUtente(const UserName: string): TModuliUtente; virtual;
    procedure RestringiComuniDellaRichiesta(const Comuni: TArray<string>); virtual;
    // Moduli per azienda (2026-11-06): i prodotti che non li hanno non ne
    // riconoscono nessuno.
    function ModuloAttivoPerAzienda(const UserName, Modulo: string): Boolean; virtual;
    // Moduli per cittadino (Riciclario, 2026-11-06): i prodotti che non hanno
    // un portale del cittadino non ne riconoscono nessuno.
    function ModuloAttivoPerCittadino(const UserName, Modulo: string): Boolean; virtual;
    function ModuliCittadino(const UserName: string): TModuliUtente; virtual;
    // Moduli senza comune dati dai gruppi (GERA, 2026-11-07): i prodotti che non
    // li hanno non ne riconoscono nessuno.
    function ModuloAttivoPerGruppo(const UserName, Modulo: string; const Scrittura: Boolean): Boolean; virtual;
    function ModuliGruppo(const UserName: string): TModuliUtente; virtual;
  end;

implementation

uses
  System.Variants,
  System.Generics.Collections,
  FireDAC.Stan.Param,
  MVCFramework.Commons,
  MVCFramework.Logger,
  Connection.Pool;

{ TAppProfileBase }

function TAppProfileBase.EseguiLogin(const Parametri: TParamValues): TJSONObject;
var
  Connessione: TFDConnection;
begin
  Connessione := TConnectionPool.Instance.Acquire({ ConContesto } False);
  try
    Result := TDataService.ExecuteStoredProc(Connessione, 'USR_LOGIN', Parametri);
  finally
    TConnectionPool.Instance.Release(Connessione);
  end;
end;

procedure TAppProfileBase.EseguiContextSet(Connessione: TFDConnection; const Parametri: TParamValues);
var
  Procedura: TFDStoredProc;
  Parametro: TPair<string, Variant>;
  ParametroTrovato: TFDParam;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := 'USR_CONTEXT_SET';
    Procedura.Prepare;

    for Parametro in Parametri do
    begin
      ParametroTrovato := Procedura.Params.FindParam(Parametro.Key);

      if not Assigned(ParametroTrovato) then
        Continue;

      if VarIsNull(Parametro.Value) or VarIsEmpty(Parametro.Value) then
        ParametroTrovato.Clear
      else
        ParametroTrovato.Value := Parametro.Value;
    end;

    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TAppProfileBase.EseguiContextClear(Connessione: TFDConnection);
var
  Procedura: TFDStoredProc;
begin
  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := 'USR_CONTEXT_CLEAR';
    Procedura.ExecProc;
  finally
    FreeAndNil(Procedura);
  end;
end;

function TAppProfileBase.EsitoNegativo(const E: Exception): TAuthResult;
begin
  Result.Clear;
  Result.Success := False;
  Result.CredenzialiNonValide := AccessoNegato(E.Message);
  Result.ErrorMessage := E.Message;
end;

function TAppProfileBase.AutenticaInArea(const UserName, Password, Area: string): TAuthResult;
begin
  // Autentica la dichiara il profilo del prodotto, non questa classe: la si
  // raggiunge dall'interfaccia, che il profilo implementa.
  Result := (Self as IAppProfile).Autentica(UserName, Password);
end;

procedure TAppProfileBase.LeggiAree(const UserName: string; const IdSessione: Int64; out Aree: TArray<string>; out Area: string);
begin
  Aree := [];
  Area := '';
end;

procedure TAppProfileBase.CambiaArea(const IdSessione: Int64; const Area: string);
begin
  raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Questo prodotto non ha aree.');
end;

function TAppProfileBase.AmmessoNellArea(const IdSessione: Int64; const Tipo, Nome: string): Boolean;
begin
  Result := True;
end;

function TAppProfileBase.OggettoAmmesso(const Oid, IdSessione: Int64): Boolean;
begin
  Result := True;
end;

function TAppProfileBase.ModuliUtente(const UserName: string): TModuliUtente;
begin
  Result := [];
end;

procedure TAppProfileBase.RestringiComuniDellaRichiesta(const Comuni: TArray<string>);
begin
end;

function TAppProfileBase.ModuloAttivoPerAzienda(const UserName, Modulo: string): Boolean;
begin
  Result := False;
end;

function TAppProfileBase.ModuloAttivoPerCittadino(const UserName, Modulo: string): Boolean;
begin
  Result := False;
end;

function TAppProfileBase.ModuliCittadino(const UserName: string): TModuliUtente;
begin
  Result := [];
end;

function TAppProfileBase.ModuloAttivoPerGruppo(const UserName, Modulo: string; const Scrittura: Boolean): Boolean;
begin
  Result := False;
end;

function TAppProfileBase.ModuliGruppo(const UserName: string): TModuliUtente;
begin
  Result := [];
end;

end.
