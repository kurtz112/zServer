// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit WT.Anpr.Stesei;

// Ricerca anagrafica su ANPR attraverso il gateway Stesei, per il gestore
// ANPR della coda.
//
// La sequenza e' quella di WT (API\Stesei\Stesei_Http.pas, CercaAnagrafe):
// ST001 residenza, poi ST006 nucleo, poi ST012 indirizzi digitali. Le prime
// due devono riuscire; la terza no, perche' INAD risponde con un errore anche
// quando il codice fiscale semplicemente non ha un domicilio digitale.
//
// Le strutture JSON sono le stesse unit di WT (cartella Stesei, copiate da
// Wintarif_Group\_src\API\Stesei\Strutture JSON senza modifiche). Il
// trasporto invece e' nuovo, per tre motivi:
//
// 1. quello di WT legge la configurazione da una variabile globale caricata
//    all'avvio dell'applicazione per il comune di lavoro; qui ogni lavoro
//    porta il suo comune e la configurazione arriva per parametro;
// 2. usa Winapi e SmartInspect.VCL, che zServer non ha e che su Linux non
//    esistono;
// 3. non distingue fra i due modi di fallire, che per la coda sono opposti.
//
// I due modi di fallire:
//
// - Stesei risponde e dice di no (codice fiscale non trovato, comune non
//   abilitato): e' un esito, non un guasto. Cerca restituisce False e il
//   motivo in Errore; il chiamante registra la richiesta in errore, come fa
//   WT, e il lavoro e' concluso.
// - Stesei non risponde, risponde con un errore del server o con un testo
//   che non e' JSON: e' un guasto. Cerca solleva ESteseiNonDisponibile e la
//   coda riprova piu' tardi.
//
// Nel registro finiscono l'indirizzo e l'esito, mai il corpo: la richiesta
// contiene la password del gateway, la risposta i dati anagrafici.

interface

uses
  System.SysUtils,
  Stesei_ST001_ANPR_LoadResidenza_Response,
  Stesei_ST006_ANPR_LoadNucleo_Response,
  Stesei_ST012_INAD_LoadIndirizziDigitali_Response;

type
  ESteseiNonDisponibile = class(Exception);

  /// <summary>
  /// Configurazione del gateway per un comune, da STESEI_CONFIG_GET.
  /// </summary>
  TSteseiConfigurazione = record
    Configurato: Boolean;
    Url: string;
    Utente: string;
    Password: string;
    IdOperatore: string;
    IdUfficio: Integer;
    CodiceIstat: string;
  end;

  TSteseiRicercaAnagrafe = class
  private
    FConfigurazione: TSteseiConfigurazione;
    FErrore: string;
    FResidenza: TST001_LoadResidenza_Response;
    FNucleo: TST006_LoadNucleo_Response;
    FIndirizziDigitali: TST012_LoadIndirizziDigitali_Response;
    function Invia(const Risorsa, Corpo: string): string;
    function CercaResidenza(const CodiceFiscale, Motivo: string): Boolean;
    function CercaNucleo(const CodiceFiscale, Motivo: string): Boolean;
    procedure CercaIndirizziDigitali(const CodiceFiscale, Motivo: string);
  public
    constructor Create(const Configurazione: TSteseiConfigurazione);
    destructor Destroy; override;

    /// <summary>
    /// True se residenza e nucleo sono arrivati. False se Stesei ha risposto
    /// con un errore, il cui testo e' in Errore. Solleva
    /// ESteseiNonDisponibile se il gateway non ha risposto in modo leggibile.
    /// </summary>
    function Cerca(const CodiceFiscale, Motivo: string): Boolean;

    property Errore: string read FErrore;
    // Di proprieta' dell'oggetto; nil se la chiamata non e' arrivata fin li'.
    property Residenza: TST001_LoadResidenza_Response read FResidenza;
    property Nucleo: TST006_LoadNucleo_Response read FNucleo;
    property IndirizziDigitali: TST012_LoadIndirizziDigitali_Response read FIndirizziDigitali;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  MVCFramework.Logger,
  Stesei_ST000_Common,
  Stesei_ST001_ANPR_LoadResidenza_Request,
  Stesei_ST006_ANPR_LoadNucleo_Request,
  Stesei_ST012_INAD_LoadIndirizziDigitali_Request;

