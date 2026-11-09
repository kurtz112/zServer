// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit eSignAnyWhere;

// Client delle API v6 di eSignAnyWhere (Namirial) per zServer.
//
// Copia ripulita di Gesty_Group\_Sorgenti\API\eSignAnyWhere\eSignAnyWhere.pas,
// che resta com'e' in Gesty desktop. Le differenze sono volute:
//
// - niente TDataModule ne' .dfm: client, autenticazione e richieste nascono
//   da codice nel costruttore. Il .dfm di Gesty porta un token e l'indirizzo
//   del sistema dimostrativo, e un TDataModule si porta dietro la classe di
//   gruppo VCL;
// - niente token ne' indirizzo predefiniti: li passa chi crea il client,
//   letti dalla configurazione del fornitore sul database;
// - niente VCL, SmartInspect, Application.ExeName e file JSON scritti accanto
//   all'eseguibile: le buste contengono nomi, indirizzi di posta e telefoni
//   dei firmatari, e un server non li lascia in una cartella;
// - un'istanza per lavoro e una risposta per richiesta, invece dell'oggetto
//   globale eSignAnyWhereEngine con una risposta condivisa: i lavori della
//   coda non si passano dati fra loro;
// - lo stato HTTP e' controllato su ogni chiamata (EeSignAnyWhereHttp): in
//   Gesty Upload, Prepare, Envelope e DownloadFiles non lo guardano, e una
//   risposta 401 di DownloadFiles verrebbe salvata come PDF firmato;
// - Validate restituisce davvero l'esito;
// - CercaBusta (envelope/find) cerca una busta per testo, per non reinviarla
//   quando il lavoro riparte dopo un invio riuscito ma non confermato;
// - CollegamentiFirma (envelope/{id}/viewerlinks, 2026-11-07) legge i
//   collegamenti alla pagina di firma dei destinatari, per la firma al banco
//   dei centri del riuso di WT. Gesty non lo chiama.
//
// La costruzione della busta (InitEnvelope, attivita' OTP e firme remote,
// conversione delle firme preparate) e' quella di Gesty, riga per riga.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  REST.Types,
  REST.Client,
  REST.Authenticator.OAuth,
  eSignAnyWhere.classes.PrepareResponse,
  eSignAnyWhere.classes.EnvelopeResponse,
  eSignAnyWhere.classes.Envelope,
  eSignAnyWhere.params;

