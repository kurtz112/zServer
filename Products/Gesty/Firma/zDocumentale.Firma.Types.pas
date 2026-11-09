unit zDocumentale.Firma.Types;

// Tipi del motore di firma elettronica multi-fornitore.
// Ospita ENTRAMBI i modelli di fornitore senza forzare l'uno nei panni dell'altro:
// - certificato remoto (es. SignHub): una persona, una credenziale, un file firmato
// - busta/envelope (es. eSignAnyWhere): piu' firmatari nominati, output doppio
//   (file firmato + audit trail)
// TzFirmaDocumento porta SIA Credenziale SIA Firmatari: ogni provider usa
// il campo che gli serve e ignora l'altro.
// Gli stati adottano i valori gia' validati in produzione da Gesty
// (OBJ_FIRME_ELETTRONICHE.STATO_PRATICA).
// Riferimento: analisi_completa_documentale_wt_gesty.md, PARTE II §7.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  EzFirmaErrore = class(Exception);
  EzFirmaNonSupportato = class(EzFirmaErrore);

  TzFirmaFunzionalita = (ffFirma, ffScaricaCertificato);
  TzFirmaFunzionalitaSet = set of TzFirmaFunzionalita;

const
  // stati della registrazione di firma (dominio OBJ_FILES_FIRMA_STATO)
  FIRMA_STATO_INSERITA  = 'I';   // in approvazione interna (opzionale)
  FIRMA_STATO_APPROVATA = 'A';   // pronta per l'invio
  FIRMA_STATO_IN_FIRMA  = 'D';   // inviata al fornitore, in attesa dei firmatari
  FIRMA_STATO_FIRMATA   = 'F';   // completata
  FIRMA_STATO_RESPINTA  = 'R';
  FIRMA_STATO_SCADUTA   = 'S';

type
  // usata solo dai provider a certificato remoto (es. SignHub);
  // e' per PERSONA (responsabile del procedimento), non per azienda
  TzFirmaCredenziale = record
    Alias_: string;
    Pin: string;
    Certificato: string;
    procedure Clear;
    function Vuota: Boolean;
  end;

  // usata solo dai provider a busta/envelope (es. eSignAnyWhere)
  TzFirmaFirmatario = record
    Ruolo: string;                  // es. 'Direttore', 'LegaleRappresentante', 'FirmaOTP'
    Cognome: string;
    Nome: string;
    Email: string;
    Telefono: string;
    // segnaposto delle firme nel documento (es. prefisso 'Direttore_')
    Placeholder: string;
    // profilo di firma remota presso il fornitore; vuoto = firma OTP
    IdentificativoFirmaRemota: string;
    procedure Clear;
  end;

  TzFirmaDocumento = record
    IdObjectFile: Int64;            // la VERSIONE di partenza (riga di OBJ_FILES)
    Oid: Int64;
    FullFileName: string;           // path della versione di partenza, risolto dal ponte
    Credenziale: TzFirmaCredenziale;         // vuota se il provider non la usa
    Firmatari: TArray<TzFirmaFirmatario>;    // vuoto se il provider non li usa
    procedure Clear;
  end;

  TzFirmaEsito = record
    Ok: Boolean;
    Stato: string;                  // I/A/D/F/R/S
    StatoEsterno: string;           // testo grezzo del fornitore (es. envelope status)
    IdDocumentoEsterno: string;     // es. envelope id
    IdObjectFileFirmato: Int64;     // versione FIR creata (0 se non ancora disponibile)
    IdObjectFileAudit: Int64;       // versione RIC dell'audit trail (0 se il provider non lo fornisce)
    Messaggio: string;
    procedure Clear;
  end;

  // Creazione delle versioni nella catena OBJ_FILES: il provider NON accede
  // al database — riceve questa callback dal ponte applicativo (es.
  // Documentazione.Firma in Gesty),
  // che la aggancia a OBJ_FILES_VERSIONE_ADD. Il provider la usa per farsi
  // assegnare id e path di destinazione del file firmato ('FIR') e
  // dell'eventuale audit trail ('RIC'), poi vi scrive i byte ricevuti.
  TzFirmaVersioneCreata = record
    IdObjectFile: Int64;
    FullFileName: string;
    procedure Clear;
  end;

  TzFirmaCreaVersioneFunc = reference to function(IdObjectFilePadre: Int64;
    const TipoVersione, NomeFileOriginale, FileSuffix: string): TzFirmaVersioneCreata;

  // log tecnico: agganciato dal ponte alle SP
  // OBJ_FILES_FIRMA_LOG_REQUEST_ADD / _RESPONSE_ADD
  TzFirmaLogRequestFunc = reference to function(const Operazione, Endpoint,
    Richiesta: string): Int64;
  TzFirmaLogResponseProc = reference to procedure(IdLogRequest: Int64;
    HttpStatus: Integer; const Risposta, Errore: string);

  // ATTENZIONE alla proprieta' di Parametri: e' un oggetto dentro un record,
  // quindi l'assegnazione fra due variabili di questo tipo copia il
  // RIFERIMENTO, non il contenuto. Chi vuole conservare la configurazione
  // oltre la vita del proprietario originale deve usare CopiaDa, non ":=".
  TzFirmaConfigurazione = record
    Fornitore: string;
    IdTenant: Integer;              // WT: ID_AZIENDA (AZIENDE) - Gesty: ID_ENTE
    UrlBase: string;
    Utente: string;
    Password: string;
    Parametri: TDictionary<string, string>;
    procedure Inizializza;
    procedure Finalizza;

    // Mantis #61 - 2026-08-31: copia profonda, per dare al destinatario un
    // dizionario di sua proprieta' invece di un riferimento condiviso
    procedure CopiaDa(const Origine: TzFirmaConfigurazione);

    function Parametro(const Chiave: string; const Default: string = ''): string;
  end;