const
  // Il gateway interroga ANPR in tempo reale: una risposta oltre il minuto
  // e' un guasto, e il lavoro torna in coda.
  ATTESA_CONNESSIONE_MS = 15000;
  ATTESA_RISPOSTA_MS = 60000;

procedure ImpostaAccesso(const Configurazione: TSteseiConfigurazione; Credenziali: TCredenzialiAccesso;
  Restrizioni: TRestrizioniAccessoAnagrafe; Criteri: TCriteriRicercaAnagrafe; const CodiceFiscale, Motivo: string);
begin
  Credenziali.utente := Configurazione.Utente;
  Credenziali.password := Configurazione.Password;

  Restrizioni.idOperatore := Configurazione.IdOperatore;
  Restrizioni.idUfficio := Configurazione.IdUfficio;
  Restrizioni.motivoRichiesta := Motivo;

  Criteri.comuneIstat := Configurazione.CodiceIstat;
  Criteri.codiceFiscale := CodiceFiscale;
end;

// WT prende il messaggio e, se manca, il tipo di errore: un errore senza
// nessuno dei due resterebbe una richiesta in errore senza motivo.
function TestoErrore(Errore: TErrore; const Servizio: string): string;
begin
  Result := Errore.messaggio.Trim;

  if Result.IsEmpty then
    Result := Errore.tipoErrore.Trim;

  if Result.IsEmpty then
    Result := Format('Stesei ha risposto con un errore senza descrizione (%s).', [Servizio]);
end;

{ TSteseiRicercaAnagrafe }

constructor TSteseiRicercaAnagrafe.Create(const Configurazione: TSteseiConfigurazione);
begin
  inherited Create;
  FConfigurazione := Configurazione;

  if not FConfigurazione.Url.EndsWith('/') then
    FConfigurazione.Url := FConfigurazione.Url + '/';
end;

destructor TSteseiRicercaAnagrafe.Destroy;
begin
  FreeAndNil(FResidenza);
  FreeAndNil(FNucleo);
  FreeAndNil(FIndirizziDigitali);
  inherited;
end;

function TSteseiRicercaAnagrafe.Invia(const Risorsa, Corpo: string): string;
var
  Client: THTTPClient;
  Flusso: TStringStream;
  Risposta: IHTTPResponse;
  Indirizzo: string;
  Valore: TJSONValue;
  Stato: Integer;
  TestoStato: string;
begin
  Indirizzo := FConfigurazione.Url + Risorsa;

  Flusso := TStringStream.Create(Corpo, TEncoding.UTF8);
  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := ATTESA_CONNESSIONE_MS;
      Client.ResponseTimeout := ATTESA_RISPOSTA_MS;
      Client.ContentType := 'application/json; charset=utf-8';
      Client.Accept := 'application/json';

      try
        Risposta := Client.Post(Indirizzo, Flusso);
      except
        on E: Exception do
          raise ESteseiNonDisponibile.CreateFmt('Stesei non raggiungibile (%s): %s', [Risorsa, E.Message]);
      end;

      // La risposta si legge tutta prima di liberare il client.
      Result := Risposta.ContentAsString(TEncoding.UTF8);
      Stato := Risposta.StatusCode;
      TestoStato := Risposta.StatusText;
    finally
      FreeAndNil(Client);
    end;
  finally
    FreeAndNil(Flusso);
  end;

  LogD(Format('Stesei: %s risposta %d, %d caratteri', [Indirizzo, Stato, Result.Length]));

  // Un errore del server o un testo che non e' JSON (pagina di errore del
  // proxy, gateway in manutenzione) non e' una risposta di ANPR.
  if Stato >= 500 then
    raise ESteseiNonDisponibile.CreateFmt('Stesei ha risposto %d %s (%s)', [Stato, TestoStato, Risorsa]);

  Valore := TJSONObject.ParseJSONValue(Result);
  try
    if not(Valore is TJSONObject) then
      raise ESteseiNonDisponibile.CreateFmt('Stesei ha risposto %d con un testo che non e'' JSON (%s)', [Stato, Risorsa]);
  finally
    FreeAndNil(Valore);
  end;