type
  /// <summary>
  /// Risposta del fornitore con stato HTTP fuori da 2xx, o senza i dati
  /// attesi. StatoHttp e' zero se la chiamata non e' arrivata al fornitore.
  /// </summary>
  EeSignAnyWhereHttp = class(Exception)
  private
    FStatoHttp: Integer;
  public
    constructor CreateStato(const Operazione: string; const StatoHttp: Integer; const Dettaglio: string);
    property StatoHttp: Integer read FStatoHttp;
  end;

  /// <summary>Collegamento alla pagina di firma di un destinatario della busta.</summary>
  TeSignAnyWhereCollegamento = record
    Email: string;
    Collegamento: string;
  end;

  TeSignAnyWhereEngine = class
  private
    FAutenticazione: TOAuth2Authenticator;
    FClient: TRESTClient;
    FBaseUrl: string;
    FParams: TeSignAnyWhereParams;
    FUltimoStatoHttp: Integer;
    FUltimoContenuto: string;
    procedure SetParams(const Value: TeSignAnyWhereParams);

    function NuovaRichiesta(const Risorsa: string; const Metodo: TRESTRequestMethod; Risposta: TRESTResponse): TRESTRequest;
    procedure Esegui(Richiesta: TRESTRequest; Risposta: TRESTResponse; const Operazione: string; const Binaria: Boolean = False);

    procedure InitEnvelope(Envelope: TEnvelope);
    function CreateActivityOTP(PrepareResponse: TPrepareResponse; out Activity: TActivities): Boolean;
    function CreateActivityRemoteSign(PrepareResponse: TPrepareResponse; const PlaceHolder: string; const IdentificativoFirmaRemota: string; out Activity: TActivities): Boolean;
    function ConvertPreparedSignature(preparedSignature: eSignAnyWhere.classes.PrepareResponse.TSignatures): TSignatures;
    function ConvertPreparedRemoteSignature(VisibleSignature: eSignAnyWhere.classes.PrepareResponse.TVisibleSignatures): TVisibleSignatures;

    function Upload(const FileName: string): string;
    function Prepare: TPrepareResponse;
    function Envelope: TEnvelopeResponse;
    function Scarica(const FileId: string): TBytes;
  public
    constructor Create(const BaseUrl, AuthToken: string);
    destructor Destroy; override;

    /// <summary>True se il token e' accettato (authorization/validate).</summary>
    function Validate: Boolean;

    /// <summary>
    /// Carica il PDF, lo prepara e invia la busta con il nome in
    /// Params.EnvelopeName. Restituisce l'identificativo della busta.
    /// </summary>
    function Firma(const FileName: string): string;

    /// <summary>Stato grezzo della busta Params.EnvelopeId.</summary>
    function EnvelopeStatus: string;

    /// <summary>
    /// Scarica firmato e audit della busta Params.EnvelopeId. I due file si
    /// scrivono solo dopo che entrambi sono arrivati: uno scarico a meta' non
    /// lascia un firmato senza audit.
    /// </summary>
    procedure DownloadFiles(const FileNameSigned, FileNameAudit: string);

    /// <summary>
    /// Cerca fra le buste inviate negli ultimi Giorni quella il cui nome
    /// contiene Testo e ne restituisce l'identificativo; vuoto se non c'e'.
    /// </summary>
    function CercaBusta(const Testo: string; const Giorni: Integer): string;

    /// <summary>
    /// Collegamenti alla pagina di firma dei destinatari della busta
    /// Params.EnvelopeId (envelope/{id}/viewerlinks); vuoto se il fornitore
    /// non ne restituisce.
    /// </summary>
    function CollegamentiFirma: TArray<TeSignAnyWhereCollegamento>;

    property BaseUrl: string read FBaseUrl;
    property Params: TeSignAnyWhereParams read FParams write SetParams;

    /// <summary>
    /// Stato HTTP e corpo dell'ultima risposta, per il registro delle
    /// chiamate. Il corpo e' vuoto per gli scarichi binari.
    /// </summary>
    property UltimoStatoHttp: Integer read FUltimoStatoHttp;
    property UltimoContenuto: string read FUltimoContenuto;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils,
  eSignAnyWhere.classes.Prepare,
  eSignAnyWhere.classes.EnvelopeFiles;

const
  // Oltre questa lunghezza il corpo della risposta non entra nel messaggio
  // dell'eccezione, che finisce in ZZ_CODA.ESITO (500 caratteri).
  LunghezzaDettaglio = 300;

{ EeSignAnyWhereHttp }

constructor EeSignAnyWhereHttp.CreateStato(const Operazione: string; const StatoHttp: Integer; const Dettaglio: string);
begin
  FStatoHttp := StatoHttp;

  if Dettaglio.IsEmpty then
    inherited CreateFmt('eSignAnyWhere, %s: risposta HTTP %d', [Operazione, StatoHttp])
  else
    inherited CreateFmt('eSignAnyWhere, %s: risposta HTTP %d: %s', [Operazione, StatoHttp, Dettaglio]);
end;

// Il messaggio d'errore del fornitore, se la risposta e' JSON e lo porta;
// altrimenti l'inizio del corpo.
function DettaglioErrore(const Contenuto: string): string;
var
  Valore: TJSONValue;
  Messaggio: string;
begin
  Result := '';

  Valore := TJSONObject.ParseJSONValue(Contenuto);
  try
    if (Valore is TJSONObject) and TJSONObject(Valore).TryGetValue<string>('Message', Messaggio) then
      Result := Messaggio;
  finally
    FreeAndNil(Valore);
  end;

  if Result.IsEmpty then
    Result := Contenuto;

  if Result.Length > LunghezzaDettaglio then
    Result := Result.Substring(0, LunghezzaDettaglio) + '...';
end;

{ TeSignAnyWhereEngine }

