// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit WT.Posta.Gestore;

// Gestore del tipo POSTA della coda ZZ_CODA per WT.
//
// zServer di WT non spedisce: passa il messaggio a EMAIL_OUTBOX con la
// procedura EMAIL_OUTBOX_ADD_INDIRIZZO, e la spedizione la fa il servizio di
// posta di WT, con i suoi account, i suoi registri e i suoi tentativi, come
// per il resto della posta del programma. Cosi' zServer non ha bisogno di un
// trasporto SMTP proprio, ne' di credenziali nel .json.
//
// L'inserimento avviene sulla connessione dell'elaboratore e viene
// confermato insieme all'esito del lavoro (vedi Queue.Service): un
// messaggio entra in EMAIL_OUTBOX una volta sola, anche se l'elaboratore
// cade a meta'. Il lavoro riesce appena la riga c'e': che il messaggio
// parta davvero lo dicono EMAIL_OUTBOX.STATO_MAIL ed EMAIL_OUTBOX_ERRORI.
//
// Account di invio, mittente e indirizzo di risposta vengono dal modello
// indicato in posta.idModello del .json (EMAIL_OUTBOX_MODELLI), che deve
// essere di posta ordinaria e senza PDF del documentale. La voce
// "mittente" della riga in coda (MAIL_PER_RISPOSTE delle procedure del
// portale) qui non si usa: in WT il mittente e' quello dell'account.
//
// Senza posta.idModello il gestore non si registra: la coda non preleva i
// messaggi e i punti di ingresso del portale che spediscono posta
// rispondono 503, invece di accettare richieste che non partirebbero mai.

interface

implementation

uses
  System.SysUtils,
  System.JSON,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  MVCFramework.Logger,
  App.Config,
  Json.Values,
  Queue.Service,
  Mail.Queue.Sender;

var
  IdModelloPosta: Int64 = 0;

function GestisciPosta(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
var
  Procedura: TFDStoredProc;
  Destinatario: string;
  Oggetto: string;
  CorpoTesto: string;
  CorpoHtml: string;
begin
  Destinatario := JsonStr(Contenuto, 'destinatario').Trim;
  Oggetto := JsonStr(Contenuto, 'oggetto');
  CorpoTesto := JsonStr(Contenuto, 'corpoTesto');
  CorpoHtml := JsonStr(Contenuto, 'corpoHtml');

  if Destinatario.IsEmpty then
  begin
    Messaggio := 'Messaggio senza destinatario.';
    Exit(False);
  end;

  // EMAIL_OUTBOX.OGGETTO e' lungo 100 caratteri e il trigger
  // EMAIL_OUTBOX_BI ci antepone il numero del messaggio: il resto lo taglia
  // lui, qui basta stare nel parametro.
  Oggetto := Copy(Oggetto, 1, 100);

  Procedura := TFDStoredProc.Create(nil);
  try
    Procedura.Connection := Connessione;
    Procedura.StoredProcName := 'EMAIL_OUTBOX_ADD_INDIRIZZO';
    Procedura.Prepare;

    Procedura.ParamByName('ID_EMAIL_OUTBOX_MODELLO').AsLargeInt := IdModelloPosta;
    Procedura.ParamByName('E_MAIL').AsString := Destinatario;
    Procedura.ParamByName('OGGETTO').AsString := Oggetto;

    // Vuoto e nullo non sono la stessa cosa per la procedura: senza testo
    // semplice usa l'HTML, senza nessuno dei due rifiuta il messaggio.
    if CorpoTesto.IsEmpty then
      Procedura.ParamByName('TESTO').Clear
    else
      Procedura.ParamByName('TESTO').AsString := CorpoTesto;

    if CorpoHtml.IsEmpty then
      Procedura.ParamByName('TESTO_HTML').Clear
    else
      Procedura.ParamByName('TESTO_HTML').AsString := CorpoHtml;

    Procedura.ExecProc;

    Messaggio := Format('EMAIL_OUTBOX %d', [Procedura.ParamByName('ID_EMAIL_OUT').AsLargeInt]);
    Result := True;
  finally
    FreeAndNil(Procedura);
  end;
end;

initialization

IdModelloPosta := TAppConfig.Instance.Posta.IdModello;

if IdModelloPosta > 0 then
begin
  TCodaGestori.Registra(TipoCodaPosta, GestisciPosta);
  LogI(Format('Posta: i messaggi del portale vanno in EMAIL_OUTBOX con il modello %d', [IdModelloPosta]));
end
else
  LogW('Posta: manca la voce posta.idModello nel .json, la posta del portale resta disattivata (risposta 503)');

end.
