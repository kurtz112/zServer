// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit WT.Anpr.Controller;

// Ricerca anagrafica su ANPR per lo sportello dell'operatore.
//
// Sostituisce la rotta anpr/cerca del vecchio server (Moduli\WT\dmANPR.pas),
// che non e' stata portata: usava un client ANPR che WT ha dismesso e una
// procedura di configurazione (WEB_ANPR_CONFIG_GET) che sul database non
// esiste piu'.
//
// La ricerca non avviene dentro la richiesta: la richiesta mette in coda un
// lavoro ANPR (gestore in WT.Anpr.Gestore) e ne aspetta l'esito per al
// massimo coda.attesaRispostaSecondi del .json.
//
// POST /api/wt/anpr/ricerche
//   corpo {"belfiore": "L626", "codiceFiscale": "...", "idIntestatario": 0, "motivo": "..."}
//   200 con la scheda se il lavoro si e' concluso in tempo;
//   202 con l'identificativo del lavoro se no: il client rilegge con
// GET /api/wt/anpr/ricerche/lavori/{idLavoro}
//   stesse risposte; 404 se il lavoro non esiste, non e' ANPR o l'ha chiesto
//   un altro utente.
//
// La scheda e' quella di WEB_ANPR_GET_SCHEDA_INTESTATARIO, la stessa che
// restituiva il vecchio server: il suo campo ERRORE dice se ANPR ha trovato
// la persona. Un lavoro fallito dopo l'ultimo tentativo (Stesei fermo)
// risponde 502 con il motivo.
//
// Il comune deve essere fra quelli dell'operatore (USR_TMP_COMUNI): il
// lavoro gira poi con la sua identita', ma il controllo si fa qui, prima di
// accodare, perche' il gestore non ha modo di rispondere 403.

interface

uses
  System.SysUtils,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller,
  Queue.Service;

