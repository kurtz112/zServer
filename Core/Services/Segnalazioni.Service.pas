// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-18
// ---------------------------------------------------------------------------
unit Segnalazioni.Service;

// Apertura di un ticket Mantis per conto dell'utente che segnala un errore
// del portale.
//
// Il browser non parla mai con Mantis: manda il testo dell'errore a zServer e
// qui nasce il ticket. Indirizzo, token, progetto e categoria di Mantis si
// leggono dalla tabella CONFIG del database servito con la procedura
// MANTIS_GET_PARAMS, la stessa che usano Gesty e WT: ogni database ha il suo
// progetto e il token non esce da questo processo. Dal file di configurazione
// di zServer (sezione "mantis", facoltativa) vengono solo le regole del
// server: interruttore, prefisso dell'oggetto, attesa massima e tetto al
// minuto.
//
// Tre protezioni, perche' il testo arriva dal browser e quindi non e' fidato:
//  - il testo viene ripulito da cio' che somiglia a un segreto (intestazioni
//    Authorization, token JWT, password) e dai parametri degli indirizzi,
//    che possono contenere dati di persone;
//  - lunghezze massime su ogni campo;
//  - un tetto di segnalazioni al minuto per utente (App.Config, LimiteAlMinuto),
//    contro un errore che si ripete in ciclo.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.JSON,
  FireDAC.Comp.Client;

type
  TSegnalazione = record
    // Chi segnala: lo decide il server dalla sessione, non il browser.
    Utente: string;
    IdUtente: Int64;
    // Quel che manda il browser (ripulito qui).
    Pagina: string;
    Testo: string;
    Nota: string;
    // Dati raccolti dal browser (richieste recenti, errori della console,
    // schermo, ora): aiutano a ricostruire cosa e' successo prima dell'errore.
    Tecnici: string;
    Agente: string;
  end;

  /// <summary>Collegamento a Mantis del database servito (tabella CONFIG).</summary>
  TParametriMantis = record
    Progetto: string;
    Url: string;
    Token: string;
    Categoria: string;
  end;

  // Al browser torna solo il numero: l'indirizzo di Mantis non gli serve e
  // l'utente di un cliente potrebbe non avere accesso a Mantis.
  TEsitoSegnalazione = record
    IdTicket: Integer;
  end;

  TSegnalazioniService = class
  private
    class var FLucchetto: TCriticalSection;
    class var FInvii: TObjectDictionary<Int64, TList<TDateTime>>;
    class var FUsaIndex: Boolean;

    class function CategoriaDelProgetto(const Url, Token, Progetto: string; const TimeoutMs: Integer): string; static;
  public
    class constructor Create;
    class destructor Destroy;

    /// <summary>
    /// Legge url, token, progetto e categoria da MANTIS_GET_PARAMS. Se la
    /// procedura non esiste (database piu' vecchio) o fallisce, risponde con
    /// valori vuoti: la funzione resta spenta, senza errori per l'utente.
    /// </summary>
    class function LeggiParametri(Connessione: TFDConnection): TParametriMantis; static;

    /// <summary>
    /// Vera se l'interruttore del .json e' acceso e il database ha indirizzo,
    /// token e progetto di Mantis.
    /// </summary>
    class function Abilitata(const Parametri: TParametriMantis): Boolean; static;

    /// <summary>
    /// Toglie dal testo cio' che non deve finire in un ticket: intestazioni
    /// Authorization, token JWT, valori di token e password, parametri degli
    /// indirizzi. Poi lo taglia a Massimo caratteri.
    /// </summary>
    class function Ripulisci(const Testo: string; const Massimo: Integer): string; static;

    /// <summary>
    /// Vero se l'utente non ha superato il tetto al minuto; in tal caso
    /// registra l'invio. Il conteggio e' in memoria: un riavvio lo azzera.
    /// </summary>
    class function InvioAmmesso(const IdUtente: Int64): Boolean; static;

    /// <summary>Apre il ticket e ne restituisce il numero.</summary>
    class function Apri(const Segnalazione: TSegnalazione; const Parametri: TParametriMantis): TEsitoSegnalazione; static;
  end;

implementation

uses
  System.DateUtils,
  System.RegularExpressions,
  System.Net.HttpClient,
  System.Net.URLClient,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Logger,
  App.Config;

const
  LunghezzaMassimaOggetto = 120;
  // Piu' errori nello stesso istante arrivano in un'unica segnalazione.
  LunghezzaMassimaTesto = 10000;
  LunghezzaMassimaNota = 2000;
  LunghezzaMassimaTecnici = 3000;
  LunghezzaMassimaPagina = 300;