constructor TeSignAnyWhereEngine.Create(const BaseUrl, AuthToken: string);
begin
  inherited Create;

  if BaseUrl.Trim.IsEmpty then
    raise Exception.Create('eSignAnyWhere: indirizzo del servizio non configurato.');

  if AuthToken.Trim.IsEmpty then
    raise Exception.Create('eSignAnyWhere: token di accesso non configurato.');

  FBaseUrl := BaseUrl.Trim;

  FAutenticazione := TOAuth2Authenticator.Create(nil);
  FAutenticazione.AccessToken := AuthToken.Trim;

  FClient := TRESTClient.Create(nil);
  FClient.BaseURL := FBaseUrl;
  FClient.Authenticator := FAutenticazione;
  FClient.Accept := 'application/json, text/plain; q=0.9, text/html;q=0.8,';
  FClient.AcceptCharset := 'utf-8, *;q=0.8';
  FClient.SecureProtocols := [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13];
  FClient.SynchronizedEvents := False;
  // Lo stato HTTP lo controlla Esegui per ogni chiamata, 4xx compresi.
  FClient.RaiseExceptionOn500 := False;

  FParams.Init;
  // Nessun file JSON accanto all'eseguibile: vedi il commento di testa.
  FParams.LogResponse := False;
end;

destructor TeSignAnyWhereEngine.Destroy;
begin
  FreeAndNil(FClient);
  FreeAndNil(FAutenticazione);
  inherited;
end;

procedure TeSignAnyWhereEngine.SetParams(const Value: TeSignAnyWhereParams);
begin
  FParams.Assign(Value);
  FParams.LogResponse := False;
end;

function TeSignAnyWhereEngine.NuovaRichiesta(const Risorsa: string; const Metodo: TRESTRequestMethod; Risposta: TRESTResponse): TRESTRequest;
begin
  Result := TRESTRequest.Create(nil);
  Result.Client := FClient;
  Result.Resource := Risorsa;
  Result.Method := Metodo;
  Result.Response := Risposta;
  Result.SynchronizedEvents := False;
end;

procedure TeSignAnyWhereEngine.Esegui(Richiesta: TRESTRequest; Risposta: TRESTResponse; const Operazione: string; const Binaria: Boolean);
begin
  FUltimoStatoHttp := 0;
  FUltimoContenuto := '';

  Richiesta.Execute;

  FUltimoStatoHttp := Risposta.StatusCode;

  if not Binaria then
    FUltimoContenuto := Risposta.Content;

  if (Risposta.StatusCode < 200) or (Risposta.StatusCode > 299) then
  begin
    if Binaria then
      FUltimoContenuto := Risposta.Content;

    raise EeSignAnyWhereHttp.CreateStato(Operazione, Risposta.StatusCode, DettaglioErrore(Risposta.Content));
  end;
end;

function TeSignAnyWhereEngine.Validate: Boolean;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
begin
  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('authorization/validate', TRESTRequestMethod.rmGET, Risposta);
  try
    Richiesta.Execute;
    FUltimoStatoHttp := Risposta.StatusCode;
    FUltimoContenuto := Risposta.Content;
    Result := (Risposta.StatusCode >= 200) and (Risposta.StatusCode <= 299);
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

function TeSignAnyWhereEngine.ConvertPreparedRemoteSignature(VisibleSignature: eSignAnyWhere.classes.PrepareResponse.TVisibleSignatures): TVisibleSignatures;
begin
  Result := TVisibleSignatures.Create;
  Result.DocumentNumber := VisibleSignature.DocumentNumber;
  Result.UseExternalTimestampServer := VisibleSignature.UseExternalTimestampServer;

  Result.FieldDefinition := TFieldDefinition.Create;
  Result.FieldDefinition.Position.PageNumber := VisibleSignature.FieldDefinition.Position.PageNumber;
  Result.FieldDefinition.Position.X := VisibleSignature.FieldDefinition.Position.X;
  Result.FieldDefinition.Position.Y := VisibleSignature.FieldDefinition.Position.Y;
  Result.FieldDefinition.Size.Height := 50;
  Result.FieldDefinition.Size.Width := 200;

  Result.FieldDefinition.TextFormat.Bold := True;
  Result.FieldDefinition.TextFormat.FontName := 'Times New Roman';
  Result.FieldDefinition.TextFormat.FontSizeInPt := 14;
  Result.FieldDefinition.TextFormat.Italic := False;
end;

