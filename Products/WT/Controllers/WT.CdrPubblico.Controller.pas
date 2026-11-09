// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit WT.CdrPubblico.Controller;

// Bacheca pubblica dei centri del riuso (lavoro OUT\20261107-pipa-centri-del-riuso-completamento,
// decisione 1): chi non ha fatto l'accesso vede i beni pubblicati nei comuni di un portale del
// cittadino, con le foto, e per prenotare passa dall'accesso al portale (vetrina del rilascio
// OUT/20261104-pipa-modulo-geco/036).
//
// Le tre azioni sono in TWTProfile.AzioniPubbliche: niente token, quindi niente utente e niente
// perimetro di zServer. Il perimetro lo fanno le procedure CDR_BACHECA_*: solo comuni del portale
// (WEB_CIT_PORTALI_COMUNI), solo beni pubblicati o prenotati di centri attivi, nessun dato di
// persone (cedente e prenotante non escono mai). Il portale si indica con il suo nome
// (WEB_CIT_PORTALI.NOME_CONFIGURAZIONE); senza nome vale l'unico portale dell'installazione, come
// nell'accesso del cittadino.
//
// Un RAISE_ERROR delle procedure (portale o comune non validi) arriva al client come 400 con il
// testo della procedura, tramite TBaseController.OnException.

interface

uses
  System.SysUtils,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Swagger.Commons,
  Base.Controller;

