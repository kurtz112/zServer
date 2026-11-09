// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-18
// ---------------------------------------------------------------------------
unit Segnalazioni.Controller;

// Segnalazione degli errori del portale a Mantis, a scelta dell'utente.
//
// GET  /api/segnalazioni/abilitata
//   {"abilitata": true|false}: dice al portale se mostrare il pulsante
//   "Segnala all'assistenza". Non rivela mai indirizzo, progetto o token.
// POST /api/segnalazioni
//   {"pagina": "...", "testo": "...", "nota": "...", "tecnici": "..."}
//   "tecnici" e' facoltativo: i dati del browser (richieste recenti, console).
//   Apre il ticket e risponde 201 {"success": true, "idTicket": 1234}.
//   Risponde 503 se la funzione e' spenta, 429 se l'utente ha superato il
//   tetto al minuto, 502 se Mantis rifiuta la richiesta.
//
// Servono entrambe l'utente collegato (JWT): chi segnala e' quello della
// sessione, non quello che dichiara il browser. Indirizzo, token, progetto e
// categoria di Mantis si leggono dalla tabella CONFIG del database servito con
// MANTIS_GET_PARAMS (come Gesty e WT); la sezione "mantis" del .json, facoltativa,
// porta solo interruttore, prefisso, attesa e tetto al minuto. Valgono per tutti
// i prodotti.

interface

uses
  System.SysUtils,
  System.JSON,
  FireDAC.Comp.Client,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Swagger.Commons,
  Base.Controller,
  Segnalazioni.Service;

type
  [MVCPath('/api/segnalazioni')]
  [MVCDoc('Segnalazione degli errori del portale a Mantis')]
  TSegnalazioniController = class(TBaseController)
  private
    function ParametriMantis: TParametriMantis;
  public
    [MVCPath('/abilitata')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Dice se la segnalazione degli errori e'' attiva su questo server')]
    procedure Abilitata;

    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Apre un ticket Mantis con l''errore indicato')]
    procedure Segnala;
  end;

implementation

// Indirizzo, token e progetto vengono dalla tabella CONFIG del database
// servito (procedura MANTIS_GET_PARAMS): si leggono a ogni richiesta, cosi' una
// modifica di CONFIG vale subito, senza riavviare zServer.
function TSegnalazioniController.ParametriMantis: TParametriMantis;
var
  Connessione: TFDConnection;
begin
  Connessione := PrendiConnessione;
  try
    Result := TSegnalazioniService.LeggiParametri(Connessione);
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TSegnalazioniController.Abilitata;
begin
  RenderJson(TJSONObject.Create.AddPair('abilitata', TJSONBool.Create(TSegnalazioniService.Abilitata(ParametriMantis))));
end;

procedure TSegnalazioniController.Segnala;
var
  Corpo: TJSONObject;
  Segnalazione: TSegnalazione;
  Parametri: TParametriMantis;
  Esito: TEsitoSegnalazione;
  Risposta: TJSONObject;
begin
  Parametri := ParametriMantis;
  if not TSegnalazioniService.Abilitata(Parametri) then
    raise EMVCException.Create(503, 'La segnalazione degli errori non è attiva su questo server.');

  // Il tetto si controlla prima di leggere il corpo: un ciclo di errori non
  // deve costare nemmeno l'analisi del testo.
  if not TSegnalazioniService.InvioAmmesso(UserId) then
    raise EMVCException.Create(429, 'Troppe segnalazioni in poco tempo. Attendere un minuto e riprovare.');

  Corpo := CorpoJson;
  try
    Segnalazione.Utente := UserName;
    Segnalazione.IdUtente := UserId;
    Segnalazione.Pagina := Corpo.GetValue<string>('pagina', '');
    Segnalazione.Testo := Corpo.GetValue<string>('testo', '');
    Segnalazione.Nota := Corpo.GetValue<string>('nota', '');
    Segnalazione.Tecnici := Corpo.GetValue<string>('tecnici', '');
    Segnalazione.Agente := Context.Request.Headers['User-Agent'];
  finally
    Corpo.Free;
  end;

  Esito := TSegnalazioniService.Apri(Segnalazione, Parametri);

  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('success', TJSONBool.Create(True));
    Risposta.AddPair('idTicket', TJSONNumber.Create(Esito.IdTicket));
    RenderTestoJson(201, Risposta);
  finally
    Risposta.Free;
  end;
end;

end.
