// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-28
// ---------------------------------------------------------------------------
unit App.Config;

interface

uses
  System.SysUtils,
  System.JSON,
  System.IniFiles,
  System.IOUtils;

type
  TJWTConfig = record
    SecretKey: string;
    Issuer: string;
    Audience: string;
    ExpirationMinutes: Integer;
    LeewaySeconds: Integer;
    RefreshTokenDays: Integer;
    RefreshTokenCleanupDays: Integer;

    procedure Init;
    function IsValid: Boolean;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  TDatabaseConfig = record
  public const
    DriverId = 'zServer';
    ConnectionName = 'zServer';
  public
    Server: string;
    Port: Integer;
    Database: string;
    Username: string;
    Password: string;
    Protocol: string;
    CharacterSet: string;
    ClientLibrary: string;
    /// <summary>
    /// Minuti dopo i quali il raggruppamento chiude una connessione rimasta
    /// inutilizzata (voce poolScadenzaMinuti, almeno 1).
    /// </summary>
    PoolScadenzaMinuti: Integer;

    procedure Init;
    /// <summary>
    /// Protocollo Local: Firebird incorporato (embedded) nel processo, senza
    /// server. Serve alla copia portatile, che gira su un PC senza Firebird
    /// installato; il server e la porta allora non contano.
    /// </summary>
    function Incorporato: Boolean;
    function IsValid: Boolean;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  /// <summary>
  /// Impostazioni del documentale, usate dal controller dei file (Z5).
  /// La cartella di destinazione la decide la classe OBJ_CLASSES
  /// (colonne FOLDER e FILE_PREFIX): qui sta solo la radice usata quando la
  /// classe non porta un percorso assoluto, piu' i limiti di accettazione.
  /// </summary>
  TDocumentiConfig = record
    Cartella: string;
    DimensioneMassimaMB: Integer;
    TipiAmmessi: string;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
    function TipoAmmesso(const NomeFile: string): Boolean;
    function DimensioneMassimaByte: Int64;
  end;

  /// <summary>
  /// Indirizzi dei servizi Neta, usati dal controller di dominio omonimo di
  /// WT. Nel vecchio server erano voci di ConfigProps (Neta_DSServerHost,
  /// Neta_DSServerPort, Neta_StreamServerURL, Neta_StreamServerURI).
  /// </summary>
  TNetaConfig = record
    Host: string;
    Porta: Integer;
    StreamServerUrl: string;
    StreamServerUri: string;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  /// <summary>
  /// Elaboratore della coda generica (ZZ_CODA), solo nell'eseguibile autonomo.
  /// Attiva = false lo spegne senza toccare il resto: utile quando la coda e'
  /// consumata da un'altra istanza o dall'attivita' pianificata di WT.
  /// AttesaRispostaSecondi e' quanto una richiesta HTTP che ha accodato un
  /// lavoro breve (ANPR, una ricevuta) aspetta l'esito prima di rispondere
  /// 202 con l'identificativo del lavoro da rileggere.
  /// </summary>
  TCodaConfig = record
    Attiva: Boolean;
    IntervalloSecondi: Integer;
    MinutiBlocco: Integer;
    AttesaRispostaSecondi: Integer;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  /// <summary>
  /// Posta in uscita, letta dal gestore POSTA della coda del prodotto.
  /// Gesty spedisce da se' e usa le voci SMTP (Server, Porta, Utente,
  /// Password, Tls, VersioneTls, Mittente, NomeMittente). WT passa il
  /// messaggio a EMAIL_OUTBOX e usa solo IdModello: account di invio e
  /// mittente li prende dal modello, come il resto della posta di WT.
  /// Finche' le voci del prodotto mancano il gestore non si registra e la
  /// posta risponde 503.
  /// </summary>
  TPostaConfig = record
    Server: string;
    Porta: Integer;
    Utente: string;
    Password: string;
    /// <summary>
    /// Come si cifra la connessione: RequireTLS (STARTTLS obbligatorio,
    /// porta 587), ImplicitTLS (cifrata dall'inizio, porta 465),
    /// ExplicitTLS (STARTTLS se il server lo offre), NoTLS. Accetta anche
    /// le sigle R, I, E, N dei dati di WT e Gesty.
    /// </summary>
    Tls: string;
    /// <summary>Vuoto = la versione la negozia Windows; altrimenti TLSv1_2, TLSv1_3.</summary>
    VersioneTls: string;
    Mittente: string;
    NomeMittente: string;
    IdModello: Integer;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
    function SmtpConfigurato: Boolean;
  end;

  /// <summary>
  /// Firma remota dei documenti attraverso la coda (gestori FIRMA e
  /// FIRMA-STATO di Gesty). IntervalloStatoSecondi e' l'attesa fra due
  /// controlli dello stato di una busta inviata; GiriMassimi e' il numero di
  /// controlli dopo cui la coda smette di seguirla (predefinito: 30 giorni a
  /// 600 secondi, piu' della scadenza predefinita delle buste, 28 giorni).
  /// </summary>
  TFirmaConfig = record
    IntervalloStatoSecondi: Integer;
    GiriMassimi: Integer;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  /// <summary>
  /// Segnalazione degli errori a Mantis, a scelta dell'utente: il portale
  /// manda l'errore a zServer (POST /api/segnalazioni) e zServer apre il
  /// ticket. Indirizzo, token, progetto e categoria di Mantis NON stanno in
  /// questo file: si leggono dalla tabella CONFIG del database servito con la
  /// procedura MANTIS_GET_PARAMS, la stessa che usano Gesty e WT, cosi' ogni
  /// database ha il suo progetto e il token non si duplica in un secondo posto.
  /// La sezione "mantis" del .json e' facoltativa e contiene solo le regole
  /// del server: Abilitato (predefinito vero; falso spegne la funzione anche
  /// se il database e' configurato), Prefisso dell'oggetto del ticket,
  /// TimeoutMs della chiamata a Mantis e LimiteAlMinuto, il numero di
  /// segnalazioni che un utente puo' inviare in un minuto (protegge Mantis da
  /// un errore che si ripete in ciclo).
  /// </summary>
  TMantisConfig = record
    Abilitato: Boolean;
    Prefisso: string;
    TimeoutMs: Integer;
    LimiteAlMinuto: Integer;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  /// <summary>
  /// Accesso del cittadino con il gateway SPID (rotta POST /api/auth/login-spid-gateway).
  /// ChiaveCifratura e' la stessa del gateway (clients.NOME.encKey di spid-php-proxy.json):
  /// serve a decifrare e a verificare i dati che il gateway manda al portale. Sta SOLO qui,
  /// nel file del server, mai nel config.json del sito, che il browser puo' leggere.
  /// Vuota = rotta spenta (403).
  /// </summary>
  TSpidConfig = record
    ChiaveCifratura: string;

    procedure Init;
    procedure LoadFromJSON(JSONObject: TJSONObject);
    procedure SaveToJSON(JSONObject: TJSONObject);
  end;

  TAppConfig = class
  private
    FSpid: TSpidConfig;
    FAutoOpenBrowser: Boolean;
    FCartellaInterfaccia: string;
    FCoda: TCodaConfig;
    FCorsOrigin: string;
    FDatabase: TDatabaseConfig;
    FDevelopment: Boolean;
    FDocumenti: TDocumentiConfig;
    FEnableSwagger: Boolean;
    FFirma: TFirmaConfig;
    FIndirizzoAscolto: string;
    FJWT: TJWTConfig;
    FLogLevel: string;
    FLogMaxFileSizeKB: Integer;
    FLogMaxFiles: Integer;
    FLogPath: string;
    FMantis: TMantisConfig;
    FNeta: TNetaConfig;
    FPosta: TPostaConfig;
    FServerPort: Integer;
  private
    procedure ApplicaLivelloRegistro;
    function GetConfigFilePath: string;
    procedure LoadFromFile;
    procedure SaveDefaultConfig;

    constructor Create;
  private
    class var FInstance: TAppConfig;
  public
    destructor Destroy; override;

    class function Instance: TAppConfig;

    property Coda: TCodaConfig read FCoda write FCoda;
    property Database: TDatabaseConfig read FDatabase write FDatabase;
    property Documenti: TDocumentiConfig read FDocumenti write FDocumenti;
    property Firma: TFirmaConfig read FFirma write FFirma;
    property JWT: TJWTConfig read FJWT write FJWT;
    property Mantis: TMantisConfig read FMantis write FMantis;
    property Neta: TNetaConfig read FNeta write FNeta;
    property Posta: TPostaConfig read FPosta write FPosta;
    property Spid: TSpidConfig read FSpid write FSpid;

    property AutoOpenBrowser: Boolean read FAutoOpenBrowser;
    /// <summary>
    /// Cartella con la compilazione dell'interfaccia web (Agora'), pubblicata
    /// su "/" dallo stesso server: serve alla copia portatile, che non ha un
    /// server web davanti. Vuota = nessuna interfaccia, come prima. Un
    /// percorso relativo si legge dalla cartella dell'eseguibile.
    /// </summary>
    property CartellaInterfaccia: string read FCartellaInterfaccia;
    /// <summary>Origine ammessa per le richieste da browser (Z10). '*' solo in sviluppo.</summary>
    property CorsOrigin: string read FCorsOrigin;
    property Development: Boolean read FDevelopment;
    property EnableSwagger: Boolean read FEnableSwagger;
    /// <summary>
    /// Indirizzo su cui il server ascolta. Vuoto = tutti, come prima;
    /// 127.0.0.1 = solo dallo stesso PC, che e' quello che serve alla copia
    /// portatile: nessuno dalla rete a cui e' collegato il portatile
    /// raggiunge i dati, e Windows non chiede di aprire il firewall.
    /// </summary>
    property IndirizzoAscolto: string read FIndirizzoAscolto;
    /// <summary>
    /// Livello minimo del registro generale: DEBUG, INFO, WARNING, ERROR,
    /// FATAL. Si applica al caricamento della configurazione.
    /// </summary>
    property LogLevel: string read FLogLevel;
    /// <summary>Dimensione massima di un file del registro dei controller, in KB, prima di passare al successivo.</summary>
    property LogMaxFileSizeKB: Integer read FLogMaxFileSizeKB;
    /// <summary>File del registro dei controller conservati oltre a quello in uso.</summary>
    property LogMaxFiles: Integer read FLogMaxFiles;
    property LogPath: string read FLogPath;
    property ServerPort: Integer read FServerPort;

    function IsValid: Boolean;
  end;