function TeSignAnyWhereEngine.Upload(const FileName: string): string;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  Parametro: TRESTRequestParameter;
begin
  Result := '';

  if FileName.IsEmpty then
    raise Exception.Create('eSignAnyWhere: file da caricare non specificato.');

  if not TFile.Exists(FileName) then
    raise Exception.Create('eSignAnyWhere: file da caricare non trovato: ' + FileName);

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('file/upload', TRESTRequestMethod.rmPOST, Risposta);
  try
    Parametro := Richiesta.Params.AddItem;
    Parametro.Name := 'File';
    Parametro.Kind := TRESTRequestParameterKind.pkFILE;
    Parametro.Value := FileName;
    Parametro.ContentTypeStr := 'application/pdf';

    Esegui(Richiesta, Risposta, 'caricamento del PDF');

    if not Risposta.GetSimpleValue('FileId', Result) or Result.IsEmpty then
      raise EeSignAnyWhereHttp.CreateStato('caricamento del PDF, FileId assente', Risposta.StatusCode, DettaglioErrore(Risposta.Content));

    FParams.FileId := Result;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

function TeSignAnyWhereEngine.Prepare: TPrepareResponse;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  PrepareRequest: TPrepareRequest;
  SigStringConfiguration: TSigStringConfigurations;
begin
  Result := nil;

  FParams.CheckFileId;

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('file/prepare', TRESTRequestMethod.rmPOST, Risposta);
  try
    PrepareRequest := TPrepareRequest.Create;
    try
      PrepareRequest.FileIds.Add(FParams.FileId);
      PrepareRequest.ClearAdvancedDocumentTags := True;

      SigStringConfiguration := TSigStringConfigurations.Create;
      SigStringConfiguration.StartPattern := '{{';
      SigStringConfiguration.EndPattern := '}}';
      SigStringConfiguration.ClearSigString := True;
      SigStringConfiguration.SearchEntireWordOnly := True;
      PrepareRequest.SigStringConfigurations.Add(SigStringConfiguration);

      Richiesta.AddBody(PrepareRequest);
    finally
      FreeAndNil(PrepareRequest);
    end;

    Esegui(Richiesta, Risposta, 'preparazione del PDF');

    Result := TPrepareResponse.Create;
    try
      Result.AsJson := Risposta.Content;

      if Result.UnassignedElements.Signatures.Count = 0 then
        raise Exception.Create('eSignAnyWhere: documento non valido, nessun segnaposto di firma trovato.');
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

procedure TeSignAnyWhereEngine.InitEnvelope(Envelope: TEnvelope);
begin
  Envelope.Name := FParams.EnvelopeName;
  Envelope.AddDocumentTimestamp := FParams.AddDocumentTimestamp;
  Envelope.ShareWithTeam := FParams.ShareWithTeam;
  Envelope.ReminderConfiguration.Enabled := FParams.Reminder;
  Envelope.ReminderConfiguration.FirstReminderInDays := FParams.FirstReminderInDays;
  Envelope.ReminderConfiguration.ReminderResendIntervalInDays := FParams.ReminderResendIntervalInDays;
  Envelope.ReminderConfiguration.BeforeExpirationInDays := FParams.BeforeExpirationInDays;
  Envelope.ExpirationConfiguration.ExpirationInSecondsAfterSending := FParams.ExpirationInSecondsAfterSending;

  Envelope.EmailConfiguration.Subject := FParams.EmailConfigurationSubject;
  Envelope.EmailConfiguration.Message := FParams.EmailConfigurationMessage;
end;

function TeSignAnyWhereEngine.ConvertPreparedSignature(preparedSignature: eSignAnyWhere.classes.PrepareResponse.TSignatures): TSignatures;
begin
  Result := TSignatures.Create;
  Result.AllowedSignatureTypes.OneTimePassword.UseExternalSignatureImage := preparedSignature.AllowedSignatureTypes.OneTimePassword.UseExternalSignatureImage;
  Result.DisplayName := preparedSignature.DisplayName;
  Result.DocumentNumber := preparedSignature.DocumentNumber;
  Result.ElementId := preparedSignature.ElementId;

  Result.FieldDefinition.Position.PageNumber := preparedSignature.FieldDefinition.Position.PageNumber;
  Result.FieldDefinition.Position.X := preparedSignature.FieldDefinition.Position.X;
  Result.FieldDefinition.Position.Y := preparedSignature.FieldDefinition.Position.Y;
  Result.FieldDefinition.Size.Height := 50;
  Result.FieldDefinition.Size.Width := 200;

  Result.FieldDefinition.TextFormat.Bold := True;
  Result.FieldDefinition.TextFormat.FontName := 'Times New Roman';
  Result.FieldDefinition.TextFormat.FontSizeInPt := 14;
  Result.FieldDefinition.TextFormat.Italic := False;

  Result.Required := True;
  Result.UseExternalTimestampServer := False;
  Result.TaskConfiguration.BatchGroup := '1';

  Result.AllowedSignatureTypes.OneTimePassword.Preferred := False;
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.DisplayPhoneNumber := False;
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.DisplayName := True;
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.DisplayExtraInformation := True;
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.DisplaySignatureDate := True;
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.FontName := 'Times New Roman';
  Result.AllowedSignatureTypes.OneTimePassword.StampImprintConfiguration.FontSizeInPt := 14;
  Result.AllowedSignatureTypes.OneTimePassword.UseExternalSignatureImage := 'Disabled';
