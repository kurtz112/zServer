// JCL_DEBUG_EXPERT_GENERATEJDBG OFF
// JCL_DEBUG_EXPERT_INSERTJDBG OFF
// JCL_DEBUG_EXPERT_DELETEMAPFILE OFF
program zServer;

// Eseguibile autonomo, con server HTTP incorporato.
//
// Serve quattro dei sei bersagli richiesti:
//
// Win64  Debug    la console di prova e l'applicazione di prova
// Linux64 Release  il servizio su Linux, anche quando sta dietro NGINX
//
// Dietro NGINX non cambia niente nell'eseguibile: il proxy inverso gira
// davanti e parla con questa stessa porta. Apache e IIS invece caricano un
// modulo, e hanno i loro due progetti.
//
// Il prodotto lo decide la configurazione di compilazione, che definisce
// PRODOTTO_WT oppure PRODOTTO_GESTY: e' l'unico punto in cui i due prodotti
// sono nominati.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  MVCFramework,
  MVCFramework.Logger,
  MVCFramework.Commons,
  MVCFramework.Signal,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ShellAPI,
{$ENDIF}
  Web.ReqMulti,
  Web.WebReq,
  Web.WebBroker,
  IdContext,
  IdSocketHandle,
  IdHTTPWebBrokerBridge,
  // ── Nucleo ──
  App.Config in 'Core\Config\App.Config.pas',
  App.Profile in 'Core\App.Profile.pas',
  App.Profile.Base in 'Core\App.Profile.Base.pas',
  Authentication.Service in 'Core\Services\Authentication.Service.pas',
  Data.Service in 'Core\Services\Data.Service.pas',
  RefreshToken.Service in 'Core\Services\RefreshToken.Service.pas',
  Session.Context in 'Core\Services\Session.Context.pas',
  Token.Service in 'Core\Services\Token.Service.pas',
  Queue.Service in 'Core\Services\Queue.Service.pas',
  Metadata.Transfer.Service in 'Core\Services\Metadata.Transfer.Service.pas',
  Connection.Definition in 'Core\Utils\Connection.Definition.pas',
  Files.Signature in 'Core\Utils\Files.Signature.pas',
  Connection.Pool in 'Core\Utils\Connection.Pool.pas',
  DevExtremeHelper in 'Core\Utils\DevExtremeHelper.pas',
  FirebirdExceptions in 'Core\Utils\FirebirdExceptions.pas',
  FiredacHelper in 'Core\Utils\FiredacHelper.pas',
  Json.Values in 'Core\Utils\Json.Values.pas',
  LoggerPro.SmartInspectAppender in 'Core\Utils\LoggerPro.SmartInspectAppender.pas',
  Mail.Sender in 'Core\Utils\Mail.Sender.pas',
  Mail.Queue.Sender in 'Core\Utils\Mail.Queue.Sender.pas',
  fib.SqlTxtRtns in 'Core\Utils\fib.SqlTxtRtns.pas',
  fib.StrUtil in 'Core\Utils\fib.StrUtil.pas',
  JWTRefresh.Middleware in 'Core\Middleware\JWTRefresh.Middleware.pas',
  Base.Controller in 'Core\Controllers\Base.Controller.pas',
  Auth.Controller in 'Core\Controllers\Auth.Controller.pas',
  DynamicDataset.Controller in 'Core\Controllers\DynamicDataset.Controller.pas',
  Files.Controller in 'Core\Controllers\Files.Controller.pas',
  Metadata.Editor.Controller in 'Core\Controllers\Metadata.Editor.Controller.pas',
  Metadata.Patch.Controller in 'Core\Controllers\Metadata.Patch.Controller.pas',
  Segnalazioni.Service in 'Core\Services\Segnalazioni.Service.pas',
  Segnalazioni.Controller in 'Core\Controllers\Segnalazioni.Controller.pas',
  Publics.Controller in 'Core\Controllers\Publics.Controller.pas',
  WebModuleMain in 'WebModuleMain.pas' {MainWebModule: TWebModule},
  // ── Firma remota, comune ai prodotti (2026-11-07) ──
  // Motore multi-fornitore e fornitori: prima solo nel blocco di Gesty, ora
  // servono anche a WT (liberatorie dei centri del riuso). Le unit restano
  // nella cartella storica Products\Gesty\Firma. Il fornitore si sceglie per
  // configurazione (OBJ_FILES_FIRMA_CONFIGURAZIONE), non qui.
  zz.JSON.DTO in 'Products\Gesty\Firma\zz.JSON.DTO.pas',
  zDocumentale.Firma.Types in 'Products\Gesty\Firma\zDocumentale.Firma.Types.pas',
  zDocumentale.Firma.Intf in 'Products\Gesty\Firma\zDocumentale.Firma.Intf.pas',
  zDocumentale.Firma.ProviderBase in 'Products\Gesty\Firma\zDocumentale.Firma.ProviderBase.pas',
  zDocumentale.Firma.Factory in 'Products\Gesty\Firma\zDocumentale.Firma.Factory.pas',
  eSignAnyWhere.params in 'Products\Gesty\Firma\eSignAnyWhere.params.pas',
  eSignAnyWhere.classes.Envelope in 'Products\Gesty\Firma\eSignAnyWhere.classes.Envelope.pas',
  eSignAnyWhere.classes.EnvelopeFiles in 'Products\Gesty\Firma\eSignAnyWhere.classes.EnvelopeFiles.pas',
  eSignAnyWhere.classes.EnvelopeResponse in 'Products\Gesty\Firma\eSignAnyWhere.classes.EnvelopeResponse.pas',
  eSignAnyWhere.classes.Prepare in 'Products\Gesty\Firma\eSignAnyWhere.classes.Prepare.pas',
  eSignAnyWhere.classes.PrepareResponse in 'Products\Gesty\Firma\eSignAnyWhere.classes.PrepareResponse.pas',
  eSignAnyWhere in 'Products\Gesty\Firma\eSignAnyWhere.pas',
  Documentazione.Firma.ESignAnyWhere in 'Products\Gesty\Firma\Documentazione.Firma.ESignAnyWhere.pas',
  Documentazione.Firma.Zucchetti in 'Products\Gesty\Firma\Documentazione.Firma.Zucchetti.pas',
  Firma.Gestore in 'Core\Services\Firma.Gestore.pas',
  // ── Prodotto ──
{$IFDEF PRODOTTO_WT}
  WT.Profile in 'Products\WT\WT.Profile.pas',
  WT.Admin.Controller in 'Products\WT\Controllers\WT.Admin.Controller.pas',
  Geco.Common.Consts in 'Products\WT\Geco.Common.Consts.pas',
  WT.Geco.Controller in 'Products\WT\Controllers\WT.Geco.Controller.pas',
  WT.Tvb.Controller in 'Products\WT\Controllers\WT.Tvb.Controller.pas',
  WT.Posta.Gestore in 'Products\WT\WT.Posta.Gestore.pas',
  WT.CdrAvvisi.Gestore in 'Products\WT\WT.CdrAvvisi.Gestore.pas',
  WT.Firma.Gestore in 'Products\WT\WT.Firma.Gestore.pas',
  Stesei_ST000_Common in 'Products\WT\Stesei\Stesei_ST000_Common.pas',
  Stesei_ST001_ANPR_LoadResidenza_Request in 'Products\WT\Stesei\Stesei_ST001_ANPR_LoadResidenza_Request.pas',
  Stesei_ST001_ANPR_LoadResidenza_Response in 'Products\WT\Stesei\Stesei_ST001_ANPR_LoadResidenza_Response.pas',
  Stesei_ST006_ANPR_LoadNucleo_Request in 'Products\WT\Stesei\Stesei_ST006_ANPR_LoadNucleo_Request.pas',
  Stesei_ST006_ANPR_LoadNucleo_Response in 'Products\WT\Stesei\Stesei_ST006_ANPR_LoadNucleo_Response.pas',
  Stesei_ST012_INAD_LoadIndirizziDigitali_Request in 'Products\WT\Stesei\Stesei_ST012_INAD_LoadIndirizziDigitali_Request.pas',
  Stesei_ST012_INAD_LoadIndirizziDigitali_Response in 'Products\WT\Stesei\Stesei_ST012_INAD_LoadIndirizziDigitali_Response.pas',
  WT.Anpr.Stesei in 'Products\WT\WT.Anpr.Stesei.pas',
  WT.Anpr.Gestore in 'Products\WT\WT.Anpr.Gestore.pas',
  WT.Anpr.Controller in 'Products\WT\Controllers\WT.Anpr.Controller.pas',
  WT.Agora.Controller in 'Products\WT\Controllers\WT.Agora.Controller.pas',
  WT.Cittadino.Controller in 'Products\WT\Controllers\WT.Cittadino.Controller.pas',
  WT.CdrPubblico.Controller in 'Products\WT\Controllers\WT.CdrPubblico.Controller.pas',
