// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-28
// ---------------------------------------------------------------------------
unit Connection.Definition;

// Definizione della connessione FireDAC al database, una per processo.
//
// Prima la definizione nasceva in TMainWebModule.ConfigureFirebird, cioe'
// alla creazione del primo modulo web, quindi alla prima richiesta HTTP.
// Due conseguenze:
//
// - l'elaboratore della coda (Queue.Service), che parte all'avvio, restava
//   fermo finche' qualcuno non chiamava il server: una posta accodata da un
//   processo precedente aspettava la prima richiesta per partire;
//
// - il TFDPhysFBDriverLink era un componente del modulo web, e i moduli web
//   sono piu' d'uno (il ponte HTTP ne crea uno per richiesta contemporanea):
//   ogni modulo ne aveva una copia con lo stesso DriverID, che la
//   definizione condivisa usava senza possederla.
//
// Qui driver e definizione appartengono al processo. Registra si chiama
// all'avvio dell'eseguibile autonomo (zServer.dpr, prima di aprire la porta
// e di avviare l'elaboratore) e dalla creazione di ogni modulo web, che
// nei moduli per Apache e IIS e' il primo punto in cui il codice gira: la
// seconda chiamata e le successive non fanno niente. E' protetta da un
// lucchetto perche' Apache e IIS possono creare piu' moduli web insieme.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.IBBase,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Comp.Client;

type
  TConnectionDefinition = class
  private
    class var FLucchetto: TCriticalSection;
    class var FDriver: TFDPhysFBDriverLink;
  public
    /// <summary>
    /// Registra driver e definizione della connessione con i dati della voce
    /// database del .json. Si puo' chiamare piu' volte e da piu' fili: solo
    /// la prima ha effetto.
    /// </summary>
    class procedure Registra; static;
    class function Registrata: Boolean; static;
  end;

implementation

uses
  MVCFramework.Logger,
  App.Config;

{ TConnectionDefinition }

class function TConnectionDefinition.Registrata: Boolean;
begin
  Result := FDManager.IsConnectionDef(TAppConfig.Instance.Database.ConnectionName);
end;

class procedure TConnectionDefinition.Registra;
var
  Config: TAppConfig;
  Parametri: TStringList;
  Definizione: IFDStanConnectionDef;
begin
  FLucchetto.Enter;
  try
    if Registrata then
      Exit;

    Config := TAppConfig.Instance;

    // Il driver ha un DriverID proprio (zServer) per poter indicare la
    // libreria client del .json senza toccare il driver FB predefinito.
    if not Assigned(FDriver) then
    begin
      FDriver := TFDPhysFBDriverLink.Create(nil);
      FDriver.DriverID := Config.Database.DriverId;
      FDriver.VendorLib := Config.Database.ClientLibrary;

      // Firebird incorporato (copia portatile): senza Embedded, con il
      // protocollo Local FireDAC trasforma il percorso in xnet://...
      // (FireDAC.Phys.IBBase, TFDPhysIBConnectionBase.InternalConnect), e
      // XNET cerca un server Firebird gia' avviato sullo stesso PC invece di
      // aprire il file con il motore della libreria: se c'e' risponde lui con
      // il suo archivio utenti, se non c'e' l'apertura fallisce con
      // "unavailable database".
      FDriver.Embedded := Config.Database.Incorporato;
    end;

    Parametri := TStringList.Create;
    try
      Parametri.Add('DriverID=' + Config.Database.DriverId);
      Parametri.AddPair('Server', Config.Database.Server);
      Parametri.AddPair('Port', Config.Database.Port.ToString);
      Parametri.AddPair('Database', Config.Database.Database);
      Parametri.AddPair('User_Name', Config.Database.Username);
      Parametri.AddPair('Password', Config.Database.Password);
      Parametri.AddPair('Protocol', Config.Database.Protocol);
      Parametri.AddPair('CharacterSet', Config.Database.CharacterSet);

      // Raggruppamento delle connessioni. La scadenza viene dalla voce
      // poolScadenzaMinuti: con i 90 secondi di prima il raggruppamento si
      // svuotava a ogni pausa di un operatore, e la richiesta successiva
      // pagava l'apertura delle connessioni e, se zServer era l'unico
      // collegato, anche la riapertura del database da parte di Firebird.
      Parametri.Add('Pooled=True');
      Parametri.Add('POOL_MaximumItems=50');
      Parametri.Add('POOL_CleanupTimeout=30000');
      Parametri.Add('POOL_ExpireTimeout=' + (Int64(Config.Database.PoolScadenzaMinuti) * 60 * 1000).ToString);

      FDManager.AddConnectionDef(Config.Database.ConnectionName, FDriver.DriverID, Parametri);
    finally
      FreeAndNil(Parametri);
    end;

    LogI(Format('Database configurato: %s@%s:%d', [Config.Database.Database, Config.Database.Server, Config.Database.Port]));

    // Il raggruppamento legge la scadenza dalla definizione registrata in
    // FDManager, non da Parametri: la si rilegge da li', insieme al file
    // delle definizioni, per vedere nel registro quella che vale davvero.
    // Serve a capire perche' dopo il 2026-10-28 le connessioni inattive
    // sparivano ancora dopo 90 secondi invece dei 30 minuti attesi.
    Definizione := FDManager.ConnectionDefs.FindConnectionDef(Config.Database.ConnectionName);
    if Assigned(Definizione) then
      LogI(Format('Raggruppamento: voce poolScadenzaMinuti %d, nella definizione POOL_ExpireTimeout=%s, POOL_CleanupTimeout=%s, Pooled=%s; file delle definizioni "%s"',
        [Config.Database.PoolScadenzaMinuti, Definizione.AsString['POOL_ExpireTimeout'], Definizione.AsString['POOL_CleanupTimeout'], Definizione.AsString['Pooled'], FDManager.ConnectionDefFileName]))
    else
      LogW('Raggruppamento: definizione ' + Config.Database.ConnectionName + ' non trovata dopo la registrazione');
  finally
    FLucchetto.Leave;
  end;
end;

initialization

TConnectionDefinition.FLucchetto := TCriticalSection.Create;

finalization

// Prima il gestore delle connessioni, poi il driver: chiudere il driver con
// connessioni ancora nel raggruppamento le lascerebbe senza libreria client.
if Assigned(TConnectionDefinition.FDriver) then
begin
  FDManager.Close;
  FreeAndNil(TConnectionDefinition.FDriver);
end;

FreeAndNil(TConnectionDefinition.FLucchetto);

end.
