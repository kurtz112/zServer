// JCL_DEBUG_EXPERT_GENERATEJDBG OFF
library zServerApache;

// Modulo per Apache 2.4, 64 bit, Windows.
//
// La clausola uses era rimasta ai nomi di unit di due riordini fa
// (TicketController, AuthenticationService, DatabaseService, AppConfig):
// questo progetto non compilava piu' da tempo. Ora contiene le stesse unit
// del progetto autonomo, meno quelle che servono solo a chi ha un server
// HTTP proprio.
//
// Su Linux non esiste: il modulo Apache di WebBroker e' solo Windows, e
// sotto Linux il servizio si ospita con l'eseguibile autonomo dietro NGINX.

uses
  System.SysUtils,
  System.Classes,
  Winapi.ActiveX,
  System.Win.ComObj,
  Web.ReqMulti,
  Web.WebBroker,
  Web.ApacheApp,
  Web.HTTPD24Impl,
  MVCFramework.Logger,
  MVCFramework.Commons,
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
  System.IOUtils;

{$R *.res}

// Informazioni di versione della variante (societa', copyright, nome del
// file): una risorsa per prodotto, ricompilata a ogni compilazione
// dall'evento prima della compilazione del .dproj. Non si usa la pagina
// Version Info del progetto perche' il .res e' uno solo per tutte le
// configurazioni e restava quello dell'ultima compilazione.
{$IF DEFINED(PRODOTTO_WT)}
  {$R 'Versione\zServerApache.WT.res'}
{$ELSEIF DEFINED(PRODOTTO_GESTY)}
  {$R 'Versione\zServerApache.Gesty.res'}
{$IFEND}

// Esportazione richiesta da Apache. Ogni prodotto ha il proprio nome di
// modulo e il proprio nome di gestore, cosi' WT e Gesty possono essere
// caricati insieme nella stessa istanza di Apache senza collidere:
//
//   WT:
//     LoadModule zserver_wt_module modules/zServerApacheWT.dll
//     <Location /wt>
//       SetHandler zserver-wt-handler
//     </Location>
//
//   Gesty:
//     LoadModule zserver_gesty_module modules/zServerApacheGesty.dll
//     <Location /gesty>
//       SetHandler zserver-gesty-handler
//     </Location>
//
// Il nome del modulo (primo argomento di LoadModule) deve coincidere con
// quello esportato qui sotto. Il gestore si dichiara esplicitamente: se si
// lasciasse vuoto, il nome dipenderebbe dal nome del file della DLL.
// Modello: mod_gesty_server_24.dpr del vecchio server di Gesty.
const
{$IFDEF PRODOTTO_WT}
  NomeModulo = 'zserver_wt_module';
  NomeGestore = 'zserver-wt-handler';
{$ENDIF}
{$IFDEF PRODOTTO_GESTY}
  NomeModulo = 'zserver_gesty_module';
  NomeGestore = 'zserver-gesty-handler';
{$ENDIF}

var
  DatiModulo: TApacheModuleData;

exports
  DatiModulo name NomeModulo;

begin
  CoInitFlags := COINIT_MULTITHREADED;
  Web.ApacheApp.InitApplication(@DatiModulo, NomeGestore);
  Application.Initialize;
  Application.WebModuleClass := WebModuleClass;
  Application.Run;
end.