implementation

uses
  System.StrUtils,
  LoggerPro,
  MVCFramework.Logger;

procedure TJWTConfig.Init;
begin
  SecretKey := '';
  Issuer := '';
  Audience := '';
  ExpirationMinutes := 480;
  LeewaySeconds := 0;
  // ZC 02.11.2026: con 0 i token di rinnovo nascevano gia' scaduti e ogni
  // /api/auth/refresh rispondeva "Sessione scaduta" quando la voce mancava
  // dalla configurazione
  RefreshTokenDays := 30;
  RefreshTokenCleanupDays := 0;
end;

function TJWTConfig.IsValid: Boolean;
begin
  Result := not SecretKey.IsEmpty;
end;

{ TJWTConfig }

procedure TJWTConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('secretKey', SecretKey);
  JSONObject.TryGetValue<string>('issuer', Issuer);
  JSONObject.TryGetValue<string>('audience', Audience);
  JSONObject.TryGetValue<Integer>('expirationMinutes', ExpirationMinutes);
  JSONObject.TryGetValue<Integer>('leewaySeconds', LeewaySeconds);
  JSONObject.TryGetValue<Integer>('refreshTokenDays', RefreshTokenDays);
  // ZC 02.11.2026: SaveToJSON scrive la voce anche col valore predefinito, e un
  // file salvato quando il predefinito era 0 la conserva: 0 o meno vale "non indicato"
  if RefreshTokenDays <= 0 then
    RefreshTokenDays := 30;
  JSONObject.TryGetValue<Integer>('refreshTokenCleanupDays', RefreshTokenCleanupDays);
