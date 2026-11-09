// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-28
// ---------------------------------------------------------------------------
unit WebModuleMain;

// Avvio del motore: configurazione, middleware, controller.
//
// Tre differenze rispetto a prima:
//
// - i controller del nucleo vengono registrati qui, quelli del prodotto li
// chiede al profilo corrente: e' l'unico punto in cui il nucleo tocca il
// prodotto, e lo fa senza nominarlo;
//
// - TTicketController non c'e' piu': erano 360 righe interamente
// commentate che dichiaravano cinque punti di ingresso /tickets che
// rispondevano a vuoto (Z8);
//
// - il controller dei file e' nuovo (Z5) e vale per entrambi i prodotti.
//
// Dal 2026-10-06 il driver Firebird e la definizione della connessione non
// stanno piu' qui ma in Connection.Definition, una volta per processo:
// nascevano con il primo modulo web, cioe' alla prima richiesta, e ogni
// modulo web aveva la sua copia del driver. La chiamata in WebModuleCreate
// resta per i moduli di Apache e IIS, dove e' il primo codice che gira;
// nell'eseguibile autonomo la definizione c'e' gia' e non fa niente.
//
// Dal 2026-10-15, con la voce cartellaInterfaccia, lo stesso server pubblica
// anche l'interfaccia web su "/": e' la copia portatile di Agora', che gira
// su un PC senza server web davanti (vedi TInterfacciaMiddleware).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Data.DB,
  Web.HTTPApp,
  MVCFramework,
  MVCFramework.Logger,
  MVCFramework.Commons,
  MVCFramework.Middleware.JWT,
  MVCFramework.Middleware.CORS,
  MVCFramework.Middleware.Compression,
  MVCFramework.Middleware.Session,
  MVCFramework.Middleware.Analytics,
  MVCFramework.Swagger.Commons,
  MVCFramework.Container,
  FireDAC.Phys.FBDef,
  FireDAC.Stan.Intf,
  FireDAC.Phys,
  FireDAC.Phys.IBBase,
  FireDAC.Phys.FB,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf;

type
  TMainWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    MVCEngine: TMVCEngine;
  private
    procedure ConfigureCORSMiddleware;
    procedure ConfigureInterfaccia;
    procedure ConfigureJWTMiddleware;
    procedure ConfigureSwagger;
    procedure RegistraControllers;
  public

  end;

var
  WebModuleClass: TComponentClass = TMainWebModule;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}

uses
  System.DateUtils,
  System.IOUtils,
  System.NetEncoding,
  MVCFramework.Middleware.StaticFiles,
  MVCFramework.Middleware.Swagger,
  MVCFramework.JWT,
  App.Config,
  App.Profile,
  Connection.Definition,
  Connection.Pool,
  Data.Service,
  Authentication.Service,
  Auth.Controller,
  DynamicDataset.Controller,
  Files.Controller,
  Metadata.Editor.Controller,
  Metadata.Patch.Controller,
  Publics.Controller,
  Segnalazioni.Controller,
  JWTRefresh.Middleware;

type
  // I file dell'interfaccia web, pubblicati su "/" con il ritorno a
  // index.html per i percorsi che non sono file (le rotte di Angular, al
  // ricaricamento della pagina). Il middleware dei file statici di DMVC
  // pubblicato su "/" risponderebbe index.html anche a /api/...: le regole
  // che accetta possono solo bloccare una richiesta, non lasciarla passare ai
  // controller. Per questo gli si passano solo le richieste di lettura che
  // non appartengono ai controller.
  TInterfacciaMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private
    FFileStatici: IMVCMiddleware;
    function DeiController(const Percorso: string): Boolean;
  public
    constructor Create(const Cartella: string);
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext; const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext; const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  end;

constructor TInterfacciaMiddleware.Create(const Cartella: string);
begin
  inherited Create;
  FFileStatici := TMVCStaticFilesMiddleware.Create('/', Cartella, 'index.html', True);
end;

function TInterfacciaMiddleware.DeiController(const Percorso: string): Boolean;
const
  // /system sono i controller di sistema di DMVC (LoadSystemControllers).
  Prefissi: array [0 .. 2] of string = ('/api', '/swagger', '/system');
var
  Prefisso: string;
begin
  for Prefisso in Prefissi do
    if SameText(Percorso, Prefisso) or Percorso.StartsWith(Prefisso + '/', True) then
      Exit(True);

  Result := False;
end;

