// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-06
// ---------------------------------------------------------------------------
unit App.Profile;

// Interfaccia e registro dei profili applicativi.
//
// Il nucleo di zServer non sa che esistono WT e Gesty: chiede al profilo
// corrente il codice dell'applicativo, come autenticare, come impostare il
// contesto di sessione sul database, quale clausola di perimetro aggiungere
// e quali controller di dominio registrare.
//
// Nessuna unit di questo file dipende da WT o da Gesty. I profili si
// iscrivono da soli nella propria sezione initialization, e quale profilo
// finisca nell'eseguibile lo decide la clausola uses del progetto.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  MVCFramework;

type
  /// <summary>
  /// Esito dell'autenticazione. E' l'unione dei parametri di uscita di
  /// USR_LOGIN dei due prodotti: WT restituisce RUOLO, Gesty TIPO_USER e
  /// HOST_LDAP. Il campo Ruolo porta il valore di entrambi, perche' per il
  /// nucleo il significato e' lo stesso.
  /// </summary>
  TAuthResult = record
    Success: Boolean;
    UserId: Int64;
    IdSessione: Int64;
    Nominativo: string;
    Ruolo: string;
    AdminUser: Boolean;
    DataScadenzaPassword: TDateTime;
    HostLDAP: string;
    RichiedeOtp: Boolean;
    // Distingue le credenziali sbagliate da un guasto: senza questo il
    // chiamante restituisce 500 anche quando la password e' solo errata (Z13).
    CredenzialiNonValide: Boolean;
    ErrorMessage: string;
    // Aree web dell'utente e area della sessione (fase 0 delle aree,
    // OUT\20261102-pipa-inizializzazione-progetto). Vuote dove il prodotto
    // non ha aree: il token resta quello di prima.
    Aree: TArray<string>;
    Area: string;
    procedure Clear;
  end;

  /// <summary>
  /// Un modulo dell'utente in un comune (2026-11-06, moduli di Pipa per comune
  /// e per gruppo). In WT e' una riga di USR_UTENTE_MODULI_WEB: la coppia
  /// modulo-comune e' gia' calcolata gruppo per gruppo, e Scrittura e' vero se
  /// almeno un gruppo che la porta ha ACCESS W.
  /// </summary>
  TModuloUtente = record
    Modulo: string;
    Belfiore: string;
    Scrittura: Boolean;
  end;

  TModuliUtente = TArray<TModuloUtente>;

  IAppProfile = interface
    ['{3F1B8C42-9E7A-4D65-9C31-7A2E6D5B0418}']
    // ── Identificazione ──
    function Codice: string;
    function CodiceApplicativo: string;

    // ── Autenticazione: incapsula la firma di USR_LOGIN del prodotto ──
    function Autentica(const UserName, Password: string): TAuthResult;

    // ── Contesto: incapsula la firma di USR_CONTEXT_SET del prodotto ──
    procedure ImpostaContesto(Connessione: TFDConnection; const UserId, IdSessione: Int64; const UserName: string);

    /// <summary>
    /// Svuota il contesto della connessione (USR_CONTEXT_CLEAR). Serve alle
    /// richieste senza utente: il raggruppamento ricicla la connessione
    /// fisica insieme al contesto di chi l'ha usata prima, e senza questa
    /// pulizia USR_LOG attribuirebbe a lui le scritture delle azioni pubbliche.
    /// </summary>
    procedure AzzeraContesto(Connessione: TFDConnection);

    // ── Perimetro di visibilita: su WT il filtro sui comuni abilitati,
    // su Gesty una stringa vuota ──
    function ClausolaPerimetro(const NomeRelazione: string): string;

    /// <summary>
    /// Verifica che il comune e l'azienda di lavoro scelti dall'operatore
    /// siano fra quelli abilitati all'utente. Arrivano dal browser, quindi
    /// non ci si puo' fidare: il controllo e' la differenza fra un filtro e
    /// una sicurezza. Su Gesty non esiste un perimetro per comune o azienda
    /// e non c'e' niente da verificare.
    /// </summary>
    function AmbitoAmmesso(const Belfiore: string; const IdAzienda: Int64): Boolean;

    // ── Documentale: la classe OBJ_CLASSES da usare per una entita ──
    function ClasseDocumentale(const NomeEntita: string): string;

    /// <summary>
    /// Percorso completo del file nel documentale, solo se il file sta nel
    /// perimetro della sessione; vuoto se il file non esiste o l'utente non
    /// lo puo' vedere. Il nucleo risponde 404 in tutti e due i casi. La
    /// funzione che lo calcola ha nome e regole diverse nei due prodotti — in
    /// WT WEB_OBJ_FILES_GET_FULL_FILE_NAME(ID_SESSIONE_WEB, ID_OBJECT_FILE),
    /// in Gesty WEB.FILE_GET_FULL_FILE_NAME(ID_SESSIONE, ID_OBJECT_FILE) —
    /// quindi il nucleo chiede il risultato, non la SQL.
    /// </summary>
    function PercorsoFile(const IdObjectFile, IdSessione: Int64): string;

    /// <summary>
    /// Vero se la sessione puo' allegare un file all'oggetto Oid. Il
    /// caricamento riceve l'Oid dal browser e OBJ_FILES_ADD accetta qualunque
    /// valore: senza questa verifica un cittadino allegherebbe un file a una
    /// richiesta di un altro. Il prodotto restringe solo dove serve; il
    /// predefinito non cambia niente rispetto a prima.
    /// </summary>
    function OggettoAmmesso(const Oid, IdSessione: Int64): Boolean;

    // ── Controller specifici del prodotto ──
    function ControllerDiDominio: TArray<TMVCControllerClazz>;

    /// <summary>
    /// Azioni raggiungibili senza token, nella forma 'TWTAdminController.Ping'.
    /// Sostituisce l'attributo [SkipJWT] del vecchio server, che in
    /// DMVCFramework non esiste: la deroga vive qui, in un elenco esplicito
    /// che si legge tutto in una volta, invece di essere sparsa sui metodi.
    /// </summary>
    function AzioniPubbliche: TArray<string>;

    // ── Aree (fase 0): un'area e' un'app web del prodotto (in WT una riga
    // di USR_APPS). I prodotti senza aree le implementano con
    // TAppProfileBase, che non cambia niente rispetto a prima ──

    /// <summary>
    /// Come Autentica, ma entra nell'area chiesta se l'utente la puo' aprire.
    /// Area vuota o non ammessa: decide il prodotto. Riempie Aree e Area.
    /// </summary>
    function AutenticaInArea(const UserName, Password, Area: string): TAuthResult;

    /// <summary>Aree dell'utente e area della sessione, per il rinnovo del token.</summary>
    procedure LeggiAree(const UserName: string; const IdSessione: Int64; out Aree: TArray<string>; out Area: string);

    /// <summary>
    /// Porta la sessione in un'altra area dell'utente. Solleva EMVCException
    /// con il motivo se l'area non e' ammessa, e' fuori fascia oraria o
    /// chiede un secondo fattore che la sessione non ha verificato.
    /// </summary>
    procedure CambiaArea(const IdSessione: Int64; const Area: string);

    /// <summary>
    /// Vero se la procedura (Tipo 'P') o il dataset (Tipo 'D') si puo' usare
    /// nell'area della sessione. Chiamata dopo la verifica dell'autorizzazione.
    /// </summary>
    function AmmessoNellArea(const IdSessione: Int64; const Tipo, Nome: string): Boolean;

    // ── Moduli (2026-11-06): un dataset o una procedura possono appartenere a
    // un modulo (BASE_WEB_DATASETS.MODULO, BASE_WEB_PROCEDURE.MODULO). I
    // prodotti senza moduli li implementano con TAppProfileBase: nessun modulo
    // per l'utente, e un oggetto con il modulo non esiste perche' la colonna
    // manca ──

    /// <summary>
    /// Moduli dell'utente, una riga per modulo e comune. Un elenco vuoto vuol
    /// dire nessun modulo: ogni dataset o procedura con un modulo e' rifiutato.
    /// </summary>
    function ModuliUtente(const UserName: string): TModuliUtente;

    /// <summary>
    /// Restringe il perimetro della richiesta in corso ai soli comuni dati,
    /// cioe' quelli in cui l'utente ha il modulo dell'oggetto chiesto. Vale
    /// sulla connessione della richiesta fino alla sua fine: la richiesta
    /// successiva dichiara di nuovo il contesto e riparte dal perimetro intero.
    /// Restringe soltanto, non allarga mai. Nessun effetto dove il prodotto
    /// non ha un perimetro per comune.
    /// </summary>
    procedure RestringiComuniDellaRichiesta(const Comuni: TArray<string>);

    /// <summary>
    /// Vero se il modulo e' uno di quelli attivati dall'azienda (GeCo,
    /// 2026-11-06) e l'utente lo ha in almeno una delle aziende dei suoi
    /// gruppi. Si chiede solo dopo che ModuliUtente non ha dato il modulo per
    /// nessun comune: un modulo per comune non e' mai per azienda. Non
    /// restringe niente: le aziende non cambiano il perimetro per comune.
    /// </summary>
    function ModuloAttivoPerAzienda(const UserName, Modulo: string): Boolean;

    /// <summary>
    /// Vero se il modulo e' attivo (USR_MODULI_COMUNI) in almeno uno dei comuni
    /// del cittadino, cioe' quelli delle utenze e dell'intestatario che sta
    /// usando (Riciclario, 2026-11-06). Si chiede solo dopo che ne' i comuni
    /// ne' l'azienda hanno dato il modulo. Non restringe niente: i dataset del
    /// cittadino filtrano gia' per intestatario, quindi il modulo e' un
    /// permesso tutto o niente.
    /// </summary>
    function ModuloAttivoPerCittadino(const UserName, Modulo: string): Boolean;

    /// <summary>
    /// Moduli del portale del cittadino attivi nei comuni del cittadino, una
    /// riga per modulo e comune, sempre in sola lettura (Scrittura falsa).
    /// Servono a /auth/moduli perche' Pipa nasconda le voci spente del
    /// portale; la protezione resta a VerificaModulo. Vuoto se il prodotto non
    /// ha un portale del cittadino.
    /// </summary>
    function ModuliCittadino(const UserName: string): TModuliUtente;

    /// <summary>
    /// Vero se il modulo e' dato all'utente da uno dei suoi gruppi
    /// (USR_GRUPPI_MODULI), senza comuni: e' il caso dei moduli di GERA
    /// (2026-11-07), che seguono l'operatore e non un comune. Con Scrittura si
    /// chiede l'accesso W. Si chiede solo dopo che i comuni, l'azienda e il
    /// cittadino non hanno dato il modulo. Non restringe niente.
    /// </summary>
    function ModuloAttivoPerGruppo(const UserName, Modulo: string; const Scrittura: Boolean): Boolean;

    /// <summary>
    /// Moduli senza comune dati all'utente dai suoi gruppi (Gera.*), una riga
    /// per modulo con Belfiore vuoto. Servono a /auth/moduli perche' Pipa
    /// nasconda le voci spente; la protezione resta a VerificaModulo.
    /// </summary>
    function ModuliGruppo(const UserName: string): TModuliUtente;
  end;

  TAppProfiles = class
  private
    class var FRegistrati: TDictionary<string, IAppProfile>;
    class var FCorrente: IAppProfile;
  public
    class procedure Registra(const Profilo: IAppProfile);
    class function Corrente: IAppProfile;
    class function Registrati: TArray<string>;
  end;