// Sospeso finche' mancano Neta_Proxy e Neta_StreamServer (solo Windows).
{$IFDEF WT_CONTROLLER_NETA}
{$IFDEF MSWINDOWS}
  WT.Neta.Controller in 'Products\WT\Controllers\WT.Neta.Controller.pas',
{$ENDIF}
{$ENDIF}
{$ENDIF}
{$IFDEF PRODOTTO_GESTY}
  Gesty.Profile in 'Products\Gesty\Gesty.Profile.pas',
  Gesty.SitoWeb.Controller in 'Products\Gesty\Controllers\Gesty.SitoWeb.Controller.pas',
  Gesty.Capac.Controller in 'Products\Gesty\Controllers\Gesty.Capac.Controller.pas',
  Gesty.Codebri.Controller in 'Products\Gesty\Controllers\Gesty.Codebri.Controller.pas',
  Gesty.Questionari.Controller in 'Products\Gesty\Controllers\Gesty.Questionari.Controller.pas',
  Gesty.Posta.Gestore in 'Products\Gesty\Gesty.Posta.Gestore.pas',
  Gesty.Firma.Gestore in 'Products\Gesty\Gesty.Firma.Gestore.pas',
  Gesty.Firma.Controller in 'Products\Gesty\Controllers\Gesty.Firma.Controller.pas',
{$ENDIF}
  // Ultima voce della clausola, dopo i blocchi condizionati: cosi' ogni
  // blocco di prodotto finisce con la virgola e la lista resta valida con
  // uno, l'altro o entrambi i prodotti definiti.
  System.Classes;