end;

function TeSignAnyWhereEngine.CreateActivityOTP(PrepareResponse: TPrepareResponse; out Activity: TActivities): Boolean;
var
  VisibilityOption: TVisibilityOptions;
  preparedSignature: eSignAnyWhere.classes.PrepareResponse.TSignatures;
begin
  Activity := eSignAnyWhere.classes.Envelope.TActivities.Create;
  try
    VisibilityOption := TVisibilityOptions.Create;
    VisibilityOption.DocumentNumber := 1;
    VisibilityOption.IsHidden := False;
    Activity.VisibilityOptions.Add(VisibilityOption);

    Activity.Action.Sign := TSign.Create;
    Activity.Action.Sign.SequenceMode := FParams.FirmaOTP.SequenceMode;
    Activity.Action.Sign.SigningGroup := FParams.FirmaOTP.SigningGroup;

    Activity.Action.Sign.BatchConfiguration.Mode := 'OptOut';
    Activity.Action.Sign.BatchConfiguration.RequireScrollingOverAllSignaturesBeforeSigning := True;

    Activity.Action.Sign.RecipientConfiguration.AllowAccessAfterFinish := FParams.FirmaOTP.AllowAccessAfterFinish;
    Activity.Action.Sign.RecipientConfiguration.AllowDelegation := FParams.FirmaOTP.AllowDelegation;

    Activity.Action.Sign.RecipientConfiguration.IncludedEmailAppLinks.AndroId := FParams.FirmaOTP.AppLinks_AndroId;
    Activity.Action.Sign.RecipientConfiguration.IncludedEmailAppLinks.IOS := FParams.FirmaOTP.AppLinks_IOS;
    Activity.Action.Sign.RecipientConfiguration.IncludedEmailAppLinks.Windows := FParams.FirmaOTP.AppLinks_Windows;

    Activity.Action.Sign.RecipientConfiguration.RequireViewContentBeforeFormFilling := FParams.FirmaOTP.RequireViewContentBeforeFormFilling;
    Activity.Action.Sign.RecipientConfiguration.ContactInformation.LanguageCode := FParams.FirmaOTP.LanguageCode;
    Activity.Action.Sign.RecipientConfiguration.NotificationChannel := FParams.FirmaOTP.NotificationChannel;

    // Come in Gesty: givenName riceve il cognome e surName il nome.
    // Lasciato identico per non cambiare le buste rispetto al desktop.
    Activity.Action.Sign.RecipientConfiguration.ContactInformation.givenName := FParams.FirmaOTP.Cognome;
    Activity.Action.Sign.RecipientConfiguration.ContactInformation.surName := FParams.FirmaOTP.Nome;
    Activity.Action.Sign.RecipientConfiguration.ContactInformation.email := FParams.FirmaOTP.email;
    Activity.Action.Sign.RecipientConfiguration.ContactInformation.phoneNumber := FParams.FirmaOTP.Telefono;

    for preparedSignature in PrepareResponse.UnassignedElements.Signatures do
      if preparedSignature.ElementId.StartsWith(FParams.FirmaOTP.PlaceHolder, True) then
        Activity.Action.Sign.Elements.Signatures.Add(ConvertPreparedSignature(preparedSignature));

    Result := Activity.Action.Sign.Elements.Signatures.Count > 0;

    if not Result then
      FreeAndNil(Activity);
  except
    FreeAndNil(Activity);
    raise;
  end;
end;

function TeSignAnyWhereEngine.CreateActivityRemoteSign(PrepareResponse: TPrepareResponse; const PlaceHolder: string; const IdentificativoFirmaRemota: string; out Activity: TActivities): Boolean;
var
  VisibilityOption: TVisibilityOptions;
  preparedSignature: eSignAnyWhere.classes.PrepareResponse.TSignatures;
  preparedActivity: eSignAnyWhere.classes.PrepareResponse.TActivities;
  VisibleSignature: eSignAnyWhere.classes.PrepareResponse.TVisibleSignatures;
