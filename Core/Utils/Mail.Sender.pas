// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit Mail.Sender;

// Invio di posta: l'interfaccia, non l'implementazione.
//
// Quattro punti di ingresso portati dal vecchio server — recupero del nome
// utente, recupero della password, richiesta e conferma di registrazione —
// funzionano cosi': una stored procedure prepara destinatario, oggetto e
// corpo del messaggio, il server lo spedisce e solo se la spedizione riesce
// conferma la transazione. Senza spedizione la procedura non si puo'
// confermare: l'utente si ritroverebbe con una password nuova e nessun modo
// di conoscerla.
//
// L'implementazione non e' in questa consegna, e la ragione e' una scelta,
// non una dimenticanza: il vecchio server spediva con Indy e
// IdSSLOpenSSL, e portare qui quella dipendenza andrebbe contro il lavoro
// di eliminazione di OpenSSL in corso su WT e Gesty. La strada va scelta
// una volta (fornitore TLS di sistema, oppure la coda di posta del
// prodotto) e vale per entrambi.
//
// Dal 2026-10-06 la strada e' la coda generica: Mail.Queue.Sender mette il
// messaggio in ZZ_CODA nella stessa transazione, e il gestore del tipo POSTA
// del prodotto lo consegna: Gesty.Posta.Gestore spedisce via SMTP con
// SChannel, WT.Posta.Gestore lo passa a EMAIL_OUTBOX, da cui spedisce WT.
//
// Finche' nessuno si registra, quei quattro punti di ingresso rispondono
// 503 e non confermano niente. E' l'unico comportamento onesto: meglio un
// errore esplicito che una registrazione a metà.

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

type
  TMailMessage = record
    Mittente: string;
    Destinatario: string;
    Oggetto: string;
    CorpoTesto: string;
    CorpoHtml: string;
  end;

  IMailSender = interface
    ['{7C4A9E51-2D83-4F17-B6A0-93E5D1C74A28}']
    /// <summary>
    /// Vero se questo servizio e' in grado di spedire davvero. Un servizio
    /// registrato ma senza chi lo esegue (la coda senza gestore POSTA) dice
    /// falso, e i punti di ingresso rispondono 503 invece di far credere a
    /// un utente che la posta sia partita.
    /// </summary>
    function Disponibile: Boolean;
    /// <summary>
    /// Spedisce o mette in coda. Connessione e' quella della transazione di
    /// dominio in corso: un servizio che accoda scrive li' e lascia la
    /// conferma a chi chiama, cosi' dato e messaggio nascono insieme. Puo'
    /// essere nulla se non c'e' una transazione da accompagnare.
    /// </summary>
    function Invia(const Messaggio: TMailMessage; Connessione: TFDConnection): Boolean;
  end;

  EMailNonConfigurata = class(Exception);

  TMailSenders = class
  private
    class var FCorrente: IMailSender;
  public
    class procedure Registra(const Sender: IMailSender);
    class function Disponibile: Boolean;
    /// <summary>
    /// Spedisce, oppure solleva EMailNonConfigurata se nessun servizio di
    /// posta e' stato registrato all'avvio.
    /// </summary>
    class function Invia(const Messaggio: TMailMessage; Connessione: TFDConnection = nil): Boolean;
  end;

implementation

{ TMailSenders }

class procedure TMailSenders.Registra(const Sender: IMailSender);
begin
  FCorrente := Sender;
end;

class function TMailSenders.Disponibile: Boolean;
begin
  Result := Assigned(FCorrente) and FCorrente.Disponibile;
end;

class function TMailSenders.Invia(const Messaggio: TMailMessage; Connessione: TFDConnection): Boolean;
begin
  if not Disponibile then
    raise EMailNonConfigurata.Create('Invio della posta non configurato su questo server.');

  Result := FCorrente.Invia(Messaggio, Connessione);
end;

initialization

finalization

TMailSenders.FCorrente := nil;

end.
