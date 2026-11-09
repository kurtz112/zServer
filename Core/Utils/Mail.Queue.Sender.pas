// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit Mail.Queue.Sender;

// Invio della posta tramite la coda generica.
//
// I quattro punti di ingresso che mandano una e-mail (recupero del nome
// utente, recupero della password, richiesta e conferma di registrazione)
// chiamavano un servizio di posta DENTRO la richiesta, e confermavano la
// transazione solo se la spedizione riusciva. Qui la "spedizione" e' una
// riga in ZZ_CODA, scritta sulla stessa connessione e nella stessa
// transazione del dato di dominio: la password nuova e il messaggio che la
// comunica nascono insieme o non nascono. La spedizione vera la fa il
// gestore del tipo POSTA del prodotto (Gesty.Posta.Gestore,
// WT.Posta.Gestore), con i tentativi e le attese della coda.
//
// Finche' nessun gestore POSTA e' registrato, Disponibile e' falso e i
// quattro punti di ingresso continuano a rispondere 503: mettere in coda un
// messaggio che nessuno spedira' farebbe credere all'utente di aver
// ricevuto una e-mail mai partita.
//
// Contenuto della riga (JSON): mittente, destinatario, oggetto, corpoTesto,
// corpoHtml. E' il formato che il gestore POSTA deve leggere.

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  Mail.Sender;

const
  TipoCodaPosta = 'POSTA';

type
  TMailQueueSender = class(TInterfacedObject, IMailSender)
  public
    function Disponibile: Boolean;
    function Invia(const Messaggio: TMailMessage; Connessione: TFDConnection): Boolean;
  end;

implementation

uses
  Queue.Service,
  Connection.Pool;

{ TMailQueueSender }

function TMailQueueSender.Disponibile: Boolean;
begin
  Result := TCodaGestori.HaGestore(TipoCodaPosta);
end;

function TMailQueueSender.Invia(const Messaggio: TMailMessage; Connessione: TFDConnection): Boolean;
var
  Contenuto: TJSONObject;
  Propria: TFDConnection;
begin
  Contenuto := TJSONObject.Create;
  try
    Contenuto.AddPair('mittente', Messaggio.Mittente);
    Contenuto.AddPair('destinatario', Messaggio.Destinatario);
    Contenuto.AddPair('oggetto', Messaggio.Oggetto);
    Contenuto.AddPair('corpoTesto', Messaggio.CorpoTesto);
    Contenuto.AddPair('corpoHtml', Messaggio.CorpoHtml);

    if Assigned(Connessione) then
      // La conferma e' di chi chiama, insieme al dato di dominio.
      TCoda.Accoda(Connessione, TipoCodaPosta, Contenuto)
    else
    begin
      // Nessuna transazione di dominio da accompagnare: si conferma subito.
      Propria := TConnectionPool.Instance.Acquire;
      try
        TCoda.Accoda(Propria, TipoCodaPosta, Contenuto);
        Propria.Commit;
      finally
        TConnectionPool.Instance.Release(Propria);
      end;
    end;

    Result := True;
  finally
    FreeAndNil(Contenuto);
  end;
end;

initialization

TMailSenders.Registra(TMailQueueSender.Create);

end.
