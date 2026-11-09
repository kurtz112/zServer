// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit Gesty.Posta.Gestore;

// Gestore del tipo POSTA della coda ZZ_CODA per Gesty.
//
// Gesty non ha una coda di posta propria (niente EMAIL_OUTBOX): zServer
// spedisce da se', via SMTP con Indy, e la cifratura la fa SChannel, il TLS
// di Windows (zPack\zLibs\zNet.Tls.SChannel). Niente OpenSSL: le DLL
// libeay32/ssleay32 sono in eliminazione da WT e Gesty, e il fornitore
// zNet.Tls.OpenSsl qui di proposito non e' incluso.
//
// Server, porta, credenziali, modalita' TLS e mittente stanno nella voce
// posta del .json (TPostaConfig). Il mittente e' quello della
// configurazione, non quello della riga in coda: un server SMTP accetta di
// norma solo gli indirizzi della casella con cui ci si autentica. La voce
// "mittente" della riga (l'indirizzo per le risposte, nelle procedure del
// portale) diventa il Reply-To.
//
// Una spedizione riuscita il cui esito non si riesce a scrivere viene
// ripetuta al ripescaggio del lavoro: il destinatario puo' ricevere due
// volte lo stesso messaggio. E' il limite di ogni consegna "almeno una
// volta" verso un servizio esterno (vedi Queue.Service), preferito alla
// perdita del messaggio.
//
// Solo Windows: SChannel non esiste su Linux. Sulla compilazione Linux64 il
// gestore non si registra e la posta del portale risponde 503; servira' un
// fornitore TLS per Linux, o un elaboratore della coda su Windows accanto.
//
// Senza server o mittente nel .json il gestore non si registra, per lo
// stesso motivo: meglio un 503 che una richiesta accettata e mai spedita.

interface

implementation

{$IFDEF MSWINDOWS}

uses
  System.SysUtils,
  System.JSON,
  IdSMTP,
  IdMessage,
  IdText,
  IdSSL,
  IdExplicitTLSClientServerBase,
  FireDAC.Comp.Client,
  MVCFramework.Logger,
  zNet.Tls,
  zNet.Tls.SChannel,
  App.Config,
  Json.Values,
  Queue.Service,
  Mail.Queue.Sender;

const
  // Codice con cui zNet.Tls.SChannel si registra in zNet.Tls.
  MotoreTls = 'SCHANNEL';

function CreaMessaggio(const Config: TPostaConfig; Contenuto: TJSONObject; const Destinatario: string): TIdMessage;
var
  Risposte: string;
  CorpoTesto: string;
  CorpoHtml: string;
  Parte: TIdText;
