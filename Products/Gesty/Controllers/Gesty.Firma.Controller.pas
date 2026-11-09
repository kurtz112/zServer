// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-12
// ---------------------------------------------------------------------------
unit Gesty.Firma.Controller;

// Firma remota di un documento di Gesty chiesta dal web.
//
// POST /api/firma/registrazioni
//   corpo {"idObjectFile": 123, "tipoDocumento": "CON"}
//   crea la registrazione di firma in stato A (dal web non c'e'
//   approvazione interna), con i firmatari ricavati dal database, e accoda
//   il lavoro FIRMA: l'invio al fornitore lo fa la coda
//   (Gesty.Firma.Gestore). Risponde 202 con l'identificativo della
//   registrazione. Il client non sceglie i firmatari.
// GET /api/firma/registrazioni/{id}
//   stato della registrazione; a firma conclusa, il documento firmato si
//   scarica con GET /api/files/{idObjectFileFirmato}.
//
// L'ente (ID_TENANT) e' quello dell'oggetto a cui appartiene il documento:
// per un incarico l'ente del progetto. Lo dice OBJ_FILES_FIRMA_ENTE_GET, con
// gli stessi rami di OBJ_FILES_FIRMA_FIRMATARI_GET; una classe che li' non
// ha firmatari non ha neppure un ente, e la firma non e' disponibile.
//
// Tutto avviene in una transazione: se i firmatari mancano o la pratica e'
// gia' in corso (OBJ_FILES_FIRMA_REGISTRAZIONE_ADD ne ammette una sola
// attiva per oggetto e tipo), non resta niente sul database.
//
// Il documento deve stare nel perimetro dell'utente: lo dice
// PercorsoFile del profilo, la stessa verifica di GET /api/files.

interface

uses
  System.SysUtils,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller;

