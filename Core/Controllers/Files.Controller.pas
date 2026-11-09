// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-03
// ---------------------------------------------------------------------------
unit Files.Controller;

// Z5 - Trasmissione dei file.
//
// Prima nessun controller riceveva file: la scheda Allegati del portale non
// aveva dove mandare i documenti.
//
// Il controller sta nel nucleo perche' il documentale e' lo stesso impianto
// zPack nei due prodotti: OBJ_FILES, OBJ_CLASSES, e la procedura
// OBJ_FILES_ADD che registra la riga e restituisce il percorso in cui
// scrivere i byte. Cambia solo la funzione che ricalcola quel percorso per
// un file gia registrato, e quella la chiede al profilo.
//
// Dove finisce il file non lo decide zServer: OBJ_FILES_ADD compone il
// percorso a partire da OBJ_CLASSES.FOLDER e FILE_PREFIX della classe
// dell'oggetto. Il processo del server deve avere il permesso di scrittura
// su quella cartella.
//
// L'OID identifica l'oggetto a cui il file si allega e porta con se' la
// classe documentale: il percorso della richiesta non la ripete, cosi' non
// si puo' spedire una coppia classe/oggetto incoerente.
//
// Chi puo' vedere o annullare un file lo decide il profilo: PercorsoFile
// riceve la sessione e restituisce un percorso vuoto per un file fuori dal
// perimetro dell'utente. Scarico e annullamento lo chiedono per primo, e a
// un file fuori perimetro rispondono 404 come a un file inesistente: con un
// 403 chi prova gli identificativi in sequenza saprebbe quali esistono.
//
// Il tipo si controlla due volte: l'estensione contro documenti.tipiAmmessi
// e i primi byte contro la firma attesa per quell'estensione (Files.Signature).
//
// I parametri facoltativi del caricamento (tipoAllegato, tipologiaDocumentale,
// profiloDocumentale) si leggono solo dall'indirizzo. ParamByName di
// DelphiMVCFramework li cercherebbe anche fra i campi del corpo: su una
// richiesta multipart questo decodifica come testo l'intero corpo, e i byte
// di un PDF o di un'immagine fanno sollevare EEncodingError (500).

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller,
  Data.Service;