end;

procedure TJWTConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('secretKey', SecretKey);
  JSONObject.AddPair('issuer', Issuer);
  JSONObject.AddPair('audience', Audience);
  JSONObject.AddPair('expirationMinutes', ExpirationMinutes);
  JSONObject.AddPair('leewaySeconds', LeewaySeconds);
  JSONObject.AddPair('refreshTokenDays', RefreshTokenDays);
  JSONObject.AddPair('refreshTokenCleanupDays', RefreshTokenCleanupDays);
end;

procedure TDatabaseConfig.Init;
begin
  Server := '';
  Port := 3050;
  Database := '';
  Username := 'SYSDBA';
  Password := 'masterkey';
  Protocol := 'TCPIP';
  CharacterSet := 'UTF8';
  ClientLibrary := '';
  PoolScadenzaMinuti := 30;
end;

function TDatabaseConfig.Incorporato: Boolean;
begin
  Result := SameText(Protocol.Trim, 'Local');
end;

function TDatabaseConfig.IsValid: Boolean;
begin
  if Incorporato then
    Exit(not Database.IsEmpty);

  Result := (not Server.IsEmpty) and (Port <> 0) and (not Database.IsEmpty);
end;

{ TDatabaseConfig }

procedure TDatabaseConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('server', Server);
  JSONObject.TryGetValue<Integer>('port', Port);
  JSONObject.TryGetValue<string>('database', Database);
  JSONObject.TryGetValue<string>('username', Username);
  JSONObject.TryGetValue<string>('password', Password);
  JSONObject.TryGetValue<string>('protocol', Protocol);
  JSONObject.TryGetValue<string>('characterSet', CharacterSet);
  JSONObject.TryGetValue<string>('clientLibrary', ClientLibrary);
  JSONObject.TryGetValue<Integer>('poolScadenzaMinuti', PoolScadenzaMinuti);

  if PoolScadenzaMinuti < 1 then
    PoolScadenzaMinuti := 1;

  // Con Firebird incorporato database e libreria stanno di norma accanto
  // all'eseguibile, e la cartella cambia a ogni copia: un percorso relativo
  // si legge dalla cartella dell'eseguibile, non da quella corrente, che
  // dipende da come e' stato lanciato.
  if Incorporato then
  begin
    if (not Database.IsEmpty) and TPath.IsRelativePath(Database) then
      Database := TPath.GetFullPath(TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), Database));

    if (not ClientLibrary.IsEmpty) and TPath.IsRelativePath(ClientLibrary) then
      ClientLibrary := TPath.GetFullPath(TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), ClientLibrary));
  end;