{ TSegnalazioniService }

class constructor TSegnalazioniService.Create;
begin
  FLucchetto := TCriticalSection.Create;
  FInvii := TObjectDictionary<Int64, TList<TDateTime>>.Create([doOwnsValues]);
  FUsaIndex := False;
end;

class destructor TSegnalazioniService.Destroy;
begin
  FreeAndNil(FInvii);
  FreeAndNil(FLucchetto);
end;

class function TSegnalazioniService.LeggiParametri(Connessione: TFDConnection): TParametriMantis;
var
  Query: TFDQuery;
begin
  Result := Default(TParametriMantis);

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text := 'SELECT MANTIS_GET_PARAMS.DB, MANTIS_GET_PARAMS.MANTIS_URL, MANTIS_GET_PARAMS.MANTIS_TOKEN, MANTIS_GET_PARAMS.MANTIS_CATEGORIA FROM MANTIS_GET_PARAMS';
    try
      Query.Open;
      if not Query.IsEmpty then
      begin
        Result.Progetto := Query.FieldByName('DB').AsString.Trim;
        Result.Url := Query.FieldByName('MANTIS_URL').AsString.Trim;
        Result.Token := Query.FieldByName('MANTIS_TOKEN').AsString.Trim;
        Result.Categoria := Query.FieldByName('MANTIS_CATEGORIA').AsString.Trim;
      end;
    except
      on E: Exception do
      begin
        // Il messaggio puo' dire solo che la procedura manca: niente valori,
        // niente segnalazione, e il registro spiega perche'.
        Log.Warn('MANTIS_GET_PARAMS non letta, segnalazioni spente: ' + E.Message, 'segnalazioni');
        Result := Default(TParametriMantis);
      end;
    end;
  finally
    Query.Free;
  end;
end;

class function TSegnalazioniService.Abilitata(const Parametri: TParametriMantis): Boolean;
begin
  // Senza indirizzo non c'e' dove aprire il ticket, senza token Mantis
  // rifiuta la richiesta, senza progetto non sa dove metterlo.
  Result := TAppConfig.Instance.Mantis.Abilitato and (not Parametri.Url.IsEmpty) and (not Parametri.Token.IsEmpty) and (not Parametri.Progetto.IsEmpty);
end;