{$R *.res}

// Informazioni di versione della variante (societa', copyright, nome del
// file): una risorsa per prodotto, ricompilata a ogni compilazione
// dall'evento prima della compilazione del .dproj. Non si usa la pagina
// Version Info del progetto perche' il .res e' uno solo per tutte le
// configurazioni e restava quello dell'ultima compilazione. Su Linux
// l'eseguibile non porta informazioni di versione.
{$IFDEF MSWINDOWS}
  {$IF DEFINED(PRODOTTO_WT)}
    {$R 'Versione\zServer.WT.res'}
  {$ELSEIF DEFINED(PRODOTTO_GESTY)}
    {$R 'Versione\zServer.Gesty.res'}
  {$IFEND}
{$ENDIF}

{$IFDEF MSWINDOWS}
// Icona e titolo della finestra della console, perche' sulla barra delle
// applicazioni si distingua lo zServer di WT da quello di Gesty. L'icona
// ICONA_ZSERVER sta nella risorsa di versione del prodotto. Con il terminale
// classico di Windows icona e titolo vanno sulla finestra; con Windows
// Terminal la finestra della console e' nascosta e la barra mostra l'icona
// del terminale, ma il titolo arriva comunque sulla scheda.
procedure ImpostaFinestraConsole(APort: Integer);
var
  Finestra: HWND;
  Icona: HICON;