type

  [MVCPath('/api/files')]
  [MVCDoc('Allegati: ricezione, scarico e annullamento')]
  TFilesController = class(TBaseController)
  private
    function CalcolaSha256(Contenuto: TStream): string;
    procedure VerificaAmmissibilita(const NomeFile: string; Contenuto: TStream);
    function PercorsoNelPerimetro(const IdObjectFile: Int64): string;
    procedure ScriviFile(Contenuto: TStream; const PercorsoCompleto: string);
    function ParametroIndirizzo(const Nome: string): string;
    function TipoContenuto(const PercorsoCompleto: string): string;
  public
    [MVCPath('/($oid)')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Riceve un file e lo affida al documentale, restituendo ID_OBJECT_FILE')]
    [MVCSwagSummary('Allegati', 'Carica un allegato', 'default')]
    [MVCSwagParam(plPath, 'oid', 'OID dell''oggetto a cui allegare il file', ptInteger, true)]
    [MVCSwagResponses(201, 'File registrato')]
    [MVCSwagResponses(400, 'File assente, troppo grande, di tipo non ammesso o con un contenuto diverso dal tipo dichiarato')]
    [MVCSwagResponses(401, 'Non autorizzato')]
    procedure Carica(oid: Int64);

    [MVCPath('/($idObjectFile)')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Restituisce il contenuto del file')]
    [MVCSwagSummary('Allegati', 'Scarica un allegato', 'default')]
    [MVCSwagParam(plPath, 'idObjectFile', 'Identificativo del file', ptInteger, true)]
    [MVCSwagResponses(200, 'Contenuto del file')]
    [MVCSwagResponses(404, 'File non trovato, annullato o fuori dal perimetro dell''utente')]
    procedure Scarica(idObjectFile: Int64);

    [MVCPath('/($idObjectFile)')]
    [MVCHTTPMethod([httpDELETE])]
    [MVCDoc('Annulla logicamente il file (OBJ_FILES.ANNULLATO), senza cancellarlo dal disco')]
    [MVCSwagSummary('Allegati', 'Annulla un allegato', 'default')]
    [MVCSwagParam(plPath, 'idObjectFile', 'Identificativo del file', ptInteger, true)]
    [MVCSwagResponses(200, 'File annullato')]
    [MVCSwagResponses(404, 'File non trovato o fuori dal perimetro dell''utente')]
    procedure AnnullaFile(idObjectFile: Int64);
  end;

implementation

uses
  System.IOUtils,
  System.Hash,
  Web.HTTPApp,
  App.Config,
  App.Profile,
  Json.Values,
  Files.Signature;

{ TFilesController }

function TFilesController.ParametroIndirizzo(const Nome: string): string;
begin
  // Solo la query string: i campi del corpo multipart non si toccano (vedi
  // l'intestazione della unit).
  Result := string(Context.Request.RawWebRequest.QueryFields.Values[Nome]).Trim;
end;

function TFilesController.TipoContenuto(const PercorsoCompleto: string): string;
var
  Estensione: string;
begin
  Estensione := TPath.GetExtension(PercorsoCompleto).ToLower;
  if Estensione = '.pdf' then
    Result := 'application/pdf'
  else if (Estensione = '.jpg') or (Estensione = '.jpeg') then
    Result := 'image/jpeg'
  else if Estensione = '.png' then
    Result := 'image/png'
  else if Estensione = '.txt' then
    Result := 'text/plain; charset=utf-8'
  else
    Result := 'application/octet-stream';
end;

function TFilesController.CalcolaSha256(Contenuto: TStream): string;
var
  PosizioneIniziale: Int64;
begin
  PosizioneIniziale := Contenuto.Position;
  try
    Contenuto.Position := 0;
    Result := THashSHA2.GetHashString(Contenuto, THashSHA2.TSHA2Version.SHA256);
  finally
    Contenuto.Position := PosizioneIniziale;
  end;
end;

procedure TFilesController.VerificaAmmissibilita(const NomeFile: string; Contenuto: TStream);
var
  Documenti: TDocumentiConfig;
  Dimensione: Int64;
begin
  Documenti := TAppConfig.Instance.Documenti;
  Dimensione := Contenuto.Size;

  if NomeFile.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Nome del file non indicato.');

  if Dimensione <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'File vuoto.');

  if Dimensione > Documenti.DimensioneMassimaByte then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('File troppo grande: il limite e %d MB.', [Documenti.DimensioneMassimaMB]));

  if not Documenti.TipoAmmesso(NomeFile) then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Tipo di file non ammesso: %s.', [ExtractFileExt(NomeFile)]));

  case TFirmaFile.Verifica(ExtractFileExt(NomeFile), Contenuto) of
    efNonConforme:
      begin
        Registro.Warn(Format('Carica - rifiutato %s: il contenuto non corrisponde all''estensione', [NomeFile]), 'FilesController');
        raise EMVCException.Create(HTTP_STATUS.BadRequest, Format('Il contenuto del file non corrisponde al tipo %s.', [ExtractFileExt(NomeFile)]));
      end;
    efSenzaFirmaNota:
      // Estensione ammessa dal .json ma senza firma in Files.Signature: passa
      // col solo controllo dell'estensione, e l'avviso dice quale aggiungere.
      Registro.Warn(Format('Carica - %s accettato senza controllo del contenuto: nessuna firma nota per l''estensione %s', [NomeFile, ExtractFileExt(NomeFile)]), 'FilesController');
  end;
end;

function TFilesController.PercorsoNelPerimetro(const IdObjectFile: Int64): string;
begin
  if IdObjectFile <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Identificativo del file non valido.');

  Result := TAppProfiles.Corrente.PercorsoFile(IdObjectFile, IdSessione);

  if Result.Trim.IsEmpty then
  begin
    Registro.Info(Format('File %d inesistente o fuori dal perimetro dell''utente %d', [IdObjectFile, UserId]), 'FilesController');
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'File non trovato.');
  end;
end;

procedure TFilesController.ScriviFile(Contenuto: TStream; const PercorsoCompleto: string);
var
  Cartella: string;
  Destinazione: TFileStream;