end;

procedure TDatabaseConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('server', Server);
  JSONObject.AddPair('port', Port);
  JSONObject.AddPair('database', Database);
  JSONObject.AddPair('username', Username);
  JSONObject.AddPair('password', Password);
  JSONObject.AddPair('protocol', Protocol);
  JSONObject.AddPair('characterSet', CharacterSet);
  JSONObject.AddPair('clientLibrary', ClientLibrary);
  JSONObject.AddPair('poolScadenzaMinuti', PoolScadenzaMinuti);
end;

{ TDocumentiConfig }

procedure TDocumentiConfig.Init;
begin
  Cartella := '';
  DimensioneMassimaMB := 20;
  TipiAmmessi := '.pdf;.p7m;.jpg;.jpeg;.png;.tif;.tiff;.xml;.txt;.csv;.doc;.docx;.xls;.xlsx;.odt;.ods;.zip';
end;

procedure TDocumentiConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('cartella', Cartella);
  JSONObject.TryGetValue<Integer>('dimensioneMassimaMB', DimensioneMassimaMB);
  JSONObject.TryGetValue<string>('tipiAmmessi', TipiAmmessi);
end;

procedure TDocumentiConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('cartella', Cartella);
  JSONObject.AddPair('dimensioneMassimaMB', DimensioneMassimaMB);
  JSONObject.AddPair('tipiAmmessi', TipiAmmessi);
end;

function TDocumentiConfig.TipoAmmesso(const NomeFile: string): Boolean;
var
  Estensione: string;
begin
  // Elenco vuoto: nessun tipo ammesso. La configurazione predefinita ne porta
  // uno, quindi un elenco vuoto e' una scelta esplicita di chi installa.
  if TipiAmmessi.Trim.IsEmpty then
    Exit(False);

  Estensione := LowerCase(ExtractFileExt(NomeFile));
  Result := MatchStr(Estensione, SplitString(LowerCase(TipiAmmessi), ';'));
end;

function TDocumentiConfig.DimensioneMassimaByte: Int64;
begin
  Result := Int64(DimensioneMassimaMB) * 1024 * 1024;
end;

{ TNetaConfig }