begin
  SetConsoleTitle(PChar(Format('zServer %s - porta %d', [TAppProfiles.Corrente.Codice, APort])));

  Finestra := GetConsoleWindow;
  if Finestra = 0 then
    Exit;

  Icona := LoadImage(HInstance, 'ICONA_ZSERVER', IMAGE_ICON,
    GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), 0);
  if Icona <> 0 then
    SendMessage(Finestra, WM_SETICON, ICON_BIG, LPARAM(Icona));

  Icona := LoadImage(HInstance, 'ICONA_ZSERVER', IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
  if Icona <> 0 then
    SendMessage(Finestra, WM_SETICON, ICON_SMALL, LPARAM(Icona));
end;
{$ENDIF}

procedure RunServer(APort: Integer);
var
  Server: TIdHTTPWebBrokerBridge;
  Legame: TIdSocketHandle;
begin

  if not TAppConfig.Instance.IsValid then
  begin
    LogE('ERRORE: Configurazione non valida. Verificare il file di configurazione .json');
    ExitCode := 2;
    Exit;
  end;

{$IFDEF MSWINDOWS}
  ImpostaFinestraConsole(APort);
{$ENDIF}

  LogI('** zServer v1.0 **');
  LogI(Format('** Prodotto: %s **', [TAppProfiles.Corrente.Codice]));
  LogI(Format('** Porta: %d **', [APort]));
  LogI(Format('** Database: %s **', [TAppConfig.Instance.Database.Database]));
  writeln;

  Server := TIdHTTPWebBrokerBridge.Create(nil);
  try
    // La definizione della connessione nasce qui, prima di aprire la porta:
    // prima nasceva con il primo modulo web, cioe' alla prima richiesta, e
    // l'elaboratore della coda restava fermo fino ad allora.
    TConnectionDefinition.Registra;

    // L'elaboratore della coda gira solo qui: i moduli per Apache e IIS
    // mettono in coda e basta (vedi Queue.Service).
    TCodaElaboratore.Avvia;

    Server.OnParseAuthentication := TMVCParseAuthentication.OnParseAuthentication;
    Server.DefaultPort := APort;

    // Con un indirizzo il server ascolta solo li': 127.0.0.1 nella copia
    // portatile, perche' dalla rete del portatile non si arrivi ai dati.
    if not TAppConfig.Instance.IndirizzoAscolto.IsEmpty then
    begin
      Legame := Server.Bindings.Add;
      Legame.IP := TAppConfig.Instance.IndirizzoAscolto;
      Legame.Port := APort;
      LogI(Format('** In ascolto solo su %s **', [Legame.IP]));
    end;

    Server.MaxConnections := 0;
    Server.ListenQueue := 500;
    Server.Active := True;

    LogI('Server avviato con successo');
    LogI('Premi CTRL+C per arrestare il server');

    if not TAppConfig.Instance.CartellaInterfaccia.IsEmpty then
      LogI(Format('Interfaccia web su: http://localhost:%d/', [APort]));

    if TAppConfig.Instance.EnableSwagger then
      LogI(Format('Swagger disponibile su: http://localhost:%d/swagger', [APort]));

    writeln;

{$IFDEF MSWINDOWS}
    // Apri il browser automaticamente: sull'interfaccia, se c'e', altrimenti
    // su Swagger.
    if TAppConfig.Instance.AutoOpenBrowser then
    begin
      if not TAppConfig.Instance.CartellaInterfaccia.IsEmpty then
        ShellExecute(0, 'open', PChar(Format('http://localhost:%d/', [APort])), nil, nil, SW_SHOW)
      else if TAppConfig.Instance.EnableSwagger then
        ShellExecute(0, 'open', PChar(Format('http://localhost:%d/swagger', [APort])), nil, nil, SW_SHOW);
    end;
{$ENDIF}
    // Gestione segnali per shutdown pulito
    WaitForTerminationSignal;
    EnterInShutdownState;

  finally
    TCodaElaboratore.Ferma;
    Server.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := DebugHook <> 0;

  IsMultiThread := True;
  try
    // La verifica che il profilo compilato sia quello atteso dalla
    // configurazione va fatta prima di aprire la porta: una configurazione
    // copiata dall'installazione sbagliata deve fermare l'avvio, non far
    // partire il server sul database di un altro prodotto.
    LogI(Format('Profilo applicativo: %s', [TAppProfiles.Corrente.Codice]));

    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;

    WebRequestHandlerProc.MaxConnections := 1024;

    RunServer(TAppConfig.Instance.ServerPort);

  except
    on E: Exception do
    begin
      LogE(E);
      ExitCode := 1;
    end;
  end;

end.
