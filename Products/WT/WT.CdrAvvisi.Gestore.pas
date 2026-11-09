// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit WT.CdrAvvisi.Gestore;

// Gestore del tipo CDR_PUBBLICAZIONE della coda ZZ_CODA (lavoro
// OUT\20261107-pipa-centri-del-riuso-completamento, decisione 2).
//
// Il trigger CDR_BENI_AVVISO_PUBBLICAZIONE accoda { "idBene": n } quando un bene
// diventa pubblicato e qualcuno ha chiesto l'avviso per quel comune. Qui si
// leggono i messaggi gia' pronti da CDR_AVVISO_PUBBLICAZIONE_DESTINATARI (uno per
// indirizzo, testo scritto nel database) e si passano alla posta di zServer con
// TMailSenders.Invia sulla connessione del lavoro: ogni messaggio diventa un
// lavoro POSTA nella stessa transazione, confermato insieme all'esito di questo.
//
// Scelte:
// - senza posta configurata (posta.idModello mancante, nessun gestore POSTA) il
//   lavoro riesce con l'esito "posta non configurata": ritentare non servirebbe,
//   e la coda resterebbe piena di lavori che non partiranno mai;
// - un bene non piu' pubblicato quando il lavoro gira (prenotato o ceduto
//   subito) non produce messaggi: la procedura non restituisce righe;
// - nessun commit qui: lo fa Queue.Service.

interface

implementation

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  MVCFramework.Logger,
  Data.Service,
  Json.Values,
  Queue.Service,
  Mail.Sender;

const
  TipoCodaPubblicazioneCdr = 'CDR_PUBBLICAZIONE';

function GestisciPubblicazione(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
var
  IdBene: Int64;
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Posta: TMailMessage;
  Spediti: Integer;
begin
  IdBene := JsonInt64(Contenuto, 'idBene');
  if IdBene <= 0 then
  begin
    // Contenuto sbagliato: ritentare non lo correggerebbe
    Messaggio := 'Lavoro senza idBene.';
    Exit(True);
  end;

  if not TMailSenders.Disponibile then
  begin
    Messaggio := Format('Bene %d: posta non configurata, nessun avviso spedito.', [IdBene]);
    Exit(True);
  end;

  Spediti := 0;

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_BENE', IdBene);
    Righe := TDataService.ExecuteQuery(Connessione,
      'SELECT CDR_AVVISO_PUBBLICAZIONE_DESTINATARI.E_MAIL, CDR_AVVISO_PUBBLICAZIONE_DESTINATARI.OGGETTO, ' +
      'CDR_AVVISO_PUBBLICAZIONE_DESTINATARI.TESTO FROM CDR_AVVISO_PUBBLICAZIONE_DESTINATARI(:ID_BENE)',
      Parametri, False);
    try
      for Riga in Righe do
      begin
        Posta := Default(TMailMessage);
        Posta.Destinatario := JsonStr(TJSONObject(Riga), 'E_MAIL').Trim;
        Posta.Oggetto := JsonStr(TJSONObject(Riga), 'OGGETTO');
        Posta.CorpoTesto := JsonStr(TJSONObject(Riga), 'TESTO');

        if Posta.Destinatario.IsEmpty then
          Continue;

        if TMailSenders.Invia(Posta, Connessione) then
          Inc(Spediti);
      end;
    finally
      FreeAndNil(Righe);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  Messaggio := Format('Bene %d: %d avvisi in coda di posta.', [IdBene, Spediti]);
  Result := True;
end;

initialization

TCodaGestori.Registra(TipoCodaPubblicazioneCdr, GestisciPubblicazione);
LogI('Riuso: avvisi di pubblicazione dei centri del riuso attivi (coda CDR_PUBBLICAZIONE)');

end.