type
  [MVCPath('/api/wt/anpr')]
  [MVCDoc('Ricerca anagrafica su ANPR attraverso il gateway Stesei')]
  TWTAnprController = class(TBaseController)
  private
    procedure RispondiLavoro(Connessione: TFDConnection; const Lavoro: TCodaLavoro);
    function LeggiScheda(Connessione: TFDConnection; const IdRichiesta: Int64): TJSONObject;
  public
    [MVCPath('/ricerche')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Accoda la ricerca di un codice fiscale e ne attende l''esito per qualche secondo')]
    procedure Ricerca;

    [MVCPath('/ricerche/lavori/($idLavoro)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Stato di una ricerca accodata; a lavoro concluso, la scheda')]
    procedure StatoRicerca(const idLavoro: Int64);
  end;

implementation

uses
  App.Config,
  App.Profile,
  Json.Values,
  FiredacHelper,
  WT.Anpr.Gestore;

function DescrizioneStato(const Stato: string): string;
begin
  if Stato = 'A' then
    Result := 'in coda'
  else
    if Stato = 'L' then
      Result := 'in lavorazione'
    else
      if Stato = 'C' then
        Result := 'completato'
      else
        if Stato = 'F' then
          Result := 'fallito'
        else
          Result := Stato;
end;

{ TWTAnprController }

function TWTAnprController.LeggiScheda(Connessione: TFDConnection; const IdRichiesta: Int64): TJSONObject;
var
  Query: TFDQuery;
begin
  Query := CreaQuery(Connessione, 'SELECT * FROM WEB_ANPR_GET_SCHEDA_INTESTATARIO(:ID_SESSIONE_WEB, :ID_ANPR_RICHIESTA)');
  try
    Query.ParamByName('ID_SESSIONE_WEB').AsLargeInt := IdSessione;
    Query.ParamByName('ID_ANPR_RICHIESTA').AsLargeInt := IdRichiesta;
    Query.Open;

    if Query.IsEmpty then
      Result := TJSONObject.Create
    else
      Result := Query.RecordToJSON({ encodeBlobs } True);
  finally
    FreeAndNil(Query);
  end;
end;

procedure TWTAnprController.RispondiLavoro(Connessione: TFDConnection; const Lavoro: TCodaLavoro);
var
  Risposta: TJSONObject;
  IdRichiesta: Int64;
  StatoHttp: Integer;
begin
  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('idLavoro', TJSONNumber.Create(Lavoro.IdCoda));
    Risposta.AddPair('stato', DescrizioneStato(Lavoro.Stato));

    if Lavoro.Stato = 'C' then
    begin
      IdRichiesta := IdRichiestaDaEsito(Lavoro.Esito);
      Risposta.AddPair('idAnprRichiesta', TJSONNumber.Create(IdRichiesta));
      Risposta.AddPair('scheda', LeggiScheda(Connessione, IdRichiesta));
      StatoHttp := HTTP_STATUS.OK;
    end
    else
      if Lavoro.Stato = 'F' then
      begin
        Risposta.AddPair('messaggio', Lavoro.Esito);
        StatoHttp := HTTP_STATUS.BadGateway;
      end
      else
      begin
        // Ancora in coda o in lavorazione: l'esito, se c'e', e' il motivo
        // dell'ultimo tentativo fallito (Stesei non raggiungibile).
        if not Lavoro.Esito.IsEmpty then
          Risposta.AddPair('ultimoErrore', Lavoro.Esito);

        Risposta.AddPair('tentativi', TJSONNumber.Create(Lavoro.Tentativi));
        Risposta.AddPair('rileggi', Format('/api/wt/anpr/ricerche/lavori/%d', [Lavoro.IdCoda]));
        StatoHttp := HTTP_STATUS.Accepted;
      end;

    RenderTestoJson(StatoHttp, Risposta);
  finally
    FreeAndNil(Risposta);
  end;
end;

procedure TWTAnprController.Ricerca;
var
  Corpo: TJSONObject;
  Belfiore: string;
  CodiceFiscale: string;
  Contenuto: TJSONObject;
  Connessione: TFDConnection;
  IdCoda: Int64;
  Lavoro: TCodaLavoro;
begin
  Corpo := CorpoJson;
  try
    Belfiore := JsonStr(Corpo, 'belfiore').Trim.ToUpper;
    CodiceFiscale := JsonStr(Corpo, 'codiceFiscale').Trim.ToUpper;

    if Belfiore.IsEmpty or CodiceFiscale.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Comune (belfiore) e codice fiscale sono obbligatori.');

    if not TAppProfiles.Corrente.AmbitoAmmesso(Belfiore, 0) then
      raise EMVCException.Create(HTTP_STATUS.Forbidden, Format('Il comune %s non e'' fra quelli abilitati per l''utente.', [Belfiore]));

    Contenuto := TJSONObject.Create;
    try
      Contenuto.AddPair('userId', TJSONNumber.Create(UserId));
      Contenuto.AddPair('idSessione', TJSONNumber.Create(IdSessione));
      Contenuto.AddPair('userName', UserName);
      Contenuto.AddPair('belfiore', Belfiore);
      Contenuto.AddPair('codiceFiscale', CodiceFiscale);
      Contenuto.AddPair('origine', OrigineSportello);
      Contenuto.AddPair('idIntestatario', TJSONNumber.Create(JsonInt64(Corpo, 'idIntestatario')));
      Contenuto.AddPair('motivo', JsonStr(Corpo, 'motivo', 'Ricerca Anagrafe'));

      Connessione := PrendiConnessione;
      try
        ApriTransazione(Connessione);
        IdCoda := TCoda.Accoda(Connessione, TipoCodaAnpr, Contenuto);
        Conferma(Connessione);

        TCodaElaboratore.Sveglia;
        Lavoro := TCoda.Attendi(Connessione, IdCoda, Cardinal(TAppConfig.Instance.Coda.AttesaRispostaSecondi) * 1000);
        RispondiLavoro(Connessione, Lavoro);
      finally
        RilasciaConnessione(Connessione);
      end;
    finally
      FreeAndNil(Contenuto);
    end;
  finally
    FreeAndNil(Corpo);
  end;
end;

procedure TWTAnprController.StatoRicerca(const idLavoro: Int64);
var
  Connessione: TFDConnection;
  Lavoro: TCodaLavoro;
  Valore: TJSONValue;
  Proprietario: Int64;
begin
  Connessione := PrendiConnessione;
  try
    Lavoro := TCoda.Leggi(Connessione, idLavoro);

    // Chi chiede deve essere chi ha accodato: l'identificativo del lavoro e'
    // un numero progressivo, e senza questo controllo chiunque potrebbe
    // leggere le ricerche degli altri.
    Proprietario := 0;

    if Lavoro.Trovato and SameText(Lavoro.Tipo, TipoCodaAnpr) then
    begin
      Valore := TJSONObject.ParseJSONValue(Lavoro.Contenuto);
      try
        if Valore is TJSONObject then
          Proprietario := JsonInt64(TJSONObject(Valore), 'userId');
      finally
        FreeAndNil(Valore);
      end;
    end;

    if (Proprietario = 0) or (Proprietario <> UserId) then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Ricerca ANPR non trovata.');

    RispondiLavoro(Connessione, Lavoro);
  finally
    RilasciaConnessione(Connessione);
  end;
end;

end.
