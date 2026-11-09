// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-03
// ---------------------------------------------------------------------------
unit Publics.Controller;

{ ===========================================================================
  Controller Pubblico - Nessuna autenticazione richiesta
  Espone endpoint accessibili senza token JWT:
  - GET  /api/status      -> stato del server, profilo attivo e database
  - GET  /api/version     -> versione API
  - GET  /api/time        -> data/ora server
  =========================================================================== }

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.IOUtils,
  MVCFramework,
  MVCFramework.Commons,
  Base.Controller;

type

  [MVCPath('/api')]
  [MVCDoc('Endpoint pubblici - nessuna autenticazione richiesta')]
  TPublicController = class(TBaseController)
  public
    { ===================================================================
      GET /api/status
      Health check per monitoring e load balancer.
      Risponde sempre 200 se il server è operativo.

      Riporta anche profilo attivo e database: con due istanze sulla stessa
      macchina — una WT e una Gesty — e' l'unico modo per capire in un colpo
      d'occhio con quale si sta parlando.
      =================================================================== }
    [MVCPath('/status')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Stato del server, profilo applicativo attivo e database servito')]
    procedure Status;

    { ===================================================================
      GET /api/version
      Restituisce versione API e informazioni build.
      =================================================================== }
    [MVCPath('/version')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Versione API e informazioni build')]
    procedure Version;

    { ===================================================================
      GET /api/time
      Restituisce data/ora del server (utile per debug clock skew).
      =================================================================== }
    [MVCPath('/time')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Data/ora corrente del server')]
    procedure ServerTime;
  end;

implementation

uses
  System.JSON,
  App.Config,
  App.Profile;

var
  DataAvvioProcesso: TDateTime;

procedure TPublicController.Status;
var
  Configurazione: TAppConfig;
  Risposta: TJSONObject;
begin
  Configurazione := TAppConfig.Instance;

  Risposta := TJSONObject.Create;
  Risposta.AddPair('status', 'online');
  Risposta.AddPair('service', 'zServer');
  // Il prodotto lo decide la compilazione: non c'e' piu' una voce del .json
  // da confrontare, e "applicazione" resta nella risposta per chi la legge.
  Risposta.AddPair('applicazione', TAppProfiles.Corrente.Codice);
  Risposta.AddPair('profilo', TAppProfiles.Corrente.Codice);
  Risposta.AddPair('applicativo', TAppProfiles.Corrente.CodiceApplicativo);
  Risposta.AddPair('database', Format('%s@%s:%d', [Configurazione.Database.Database, Configurazione.Database.Server, Configurazione.Database.Port]));
  Risposta.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', TTimeZone.Local.ToUniversalTime(Now)));

  RenderJson(Risposta);
end;

procedure TPublicController.Version;
var
  Risposta: TJSONObject;
begin
  Risposta := TJSONObject.Create;
  Risposta.AddPair('api_version', '1.0.0');
  Risposta.AddPair('framework', 'DMVCFramework');
  Risposta.AddPair('build_date', {$IFDEF DEBUG}'DEBUG'{$ELSE}'RELEASE'{$ENDIF} + ' - ' + FormatDateTime('yyyy-mm-dd', Now));

  // Dati sensibili dell'eseguibile solo nelle compilazioni DEBUG: se mancano,
  // l'eseguibile e' una release. Servono a capire quale zServer sta rispondendo
  // e se e' stato ricompilato dopo l'ultima modifica dei sorgenti (build_date
  // riporta la data di oggi, non quella di compilazione).
  {$IFDEF DEBUG}
  Risposta.AddPair('exe_percorso', ParamStr(0));
  Risposta.AddPair('exe_data_file', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', TFile.GetLastWriteTime(ParamStr(0))));
  Risposta.AddPair('avvio_processo', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DataAvvioProcesso));
  Risposta.AddPair('piattaforma', {$IFDEF WIN64}'Win64'{$ELSEIF DEFINED(MSWINDOWS)}'Win32'{$ELSEIF DEFINED(LINUX)}'Linux'{$ELSE}'Altro'{$ENDIF});
  {$ENDIF}

  RenderJson(Risposta);
end;

procedure TPublicController.ServerTime;
var
  Risposta: TJSONObject;
begin
  Risposta := TJSONObject.Create;
  Risposta.AddPair('local_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now));
  Risposta.AddPair('utc_time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', TTimeZone.Local.ToUniversalTime(Now)));
  Risposta.AddPair('timezone', TTimeZone.Local.DisplayName);
  Risposta.AddPair('utc_offset_minutes', TJSONNumber.Create(Round(TTimeZone.Local.UtcOffset.TotalMinutes)));

  RenderJson(Risposta);
end;

initialization
  DataAvvioProcesso := Now;

end.