procedure TInterfacciaMiddleware.OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
begin
  if not(AContext.Request.HTTPMethod in [httpGET, httpHEAD]) then
    Exit;

  if DeiController(AContext.Request.PathInfo) then
    Exit;

  FFileStatici.OnBeforeRouting(AContext, AHandled);
end;

procedure TInterfacciaMiddleware.OnBeforeControllerAction(AContext: TWebContext; const AControllerQualifiedClassName: string; const AActionName: string; var AHandled: Boolean);
begin
end;

procedure TInterfacciaMiddleware.OnAfterControllerAction(AContext: TWebContext; const AControllerQualifiedClassName: string; const AActionName: string; const AHandled: Boolean);
begin
end;

procedure TInterfacciaMiddleware.OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
begin
end;

procedure TMainWebModule.WebModuleCreate(Sender: TObject);
begin
  TConnectionDefinition.Registra;

  MVCEngine := TMVCEngine.Create(Self,
    procedure(Config: TMVCConfig)
    begin
      // Configurazione generale
      Config[TMVCConfigKey.DefaultContentType] := TMVCMediaType.APPLICATION_JSON;
      Config[TMVCConfigKey.DefaultContentCharset] := TMVCCharset.UTF_8;
      Config[TMVCConfigKey.AllowUnhandledAction] := 'false';
      Config[TMVCConfigKey.LoadSystemControllers] := 'true';
      Config[TMVCConfigKey.DefaultViewFileExtension] := '.html';
      Config[TMVCConfigKey.ViewPath] := 'templates';
      Config[TMVCConfigKey.MaxEntitiesRecordCount] := '200';
      Config[TMVCConfigKey.ExposeServerSignature] := 'false';
      Config[TMVCConfigKey.ExposeXPoweredBy] := 'false';
      // Deve stare almeno alla dimensione massima ammessa per gli allegati,
      // altrimenti il caricamento viene rifiutato prima di arrivare al
      // controller, che non puo' spiegare perche'.
      Config[TMVCConfigKey.MaxRequestSize] := IntToStr(TAppConfig.Instance.Documenti.DimensioneMassimaByte + (1024 * 1024));
    end);

  // Una connessione al database per richiesta (Connection.Pool). La
  // distruzione del contesto web DMVC la chiama in un finally, quindi la
  // connessione torna al raggruppamento anche quando la richiesta fallisce.
  MVCEngine.OnWebContextCreate(
    procedure(const AContext: TWebContext)
    begin
      TConnectionPool.IniziaRichiesta;
    end);
  MVCEngine.OnWebContextDestroy(
    procedure(const AContext: TWebContext)
    begin
      TConnectionPool.FineRichiesta;
    end);

  /// ///////////////////////////////////////////////
  // NON VARIARE L'ORDINE DEI MIDDLEWARE
  // Interfaccia per prima: i suoi file non passano da sessione e JWT.
  // CORS prima di JWT

  ConfigureInterfaccia;

  ConfigureCORSMiddleware;

  // Session prima di JWT
  MVCEngine.AddMiddleware(UseMemorySessionMiddleware());

  // Aggiungi middleware JWT
  ConfigureJWTMiddleware;

  MVCEngine.AddMiddleware(TMVCCompressionMiddleware.Create);

  ConfigureSwagger;

  RegistraControllers;

  LogI(Format('zServer inizializzato: profilo %s, applicativo %s, database %s', [TAppProfiles.Corrente.Codice, TAppProfiles.Corrente.CodiceApplicativo, TAppConfig.Instance.Database.Database]));
end;

procedure TMainWebModule.WebModuleDestroy(Sender: TObject);
begin
  MVCEngine.Free;
  LogI('zServer terminato');
end;

procedure TMainWebModule.RegistraControllers;
var
  ControllerDiDominio: TMVCControllerClazz;
begin
  // Nucleo: valgono per tutti i prodotti.
  MVCEngine.AddController(TPublicController);
  MVCEngine.AddController(TAuthController);
  MVCEngine.AddController(TDynamicDatasetController);
  MVCEngine.AddController(TFilesController);
  MVCEngine.AddController(TMetaEditorController);
  MVCEngine.AddController(TMetadataPatchController);
  MVCEngine.AddController(TSegnalazioniController);

  // Prodotto: li dichiara il profilo compilato in questo eseguibile.
  for ControllerDiDominio in TAppProfiles.Corrente.ControllerDiDominio do
  begin
    MVCEngine.AddController(ControllerDiDominio);
    LogD('Controller di dominio registrato: ' + ControllerDiDominio.ClassName);
  end;