begin
  Activity := eSignAnyWhere.classes.Envelope.TActivities.Create;
  try
    VisibilityOption := TVisibilityOptions.Create;
    VisibilityOption.DocumentNumber := 1;
    VisibilityOption.IsHidden := False;
    Activity.VisibilityOptions.Add(VisibilityOption);

    Activity.Action.SignAutomatic := TSignAutomatic.Create;
    Activity.Action.SignAutomatic.ProfileId := IdentificativoFirmaRemota;
    Activity.Action.SignAutomatic.RenderingLanguageCode := 'IT';

    // Identico a Gesty, compreso il ciclo esterno sulle firme non assegnate,
    // che ripete la stessa ricerca per ognuna e aggiunge piu' volte le stesse
    // firme visibili: le buste devono restare uguali a quelle del desktop.
    for preparedSignature in PrepareResponse.UnassignedElements.Signatures do
      for preparedActivity in PrepareResponse.Activities do
        if preparedActivity.Action.SignAutomatic <> nil then
          for VisibleSignature in preparedActivity.Action.SignAutomatic.VisibleSignatures do
            if VisibleSignature.id.StartsWith(PlaceHolder, True) then
              Activity.Action.SignAutomatic.VisibleSignatures.Add(ConvertPreparedRemoteSignature(VisibleSignature));

    // Come in Gesty, l'attivita' di firma remota si aggiunge anche senza
    // firme visibili: il profilo remoto firma comunque il documento.
    Result := True;
  except
    FreeAndNil(Activity);
    raise;
  end;
end;

function TeSignAnyWhereEngine.Firma(const FileName: string): string;
var
  PrepareResponse: TPrepareResponse;
  Envelope: TEnvelope;
  Documento: eSignAnyWhere.classes.Envelope.TDocuments;
  Activity: TActivities;
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  IdErrore: string;
begin
  Result := '';

  Upload(FileName);

  PrepareResponse := Prepare;
  try
    Envelope := TEnvelope.Create;
    try
      InitEnvelope(Envelope);

      Documento := eSignAnyWhere.classes.Envelope.TDocuments.Create;
      Documento.FileId := FParams.FileId;
      Documento.DocumentNumber := 1;
      Envelope.Documents.Add(Documento);

      if not FParams.FirmaRemota1.IdentificativoFirmaRemota.IsEmpty then
        if CreateActivityRemoteSign(PrepareResponse, FParams.FirmaRemota1.PlaceHolder, FParams.FirmaRemota1.IdentificativoFirmaRemota, Activity) then
          Envelope.Activities.Add(Activity);

      if not FParams.FirmaRemota2.IdentificativoFirmaRemota.IsEmpty then
        if CreateActivityRemoteSign(PrepareResponse, FParams.FirmaRemota2.PlaceHolder, FParams.FirmaRemota2.IdentificativoFirmaRemota, Activity) then
          Envelope.Activities.Add(Activity);

      if CreateActivityOTP(PrepareResponse, Activity) then
        Envelope.Activities.Add(Activity);

      Risposta := TRESTResponse.Create(nil);
      Richiesta := NuovaRichiesta('envelope/send', TRESTRequestMethod.rmPOST, Risposta);
      try
        Richiesta.AddBody(Envelope);
        Esegui(Richiesta, Risposta, 'invio della busta');

        // Il fornitore puo' rispondere 200 con un errore nel corpo.
        if Risposta.GetSimpleValue('ErrorId', IdErrore) then
          raise EeSignAnyWhereHttp.CreateStato('invio della busta', Risposta.StatusCode, DettaglioErrore(Risposta.Content));

        if not Risposta.GetSimpleValue('EnvelopeId', Result) or Result.IsEmpty then
          raise EeSignAnyWhereHttp.CreateStato('invio della busta, EnvelopeId assente', Risposta.StatusCode, DettaglioErrore(Risposta.Content));

        FParams.EnvelopeId := Result;
      finally
        FreeAndNil(Richiesta);
        FreeAndNil(Risposta);
      end;
    finally
      FreeAndNil(Envelope);
    end;
  finally
    FreeAndNil(PrepareResponse);
  end;
end;

