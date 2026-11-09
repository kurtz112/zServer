unit zDocumentale.Firma.ProviderBase;

// Classe base dei provider di firma: default che sollevano EzFirmaNonSupportato,
// log e creazione versioni via callback iniettate dal ponte applicativo
// (es. Documentazione.Firma in Gesty).

interface

uses
  System.SysUtils,
  zDocumentale.Firma.Types,
  zDocumentale.Firma.Intf;

type
  TzFirmaProviderBase = class(TInterfacedObject, IzFirmaProvider)
  private
    FOnLogRequest: TzFirmaLogRequestFunc;
    FOnLogResponse: TzFirmaLogResponseProc;
    FOnCreaVersione: TzFirmaCreaVersioneFunc;
  protected
    FConfigurazione: TzFirmaConfigurazione;

    procedure NonSupportato(const Operazione: string);
    function LogRequest(const Operazione, Endpoint, Richiesta: string): Int64;
    procedure LogResponse(IdLogRequest: Int64; HttpStatus: Integer;
      const Risposta, Errore: string);

    // crea una versione nella catena OBJ_FILES tramite la callback del ponte;
    // solleva EzFirmaErrore se la callback non e' stata assegnata
    function CreaVersione(IdObjectFilePadre: Int64; const TipoVersione,
      NomeFileOriginale, FileSuffix: string): TzFirmaVersioneCreata;
  public
    constructor Create; virtual;

    // Mantis #61 - 2026-08-31: il provider possiede la propria copia della
    // configurazione e deve liberarla
    destructor Destroy; override;

    // IzFirmaProvider
    function Nome: string; virtual; abstract;
    function Funzionalita: TzFirmaFunzionalitaSet; virtual;

    procedure Configura(const Configurazione: TzFirmaConfigurazione); virtual;
    procedure TestConnessione; virtual;

    function Firma(const Documento: TzFirmaDocumento): TzFirmaEsito; virtual;
    function AggiornaEstremi(const Documento: TzFirmaDocumento;
      const IdDocumentoEsterno: string): TzFirmaEsito; virtual;
    function ScaricaCertificato(const Credenziale: TzFirmaCredenziale): TzFirmaEsito; virtual;

    property OnLogRequest: TzFirmaLogRequestFunc read FOnLogRequest write FOnLogRequest;
    property OnLogResponse: TzFirmaLogResponseProc read FOnLogResponse write FOnLogResponse;
    property OnCreaVersione: TzFirmaCreaVersioneFunc read FOnCreaVersione write FOnCreaVersione;
  end;

implementation

{ TzFirmaProviderBase }

constructor TzFirmaProviderBase.Create;
begin
  inherited Create;
end;

// Mantis #61 - 2026-08-31: libera il dizionario dei parametri creato da
// Configura. Finalizza e' sicuro anche se Configura non e' mai stata
// chiamata: il record e' azzerato alla costruzione dell'oggetto e
// FreeAndNil su un riferimento nullo non fa nulla.
destructor TzFirmaProviderBase.Destroy;
begin
  FConfigurazione.Finalizza;
  inherited;
end;

procedure TzFirmaProviderBase.NonSupportato(const Operazione: string);
begin
  raise EzFirmaNonSupportato.CreateFmt(
    'Il fornitore di firma "%s" non supporta l''operazione %s', [Nome, Operazione]);
end;

function TzFirmaProviderBase.LogRequest(const Operazione, Endpoint,
  Richiesta: string): Int64;
begin
  result := 0;
  if assigned(FOnLogRequest) then
    result := FOnLogRequest(Operazione, Endpoint, Richiesta);
end;

procedure TzFirmaProviderBase.LogResponse(IdLogRequest: Int64; HttpStatus: Integer;
  const Risposta, Errore: string);
begin
  if assigned(FOnLogResponse) then
    FOnLogResponse(IdLogRequest, HttpStatus, Risposta, Errore);
end;

function TzFirmaProviderBase.CreaVersione(IdObjectFilePadre: Int64;
  const TipoVersione, NomeFileOriginale, FileSuffix: string): TzFirmaVersioneCreata;
begin
  result.Clear;
  if not assigned(FOnCreaVersione) then
    raise EzFirmaErrore.CreateFmt(
      'Callback di creazione versione non assegnata (fornitore "%s")', [Nome]);
  result := FOnCreaVersione(IdObjectFilePadre, TipoVersione, NomeFileOriginale, FileSuffix);
end;

function TzFirmaProviderBase.Funzionalita: TzFirmaFunzionalitaSet;
begin
  result := [];
end;

// Mantis #61 - 2026-08-31: era "FConfigurazione := Configurazione", che copia
// il record e quindi il RIFERIMENTO al dizionario del ponte. Il ponte lo
// distrugge a ogni CaricaConfigurazione (FreeAndNil in Finalizza): un provider
// ancora vivo si ritrovava a leggere memoria liberata e Parametro() tornava
// stringa vuota, lasciando l'AccessToken OAuth2 senza valore.
procedure TzFirmaProviderBase.Configura(const Configurazione: TzFirmaConfigurazione);
begin
  FConfigurazione.CopiaDa(Configurazione);
end;

procedure TzFirmaProviderBase.TestConnessione;
begin
  NonSupportato('TestConnessione');
end;

function TzFirmaProviderBase.Firma(const Documento: TzFirmaDocumento): TzFirmaEsito;
begin
  result.Clear;
  NonSupportato('Firma');
end;

function TzFirmaProviderBase.AggiornaEstremi(const Documento: TzFirmaDocumento;
  const IdDocumentoEsterno: string): TzFirmaEsito;
begin
  result.Clear;
  NonSupportato('AggiornaEstremi');
end;

function TzFirmaProviderBase.ScaricaCertificato(const Credenziale: TzFirmaCredenziale): TzFirmaEsito;
begin
  result.Clear;
  NonSupportato('ScaricaCertificato');
end;

end.