procedure TNetaConfig.Init;
begin
  Host := '';
  Porta := 211;
  StreamServerUrl := '';
  StreamServerUri := '';
end;

procedure TNetaConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('host', Host);
  JSONObject.TryGetValue<Integer>('porta', Porta);
  JSONObject.TryGetValue<string>('streamServerUrl', StreamServerUrl);
  JSONObject.TryGetValue<string>('streamServerUri', StreamServerUri);
end;

procedure TNetaConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('host', Host);
  JSONObject.AddPair('porta', Porta);
  JSONObject.AddPair('streamServerUrl', StreamServerUrl);
  JSONObject.AddPair('streamServerUri', StreamServerUri);
end;

{ TCodaConfig }

procedure TCodaConfig.Init;
begin
  Attiva := True;
  IntervalloSecondi := 5;
  MinutiBlocco := 15;
  AttesaRispostaSecondi := 15;
end;

procedure TCodaConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<Boolean>('attiva', Attiva);
  JSONObject.TryGetValue<Integer>('intervalloSecondi', IntervalloSecondi);
  JSONObject.TryGetValue<Integer>('minutiBlocco', MinutiBlocco);
  JSONObject.TryGetValue<Integer>('attesaRispostaSecondi', AttesaRispostaSecondi);

  // Valori che non avrebbero senso (zero o negativi) tornano al predefinito:
  // un intervallo nullo farebbe girare l'elaboratore senza pause.
  if IntervalloSecondi < 1 then
    IntervalloSecondi := 5;

  if MinutiBlocco < 1 then
    MinutiBlocco := 15;

  // Zero e' ammesso: la richiesta risponde subito 202. Oltre un minuto si
  // terrebbe occupato un thread del server web per niente.
  if AttesaRispostaSecondi < 0 then
    AttesaRispostaSecondi := 15;

  if AttesaRispostaSecondi > 60 then
    AttesaRispostaSecondi := 60;
end;

procedure TCodaConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('attiva', Attiva);
  JSONObject.AddPair('intervalloSecondi', IntervalloSecondi);
  JSONObject.AddPair('minutiBlocco', MinutiBlocco);
  JSONObject.AddPair('attesaRispostaSecondi', AttesaRispostaSecondi);
end;

{ TMantisConfig }

procedure TMantisConfig.Init;
begin
  // Acceso di partenza: a decidere se la funzione c'e' davvero e' il database
  // (MANTIS_URL e MANTIS_TOKEN della tabella CONFIG).
  Abilitato := True;
  Prefisso := '';
  TimeoutMs := 15000;
  LimiteAlMinuto := 5;
end;

procedure TMantisConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<Boolean>('abilitato', Abilitato);
  JSONObject.TryGetValue<string>('prefisso', Prefisso);
  JSONObject.TryGetValue<Integer>('timeoutMs', TimeoutMs);
  JSONObject.TryGetValue<Integer>('limiteAlMinuto', LimiteAlMinuto);
end;

procedure TMantisConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('abilitato', Abilitato);
  JSONObject.AddPair('prefisso', Prefisso);
  JSONObject.AddPair('timeoutMs', TimeoutMs);
  JSONObject.AddPair('limiteAlMinuto', LimiteAlMinuto);
end;

{ TPostaConfig }

procedure TPostaConfig.Init;
begin
  Server := '';
  Porta := 587;
  Utente := '';
  Password := '';
  Tls := 'RequireTLS';
  VersioneTls := '';
  Mittente := '';
  NomeMittente := '';
  IdModello := 0;
end;

procedure TPostaConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('server', Server);
  JSONObject.TryGetValue<Integer>('porta', Porta);
  JSONObject.TryGetValue<string>('utente', Utente);
  JSONObject.TryGetValue<string>('password', Password);
  JSONObject.TryGetValue<string>('tls', Tls);
  JSONObject.TryGetValue<string>('versioneTls', VersioneTls);
  JSONObject.TryGetValue<string>('mittente', Mittente);
  JSONObject.TryGetValue<string>('nomeMittente', NomeMittente);
  JSONObject.TryGetValue<Integer>('idModello', IdModello);
end;