begin
  Risposte := JsonStr(Contenuto, 'mittente').Trim;
  CorpoTesto := JsonStr(Contenuto, 'corpoTesto');
  CorpoHtml := JsonStr(Contenuto, 'corpoHtml');

  Result := TIdMessage.Create(nil);
  try
    Result.CharSet := 'utf-8';
    Result.From.Address := Config.Mittente.Trim;
    Result.From.Name := Config.NomeMittente.Trim;

    if (not Risposte.IsEmpty) and (not SameText(Risposte, Config.Mittente.Trim)) then
      Result.ReplyTo.EMailAddresses := Risposte;

    Result.Recipients.EMailAddresses := Destinatario;
    Result.Subject := JsonStr(Contenuto, 'oggetto');

    if CorpoHtml.IsEmpty then
    begin
      // Solo testo: un messaggio semplice, senza parti.
      Result.ContentType := 'text/plain';
      Result.ContentTransferEncoding := 'quoted-printable';
      Result.Body.Text := CorpoTesto;
    end
    else
    begin
      // Testo e HTML come alternative dello stesso contenuto: il programma
      // di posta mostra l'HTML, e il testo resta per chi non lo legge.
      Result.ContentType := 'multipart/alternative';

      Parte := TIdText.Create(Result.MessageParts, nil);
      Parte.ContentType := 'text/plain';
      Parte.CharSet := 'utf-8';
      Parte.ContentTransfer := 'quoted-printable';
      Parte.Body.Text := CorpoTesto;

      Parte := TIdText.Create(Result.MessageParts, nil);
      Parte.ContentType := 'text/html';
      Parte.CharSet := 'utf-8';
      Parte.ContentTransfer := 'quoted-printable';
      Parte.Body.Text := CorpoHtml;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function GestisciPosta(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
var
  Config: TPostaConfig;
  Destinatario: string;
  Posta: TIdMessage;
  Smtp: TIdSMTP;
  ModalitaTls: TIdUseTLS;
  VersioneTls: TzTlsVersione;
begin
  // La connessione al database non serve: la spedizione non scrive niente.
  Config := TAppConfig.Instance.Posta;
  Destinatario := JsonStr(Contenuto, 'destinatario').Trim;

  if Destinatario.IsEmpty then
  begin
    Messaggio := 'Messaggio senza destinatario.';
    Exit(False);
  end;

  ModalitaTls := ModalitaTls.FromString(Config.Tls);
  VersioneTls := VersioneTls.FromString(Config.VersioneTls);

  Posta := CreaMessaggio(Config, Contenuto, Destinatario);
  try
    Smtp := TIdSMTP.Create(nil);
    try
      // L'handler lo costruisce il motore selezionato in zNet.Tls (SChannel,
      // all'avvio): questa unit non tocca le classi del motore.
      Smtp.IOHandler := CreaIOHandlerTls(Smtp, VersioneTls);

      // UseTLS prima della porta: con ImplicitTLS Indy imposta la 465, e
      // la porta della configurazione deve venire dopo per prevalere.
      Smtp.UseTLS := ModalitaTls;
      Smtp.Host := Config.Server.Trim;
      Smtp.Port := Config.Porta;
      Smtp.ConnectTimeout := 30000;
      Smtp.ReadTimeout := 60000;
      Smtp.UseEhlo := True;

      if Config.Utente.Trim.IsEmpty then
        Smtp.AuthType := satNone
      else
      begin
        Smtp.AuthType := satDefault;
        Smtp.Username := Config.Utente;
        Smtp.Password := Config.Password;
      end;

      Smtp.Connect;
      try
        if (Smtp.AuthType <> satNone) and (not Smtp.Authenticate) then
        begin
          Messaggio := Format('Autenticazione rifiutata dal server %s per l''utente %s.', [Smtp.Host, Config.Utente]);
          Exit(False);
        end;

        Smtp.Send(Posta);
      finally
        Smtp.Disconnect;
      end;
    finally
      FreeAndNil(Smtp);
    end;

    Messaggio := Format('Spedito a %s tramite %s', [Destinatario, Config.Server]);
    Result := True;
  finally
    FreeAndNil(Posta);
  end;
end;

procedure RegistraGestore;
var
  Config: TPostaConfig;
begin
  Config := TAppConfig.Instance.Posta;

  if not Config.SmtpConfigurato then
  begin
    LogW('Posta: mancano posta.server o posta.mittente nel .json, la posta del portale resta disattivata (risposta 503)');
    Exit;
  end;

  // Il motore TLS e' una scelta del processo, fatta una volta prima della
  // prima connessione (zNet.Tls): zServer non apre altre connessioni TLS
  // con Indy, quindi la fa chi ne ha bisogno.
  SelezionaProviderTls(MotoreTls);

  TCodaGestori.Registra(TipoCodaPosta, GestisciPosta);
  LogI(Format('Posta: spedizione via SMTP %s:%d (%s, %s) a nome di %s', [Config.Server, Config.Porta, Config.Tls,
    ProviderTlsSelezionatoDescrizione, Config.Mittente]));
end;

initialization

RegistraGestore;

{$ELSE}

uses
  MVCFramework.Logger;

initialization

LogW('Posta: su questa piattaforma non c''e'' un fornitore TLS per la posta di Gesty, la posta del portale resta disattivata (risposta 503)');

{$ENDIF}

end.