/// <summary>
/// Riconosce i messaggi con cui USR_LOGIN respinge un accesso. Serve a
/// distinguere le credenziali sbagliate da un guasto del database: senza
/// questa distinzione il chiamante restituisce 500 con il messaggio grezzo
/// di Firebird anche quando la password e' solo errata (Z13).
/// I messaggi sono gli stessi in WT e in Gesty: entrambe le procedure
/// sollevano RAISE_ERROR con lo stesso testo.
/// </summary>
function AccessoNegato(const Messaggio: string): Boolean;

implementation

uses
  System.StrUtils,
  App.Config;

function AccessoNegato(const Messaggio: string): Boolean;
const
  MessaggiDiRifiuto: array [0 .. 4] of string = (
    'Utente/password non validi',
    'Utente/Password non validi',
    'Utente non valido',
    'Utente non abilitato per questa applicazione',
    'Risultano attive');
var
  Rifiuto: string;
begin
  Result := False;

  for Rifiuto in MessaggiDiRifiuto do
    if ContainsText(Messaggio, Rifiuto) then
      Exit(True);
end;

{ TAuthResult }

procedure TAuthResult.Clear;
begin
  Success := False;
  UserId := 0;
  IdSessione := 0;
  Nominativo := '';
  Ruolo := '';
  AdminUser := False;
  DataScadenzaPassword := 0;
  HostLDAP := '';
  RichiedeOtp := False;
  CredenzialiNonValide := False;
  ErrorMessage := '';
  Aree := [];
  Area := '';