procedure TPostaConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('server', Server);
  JSONObject.AddPair('porta', Porta);
  JSONObject.AddPair('utente', Utente);
  JSONObject.AddPair('password', Password);
  JSONObject.AddPair('tls', Tls);
  JSONObject.AddPair('versioneTls', VersioneTls);
  JSONObject.AddPair('mittente', Mittente);
  JSONObject.AddPair('nomeMittente', NomeMittente);
  JSONObject.AddPair('idModello', IdModello);
end;

function TPostaConfig.SmtpConfigurato: Boolean;
begin
  // Senza server non c'e' dove spedire; senza mittente il server SMTP
  // rifiuterebbe il messaggio, o peggio lo spedirebbe a nome di chi ha
  // compilato il modulo del portale.
  Result := (not Server.Trim.IsEmpty) and (Porta > 0) and (not Mittente.Trim.IsEmpty);
end;

{ TFirmaConfig }

procedure TFirmaConfig.Init;
begin
  IntervalloStatoSecondi := 600;
  GiriMassimi := 4320;
end;

procedure TFirmaConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<Integer>('intervalloStatoSecondi', IntervalloStatoSecondi);
  JSONObject.TryGetValue<Integer>('giriMassimi', GiriMassimi);

  // Sotto il minuto si interrogherebbe il fornitore senza motivo: una busta
  // la firmano persone, in minuti o giorni.
  if IntervalloStatoSecondi < 60 then
    IntervalloStatoSecondi := 600;

  if GiriMassimi < 1 then
    GiriMassimi := 4320;
end;

procedure TFirmaConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('intervalloStatoSecondi', IntervalloStatoSecondi);
  JSONObject.AddPair('giriMassimi', GiriMassimi);
end;

{ TSpidConfig }

procedure TSpidConfig.Init;
begin
  ChiaveCifratura := '';
end;

procedure TSpidConfig.LoadFromJSON(JSONObject: TJSONObject);
begin
  JSONObject.TryGetValue<string>('chiaveCifratura', ChiaveCifratura);
end;

procedure TSpidConfig.SaveToJSON(JSONObject: TJSONObject);
begin
  JSONObject.AddPair('chiaveCifratura', ChiaveCifratura);
end;

{ TAppConfig }

constructor TAppConfig.Create;
begin
  inherited Create;
  FAutoOpenBrowser := True;
  FCartellaInterfaccia := '';
  FCorsOrigin := '*';
  FDevelopment := False;
  FEnableSwagger := True;
  FIndirizzoAscolto := '';
  FLogLevel := 'INFO';
  // Stessi valori del registro generale (LoggerPro.SmartInspectAppender):
  // 10 file da 10 MB. Prima il registro dei controller ruotava su file da
  // 5 KB, e la riga che spiegava un 403 spariva in pochi minuti.
  FLogMaxFileSizeKB := 10000;
  FLogMaxFiles := 10;
  FLogPath := 'logs';
  FServerPort := 8443;
  FDatabase.Init;
  FDocumenti.Init;
  FJWT.Init;
  FNeta.Init;
  FCoda.Init;
  FPosta.Init;
  FMantis.Init;
  FFirma.Init;
  FSpid.Init;

  LoadFromFile;
end;

destructor TAppConfig.Destroy;
begin
  inherited;
end;

class function TAppConfig.Instance: TAppConfig;
begin
  if not Assigned(FInstance) then
    FInstance := TAppConfig.Create;
  Result := FInstance;
end;

procedure TAppConfig.ApplicaLivelloRegistro;
var
  Livello: TLogLevel;
  LivelloLoggerPro: TLogType;
