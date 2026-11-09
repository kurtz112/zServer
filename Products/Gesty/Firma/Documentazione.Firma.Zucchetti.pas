// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit Documentazione.Firma.Zucchetti;

// Fornitore di firma ZUCCHETTI: solo il posto nell'elenco dei fornitori e il
// contratto da implementare. Nessuna chiamata al fornitore.
//
// Perche' esiste gia': la firma con valore legale delle liberatorie dei
// centri del riuso (WT) resta aperta fra eSignAnyWhere e i sistemi di firma
// Zucchetti (analisi 20260921-centri-del-riuso-database-e-zserver, par. 6.3).
// Il meccanismo e' pronto per tutti e due: quando si sceglie Zucchetti si
// scrive il corpo dei metodi qui sotto, senza toccare la coda (Firma.Gestore)
// ne' il database, e si attiva con la sola configurazione:
//   - OBJ_FILES_FIRMA_FORNITORI.SUPPORTA_FIRMA = TRUE per ZUCCHETTI (oggi
//     FALSE: il database non chiede firme a un fornitore che non le sa fare);
//   - OBJ_FILES_FIRMA_CONFIGURAZIONE del tenant con FORNITORE = 'ZUCCHETTI',
//     ATTIVO, URL_BASE, UTENTE, PASSWORD_ e i parametri del fornitore in
//     OBJ_FILES_FIRMA_CONFIG_PARAMETRI (chiavi in maiuscolo).
//
// Da implementare, sullo schema di Documentazione.Firma.ESignAnyWhere:
//   - Firma: invio della busta con Documento.FullFileName e
//     Documento.Firmatari (cognome, nome, e-mail, telefono, segnaposto);
//     Stato 'D' e IdDocumentoEsterno = identificativo della busta. Il nome
//     della busta comincia con il contrassegno ricevuto da
//     ImpostaContrassegno;
//   - AggiornaEstremi: stato della busta; firmata = 'F' con il file firmato
//     (ed eventuale attestazione) scritti nelle versioni create con
//     CreaVersione(IdObjectFilePadre, 'FIR' o 'RIC', ...); scaduta 'S',
//     respinta 'R', altrimenti 'D' con StatoEsterno;
//   - CercaBusta: busta inviata negli ultimi Giorni il cui nome contiene il
//     contrassegno, vuoto se non c'e' (protegge dal doppio invio quando la
//     coda riprende un lavoro);
//   - TestConnessione, e Funzionalita = [ffFirma];
//   - CollegamentoFirma (IzFirmaCollegamento, firma al banco, 2026-11-07):
//     URL della pagina di firma del firmatario. Per SignBook e' l'operazione
//     "Recupero dell'URL per iniziare il processo di firma"; IndirizzoRitorno
//     va nell'indirizzo di richiamata. Vuoto se la pratica non ha ancora un
//     collegamento.
// Ogni chiamata passa da LogRequest/LogResponse, mai con token o password
// nel testo registrato.
//
// Si registra da solo: basta includere la unit nel progetto.

interface

uses
  System.SysUtils,
  zDocumentale.Firma.Types,
  zDocumentale.Firma.Intf,
  zDocumentale.Firma.ProviderBase,
  zDocumentale.Firma.Factory;

const
  FIRMA_FORNITORE_ZUCCHETTI = 'ZUCCHETTI';

type
  TzFirmaZucchettiProvider = class(TzFirmaProviderBase, IzFirmaRicercaBusta, IzFirmaCollegamento)
  private
    FContrassegno: string;
    procedure NonImplementato(const Operazione: string);
  public
    function Nome: string; override;

    // Funzionalita resta quella della classe base (vuota) finche' il
    // fornitore non e' implementato: l'interfaccia non mostra il comando.

    function Firma(const Documento: TzFirmaDocumento): TzFirmaEsito; override;
    function AggiornaEstremi(const Documento: TzFirmaDocumento; const IdDocumentoEsterno: string): TzFirmaEsito; override;

    // IzFirmaRicercaBusta
    procedure ImpostaContrassegno(const Valore: string);
    function CercaBusta(const Contrassegno: string; const Giorni: Integer): string;

    // IzFirmaCollegamento
    function CollegamentoFirma(const IdDocumentoEsterno: string; const Firmatario: TzFirmaFirmatario;
      const IndirizzoRitorno: string): string;
  end;

implementation

function TzFirmaZucchettiProvider.Nome: string;
begin
  Result := FIRMA_FORNITORE_ZUCCHETTI;
end;

procedure TzFirmaZucchettiProvider.NonImplementato(const Operazione: string);
begin
  raise EzFirmaNonSupportato.CreateFmt(
    'Il fornitore di firma "%s" e'' previsto ma non ancora implementato (operazione %s).', [Nome, Operazione]);
end;

function TzFirmaZucchettiProvider.Firma(const Documento: TzFirmaDocumento): TzFirmaEsito;
begin
  Result.Clear;
  NonImplementato('Firma');
end;

function TzFirmaZucchettiProvider.AggiornaEstremi(const Documento: TzFirmaDocumento; const IdDocumentoEsterno: string): TzFirmaEsito;
begin
  Result.Clear;
  NonImplementato('AggiornaEstremi');
end;

procedure TzFirmaZucchettiProvider.ImpostaContrassegno(const Valore: string);
begin
  FContrassegno := Valore;
end;

function TzFirmaZucchettiProvider.CercaBusta(const Contrassegno: string; const Giorni: Integer): string;
begin
  Result := '';
  NonImplementato('CercaBusta');
end;

function TzFirmaZucchettiProvider.CollegamentoFirma(const IdDocumentoEsterno: string; const Firmatario: TzFirmaFirmatario;
  const IndirizzoRitorno: string): string;
begin
  Result := '';
  NonImplementato('CollegamentoFirma');
end;

initialization

TzFirmaFactory.Registra(FIRMA_FORNITORE_ZUCCHETTI, TzFirmaZucchettiProvider);

end.