class function TSegnalazioniService.Ripulisci(const Testo: string; const Massimo: Integer): string;
begin
  Result := Testo;

  // Intestazioni di autenticazione: "Bearer xxx", "Basic xxx".
  Result := TRegEx.Replace(Result, '(?i)\b(bearer|basic)\s+[A-Za-z0-9\-\._~\+/=]+', '$1 ***');
  // Token JWT: tre blocchi separati da punti, il primo comincia con eyJ.
  Result := TRegEx.Replace(Result, 'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*', '***');
  // Coppie nome/valore con un nome che indica un segreto.
  Result := TRegEx.Replace(Result, '(?i)((?:token|password|passwd|pwd|secret|apikey|api_key|authorization)["'']?\s*[:=]\s*["'']?)[^\s"''&,;}]+', '$1***');
  // Parametri degli indirizzi (filtri, ricerche): possono contenere dati di persone.
  Result := TRegEx.Replace(Result, '(?<=\S)\?[^\s"'']+', '?...');

  Result := Result.Replace(#0, '').Trim;
  if (Massimo > 0) and (Result.Length > Massimo) then
    Result := Result.Substring(0, Massimo) + '...';
end;

class function TSegnalazioniService.InvioAmmesso(const IdUtente: Int64): Boolean;
var
  Limite: Integer;
  Adesso: TDateTime;
  Invii: TList<TDateTime>;
  Posizione: Integer;
begin
  Limite := TAppConfig.Instance.Mantis.LimiteAlMinuto;
  // Un tetto zero o negativo nel file vorrebbe dire "mai": si prende come
  // "nessun tetto", e non come spegnimento, che si fa con "abilitato".
  if Limite <= 0 then
    Exit(True);

  Adesso := Now;
  FLucchetto.Enter;
  try
    if not FInvii.TryGetValue(IdUtente, Invii) then
    begin
      Invii := TList<TDateTime>.Create;
      FInvii.Add(IdUtente, Invii);
    end;

    for Posizione := Invii.Count - 1 downto 0 do
      if SecondsBetween(Adesso, Invii[Posizione]) >= 60 then
        Invii.Delete(Posizione);

    Result := Invii.Count < Limite;
    if Result then
      Invii.Add(Adesso);
  finally
    FLucchetto.Leave;
  end;
end;

// Prima categoria del progetto, per quando CONFIG non ne indica una.
// Mantis risponde su /api/rest o, se il server web non riscrive gli
// indirizzi, su /api/rest/index.php: si prova la prima e, a un 404, la
// seconda (come TMantisApi nei programmi desktop).
class function TSegnalazioniService.CategoriaDelProgetto(const Url, Token, Progetto: string; const TimeoutMs: Integer): string;
var
  Client: THTTPClient;
  Risposta: IHTTPResponse;
  Radice, Elemento, Categoria: TJSONValue;
  Progetti, Categorie: TJSONArray;
  Corpo: string;
  Indirizzo: string;
begin
  Result := '';

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := TimeoutMs;
    Client.ResponseTimeout := TimeoutMs;
    Client.Accept := 'application/json';
    Client.CustomHeaders['Authorization'] := Token;

    Indirizzo := Url + '/api/rest/projects';
    if FUsaIndex then
      Indirizzo := Url + '/api/rest/index.php/projects';

    Risposta := Client.Get(Indirizzo);
    if (Risposta.StatusCode = 404) and (not FUsaIndex) then
    begin
      FUsaIndex := True;
      Risposta := Client.Get(Url + '/api/rest/index.php/projects');
    end;

    if (Risposta.StatusCode < 200) or (Risposta.StatusCode >= 300) then
      Exit;

    Corpo := Risposta.ContentAsString(TEncoding.UTF8);
  finally
    Client.Free;
  end;

  Radice := TJSONObject.ParseJSONValue(Corpo);
  try
    if not(Radice is TJSONObject) then
      Exit;
    if not TJSONObject(Radice).TryGetValue<TJSONArray>('projects', Progetti) then
      Exit;

    for Elemento in Progetti do
      if (Elemento is TJSONObject) and SameText(TJSONObject(Elemento).GetValue<string>('name', ''), Progetto) then
      begin
        if TJSONObject(Elemento).TryGetValue<TJSONArray>('categories', Categorie) and (Categorie.Count > 0) then
        begin
          Categoria := Categorie.Items[0];
          if Categoria is TJSONObject then
            Result := TJSONObject(Categoria).GetValue<string>('name', '')
          else
            Result := Categoria.Value;
        end;
        Break;
      end;
  finally
    Radice.Free;
  end;
end;

class function TSegnalazioniService.Apri(const Segnalazione: TSegnalazione; const Parametri: TParametriMantis): TEsitoSegnalazione;
var
  Configurazione: TMantisConfig;
  Client: THTTPClient;
  Risposta: IHTTPResponse;
  Corpo: TJSONObject;
  Voce: TJSONObject;
  Radice: TJSONValue;
  Flusso: TStringStream;
  Oggetto, Descrizione, Pagina, Testo, Nota, Tecnici, Agente, Categoria, Base: string;
  Intestazioni: TNetHeaders;
  Tentativo: Integer;
  Indirizzo, Contenuto: string;
  Stato: Integer;
  Id: Integer;
begin
  Configurazione := TAppConfig.Instance.Mantis;
  if not Abilitata(Parametri) then
    raise EMVCException.Create(503, 'La segnalazione degli errori non è attiva su questo server.');

  Base := Parametri.Url;
  while Base.EndsWith('/') do
    Base := Base.Substring(0, Base.Length - 1);

  Pagina := Ripulisci(Segnalazione.Pagina, LunghezzaMassimaPagina);
  Testo := Ripulisci(Segnalazione.Testo, LunghezzaMassimaTesto);
  Nota := Ripulisci(Segnalazione.Nota, LunghezzaMassimaNota);
  Tecnici := Ripulisci(Segnalazione.Tecnici, LunghezzaMassimaTecnici);
  Agente := Ripulisci(Segnalazione.Agente, LunghezzaMassimaPagina);

  if Testo.IsEmpty then
    raise EMVCException.Create(400, 'Manca il testo dell''errore da segnalare.');

  // Oggetto: la prima riga dell'errore, che di solito dice cosa e' successo.
  Oggetto := Testo;
  if Oggetto.Contains(#10) then
    Oggetto := Oggetto.Substring(0, Oggetto.IndexOf(#10));
  Oggetto := Oggetto.Trim;
  if Oggetto.Length > LunghezzaMassimaOggetto then
    Oggetto := Oggetto.Substring(0, LunghezzaMassimaOggetto) + '...';

  if not Configurazione.Prefisso.Trim.IsEmpty then
    Oggetto := Configurazione.Prefisso.Trim + ' ' + Oggetto;

  Descrizione := 'Segnalazione di un errore dal portale, aperta dall''utente.' + sLineBreak + sLineBreak + 'Segnalato da: ' + Segnalazione.Utente + ' (id ' + Segnalazione.IdUtente.ToString + ')' + sLineBreak + 'Quando: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + sLineBreak + 'Pagina: ' + Pagina + sLineBreak + 'Browser: ' + Agente;

  if not Nota.IsEmpty then
    Descrizione := Descrizione + sLineBreak + sLineBreak + 'Nota dell''utente:' + sLineBreak + Nota;

  // Le richieste recenti e la console dicono cosa e' successo prima dell'errore:
  // stanno prima del dettaglio, che e' la parte lunga.
  if not Tecnici.IsEmpty then
    Descrizione := Descrizione + sLineBreak + sLineBreak + 'Dati tecnici del browser:' + sLineBreak + Tecnici;

  Descrizione := Descrizione + sLineBreak + sLineBreak + 'Dettaglio tecnico:' + sLineBreak + Testo;

  // La categoria e' obbligatoria in Mantis: se CONFIG non la indica si prende
  // la prima del progetto.
  Categoria := Parametri.Categoria;
  if Categoria.IsEmpty then
    Categoria := CategoriaDelProgetto(Base, Parametri.Token, Parametri.Progetto, Configurazione.TimeoutMs);
  if Categoria.IsEmpty then
    Categoria := 'General';

  Corpo := TJSONObject.Create;
  try
    Corpo.AddPair('summary', Oggetto);
    Corpo.AddPair('description', Descrizione);

    Voce := TJSONObject.Create;
    Voce.AddPair('name', Parametri.Progetto);
    Corpo.AddPair('project', Voce);

    Voce := TJSONObject.Create;
    Voce.AddPair('name', Categoria);
    Corpo.AddPair('category', Voce);

    Flusso := TStringStream.Create(Corpo.ToJSON, TEncoding.UTF8);
  finally
    Corpo.Free;
  end;

  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := Configurazione.TimeoutMs;
      Client.ResponseTimeout := Configurazione.TimeoutMs;
      Client.Accept := 'application/json';
      // Il token di Mantis va scritto cosi' com'e', senza "Bearer".
      Client.CustomHeaders['Authorization'] := Parametri.Token;
      Intestazioni := [TNetHeader.Create('Content-Type', 'application/json;charset=utf-8')];

      Risposta := nil;
      for Tentativo := 0 to 1 do
      begin
        Flusso.Position := 0;
        Indirizzo := Base + '/api/rest/issues';
        if FUsaIndex then
          Indirizzo := Base + '/api/rest/index.php/issues';

        Risposta := Client.Post(Indirizzo, Flusso, nil, Intestazioni);

        // Un 404 con gli indirizzi puliti vuol dire che il server web non li
        // riscrive: si riprova una volta con index.php.
        if (Risposta.StatusCode = 404) and (not FUsaIndex) then
        begin
          FUsaIndex := True;
          Continue;
        end;
        Break;
      end;

      Stato := Risposta.StatusCode;
      Contenuto := Risposta.ContentAsString(TEncoding.UTF8);
    finally
      Client.Free;
    end;
  finally
    Flusso.Free;
  end;

  if (Stato < 200) or (Stato >= 300) then
  begin
    // Il dettaglio di Mantis resta nel registro; al browser va un messaggio
    // che non rivela indirizzo, progetto o contenuto della risposta.
    Log.Error('Mantis ha rifiutato la segnalazione: HTTP %d %s', [Stato, Copy(Contenuto, 1, 500)], 'segnalazioni');
    raise EMVCException.Create(502, 'Non è stato possibile aprire la segnalazione. Riprovare più tardi o avvisare l''assistenza.');
  end;

  Id := 0;
  Radice := TJSONObject.ParseJSONValue(Contenuto);
  try
    if (Radice is TJSONObject) and TJSONObject(Radice).TryGetValue<TJSONObject>('issue', Voce) then
      Id := Voce.GetValue<Integer>('id', 0);
  finally
    Radice.Free;
  end;

  Log.Info('Segnalazione aperta su Mantis: ticket %d, utente %s', [Id, Segnalazione.Utente], 'segnalazioni');

  Result.IdTicket := Id;
end;

end.