begin
  // Prima logLevel si leggeva e basta: il registro generale nasce
  // nell'initialization di LoggerPro.SmartInspectAppender, senza livello
  // minimo, e restava a DEBUG. Bastava la coda a vuoto (una riga di
  // ZZ_CODA_PRELEVA a ogni giro) a coprire tutto il resto.
  // StrToLogLevel prende la stringa vuota per DEBUG: una voce lasciata vuota
  // nel file riporterebbe proprio il registro sommerso da correggere.
  try
    if FLogLevel.Trim.IsEmpty then
      Livello := TLogLevel.levNormal
    else
      Livello := StrToLogLevel(FLogLevel.Trim);
  except
    on E: Exception do
    begin
      LogW(Format('logLevel "%s" non valido, si usa INFO', [FLogLevel]));
      Livello := TLogLevel.levNormal;
    end;
  end;

  case Livello of
    TLogLevel.levDebug:
      LivelloLoggerPro := TLogType.Debug;
    TLogLevel.levNormal:
      LivelloLoggerPro := TLogType.Info;
    TLogLevel.levWarning:
      LivelloLoggerPro := TLogType.Warning;
    TLogLevel.levFatal:
      LivelloLoggerPro := TLogType.Fatal;
  else
    LivelloLoggerPro := TLogType.Error;
  end;

  // Vanno impostati tutti e due. LogD(string) passa dritto al registro, che
  // filtra con il suo livello minimo; IsDebugEnabled e simili invece
  // riallineano il registro a UseLoggerVerbosityLevel, e lasciata a
  // levDebug lo riporterebbero a DEBUG alla prima chiamata.
  UseLoggerVerbosityLevel := Livello;
  Log.SetMinimumLevel(LivelloLoggerPro);
end;

function TAppConfig.GetConfigFilePath: string;
begin
  Result := ChangeFileExt(GetModuleName(HInstance), '.json');
end;

procedure TAppConfig.LoadFromFile;
var
  ConfigFile: string;
  tmp: string;
  JSONConfig: TJSONObject;
  JWTObj, DBObj, DocObj, NetaObj, CodaObj, PostaObj, FirmaObj, MantisObj, SpidObj: TJSONObject;
  ParsedValue: TJSONValue;
begin
  ConfigFile := GetConfigFilePath;

  if not FileExists(ConfigFile) then
  begin
    LogW('File di configurazione non trovato, creazione configurazione di default');
    SaveDefaultConfig;
  end;

  tmp := TFile.ReadAllText(ConfigFile);

  ParsedValue := TJSONObject.ParseJSONValue(tmp);
  if not(ParsedValue is TJSONObject) then
  begin
    ParsedValue.Free;
    raise Exception.CreateFmt('File di configurazione non valido: %s', [ConfigFile]);
  end;

  /// ////////////////////////////////////////////////////////////////////////
  ///
  JSONConfig := TJSONObject(ParsedValue);
  try

    if JSONConfig.TryGetValue<TJSONObject>('jwt', JWTObj) then
      FJWT.LoadFromJSON(JWTObj);

    if JSONConfig.TryGetValue<TJSONObject>('database', DBObj) then
      FDatabase.LoadFromJSON(DBObj);

    if JSONConfig.TryGetValue<TJSONObject>('documenti', DocObj) then
      FDocumenti.LoadFromJSON(DocObj);

    if JSONConfig.TryGetValue<TJSONObject>('neta', NetaObj) then
      FNeta.LoadFromJSON(NetaObj);

    if JSONConfig.TryGetValue<TJSONObject>('coda', CodaObj) then
      FCoda.LoadFromJSON(CodaObj);

    if JSONConfig.TryGetValue<TJSONObject>('posta', PostaObj) then
      FPosta.LoadFromJSON(PostaObj);

    if JSONConfig.TryGetValue<TJSONObject>('mantis', MantisObj) then
      FMantis.LoadFromJSON(MantisObj);

    if JSONConfig.TryGetValue<TJSONObject>('firma', FirmaObj) then
      FFirma.LoadFromJSON(FirmaObj);

    if JSONConfig.TryGetValue<TJSONObject>('spid', SpidObj) then
      FSpid.LoadFromJSON(SpidObj);

    JSONConfig.TryGetValue<Boolean>('autoOpenBrowser', FAutoOpenBrowser);
    JSONConfig.TryGetValue<string>('cartellaInterfaccia', FCartellaInterfaccia);
    JSONConfig.TryGetValue<string>('corsOrigin', FCorsOrigin);
    JSONConfig.TryGetValue<Boolean>('development', FDevelopment);
    JSONConfig.TryGetValue<Boolean>('enableSwagger', FEnableSwagger);
    JSONConfig.TryGetValue<string>('indirizzoAscolto', FIndirizzoAscolto);
    JSONConfig.TryGetValue<string>('logLevel', FLogLevel);
    JSONConfig.TryGetValue<string>('logPath', FLogPath);
    JSONConfig.TryGetValue<Integer>('logMaxFileSizeKB', FLogMaxFileSizeKB);
    JSONConfig.TryGetValue<Integer>('logMaxFiles', FLogMaxFiles);
    JSONConfig.TryGetValue<Integer>('serverPort', FServerPort);
  finally
    JSONConfig.Free;
  end;

  // Un valore assurdo nel file non deve riportare il registro a pochi KB.
  if FLogMaxFileSizeKB < 100 then
    FLogMaxFileSizeKB := 100;
  if FLogMaxFiles < 1 then
    FLogMaxFiles := 1;

  FCartellaInterfaccia := FCartellaInterfaccia.Trim;
  if (not FCartellaInterfaccia.IsEmpty) and TPath.IsRelativePath(FCartellaInterfaccia) then
    FCartellaInterfaccia := TPath.GetFullPath(TPath.Combine(ExtractFilePath(GetModuleName(HInstance)), FCartellaInterfaccia));

  FIndirizzoAscolto := FIndirizzoAscolto.Trim;

  ApplicaLivelloRegistro;

  LogI('Configurazione caricata da: ' + ConfigFile);