type

  [MVCPath('/api/pubblico/cdr')]
  [MVCDoc('Bacheca pubblica dei centri del riuso, senza accesso')]
  TWTCdrPubblicoController = class(TBaseController)
  private
    function Elenco(const SQL: string; const Parametri: array of string; const Valori: array of string): TJSONArray;
  public
    [MVCPath('/comuni')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Comuni del portale con il numero di beni disponibili: ?portale=<nome> (facoltativo con un solo portale)')]
    [MVCSwagSummary('Riuso', 'Comuni della bacheca del riuso', 'default')]
    [MVCSwagResponses(200, 'Elenco [{ BELFIORE, COMUNE, NUMERO_BENI }]')]
    [MVCSwagResponses(400, 'Portale non indicato o non valido')]
    procedure Comuni;

    [MVCPath('/bacheca')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Beni pubblicati in un comune del portale: ?belfiore=<codice>&portale=<nome>')]
    [MVCSwagSummary('Riuso', 'Bacheca del riuso di un comune', 'default')]
    [MVCSwagResponses(200, 'Elenco dei beni, senza dati di persone')]
    [MVCSwagResponses(400, 'Portale o comune non validi')]
    procedure Bacheca;

    [MVCPath('/bacheca/($codice)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Scheda di un bene con le foto in Base64: ?belfiore=<codice>&portale=<nome>')]
    [MVCSwagSummary('Riuso', 'Scheda di un bene della bacheca del riuso', 'default')]
    [MVCSwagResponses(200, 'Una riga per foto (FOTO in Base64); senza foto una riga con FOTO nullo')]
    [MVCSwagResponses(400, 'Portale o comune non validi')]
    [MVCSwagResponses(404, 'Bene non presente in bacheca')]
    procedure Bene(const codice: string);
  end;

implementation

uses
  System.Variants,
  Data.Service;

const
  // Un belfiore ha 4 caratteri, un codice bene al massimo 24 (CDR_CODICE_BENE): oltre si rifiuta
  // prima di arrivare al database.
  LUNGHEZZA_BELFIORE = 4;
  LUNGHEZZA_MASSIMA_CODICE = 24;
  LUNGHEZZA_MASSIMA_PORTALE = 100;

function TWTCdrPubblicoController.Elenco(const SQL: string; const Parametri: array of string; const Valori: array of string): TJSONArray;
var
  ParametriQuery: TParamValues;
  Indice: Integer;
begin
  ParametriQuery := TParamValues.Create;
  try
    for Indice := Low(Parametri) to High(Parametri) do
      if Valori[Indice].Trim.IsEmpty then
        ParametriQuery.Add(Parametri[Indice], Null)
      else
        ParametriQuery.Add(Parametri[Indice], Valori[Indice].Trim);

    // Nessun utente: la connessione non ha contesto, come per l'accesso del cittadino.
    // Le foto sono BLOB binari: encodeBlobs le restituisce in Base64.
    Result := TDataService.ExecuteQuery(SQL, ParametriQuery, True);
  finally
    FreeAndNil(ParametriQuery);
  end;
end;

function PortaleRichiesto(const Valore: string): string;
begin
  Result := Valore.Trim;
  if Length(Result) > LUNGHEZZA_MASSIMA_PORTALE then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Portale non valido.');
end;

function BelfioreRichiesto(const Valore: string): string;
begin
  Result := Valore.Trim.ToUpper;
  if Length(Result) <> LUNGHEZZA_BELFIORE then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Indica il comune (codice catastale di 4 caratteri).');
end;

procedure TWTCdrPubblicoController.Comuni;
var
  Righe: TJSONArray;
begin
  Righe := Elenco(
    'SELECT CDR_BACHECA_COMUNI.BELFIORE, CDR_BACHECA_COMUNI.COMUNE, CDR_BACHECA_COMUNI.NUMERO_BENI FROM CDR_BACHECA_COMUNI(:PORTALE)',
    ['PORTALE'],
    [PortaleRichiesto(ParamByName('portale'))]);
  try
    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    FreeAndNil(Righe);
  end;
end;

procedure TWTCdrPubblicoController.Bacheca;
var
  Righe: TJSONArray;
begin
  Righe := Elenco(
    'SELECT CDR_BACHECA.CODICE_BENE, CDR_BACHECA.DESCRIZIONE_CATEGORIA, CDR_BACHECA.DESCRIZIONE, CDR_BACHECA.MODELLO, ' +
    'CDR_BACHECA.STATO_USURA, CDR_BACHECA.PESO_KG, CDR_BACHECA.NUMERO_PEZZI, CDR_BACHECA.DENOMINAZIONE_CENTRO, ' +
    'CDR_BACHECA.INDIRIZZO_CENTRO, CDR_BACHECA.DATA_SCADENZA_GIACENZA, CDR_BACHECA.DISPONIBILE, CDR_BACHECA.NUMERO_FOTO ' +
    'FROM CDR_BACHECA(:PORTALE, :BELFIORE)',
    ['PORTALE', 'BELFIORE'],
    [PortaleRichiesto(ParamByName('portale')), BelfioreRichiesto(ParamByName('belfiore'))]);
  try
    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    FreeAndNil(Righe);
  end;
end;

procedure TWTCdrPubblicoController.Bene(const codice: string);
var
  Righe: TJSONArray;
  CodiceBene: string;
begin
  CodiceBene := codice.Trim;
  if CodiceBene.IsEmpty or (Length(CodiceBene) > LUNGHEZZA_MASSIMA_CODICE) then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Codice del bene non valido.');

  Righe := Elenco(
    'SELECT CDR_BACHECA_BENE.CODICE, CDR_BACHECA_BENE.DESCRIZIONE_CATEGORIA, CDR_BACHECA_BENE.DESCRIZIONE, CDR_BACHECA_BENE.MODELLO, ' +
    'CDR_BACHECA_BENE.STATO_USURA, CDR_BACHECA_BENE.PESO_KG, CDR_BACHECA_BENE.NUMERO_PEZZI, CDR_BACHECA_BENE.DENOMINAZIONE_CENTRO, ' +
    'CDR_BACHECA_BENE.INDIRIZZO_CENTRO, CDR_BACHECA_BENE.LATITUDINE, CDR_BACHECA_BENE.LONGITUDINE, ' +
    'CDR_BACHECA_BENE.DATA_SCADENZA_GIACENZA, CDR_BACHECA_BENE.DISPONIBILE, CDR_BACHECA_BENE.NUMERO_FOTO, ' +
    'CDR_BACHECA_BENE.DESCRIZIONE_FOTO, CDR_BACHECA_BENE.FOTO ' +
    'FROM CDR_BACHECA_BENE(:PORTALE, :BELFIORE, :CODICE_BENE)',
    ['PORTALE', 'BELFIORE', 'CODICE_BENE'],
    [PortaleRichiesto(ParamByName('portale')), BelfioreRichiesto(ParamByName('belfiore')), CodiceBene]);
  try
    // Un bene ceduto, ritirato o di un altro comune non c'e' piu' in bacheca: 404, senza dire perche'
    if Righe.Count = 0 then
      raise EMVCException.Create(HTTP_STATUS.NotFound, 'Bene non presente in bacheca.');

    RenderTestoJson(HTTP_STATUS.OK, Righe);
  finally
    FreeAndNil(Righe);
  end;
end;

end.