end;

procedure TMainWebModule.ConfigureCORSMiddleware;
var
  Origine: string;
begin
  // Z10 - L'origine ammessa e' una voce di configurazione. In esercizio va
  // scritta l'origine del portale: con '*' qualunque pagina su qualunque
  // sito puo' chiamare queste interfacce dal browser di un utente collegato.
  Origine := TAppConfig.Instance.CorsOrigin;

  if Origine.Trim.IsEmpty then
    Origine := '*';

  if Origine = '*' then
    LogW('CORS aperto a qualunque origine: accettabile in sviluppo, da restringere in esercizio (voce corsOrigin)');

  MVCEngine.AddMiddleware(TMVCCORSMiddleware.Create(Origine));
end;

procedure TMainWebModule.ConfigureInterfaccia;
var
  Cartella: string;
begin
  Cartella := TAppConfig.Instance.CartellaInterfaccia;

  if Cartella.IsEmpty then
    Exit;

  // Senza questo controllo il middleware di DMVC solleverebbe un'eccezione a
  // ogni richiesta, anche a quelle per le interfacce REST che non c'entrano.
  if not TFile.Exists(TPath.Combine(Cartella, 'index.html')) then
  begin
    LogW(Format('cartellaInterfaccia "%s" non contiene index.html: interfaccia web non pubblicata', [Cartella]));
    Exit;
  end;

  MVCEngine.AddMiddleware(TInterfacciaMiddleware.Create(Cartella));
  LogI('Interfaccia web pubblicata su / da ' + Cartella);
end;

procedure TMainWebModule.ConfigureJWTMiddleware;
var
  Config: TAppConfig;
  ClaimsSetup: TJWTClaimsSetup;
  MVCMiddleware: IMVCMiddleware;
  CapturedIssuer: string;
  CapturedAudience: string;
  CapturedExpirationMinutes: Integer;
begin
  Config := TAppConfig.Instance;

  CapturedIssuer := Config.JWT.Issuer;
  CapturedAudience := Config.JWT.Audience;
  CapturedExpirationMinutes := Config.JWT.ExpirationMinutes;

  ClaimsSetup := procedure(const JWT: TJWT)
    begin
      JWT.Claims.Issuer := CapturedIssuer;
      JWT.Claims.Audience := CapturedAudience;
      JWT.Claims.ExpirationTime := now + (oneMinute * CapturedExpirationMinutes);
      JWT.Claims.NotBefore := now - (oneMinute * 5);
      // valid since 5 minutes ago
      JWT.Claims.IssuedAt := now;
    end;

  MVCMiddleware := TMVCJWTRefreshMiddleware.Create(TAuthenticationService.Create, ClaimsSetup, Config.JWT.SecretKey, '/api/auth/login', [TJWTCheckableClaim.ExpirationTime, TJWTCheckableClaim.NotBefore, TJWTCheckableClaim.IssuedAt],
    Config.JWT.LeewaySeconds, 'HS256', '/api/auth/refresh', '/api/auth/logout', '/api/auth/logout-all');

  MVCEngine.AddMiddleware(MVCMiddleware);
end;

procedure TMainWebModule.ConfigureSwagger;
var
  SwagInfo: TMVCSwaggerInfo;
  MVCSwaggerMiddleware: TMVCSwaggerMiddleware;
begin
  if not TAppConfig.Instance.EnableSwagger then
    Exit;

  SwagInfo.Title := Format('zServer API - %s', [TAppProfiles.Corrente.Codice]);
  SwagInfo.Version := '1.0.0';
  SwagInfo.TermsOfService := '';
  SwagInfo.Description := Format('Interfacce di zServer per %s', [TAppProfiles.Corrente.Codice]);
  SwagInfo.ContactName := 'Luca Zebro';
  SwagInfo.ContactEmail := 'info@zebro.it';
  SwagInfo.ContactUrl := 'www.zebro.it';
  SwagInfo.LicenseName := '';
  SwagInfo.LicenseUrl := '';

  MVCEngine.AddMiddleware(TMVCStaticFilesMiddleware.Create('/swagger', { StaticFilesPath }
    TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), 'www', 'swagger')));

  MVCSwaggerMiddleware := TMVCSwaggerMiddleware.Create(MVCEngine, SwagInfo, '/api/swagger.json', 'zServer Swagger Documentation', true);
  MVCEngine.AddMiddleware(MVCSwaggerMiddleware);
end;

end.