end;

procedure TAppConfig.SaveDefaultConfig;
var
  ConfigFile: string;
  JSONConfig: TJSONObject;
  JWTObj, DBObj, DocObj, NetaObj, CodaObj, PostaObj, FirmaObj, MantisObj, SpidObj: TJSONObject;
begin

  JSONConfig := TJSONObject.Create;
  try
    JSONConfig.AddPair('autoOpenBrowser', AutoOpenBrowser);
    JSONConfig.AddPair('cartellaInterfaccia', CartellaInterfaccia);
    JSONConfig.AddPair('corsOrigin', CorsOrigin);
    JSONConfig.AddPair('enableSwagger', EnableSwagger);
    JSONConfig.AddPair('indirizzoAscolto', IndirizzoAscolto);
    // Stesso nome usato in lettura (LoadFromFile): TryGetValue distingue
    // maiuscole e minuscole, e con 'Development' la voce veniva ignorata.
    JSONConfig.AddPair('development', Development);
    JSONConfig.AddPair('logLevel', LogLevel);
    JSONConfig.AddPair('logPath', LogPath);
    JSONConfig.AddPair('logMaxFileSizeKB', LogMaxFileSizeKB);
    JSONConfig.AddPair('logMaxFiles', LogMaxFiles);
    JSONConfig.AddPair('serverPort', ServerPort);

    JWTObj := TJSONObject.Create;
    JWT.SaveToJSON(JWTObj);
    JSONConfig.AddPair('jwt', JWTObj);

    DBObj := TJSONObject.Create;
    Database.SaveToJSON(DBObj);
    JSONConfig.AddPair('database', DBObj);

    DocObj := TJSONObject.Create;
    Documenti.SaveToJSON(DocObj);
    JSONConfig.AddPair('documenti', DocObj);

    NetaObj := TJSONObject.Create;
    Neta.SaveToJSON(NetaObj);
    JSONConfig.AddPair('neta', NetaObj);

    CodaObj := TJSONObject.Create;
    Coda.SaveToJSON(CodaObj);
    JSONConfig.AddPair('coda', CodaObj);

    PostaObj := TJSONObject.Create;
    Posta.SaveToJSON(PostaObj);
    JSONConfig.AddPair('posta', PostaObj);

    MantisObj := TJSONObject.Create;
    Mantis.SaveToJSON(MantisObj);
    JSONConfig.AddPair('mantis', MantisObj);

    FirmaObj := TJSONObject.Create;
    Firma.SaveToJSON(FirmaObj);
    JSONConfig.AddPair('firma', FirmaObj);

    SpidObj := TJSONObject.Create;
    Spid.SaveToJSON(SpidObj);
    JSONConfig.AddPair('spid', SpidObj);

    /// ///////
    ConfigFile := GetConfigFilePath;
    TFile.WriteAllText(ConfigFile, JSONConfig.Format(4));
    LogI('Configurazione di default salvata in: ' + ConfigFile);
  finally
    FreeAndNil(JSONConfig);
  end;
end;

function TAppConfig.IsValid: Boolean;
begin
  Result := Database.IsValid and JWT.IsValid;

  if not Result then
    LogE('Configurazione non valida: verificare database e jwt');
end;

initialization

finalization

FreeAndNil(TAppConfig.FInstance);

end.