type
  [MVCPath('/api/firma')]
  [MVCDoc('Firma remota dei documenti attraverso la coda')]
  TGestyFirmaController = class(TBaseController)
  private
    function EnteDellOggetto(Connessione: TFDConnection; const Oid: Int64): Int64;
    function FornitoreAttivo(Connessione: TFDConnection; const IdEnte: Int64): string;
    function OidDelFile(Connessione: TFDConnection; const IdObjectFile: Int64): Int64;
    procedure VerificaPerimetro(const IdObjectFile: Int64);
  public
    [MVCPath('/registrazioni')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Crea la registrazione di firma di un documento e accoda l''invio al fornitore')]
    procedure Registra;

    [MVCPath('/registrazioni/($idFirmaRegistrazione)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Stato di una registrazione di firma')]
    procedure Stato(const idFirmaRegistrazione: Int64);
  end;

implementation

uses
  FireDAC.Stan.Param,
  App.Profile,
  Json.Values,
  Queue.Service,
  zDocumentale.Firma.Types,
  Gesty.Firma.Gestore;

const
  // Richiesta corretta ma non eseguibile: oggetto senza ente o senza
  // firmatari, fornitore non attivo.
  StatoNonEseguibile = 422;

function DescrizioneStato(const Stato: string): string;
begin
  if Stato = FIRMA_STATO_INSERITA then
    Result := 'inserita'
  else
    if Stato = FIRMA_STATO_APPROVATA then
      Result := 'in attesa di invio'
    else
      if Stato = FIRMA_STATO_IN_FIRMA then
        Result := 'inviata, in attesa dei firmatari'
      else
        if Stato = FIRMA_STATO_FIRMATA then
          Result := 'firmata'
        else
          if Stato = FIRMA_STATO_RESPINTA then
            Result := 'respinta'
          else
            if Stato = FIRMA_STATO_SCADUTA then
              Result := 'scaduta'
            else
              Result := Stato;
end;

{ TGestyFirmaController }

procedure TGestyFirmaController.VerificaPerimetro(const IdObjectFile: Int64);
begin
  if TAppProfiles.Corrente.PercorsoFile(IdObjectFile, IdSessione).IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Documento non trovato.');
end;

function TGestyFirmaController.OidDelFile(Connessione: TFDConnection; const IdObjectFile: Int64): Int64;
var
  Query: TFDQuery;
begin
  Query := CreaQuery(Connessione, 'SELECT OBJ_FILES.OID FROM OBJ_FILES WHERE OBJ_FILES.ID_OBJECT_FILE = :ID_OBJECT_FILE');
  try
    Query.ParamByName('ID_OBJECT_FILE').AsLargeInt := IdObjectFile;
    Query.Open;
    Result := Query.FieldByName('OID').AsLargeInt;
  finally
    FreeAndNil(Query);
  end;
end;

// R-058 - 2026-10-12: la regola sta in OBJ_FILES_FIRMA_ENTE_GET, la stessa
// che usa Gesty desktop (Documentazione.Bridge.Firma): i due canali ricavano
// sempre lo stesso ente. 0 = oggetto senza ente, firma non disponibile.
// Procedura eseguibile: ExecProc, non una SELECT.
function TGestyFirmaController.EnteDellOggetto(Connessione: TFDConnection; const Oid: Int64): Int64;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaStoredProc(Connessione, 'OBJ_FILES_FIRMA_ENTE_GET');
  try
    Procedura.ParamByName('OID').AsLargeInt := Oid;
    Procedura.ParamByName('ID_OBJECT_FILE').Clear;
    Procedura.ExecProc;
    if Procedura.ParamByName('ID_ENTE').IsNull then
      Result := 0
    else
      Result := Procedura.ParamByName('ID_ENTE').AsLargeInt;
  finally
    FreeAndNil(Procedura);
  end;
end;

function TGestyFirmaController.FornitoreAttivo(Connessione: TFDConnection; const IdEnte: Int64): string;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaStoredProc(Connessione, 'OBJ_FILES_FIRMA_CONFIGURAZIONE_GET');
  try
    Procedura.ParamByName('ID_TENANT').AsLargeInt := IdEnte;
    Procedura.ExecProc;

    Result := '';

    if Procedura.ParamByName('ATTIVO').AsBoolean then
      Result := Procedura.ParamByName('FORNITORE').AsString;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TGestyFirmaController.Registra;
var
  Corpo: TJSONObject;
  IdObjectFile: Int64;
  TipoDocumento: string;
  Connessione: TFDConnection;
  Oid: Int64;
  IdEnte: Int64;
  Fornitore: string;
  Procedura: TFDStoredProc;
  IdFirmaRegistrazione: Int64;
  Firmatari: TArray<TzFirmaFirmatario>;
  Firmatario: TzFirmaFirmatario;
  Contenuto: TJSONObject;
  IdCoda: Int64;
  Risposta: TJSONObject;
begin
  Corpo := CorpoJson;
  try
    IdObjectFile := JsonInt64(Corpo, 'idObjectFile');
    TipoDocumento := JsonStr(Corpo, 'tipoDocumento').Trim.ToUpper;
  finally
    FreeAndNil(Corpo);
  end;

  if IdObjectFile <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Il documento (idObjectFile) e'' obbligatorio.');

  VerificaPerimetro(IdObjectFile);

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Oid := OidDelFile(Connessione, IdObjectFile);
      IdEnte := EnteDellOggetto(Connessione, Oid);

      if IdEnte <= 0 then
        raise EMVCException.Create(StatoNonEseguibile, 'La firma non e'' disponibile per questo documento: l''oggetto non ha un ente.');

      Fornitore := FornitoreAttivo(Connessione, IdEnte);

      if Fornitore.IsEmpty then
        raise EMVCException.Create(StatoNonEseguibile, Format('Nessun fornitore di firma attivo per l''ente %d.', [IdEnte]));

      Procedura := CreaStoredProc(Connessione, 'OBJ_FILES_FIRMA_REGISTRAZIONE_ADD');
      try
        Procedura.ParamByName('ID_TENANT').AsLargeInt := IdEnte;
        Procedura.ParamByName('FORNITORE').AsString := Fornitore;
        Procedura.ParamByName('OID').AsLargeInt := Oid;
        Procedura.ParamByName('ID_OBJECT_FILE').AsLargeInt := IdObjectFile;
        Procedura.ParamByName('STATO').AsString := FIRMA_STATO_APPROVATA;

        if TipoDocumento.IsEmpty then
          Procedura.ParamByName('TIPO_DOCUMENTO').Clear
        else
          Procedura.ParamByName('TIPO_DOCUMENTO').AsString := TipoDocumento;

        Procedura.ParamByName('ID_FIRMA_CREDENZIALE').Clear;
        Procedura.ParamByName('ID_RESPONSABILE_PROCEDIMENTO').Clear;
        Procedura.ParamByName('USER_ID').AsLargeInt := UserId;
        Procedura.ExecProc;
        IdFirmaRegistrazione := Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt;
      finally
        FreeAndNil(Procedura);
      end;

      Firmatari := LeggiFirmatari(Connessione, IdFirmaRegistrazione, Oid, TipoDocumento);

      if Length(Firmatari) = 0 then
        raise EMVCException.Create(StatoNonEseguibile, 'La firma non e'' disponibile per questo documento: nessun firmatario.');

      // Come Gesty desktop: i firmatari restano nello storico della
      // registrazione. Segnaposti e firme remote non hanno colonne, e il
      // gestore li rilegge dalle procedure al momento dell'invio.
      Procedura := CreaStoredProc(Connessione, 'OBJ_FILES_FIRMA_FIRMATARIO_ADD');
      try
        for Firmatario in Firmatari do
        begin
          Procedura.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
          Procedura.ParamByName('RUOLO').AsString := Firmatario.Ruolo;
          Procedura.ParamByName('COGNOME').AsString := Firmatario.Cognome;
          Procedura.ParamByName('NOME').AsString := Firmatario.Nome;
          Procedura.ParamByName('EMAIL').AsString := Firmatario.Email;
          Procedura.ParamByName('TELEFONO').AsString := Firmatario.Telefono;
          Procedura.ExecProc;
        end;
      finally
        FreeAndNil(Procedura);
      end;

      Contenuto := TJSONObject.Create;
      try
        Contenuto.AddPair('idFirmaRegistrazione', TJSONNumber.Create(IdFirmaRegistrazione));
        Contenuto.AddPair('userId', TJSONNumber.Create(UserId));
        Contenuto.AddPair('idSessione', TJSONNumber.Create(IdSessione));
        Contenuto.AddPair('userName', UserName);
        IdCoda := TCoda.Accoda(Connessione, TipoCodaFirma, Contenuto);
      finally
        FreeAndNil(Contenuto);
      end;

      Conferma(Connessione);
    except
      Annulla(Connessione);
      raise;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  TCodaElaboratore.Sveglia;

  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('idFirmaRegistrazione', TJSONNumber.Create(IdFirmaRegistrazione));
    Risposta.AddPair('idLavoro', TJSONNumber.Create(IdCoda));
    Risposta.AddPair('stato', FIRMA_STATO_APPROVATA);
    Risposta.AddPair('descrizioneStato', DescrizioneStato(FIRMA_STATO_APPROVATA));
    Risposta.AddPair('firmatari', TJSONNumber.Create(Length(Firmatari)));
    Risposta.AddPair('rileggi', Format('/api/firma/registrazioni/%d', [IdFirmaRegistrazione]));
    RenderTestoJson(HTTP_STATUS.Accepted, Risposta);
  finally
    FreeAndNil(Risposta);
  end;
end;

procedure TGestyFirmaController.Stato(const idFirmaRegistrazione: Int64);
var
  Connessione: TFDConnection;
  Query: TFDQuery;
  Risposta: TJSONObject;
  IdObjectFile: Int64;

  procedure AggiungiId(const Nome, Campo: string);
  begin
    if Query.FieldByName(Campo).IsNull then
      Risposta.AddPair(Nome, TJSONNull.Create)
    else
      Risposta.AddPair(Nome, TJSONNumber.Create(Query.FieldByName(Campo).AsLargeInt));
  end;

begin
  Risposta := nil;
  Connessione := PrendiConnessione;
  try
    Query := CreaQuery(Connessione,
      'SELECT OBJ_FILES_FIRMA_REGISTRAZIONI.STATO, OBJ_FILES_FIRMA_REGISTRAZIONI.STATO_ESTERNO, ' +
      'OBJ_FILES_FIRMA_REGISTRAZIONI.TIPO_DOCUMENTO, OBJ_FILES_FIRMA_REGISTRAZIONI.ID_OBJECT_FILE, ' +
      'OBJ_FILES_FIRMA_REGISTRAZIONI.ID_OBJECT_FILE_FIRMATO, OBJ_FILES_FIRMA_REGISTRAZIONI.ID_OBJECT_FILE_AUDIT, ' +
      'OBJ_FILES_FIRMA_REGISTRAZIONI.ID_DOCUMENTO_ESTERNO, OBJ_FILES_FIRMA_REGISTRAZIONI.MESSAGGIO, ' +
      'OBJ_FILES_FIRMA_REGISTRAZIONI.TENTATIVI ' +
      'FROM OBJ_FILES_FIRMA_REGISTRAZIONI ' +
      'WHERE OBJ_FILES_FIRMA_REGISTRAZIONI.ID_FIRMA_REGISTRAZIONE = :ID_FIRMA_REGISTRAZIONE');
    try
      Query.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := idFirmaRegistrazione;
      Query.Open;

      if Query.IsEmpty then
        raise EMVCException.Create(HTTP_STATUS.NotFound, 'Registrazione di firma non trovata.');

      // L'identificativo e' progressivo: senza il controllo del perimetro
      // chiunque leggerebbe le pratiche degli altri. Fuori perimetro e
      // inesistente rispondono allo stesso modo.
      IdObjectFile := Query.FieldByName('ID_OBJECT_FILE').AsLargeInt;

      if TAppProfiles.Corrente.PercorsoFile(IdObjectFile, IdSessione).IsEmpty then
        raise EMVCException.Create(HTTP_STATUS.NotFound, 'Registrazione di firma non trovata.');

      Risposta := TJSONObject.Create;
      Risposta.AddPair('idFirmaRegistrazione', TJSONNumber.Create(idFirmaRegistrazione));
      Risposta.AddPair('stato', Query.FieldByName('STATO').AsString);
      Risposta.AddPair('descrizioneStato', DescrizioneStato(Query.FieldByName('STATO').AsString));
      Risposta.AddPair('statoEsterno', Query.FieldByName('STATO_ESTERNO').AsString);
      Risposta.AddPair('tipoDocumento', Query.FieldByName('TIPO_DOCUMENTO').AsString);
      AggiungiId('idObjectFile', 'ID_OBJECT_FILE');
      AggiungiId('idObjectFileFirmato', 'ID_OBJECT_FILE_FIRMATO');
      AggiungiId('idObjectFileAudit', 'ID_OBJECT_FILE_AUDIT');
      Risposta.AddPair('idBusta', Query.FieldByName('ID_DOCUMENTO_ESTERNO').AsString);
      Risposta.AddPair('messaggio', Query.FieldByName('MESSAGGIO').AsString);
      Risposta.AddPair('tentativi', TJSONNumber.Create(Query.FieldByName('TENTATIVI').AsInteger));
    finally
      FreeAndNil(Query);
    end;

    RenderTestoJson(HTTP_STATUS.OK, Risposta);
  finally
    FreeAndNil(Risposta);
    RilasciaConnessione(Connessione);
  end;
end;

end.