end;

function TSteseiRicercaAnagrafe.CercaResidenza(const CodiceFiscale, Motivo: string): Boolean;
var
  Richiesta: TST001_LoadResidenza_Request;
  Testo: string;
begin
  Richiesta := TST001_LoadResidenza_Request.Create;
  try
    ImpostaAccesso(FConfigurazione, Richiesta.credenzialiAccesso, Richiesta.restrizioniAccesso, Richiesta.criteriRicerca, CodiceFiscale, Motivo);
    Testo := Invia('ST001', Richiesta.ToJSONString);
  finally
    FreeAndNil(Richiesta);
  end;

  FResidenza := TST001_LoadResidenza_Response.FromJSON(Testo);
  Result := not FResidenza.errore.errore;

  if not Result then
    FErrore := TestoErrore(FResidenza.errore, 'ST001');
end;

function TSteseiRicercaAnagrafe.CercaNucleo(const CodiceFiscale, Motivo: string): Boolean;
var
  Richiesta: TST006_LoadNucleo_Request;
  Testo: string;
begin
  Richiesta := TST006_LoadNucleo_Request.Create;
  try
    ImpostaAccesso(FConfigurazione, Richiesta.credenzialiAccesso, Richiesta.restrizioniAccesso, Richiesta.criteriRicerca, CodiceFiscale, Motivo);
    Testo := Invia('ST006', Richiesta.ToJSONString);
  finally
    FreeAndNil(Richiesta);
  end;

  FNucleo := TST006_LoadNucleo_Response.FromJSON(Testo);
  Result := not FNucleo.errore.errore;

  if not Result then
    FErrore := TestoErrore(FNucleo.errore, 'ST006');
end;

procedure TSteseiRicercaAnagrafe.CercaIndirizziDigitali(const CodiceFiscale, Motivo: string);
var
  Richiesta: TST012_LoadIndirizziDigitali_Request;
  Testo: string;
begin
  Richiesta := TST012_LoadIndirizziDigitali_Request.Create;
  try
    ImpostaAccesso(FConfigurazione, Richiesta.credenzialiAccesso, Richiesta.restrizioniAccesso, Richiesta.criteriRicerca, CodiceFiscale, Motivo);
    Testo := Invia('ST012', Richiesta.ToJSONString);
  finally
    FreeAndNil(Richiesta);
  end;

  FIndirizziDigitali := TST012_LoadIndirizziDigitali_Response.FromJSON(Testo);

  // L'errore di INAD non ferma la ricerca: gli indirizzi semplicemente non
  // si registrano (vedi il commento di testa).
  if FIndirizziDigitali.errore.errore then
    LogD('Stesei: ST012 senza indirizzi digitali: ' + TestoErrore(FIndirizziDigitali.errore, 'ST012'));
end;

function TSteseiRicercaAnagrafe.Cerca(const CodiceFiscale, Motivo: string): Boolean;
begin
  FErrore := '';
  FreeAndNil(FResidenza);
  FreeAndNil(FNucleo);
  FreeAndNil(FIndirizziDigitali);

  Result := CercaResidenza(CodiceFiscale, Motivo) and CercaNucleo(CodiceFiscale, Motivo);

  if Result then
    CercaIndirizziDigitali(CodiceFiscale, Motivo);
end;

end.