end;

{ TAppProfiles }

class procedure TAppProfiles.Registra(const Profilo: IAppProfile);
begin
  if not Assigned(FRegistrati) then
    FRegistrati := TDictionary<string, IAppProfile>.Create;

  FRegistrati.AddOrSetValue(UpperCase(Profilo.Codice), Profilo);
end;

class function TAppProfiles.Corrente: IAppProfile;
begin
  if not Assigned(FCorrente) then
  begin
    if not Assigned(FRegistrati) then
      raise Exception.Create('Nessun profilo applicativo compilato in questo eseguibile.');

    // Con la compilazione condizionata il registro contiene un profilo solo,
    // ed e' quello dell'eseguibile: il prodotto lo decide la configurazione
    // di compilazione (PRODOTTO_WT o PRODOTTO_GESTY), non un file accanto.
    if FRegistrati.Count <> 1 then
      raise Exception.CreateFmt('Questo eseguibile deve contenere un solo profilo applicativo, ne contiene %d: %s',
        [FRegistrati.Count, string.Join(', ', Registrati)]);

    for var Voce in FRegistrati do
      FCorrente := Voce.Value;
  end;

  Result := FCorrente;
end;

class function TAppProfiles.Registrati: TArray<string>;
begin
  if Assigned(FRegistrati) then
    Result := FRegistrati.Keys.ToArray
  else
    Result := [];
end;

initialization

finalization

TAppProfiles.FCorrente := nil;
FreeAndNil(TAppProfiles.FRegistrati);

end.