function TeSignAnyWhereEngine.Envelope: TEnvelopeResponse;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
begin
  FParams.CheckEnvelopeId;

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('envelope/{EnvelopeId}', TRESTRequestMethod.rmGET, Risposta);
  try
    Richiesta.AddParameter('EnvelopeId', FParams.EnvelopeId, TRESTRequestParameterKind.pkURLSEGMENT);
    Esegui(Richiesta, Risposta, 'stato della busta');

    Result := TEnvelopeResponse.Create;
    try
      Result.AsJson := Risposta.Content;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

function TeSignAnyWhereEngine.EnvelopeStatus: string;
var
  EnvelopeResponse: TEnvelopeResponse;
begin
  EnvelopeResponse := Envelope;
  try
    Result := EnvelopeResponse.EnvelopeStatus;
  finally
    FreeAndNil(EnvelopeResponse);
  end;
end;

function TeSignAnyWhereEngine.Scarica(const FileId: string): TBytes;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
begin
  if FileId.IsEmpty then
    raise Exception.Create('eSignAnyWhere: identificativo del file da scaricare assente.');

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('file/{fileId}', TRESTRequestMethod.rmGET, Risposta);
  try
    Richiesta.Accept := 'application/pdf';
    Richiesta.AddParameter('fileId', FileId, TRESTRequestParameterKind.pkURLSEGMENT);
    Esegui(Richiesta, Risposta, 'scarico del file', True);

    Result := Risposta.RawBytes;

    if Length(Result) = 0 then
      raise EeSignAnyWhereHttp.CreateStato('scarico del file, risposta vuota', Risposta.StatusCode, '');
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

procedure TeSignAnyWhereEngine.DownloadFiles(const FileNameSigned, FileNameAudit: string);
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  EnvelopeFilesResponse: TEnvelopeFilesResponse;
  FileSignedId: string;
  FileAuditId: string;
  Firmato: TBytes;
  Audit: TBytes;
begin
  FParams.CheckEnvelopeId;

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('envelope/{EnvelopeId}/files', TRESTRequestMethod.rmGET, Risposta);
  try
    Richiesta.AddParameter('EnvelopeId', FParams.EnvelopeId, TRESTRequestParameterKind.pkURLSEGMENT);
    Esegui(Richiesta, Risposta, 'elenco dei file della busta');

    EnvelopeFilesResponse := TEnvelopeFilesResponse.Create;
    try
      EnvelopeFilesResponse.AsJson := Risposta.Content;

      if EnvelopeFilesResponse.Documents.Count = 0 then
        raise EeSignAnyWhereHttp.CreateStato('elenco dei file della busta, nessun documento', Risposta.StatusCode, '');

      FileSignedId := EnvelopeFilesResponse.Documents[0].FileId;
      FileAuditId := EnvelopeFilesResponse.AuditTrail.FileId;
    finally
      FreeAndNil(EnvelopeFilesResponse);
    end;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;

  Firmato := Scarica(FileSignedId);
  Audit := Scarica(FileAuditId);

  TFile.WriteAllBytes(FileNameSigned, Firmato);
  TFile.WriteAllBytes(FileNameAudit, Audit);
end;

// La forma della risposta di envelope/find non e' mai stata vista in Gesty,
// dove la ricerca era scritta ma non usata: si accettano sia un oggetto con
// l'elenco in "Envelopes" sia l'elenco nudo, e per ogni busta "Id" o
// "EnvelopeId". Se la busta porta il nome lo si confronta col testo, cosi'
// una ricerca che guardasse anche altri campi non adotta la busta sbagliata.
function TeSignAnyWhereEngine.CercaBusta(const Testo: string; const Giorni: Integer): string;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  Corpo: TJSONObject;
  Valore: TJSONValue;
  Elenco: TJSONArray;
  Elemento: TJSONValue;
  Coppia: TJSONPair;
  IdBusta: string;
  NomeBusta: string;