begin
  Cartella := ExcludeTrailingPathDelimiter(ExtractFilePath(PercorsoCompleto));

  if not ForceDirectories(Cartella) then
    raise EMVCException.Create(HTTP_STATUS.InternalServerError, Format('Impossibile creare la cartella di destinazione %s.', [Cartella]));

  Destinazione := TFileStream.Create(PercorsoCompleto, fmCreate);
  try
    Contenuto.Position := 0;
    Destinazione.CopyFrom(Contenuto, Contenuto.Size);
  finally
    FreeAndNil(Destinazione);
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  POST /api/files/:oid
  ────────────────────────────────────────────────────────────────────────────── }

procedure TFilesController.Carica(oid: Int64);
var
  Parametri: TParamValues;
  Esito: TJSONObject;
  Risposta: TJSONObject;
  FileRicevuto: TAbstractWebRequestFile;
  NomeOriginale: string;
  Contenuto: TStream;
  Dimensione: Int64;
  IdObjectFile: Int64;
  NomeArchiviato: string;
  PercorsoCompleto: string;
begin
  if oid <= 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'OID dell''oggetto non valido.');

  // Il perimetro prima di leggere il file: l'OID arriva dal browser, e un
  // oggetto fuori perimetro risponde 404 come uno inesistente (stesso motivo
  // di Scarica: con un 403 chi prova gli OID in sequenza saprebbe quali esistono).
  if not TAppProfiles.Corrente.OggettoAmmesso(oid, IdSessione) then
  begin
    Registro.Warn(Format('Carica - oggetto %d fuori dal perimetro dell''utente %d', [oid, UserId]), 'FilesController');
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Oggetto non trovato.');
  end;

  if Context.Request.Files.Count = 0 then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Nessun file nella richiesta: attesa una richiesta a piu'' parti (multipart/form-data).');

  FileRicevuto := Context.Request.Files[0];
  Contenuto := FileRicevuto.Stream;
  NomeOriginale := ExtractFileName(FileRicevuto.FileName);
  Dimensione := Contenuto.Size;

  VerificaAmmissibilita(NomeOriginale, Contenuto);

  Registro.Info(Format('Carica - oggetto %d, file %s, %d byte', [oid, NomeOriginale, Dimensione]), 'FilesController');

  Parametri := TParamValues.Create;
  try
    // L'elenco e' l'unione dei parametri delle due procedure: ciascun
    // prodotto riceve solo quelli che dichiara, gli altri vengono ignorati.
    // WT ricava da se' estensione, tipo e classificazione del file;
    // Gesty vuole anche l'impronta.
    Parametri.Add('OID', oid);
    Parametri.Add('NOME_FILE_ORIGINALE', NomeOriginale);
    Parametri.Add('FILE_SIZE', Dimensione);
    Parametri.Add('SHA256', CalcolaSha256(Contenuto));

    if not ParametroIndirizzo('tipoAllegato').IsEmpty then
      Parametri.Add('TIPO_ALLEGATO', ParametroIndirizzo('tipoAllegato'));

    if not ParametroIndirizzo('tipologiaDocumentale').IsEmpty then
      Parametri.Add('TIPOLOGIA_DOCUMENTALE', ParametroIndirizzo('tipologiaDocumentale'));

    if not ParametroIndirizzo('profiloDocumentale').IsEmpty then
      Parametri.Add('PROFILO_DOCUMENTALE', ParametroIndirizzo('profiloDocumentale'));

    Esito := TDataService.ExecuteStoredProc('OBJ_FILES_ADD', Parametri);
    try
      IdObjectFile := JsonInt64(Esito, 'ID_OBJECT_FILE');
      NomeArchiviato := JsonStr(Esito, 'FILE_NAME');
      PercorsoCompleto := JsonStr(Esito, 'FULL_FILE_NAME');
    finally
      FreeAndNil(Esito);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  if (IdObjectFile <= 0) or PercorsoCompleto.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Il documentale non ha restituito il percorso in cui scrivere il file.');

  // La riga e' gia confermata da TDataService: se la scrittura del file non
  // riesce, la riga resta e il file no. Meglio dell'inverso — un file senza
  // riga sarebbe invisibile — e l'annullamento logico permette di rimediare.
  try
    ScriviFile(Contenuto, PercorsoCompleto);
  except
    on E: Exception do
    begin
      Registro.Error(Format('Carica - riga %d registrata ma file non scritto in %s: %s', [IdObjectFile, PercorsoCompleto, E.Message]), 'FilesController');
      raise;
    end;
  end;

  Context.Response.CustomHeaders.Values['Location'] := Format('/api/files/%d', [IdObjectFile]);
  Risposta := TJSONObject.Create;
  try
    Risposta.AddPair('success', TJSONBool.Create(True));
    Risposta.AddPair('ID_OBJECT_FILE', TJSONNumber.Create(IdObjectFile));
    Risposta.AddPair('FILE_NAME', NomeArchiviato);
    Risposta.AddPair('NOME_FILE_ORIGINALE', NomeOriginale);
    RenderTestoJson(HTTP_STATUS.Created, Risposta);
  finally
    FreeAndNil(Risposta);
  end;