implementation

{ TzFirmaCredenziale }

procedure TzFirmaCredenziale.Clear;
begin
  Self := Default(TzFirmaCredenziale);
end;

function TzFirmaCredenziale.Vuota: Boolean;
begin
  result := Alias_.IsEmpty and Pin.IsEmpty and Certificato.IsEmpty;
end;

{ TzFirmaFirmatario }

procedure TzFirmaFirmatario.Clear;
begin
  Self := Default(TzFirmaFirmatario);
end;

{ TzFirmaDocumento }

procedure TzFirmaDocumento.Clear;
begin
  Self := Default(TzFirmaDocumento);
end;

{ TzFirmaEsito }

procedure TzFirmaEsito.Clear;
begin
  Self := Default(TzFirmaEsito);
end;

{ TzFirmaVersioneCreata }

procedure TzFirmaVersioneCreata.Clear;
begin
  Self := Default(TzFirmaVersioneCreata);
end;

{ TzFirmaConfigurazione }

procedure TzFirmaConfigurazione.Inizializza;
begin
  Self := Default(TzFirmaConfigurazione);
  Parametri := TDictionary<string, string>.Create;
end;

procedure TzFirmaConfigurazione.Finalizza;
begin
  FreeAndNil(Parametri);
end;

// Mantis #61 - 2026-08-31: il provider riceveva il record per assegnazione e
// si ritrovava a puntare al dizionario del ponte, che viene distrutto a ogni
// CaricaConfigurazione. Con la copia profonda ogni destinatario possiede i
// propri parametri e nessuna ricarica altrui puo' invalidarlo.
procedure TzFirmaConfigurazione.CopiaDa(const Origine: TzFirmaConfigurazione);
var
  Coppia: TPair<string, string>;
begin
  // se il dizionario di origine e' gia' il nostro non c'e' nulla da copiare:
  // rifarlo distruggerebbe la sorgente mentre la si legge
  if Assigned(Parametri) and (Parametri = Origine.Parametri) then
  begin
    Fornitore := Origine.Fornitore;
    IdTenant := Origine.IdTenant;
    UrlBase := Origine.UrlBase;
    Utente := Origine.Utente;
    Password := Origine.Password;
    exit;
  end;

  Finalizza;      // libera l'eventuale dizionario posseduto in precedenza
  Inizializza;    // azzera i campi e crea un dizionario nuovo, di proprieta'

  Fornitore := Origine.Fornitore;
  IdTenant := Origine.IdTenant;
  UrlBase := Origine.UrlBase;
  Utente := Origine.Utente;
  Password := Origine.Password;

  if Assigned(Origine.Parametri) then
    for Coppia in Origine.Parametri do
      Parametri.AddOrSetValue(Coppia.Key, Coppia.Value);
end;

function TzFirmaConfigurazione.Parametro(const Chiave: string;
  const Default: string): string;
begin
  result := Default;
  if assigned(Parametri) then
    if not Parametri.TryGetValue(Chiave.ToUpper, result) then
      result := Default;
end;

end.
