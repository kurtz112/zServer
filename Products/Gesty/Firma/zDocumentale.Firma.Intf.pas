unit zDocumentale.Firma.Intf;

// Contratto del provider di firma elettronica. I metodi non supportati
// sollevano EzFirmaNonSupportato; la UI si regola su Funzionalita.

interface

uses
  System.SysUtils,
  zDocumentale.Firma.Types;

type
  IzFirmaProvider = interface
    ['{A94D6E27-1B83-4F5C-B0E9-73C2D8461FA5}']
    function Nome: string;
    function Funzionalita: TzFirmaFunzionalitaSet;

    procedure Configura(const Configurazione: TzFirmaConfigurazione);
    procedure TestConnessione;

    // Avvia (o completa, se il fornitore e' sincrono) la firma.
    // Provider a certificato remoto: usa Documento.Credenziale, firma subito,
    //   ritorna Stato = 'F' con IdObjectFileFirmato valorizzato.
    // Provider a busta/envelope: usa Documento.Firmatari, invia la busta,
    //   ritorna Stato = 'D' (in firma) con IdDocumentoEsterno = envelope id.
    function Firma(const Documento: TzFirmaDocumento): TzFirmaEsito;

    // Polling dello stato per i fornitori asincroni (come UPD_STATUS in Gesty):
    // quando la busta risulta firmata, scarica firmato + audit e valorizza
    // IdObjectFileFirmato / IdObjectFileAudit tramite la callback CreaVersione
    // (il Documento porta la versione di partenza, padre delle nuove versioni).
    function AggiornaEstremi(const Documento: TzFirmaDocumento;
      const IdDocumentoEsterno: string): TzFirmaEsito;

    // Solo fornitori a certificato remoto.
    function ScaricaCertificato(const Credenziale: TzFirmaCredenziale): TzFirmaEsito;
  end;

  // 2026-11-07: ricerca di una busta gia' inviata, per i fornitori a busta.
  // La coda di zServer (Firma.Gestore) riprende i lavori "almeno una volta":
  // prima di inviare chiede se la busta col contrassegno della registrazione
  // e' gia' partita. Un fornitore che non implementa questa interfaccia non
  // e' accettato dalla coda.
  IzFirmaRicercaBusta = interface
    ['{5C2E8B41-9D37-4A6F-8E10-3B7F6C2D9A54}']
    // Testo messo in testa al nome della prossima busta inviata con Firma.
    procedure ImpostaContrassegno(const Contrassegno: string);

    // Identificativo della busta inviata negli ultimi Giorni il cui nome
    // contiene Contrassegno; vuoto se non c'e'.
    function CercaBusta(const Contrassegno: string; const Giorni: Integer): string;
  end;

  // 2026-11-07: collegamento di firma di una busta gia' inviata, per la firma
  // al banco (centri del riuso di WT): invece di aspettare l'invito per
  // e-mail, l'operatore apre il collegamento sul tablet e il firmatario firma
  // li', con il codice OTP che riceve per SMS. Facoltativa: un fornitore che
  // non la implementa resta valido per la firma a distanza, e chi chiede il
  // collegamento riceve "non gestito" (EzFirmaNonSupportato).
  IzFirmaCollegamento = interface
    ['{8B3F1D27-6E4A-4C59-A2D8-7F05C13E9B64}']
    // URL della pagina di firma del Firmatario nella busta IdDocumentoEsterno.
    // IndirizzoRitorno: pagina a cui tornare dopo la firma, se il fornitore
    // la accetta al momento della richiesta (vuoto = quella del fornitore).
    // Vuoto se il fornitore non ha (ancora) un collegamento per quel
    // firmatario; EzFirmaErrore se la busta non e' sua o la risposta non si
    // capisce.
    function CollegamentoFirma(const IdDocumentoEsterno: string; const Firmatario: TzFirmaFirmatario;
      const IndirizzoRitorno: string): string;
  end;

implementation

end.