end;

{ ──────────────────────────────────────────────────────────────────────────────
  GET /api/files/:idObjectFile
  ────────────────────────────────────────────────────────────────────────────── }

procedure TFilesController.Scarica(idObjectFile: Int64);
var
  Parametri: TParamValues;
  Riga: TJSONObject;
  NomeOriginale: string;
  Annullato: Boolean;
  PercorsoCompleto: string;
begin
  // Per primo il perimetro: senza, nome e annullamento direbbero a chiunque
  // che il file esiste.
  PercorsoCompleto := PercorsoNelPerimetro(idObjectFile);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID', idObjectFile);
    Riga :=TDataService.ExecuteQuerySingleRow('SELECT OBJ_FILES.NOME_FILE_ORIGINALE, OBJ_FILES.ANNULLATO FROM OBJ_FILES WHERE OBJ_FILES.ID_OBJECT_FILE = :ID', Parametri, False);
  finally
    FreeAndNil(Parametri);
  end;

  if not Assigned(Riga) then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'File non trovato.');

  try
    NomeOriginale := JsonStr(Riga, 'NOME_FILE_ORIGINALE');
    Annullato := JsonBool(Riga, 'ANNULLATO');
  finally
    FreeAndNil(Riga);
  end;

  if Annullato then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'File annullato.');

  if not TFile.Exists(PercorsoCompleto) then
  begin
    // La riga c'e' ma il file no: e' una incoerenza dell'archivio, non una
    // richiesta sbagliata. Va registrata, altrimenti non se ne accorge nessuno.
    Registro.Error(Format('Scarica - file %d assente su disco: %s', [idObjectFile, PercorsoCompleto]), 'FilesController');
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Contenuto del file non disponibile.');
  end;

  if not NomeOriginale.Trim.IsEmpty then
    Context.Response.CustomHeaders.Values['Content-Disposition'] := Format('attachment; filename="%s"', [NomeOriginale]);

  // Il tipo si ricava dall'estensione e va impostato sul controller: a fine
  // azione il motore riassegna alla risposta il ContentType del controller
  // (application/json), annullando quello passato a SendFile, e il browser non
  // aprirebbe il PDF.
  ContentType := TipoContenuto(PercorsoCompleto);
  TMVCStaticContents.SendFile(PercorsoCompleto, ContentType, Context);
end;

{ ──────────────────────────────────────────────────────────────────────────────
  DELETE /api/files/:idObjectFile

  Annullamento logico: il file resta sul disco e la riga resta in OBJ_FILES.
  Un documentale che cancella davvero non permette di ricostruire la storia,
  e in piu' i file sono spesso coinvolti in conservazione e protocollo.
  ────────────────────────────────────────────────────────────────────────────── }

procedure TFilesController.AnnullaFile(idObjectFile: Int64);
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  // Si annulla solo un file che l'utente potrebbe anche scaricare: il
  // percorso non serve, serve il controllo del perimetro che lo accompagna.
  PercorsoNelPerimetro(idObjectFile);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID', idObjectFile);
    Esito := TDataService.ExecuteUpdate('UPDATE OBJ_FILES SET OBJ_FILES.ANNULLATO = TRUE WHERE OBJ_FILES.ID_OBJECT_FILE = :ID', Parametri);
    try
      Registro.Info(Format('Annulla - file %d annullato da utente %d', [idObjectFile, UserId]), 'FilesController');
    finally
      FreeAndNil(Esito);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  RenderEsito(True);
end;

end.