begin
  Result := '';

  if Testo.Trim.IsEmpty then
    raise Exception.Create('eSignAnyWhere: testo da cercare vuoto.');

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('envelope/find', TRESTRequestMethod.rmPOST, Risposta);
  try
    // Corpo scritto a mano: il DTO di Gesty manda anche i campi vuoti, e il
    // fornitore li rifiuta (Status vuoto, date troppo corte).
    Corpo := TJSONObject.Create;
    try
      Corpo.AddPair('SearchText', Testo);
      Corpo.AddPair('StartDate', DateToISO8601(IncDay(Now, -Giorni), False));
      Richiesta.AddBody(Corpo.ToJSON, TRESTContentType.ctAPPLICATION_JSON);
    finally
      FreeAndNil(Corpo);
    end;

    Esegui(Richiesta, Risposta, 'ricerca della busta');

    Valore := TJSONObject.ParseJSONValue(Risposta.Content);
    try
      Elenco := nil;

      if Valore is TJSONArray then
        Elenco := TJSONArray(Valore)
      else
        if Valore is TJSONObject then
          for Coppia in TJSONObject(Valore) do
            if SameText(Coppia.JsonString.Value, 'Envelopes') and (Coppia.JsonValue is TJSONArray) then
              Elenco := TJSONArray(Coppia.JsonValue);

      if not Assigned(Elenco) then
        Exit;

      for Elemento in Elenco do
      begin
        if not (Elemento is TJSONObject) then
          Continue;

        IdBusta := '';
        NomeBusta := '';

        for Coppia in TJSONObject(Elemento) do
          if SameText(Coppia.JsonString.Value, 'Id') or SameText(Coppia.JsonString.Value, 'EnvelopeId') then
            IdBusta := Coppia.JsonValue.Value
          else
            if SameText(Coppia.JsonString.Value, 'Name') then
              NomeBusta := Coppia.JsonValue.Value;

        if IdBusta.IsEmpty then
          Continue;

        if (not NomeBusta.IsEmpty) and (Pos(UpperCase(Testo), UpperCase(NomeBusta)) = 0) then
          Continue;

        Exit(IdBusta);
      end;
    finally
      FreeAndNil(Valore);
    end;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

// La risposta di viewerlinks non e' mai stata vista (Gesty non la usa): come
// per envelope/find si accettano un oggetto con l'elenco in "ViewerLinks" o
// l'elenco nudo, e per ogni destinatario il collegamento in "ViewerLink",
// "Link", "Url" o "WorkstepRedirectionUrl" e l'indirizzo in "Email". Le voci
// senza collegamento si scartano.
function TeSignAnyWhereEngine.CollegamentiFirma: TArray<TeSignAnyWhereCollegamento>;
var
  Richiesta: TRESTRequest;
  Risposta: TRESTResponse;
  Valore: TJSONValue;
  Elenco: TJSONArray;
  Elemento: TJSONValue;
  Coppia: TJSONPair;
  Voce: TeSignAnyWhereCollegamento;
  Chiave: string;
begin
  Result := nil;
  FParams.CheckEnvelopeId;

  Risposta := TRESTResponse.Create(nil);
  Richiesta := NuovaRichiesta('envelope/{EnvelopeId}/viewerlinks', TRESTRequestMethod.rmGET, Risposta);
  try
    Richiesta.AddParameter('EnvelopeId', FParams.EnvelopeId, TRESTRequestParameterKind.pkURLSEGMENT);
    Esegui(Richiesta, Risposta, 'collegamenti di firma');

    Valore := TJSONObject.ParseJSONValue(Risposta.Content);
    try
      Elenco := nil;

      if Valore is TJSONArray then
        Elenco := TJSONArray(Valore)
      else
        if Valore is TJSONObject then
          for Coppia in TJSONObject(Valore) do
            if SameText(Coppia.JsonString.Value, 'ViewerLinks') and (Coppia.JsonValue is TJSONArray) then
              Elenco := TJSONArray(Coppia.JsonValue);

      if not Assigned(Elenco) then
        Exit;

      for Elemento in Elenco do
      begin
        if not (Elemento is TJSONObject) then
          Continue;

        Voce := Default(TeSignAnyWhereCollegamento);

        for Coppia in TJSONObject(Elemento) do
        begin
          Chiave := Coppia.JsonString.Value;

          if SameText(Chiave, 'Email') then
            Voce.Email := Coppia.JsonValue.Value
          else
            if SameText(Chiave, 'ViewerLink') or SameText(Chiave, 'Link') or SameText(Chiave, 'Url') or
              SameText(Chiave, 'WorkstepRedirectionUrl') then
              Voce.Collegamento := Coppia.JsonValue.Value;
        end;

        if not Voce.Collegamento.Trim.IsEmpty then
          Result := Result + [Voce];
      end;
    finally
      FreeAndNil(Valore);
    end;
  finally
    FreeAndNil(Richiesta);
    FreeAndNil(Risposta);
  end;
end;

end.
