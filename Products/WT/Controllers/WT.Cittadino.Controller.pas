// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit WT.Cittadino.Controller;

// Riciclario (2026-11-07, OUT\20261107-riciclario-dati-veri): il token del cittadino
// porta, oltre a WTWEB_CITTADINO, le altre aree pensate per il cittadino
// (AREE_DEL_CITTADINO, oggi solo WTWEB_RICICLARIO) che i suoi gruppi hanno in
// USR_UTENTE_AREE_WEB. Prima portava solo WTWEB_CITTADINO, quindi Pipa non gli offriva
// il Riciclario e le sue pagine personali restavano sui dati di prova. Le aree degli
// operatori non entrano mai: l'elenco e' fisso qui, non preso dai gruppi. La sessione
// nasce comunque in WTWEB_CITTADINO; il passaggio al Riciclario lo fa
// USR_SESSIONE_APP_SET quando Pipa apre l'area, con i suoi controlli.

// Accesso con SPID (2026-11-04). Due rotte, stesso accesso (EseguiAccessoSpid):
// - POST /api/auth/login-spid: identita' mandata in chiaro, SIMULATA; funziona SOLO con
//   "development": true nella configurazione, altrimenti 403;
// - POST /api/auth/login-spid-gateway: ritorno del gateway SPID vero. Il browser arriva a
//   Pipa con ?data=..., la pagina manda qui il parametro. I dati sono cifrati AES-128-CBC con
//   HMAC-SHA256 (formato di login-cf.php del portale PHP) con la chiave "spid.chiaveCifratura"
//   del file di configurazione di zServer; senza chiave la rotta risponde 403. Oltre al PHP si
//   rifiuta la risposta gia' usata (RESPONSE_ID in USR_SPID_AUTHORIZATIONS). Scadenza: i dati
//   del gateway non portano un orario, quindi non si puo' controllare.

// Accesso del cittadino al portale (fase accesso, rilascio 3 di
// OUT\20261102-pipa-inizializzazione-progetto, analisi 20261103).
//
// POST /api/auth/login-cittadino chiama WEB_CIT_LOGIN cosi' com'e': la
// procedura del portale PHP, che apre la sessione con USR_LOGIN per l'app
// WTWEB_CITTADINO, registra l'accesso nel registro del portale e scrive la
// riga di WEB_CIT_PORTALI_SESSIONI senza la quale WEB_CIT_LOGIN_DATI_INTESTATARIO
// e le procedure di richiesta (WEB_CIT_SEGN_*) non trovano portale e comune.
//
// Scelte:
// - il token porta la sola area WTWEB_CITTADINO: il login ordinario continua
//   a non offrirla (USR_UTENTE_AREE_WEB), quindi un operatore non ci entra da
//   quel canale e un cittadino non apre le aree degli operatori;
// - chi puo' entrare lo decide USR_LOGIN (gruppo con l'app WTWEB_CITTADINO):
//   gli utenti SOFTLINE entrano finche' dura la deroga di sviluppo (S2);
// - il token dura 60 minuti (S5, SESSIONE_DURATA_MINUTI del portale) e non si
//   rinnova: la risposta non porta il refresh token, quindi alla scadenza
//   il cittadino rifa' l'accesso;
// - un utente amministratore non porta il ruolo admin nel token del portale.

interface

uses
  System.SysUtils,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  Base.Controller;

type

  // Identita' SPID gia' verificata. Altri: dati del gateway (non e' proprieta' del record)
  TIdentitaSpid = record
    CodiceFiscale: string;
    Nome: string;
    Cognome: string;
    Email: string;
    Portale: string;
    Belfiore: string;
    IdRisposta: string;
    Altri: TJSONObject;
  end;

  [MVCPath('/api/auth')]
  [MVCDoc('Accesso del cittadino al portale')]
  TWTCittadinoController = class(TBaseController)
  private
    function PortaleDaUsare(const Richiesto: string): string;
    function AreeDelCittadino(const UserId: Int64): TArray<string>;
    procedure EseguiAccessoSpid(const Identita: TIdentitaSpid; const Origine: string);
  public
    [MVCPath('/login-cittadino')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Accesso del cittadino: corpo { "username": "...", "password": "...", "portale": "...", "belfiore": "..." }; portale e belfiore sono facoltativi')]
    [MVCSwagSummary('Autenticazione', 'Accesso del cittadino al portale', 'default')]
    [MVCSwagResponses(200, 'Accesso riuscito: { "token": "...", "expires_in": secondi }')]
    [MVCSwagResponses(400, 'Utente, password o portale mancanti o portale non valido')]
    [MVCSwagResponses(401, 'Credenziali non valide o utente non abilitato al portale')]
    procedure LoginCittadino;

    [MVCPath('/login-spid')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Accesso del cittadino con SPID simulato (solo in sviluppo): corpo { "fiscalNumber": "...", "name": "...", "familyName": "...", "email": "...", "portale": "...", "belfiore": "..." }')]
    [MVCSwagSummary('Autenticazione', 'Accesso del cittadino con SPID simulato', 'default')]
    [MVCSwagResponses(200, 'Accesso riuscito: { "token": "...", "expires_in": secondi, "numero_intestatari": n }')]
    [MVCSwagResponses(400, 'Codice fiscale mancante o portale non valido')]
    [MVCSwagResponses(401, 'Accesso negato')]
    [MVCSwagResponses(403, 'Accesso SPID non attivo: la configurazione non e'' di sviluppo')]
    procedure LoginSpid;

    [MVCPath('/login-spid-gateway')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Ritorno dal gateway SPID: corpo { "data": "<dati cifrati del gateway>", "portale": "...", "belfiore": "..." }; portale e belfiore sono facoltativi')]
    [MVCSwagSummary('Autenticazione', 'Accesso del cittadino con il gateway SPID', 'default')]
    [MVCSwagResponses(200, 'Accesso riuscito: { "token": "...", "expires_in": secondi, "numero_intestatari": n }')]
    [MVCSwagResponses(400, 'Dati mancanti o portale non valido')]
    [MVCSwagResponses(401, 'Dati non autentici, risposta gia'' usata o accesso negato')]
    [MVCSwagResponses(403, 'Accesso SPID non attivo: manca la chiave di cifratura nella configurazione')]
    procedure LoginSpidGateway;
  end;

implementation

uses
  System.Variants,
  System.DateUtils,
  System.Math,
  System.Hash,
  System.NetEncoding,
  FireDAC.Comp.Client,
  App.Config,
  App.Profile,
  Connection.Pool,
  Data.Service,
  Json.Values,
  Token.Service;

const
  AREA_CITTADINO = 'WTWEB_CITTADINO';

  // Aree che il cittadino puo' aprire oltre al portale, se i suoi gruppi le hanno
  AREE_DEL_CITTADINO: array[0..0] of string = ('WTWEB_RICICLARIO');

  NOME_POSTAZIONE = 'zServer';
  LINGUA_PREDEFINITA = 'it';

  // Decisione S5: la sessione del cittadino dura 60 minuti.
  DURATA_SESSIONE_MINUTI = 60;

  // Parametro di WEB_CIT_LOGIN_SPID e nome del campo nei dati del gateway (come in login-cf.php)
  CAMPI_SPID: array[0..16, 0..1] of string = (
    ('SPID_PIVA', 'ivaCode'),
    ('SPID_LUOGO_DI_NASCITA', 'placeOfBirth'),
    ('SPID_NAZIONE_DI_NASCITA', 'countyOfBirth'),
    ('SPID_DATA_DI_NASCITA', 'dateOfBirth'),
    ('SPID_SESSO', 'gender'),
    ('SPID_NOME_AZIENDA', 'companyName'),
    ('SPID_SEDE_LEGALE', 'registeredOffice'),
    ('SPID_DATI_DOCUMENTO', 'idCard'),
    ('SPID_DATA_SCADENZA_DOCUMENTO', 'expirationDate'),
    ('SPID_TELEFONO', 'mobilePhone'),
    ('SPID_INDIRIZZO', 'address'),
    ('SPID_INDIRIZZO_DIGITALE', 'digitalAddress'),
    ('SPID_RESIDENZA_INDIRIZZO', 'domicileStreetAddress'),
    ('SPID_RESIDENZA_CAP', 'domicilePostalCode'),
    ('SPID_RESIDENZA_COMUNE', 'domicileMunicipality'),
    ('SPID_RESIDENZA_PROV', 'domicileProvince'),
    ('SPID_RESIDENZA_STATO', 'domicileNation'));

// AES-128 in Pascal puro (solo decifratura), senza librerie di sistema: zServer gira anche su Linux64.
// Tabelle calcolate all'avvio (CalcolaTabelleAes), cosi' non ci sono costanti da trascrivere.
var
  SostituzioneAes: array[0..255] of Byte;
  SostituzioneAesInversa: array[0..255] of Byte;

function MoltiplicaCampoAes(Primo, Secondo: Byte): Byte;
var
  Indice: Integer;
begin
  Result := 0;
  for Indice := 0 to 7 do
  begin
    if (Secondo and 1) <> 0 then
      Result := Result xor Primo;
    if (Primo and $80) <> 0 then
      Primo := Byte((Primo shl 1) xor $1B)
    else
      Primo := Byte(Primo shl 1);
    Secondo := Secondo shr 1;
  end;
end;

function RotazioneByte(Valore: Byte; Posti: Integer): Byte;
begin
  Result := Byte((Valore shl Posti) or (Valore shr (8 - Posti)));
end;

procedure CalcolaTabelleAes;
var
  Valore: Integer;
  Candidato: Integer;
  Inverso: Byte;
  Risultato: Byte;
begin
  for Valore := 0 to 255 do
  begin
    // Inverso moltiplicativo nel campo di Galois (lo zero resta zero), poi trasformazione affine
    Inverso := 0;
    if Valore <> 0 then
      for Candidato := 1 to 255 do
        if MoltiplicaCampoAes(Byte(Valore), Byte(Candidato)) = 1 then
        begin
          Inverso := Byte(Candidato);
          Break;
        end;
    Risultato := Inverso xor RotazioneByte(Inverso, 1) xor RotazioneByte(Inverso, 2) xor RotazioneByte(Inverso, 3) xor RotazioneByte(Inverso, 4) xor $63;
    SostituzioneAes[Valore] := Risultato;
    SostituzioneAesInversa[Risultato] := Byte(Valore);
  end;
end;

// Le 11 chiavi di giro (16 byte ciascuna) dalla chiave di 16 byte
procedure EspandiChiaveAes(const Chiave: TBytes; out ChiaviDiGiro: TBytes);
var
  Indice: Integer;
  Colonna: Integer;
  Parola: array[0..3] of Byte;
  Costante: Byte;
  Salvato: Byte;
begin
  SetLength(ChiaviDiGiro, 176);
  Move(Chiave[0], ChiaviDiGiro[0], 16);
  Costante := 1;
  for Indice := 4 to 43 do
  begin
    for Colonna := 0 to 3 do
      Parola[Colonna] := ChiaviDiGiro[(Indice - 1) * 4 + Colonna];
    if Indice mod 4 = 0 then
    begin
      Salvato := Parola[0];
      Parola[0] := SostituzioneAes[Parola[1]] xor Costante;
      Parola[1] := SostituzioneAes[Parola[2]];
      Parola[2] := SostituzioneAes[Parola[3]];
      Parola[3] := SostituzioneAes[Salvato];
      Costante := MoltiplicaCampoAes(Costante, 2);
    end;
    for Colonna := 0 to 3 do
      ChiaviDiGiro[Indice * 4 + Colonna] := ChiaviDiGiro[(Indice - 4) * 4 + Colonna] xor Parola[Colonna];
  end;
end;

// Decifra un blocco di 16 byte (stato in ordine di colonne, come nello standard)
procedure DecifraBloccoAes(const ChiaviDiGiro: TBytes; const Ingresso: TBytes; Inizio: Integer; var Stato: array of Byte);
var
  Giro: Integer;
  Indice: Integer;
  Colonna: Integer;
  Riga: Integer;
  Copia: array[0..15] of Byte;
begin
  for Indice := 0 to 15 do
    Stato[Indice] := Ingresso[Inizio + Indice] xor ChiaviDiGiro[160 + Indice];

  for Giro := 9 downto 0 do
  begin
    // Scorrimento inverso delle righe
    for Indice := 0 to 15 do
      Copia[Indice] := Stato[Indice];
    for Colonna := 0 to 3 do
      for Riga := 0 to 3 do
        Stato[((Colonna + Riga) mod 4) * 4 + Riga] := Copia[Colonna * 4 + Riga];
    // Sostituzione inversa dei byte e somma con la chiave di giro
    for Indice := 0 to 15 do
      Stato[Indice] := SostituzioneAesInversa[Stato[Indice]] xor ChiaviDiGiro[Giro * 16 + Indice];
    // Rimescolamento inverso delle colonne (non nell'ultimo passo)
    if Giro > 0 then
      for Colonna := 0 to 3 do
      begin
        for Riga := 0 to 3 do
          Copia[Riga] := Stato[Colonna * 4 + Riga];
        Stato[Colonna * 4 + 0] := MoltiplicaCampoAes(Copia[0], 14) xor MoltiplicaCampoAes(Copia[1], 11) xor MoltiplicaCampoAes(Copia[2], 13) xor MoltiplicaCampoAes(Copia[3], 9);
        Stato[Colonna * 4 + 1] := MoltiplicaCampoAes(Copia[0], 9) xor MoltiplicaCampoAes(Copia[1], 14) xor MoltiplicaCampoAes(Copia[2], 11) xor MoltiplicaCampoAes(Copia[3], 13);
        Stato[Colonna * 4 + 2] := MoltiplicaCampoAes(Copia[0], 13) xor MoltiplicaCampoAes(Copia[1], 9) xor MoltiplicaCampoAes(Copia[2], 14) xor MoltiplicaCampoAes(Copia[3], 11);
        Stato[Colonna * 4 + 3] := MoltiplicaCampoAes(Copia[0], 11) xor MoltiplicaCampoAes(Copia[1], 13) xor MoltiplicaCampoAes(Copia[2], 9) xor MoltiplicaCampoAes(Copia[3], 14);
      end;
  end;
end;

// AES-128-CBC senza togliere il riempimento: chiave di 16 byte, vettore iniziale di 16 byte
function DecifraAesCbcGrezzo(const Cifrato, Chiave, VettoreIniziale: TBytes; out Chiaro: TBytes): Boolean;
var
  ChiaviDiGiro: TBytes;
  Stato: array[0..15] of Byte;
  Blocco: Integer;
  Indice: Integer;
begin
  Result := False;
  if (Length(Cifrato) = 0) or (Length(Cifrato) mod 16 <> 0) or (Length(Chiave) <> 16) or (Length(VettoreIniziale) <> 16) then
    Exit;

  EspandiChiaveAes(Chiave, ChiaviDiGiro);
  SetLength(Chiaro, Length(Cifrato));
  for Blocco := 0 to Length(Cifrato) div 16 - 1 do
  begin
    DecifraBloccoAes(ChiaviDiGiro, Cifrato, Blocco * 16, Stato);
    for Indice := 0 to 15 do
      if Blocco = 0 then
        Chiaro[Indice] := Stato[Indice] xor VettoreIniziale[Indice]
      else
        Chiaro[Blocco * 16 + Indice] := Stato[Indice] xor Cifrato[(Blocco - 1) * 16 + Indice];
  end;
  Result := True;
end;

// AES-128-CBC con riempimento PKCS7 (OPENSSL_RAW_DATA di PHP)
function DecifraAesCbc(const Cifrato, Chiave, VettoreIniziale: TBytes; out Chiaro: TBytes): Boolean;
var
  Riempimento: Integer;
  Indice: Integer;
begin
  Result := False;
  if not DecifraAesCbcGrezzo(Cifrato, Chiave, VettoreIniziale, Chiaro) then
    Exit;
  Riempimento := Chiaro[High(Chiaro)];
  if (Riempimento < 1) or (Riempimento > 16) or (Riempimento > Length(Chiaro)) then
    Exit;
  for Indice := Length(Chiaro) - Riempimento to High(Chiaro) do
    if Chiaro[Indice] <> Riempimento then
      Exit;
  SetLength(Chiaro, Length(Chiaro) - Riempimento);
  Result := True;
end;

{ TWTCittadinoController }

// Aree del token del cittadino: il portale sempre, poi quelle di AREE_DEL_CITTADINO che
// i suoi gruppi hanno in USR_UTENTE_AREE_WEB, la stessa lettura con cui
// USR_SESSIONE_APP_SET ammette il cambio d'area. Un errore lascia il solo portale: meglio
// un'area in meno che un accesso negato.
function TWTCittadinoController.AreeDelCittadino(const UserId: Int64): TArray<string>;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  App: string;
  Area: string;
begin
  Result := [AREA_CITTADINO];

  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_ID', UserId);
    try
      Righe := TDataService.ExecuteQuery(
        'SELECT USR_UTENTE_AREE_WEB.APP FROM USR_UTENTI ' +
        'INNER JOIN USR_UTENTE_AREE_WEB(USR_UTENTI.USER_NAME) ON TRUE ' +
        'WHERE USR_UTENTI.USER_ID = :USER_ID', Parametri, False);
      try
        for Riga in Righe do
          if Riga is TJSONObject then
          begin
            App := JsonStr(TJSONObject(Riga), 'APP').Trim.ToUpper;
            for Area in AREE_DEL_CITTADINO do
              if App = Area then
                Result := Result + [Area];
          end;
      finally
        FreeAndNil(Righe);
      end;
    except
      on E: Exception do
        Registro.Warn(Format('Aree del cittadino %d non lette, resta il solo portale: %s', [UserId, E.Message]), 'CittadinoController');
    end;
  finally
    FreeAndNil(Parametri);
  end;
end;

// Nome del portale (WEB_CIT_PORTALI.NOME_CONFIGURAZIONE) con cui entrare: quello
// chiesto, se esiste; se non e' indicato, l'unico portale dell'installazione.
// Con piu' portali il client deve dire quale.
function TWTCittadinoController.PortaleDaUsare(const Richiesto: string): string;
var
  Parametri: TParamValues;
  Righe: TJSONArray;
  Riga: TJSONValue;
  Nome: string;
begin
  Result := '';

  Parametri := TParamValues.Create;
  try
    Righe := TDataService.ExecuteQuery('SELECT WEB_CIT_PORTALI.NOME_CONFIGURAZIONE FROM WEB_CIT_PORTALI', Parametri, False);
    try
      if Richiesto.Trim.IsEmpty then
      begin
        if Righe.Count = 1 then
          Result := JsonStr(TJSONObject(Righe.Items[0]), 'NOME_CONFIGURAZIONE');
      end
      else
        for Riga in Righe do
        begin
          Nome := JsonStr(TJSONObject(Riga), 'NOME_CONFIGURAZIONE');
          if SameText(Nome, Richiesto.Trim) then
            Result := Nome;
        end;
    finally
      FreeAndNil(Righe);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  if Result.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Portale non indicato o non valido.');
end;

procedure TWTCittadinoController.LoginCittadino;
var
  Corpo: TJSONObject;
  NomeUtente: string;
  Password: string;
  Portale: string;
  Belfiore: string;
  Parametri: TParamValues;
  Connessione: TFDConnection;
  Uscita: TJSONObject;
  Esito: TAuthResult;
  ScadenzaSessione: TDateTime;
  Minuti: Integer;
  Token: string;
begin
  Corpo := CorpoJson;
  try
    // Il client di zNg manda jwtusername e jwtpassword come il login ordinario
    NomeUtente := JsonStr(Corpo, 'username');
    if NomeUtente.IsEmpty then
      NomeUtente := JsonStr(Corpo, 'jwtusername');

    Password := JsonStr(Corpo, 'password');
    if Password.IsEmpty then
      Password := JsonStr(Corpo, 'jwtpassword');

    Portale := JsonStr(Corpo, 'portale');
    Belfiore := JsonStr(Corpo, 'belfiore');
  finally
    FreeAndNil(Corpo);
  end;

  if NomeUtente.Trim.IsEmpty or Password.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Utente e password sono obbligatori.');

  Portale := PortaleDaUsare(Portale);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('WEB_PRJ_CLIENT', Portale);

    if Belfiore.Trim.IsEmpty then
      Parametri.Add('WEB_BELFIORE', Null)
    else
      Parametri.Add('WEB_BELFIORE', Belfiore.Trim);

    Parametri.Add('WEB_LANGUAGE', LINGUA_PREDEFINITA);
    Parametri.Add('APP', AREA_CITTADINO);
    Parametri.Add('USER_NAME', NomeUtente.Trim);
    Parametri.Add('PASSWORD_', Password);
    Parametri.Add('COMPUTER_NAME', NOME_POSTAZIONE);
    Parametri.Add('COMPUTER_USER_NAME', NomeUtente.Trim);
    Parametri.Add('SKIP_CREATE_SESSION', False);

    // Connessione senza contesto, come l'accesso ordinario: il contesto non
    // esiste ancora e lo crea USR_LOGIN. La conferma la fa TDataService, cosi'
    // la sessione e la riga del portale sono visibili alle richieste dopo.
    // WEB_CIT_LOGIN non solleva per le credenziali sbagliate: restituisce
    // USER_ID nullo.
    Connessione := TConnectionPool.Instance.Acquire(False);
    try
      try
        Uscita := TDataService.ExecuteStoredProc(Connessione, 'WEB_CIT_LOGIN', Parametri);
      except
        on E: Exception do
        begin
          Registro.Warn(Format('Accesso del cittadino %s non riuscito: %s', [NomeUtente, E.Message]), 'CittadinoController');
          if AccessoNegato(E.Message) then
            raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Credenziali non valide.');
          raise;
        end;
      end;
    finally
      TConnectionPool.Instance.Release(Connessione);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  try
    Esito.Clear;
    Esito.UserId := JsonInt64(Uscita, 'USER_ID');

    if Esito.UserId <= 0 then
    begin
      Registro.Warn(Format('Accesso del cittadino %s negato: credenziali non valide', [NomeUtente]), 'CittadinoController');
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Credenziali non valide.');
    end;

    Esito.Success := True;
    Esito.IdSessione := JsonInt64(Uscita, 'ID_SESSIONE');
    Esito.Nominativo := JsonStr(Uscita, 'NOMINATIVO');
    Esito.Ruolo := JsonStr(Uscita, 'RUOLO');
    // Nessun ruolo di amministratore nel token del portale
    Esito.AdminUser := False;
    Esito.DataScadenzaPassword := JsonDate(Uscita, 'SCADENZA_PASSWORD');
    Esito.RichiedeOtp := JsonBool(Uscita, 'OTP');
    Esito.Aree := AreeDelCittadino(Esito.UserId);
    Esito.Area := AREA_CITTADINO;

    ScadenzaSessione := JsonDate(Uscita, 'SCADENZA_SESSIONE');
  finally
    FreeAndNil(Uscita);
  end;

  // 60 minuti, o meno se il portale chiude la sessione prima
  Minuti := DURATA_SESSIONE_MINUTI;
  if ScadenzaSessione > Now then
    Minuti := Integer(Max(Int64(1), Min(Int64(Minuti), MinutesBetween(Now, ScadenzaSessione))));

  Token := TTokenService.CreaAccessToken(Esito, NomeUtente.Trim, Minuti);

  Registro.Info(Format('Accesso del cittadino riuscito: %s (utente %d, sessione %d, portale %s)', [Esito.Nominativo, Esito.UserId, Esito.IdSessione, Portale]), 'CittadinoController');

  RenderJson(TJSONObject.Create.AddPair('token', Token).AddPair('expires_in', TJSONNumber.Create(Minuti * 60)));
end;

// Chiave di cifratura del gateway: l'AES-128 usa i primi 16 byte del testo (OpenSSL di PHP
// tronca o completa con zeri allo stesso modo), l'HMAC usa il testo intero.
function ChiaveAes(const Chiave: string): TBytes;
var
  Byte_: TBytes;
begin
  Byte_ := TEncoding.UTF8.GetBytes(Chiave);
  SetLength(Result, 16);
  FillChar(Result[0], 16, 0);
  Move(Byte_[0], Result[0], Min(16, Length(Byte_)));
end;

function ConfrontoCostante(const A, B: TBytes): Boolean;
var
  Indice: Integer;
  Differenza: Byte;
begin
  Result := False;
  if Length(A) <> Length(B) then
    Exit;
  Differenza := 0;
  for Indice := 0 to High(A) do
    Differenza := Differenza or (A[Indice] xor B[Indice]);
  Result := Differenza = 0;
end;

// Dati del gateway: base64(IV 16 byte + HMAC-SHA256 32 byte + cifrato), come in login-cf.php del
// portale PHP. L'HMAC si verifica PRIMA di decifrare. Ritorna il JSON in chiaro o vuoto.
function DecifraDatiGateway(const Dati, Chiave: string): string;
var
  Testo: string;
  Blocco: TBytes;
  Vettore: TBytes;
  Firma: TBytes;
  Cifrato: TBytes;
  Chiaro: TBytes;
begin
  Result := '';
  Testo := Dati.Trim.Replace(' ', '+');
  // Il PHP fa urldecode; alcuni indirizzi arrivano codificati due volte
  if Testo.Contains('%') then
    Testo := TNetEncoding.URL.Decode(Testo);
  try
    Blocco := TNetEncoding.Base64.DecodeStringToBytes(Testo);
  except
    Exit;
  end;
  if Length(Blocco) < 16 + 32 + 16 then
    Exit;

  Vettore := Copy(Blocco, 0, 16);
  Firma := Copy(Blocco, 16, 32);
  Cifrato := Copy(Blocco, 48, Length(Blocco) - 48);

  if not ConfrontoCostante(Firma, THashSHA2.GetHMACAsBytes(Cifrato, TEncoding.UTF8.GetBytes(Chiave), THashSHA2.TSHA2Version.SHA256)) then
    Exit;
  if not DecifraAesCbc(Cifrato, ChiaveAes(Chiave), Vettore, Chiaro) then
    Exit;

  Result := TEncoding.UTF8.GetString(Chiaro);
end;

procedure TWTCittadinoController.LoginSpid;
var
  Corpo: TJSONObject;
  Identita: TIdentitaSpid;
begin
  // Senza il gateway SPID vero i dati arrivano in chiaro: si accettano solo in sviluppo
  if not TAppConfig.Instance.Development then
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Accesso SPID non attivo.');

  Corpo := CorpoJson;
  try
    Identita.CodiceFiscale := UpperCase(JsonStr(Corpo, 'fiscalNumber').Trim);
    Identita.Nome := JsonStr(Corpo, 'name');
    Identita.Cognome := JsonStr(Corpo, 'familyName');
    Identita.Email := JsonStr(Corpo, 'email');
    Identita.Portale := JsonStr(Corpo, 'portale');
    Identita.Belfiore := JsonStr(Corpo, 'belfiore');
  finally
    FreeAndNil(Corpo);
  end;
  Identita.IdRisposta := StringReplace(Copy(TGUID.NewGuid.ToString, 2, 36), '-', '', [rfReplaceAll]);
  Identita.Altri := nil;

  EseguiAccessoSpid(Identita, 'simulato');
end;

// Rotta di ritorno del gateway: il browser del cittadino arriva alla pagina di Pipa con ?data=...,
// la pagina manda qui il parametro cosi' com'e'. Si decifra con la chiave del server, poi si
// esegue lo stesso accesso della simulazione.
procedure TWTCittadinoController.LoginSpidGateway;
var
  Corpo: TJSONObject;
  Dati: string;
  Chiaro: string;
  Radice: TJSONValue;
  Identita: TIdentitaSpid;
  Chiave: string;
  Righe: TJSONArray;
  Parametri: TParamValues;
  Usato: Boolean;
begin
  Chiave := TAppConfig.Instance.Spid.ChiaveCifratura;
  if Chiave.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.Forbidden, 'Accesso SPID non attivo.');

  Corpo := CorpoJson;
  try
    Dati := JsonStr(Corpo, 'data');
    Identita.Portale := JsonStr(Corpo, 'portale');
    Identita.Belfiore := JsonStr(Corpo, 'belfiore');
  finally
    FreeAndNil(Corpo);
  end;

  if Dati.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Dati del gateway mancanti.');

  Chiaro := DecifraDatiGateway(Dati, Chiave);
  if Chiaro.IsEmpty then
  begin
    Registro.Warn('Accesso SPID: dati del gateway non validi (firma o cifratura)', 'CittadinoController');
    raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
  end;

  Radice := TJSONObject.ParseJSONValue(Chiaro);
  try
    if not (Radice is TJSONObject) then
    begin
      Registro.Warn('Accesso SPID: dati del gateway senza oggetto JSON', 'CittadinoController');
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
    end;

    Identita.CodiceFiscale := UpperCase(JsonStr(TJSONObject(Radice), 'fiscalNumber').Trim);
    Identita.Nome := JsonStr(TJSONObject(Radice), 'name');
    Identita.Cognome := JsonStr(TJSONObject(Radice), 'familyName');
    Identita.Email := JsonStr(TJSONObject(Radice), 'email');
    // Il PHP legge responseID, il proxy legge responseId: si accettano tutte e due
    Identita.IdRisposta := JsonStr(TJSONObject(Radice), 'responseID').Trim;
    if Identita.IdRisposta.IsEmpty then
      Identita.IdRisposta := JsonStr(TJSONObject(Radice), 'responseId').Trim;
    Identita.Altri := TJSONObject(Radice);

    if Identita.CodiceFiscale.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');

    // Senza identificativo della risposta non si puo' escludere il riuso dello stesso indirizzo
    if Identita.IdRisposta.IsEmpty then
    begin
      Registro.Warn('Accesso SPID: identificativo della risposta mancante', 'CittadinoController');
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
    end;

    // Riuso: la procedura di accesso scrive l'identificativo in USR_SPID_AUTHORIZATIONS.RESPONSE_ID;
    // lo stesso identificativo non entra due volte. Il PHP non lo controllava.
    Parametri := TParamValues.Create;
    try
      Parametri.Add('RESPONSE_ID', Copy(Identita.IdRisposta, 1, 32));
      Righe := TDataService.ExecuteQuery('SELECT COUNT(*) AS NUMERO FROM USR_SPID_AUTHORIZATIONS WHERE USR_SPID_AUTHORIZATIONS.RESPONSE_ID = :RESPONSE_ID', Parametri, False);
      try
        Usato := (Righe.Count > 0) and (JsonInt64(TJSONObject(Righe.Items[0]), 'NUMERO') > 0);
      finally
        FreeAndNil(Righe);
      end;
    finally
      FreeAndNil(Parametri);
    end;

    if Usato then
    begin
      Registro.Warn(Format('Accesso SPID: risposta %s gia'' usata, accesso rifiutato', [Identita.IdRisposta]), 'CittadinoController');
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
    end;

    EseguiAccessoSpid(Identita, 'gateway');
  finally
    FreeAndNil(Radice);
  end;
end;

// Accesso con l'identita' SPID gia' verificata (simulata o decifrata dal gateway)
procedure TWTCittadinoController.EseguiAccessoSpid(const Identita: TIdentitaSpid; const Origine: string);
var
  CodiceFiscale: string;
  Nome: string;
  Cognome: string;
  Email: string;
  Portale: string;
  Belfiore: string;
  Parametri: TParamValues;
  Connessione: TFDConnection;
  Uscita: TJSONObject;
  Esito: TAuthResult;
  ScadenzaSessione: TDateTime;
  Minuti: Integer;
  Token: string;
  NumeroIntestatari: Int64;
  Indice: Integer;
  Valore: string;
begin
  CodiceFiscale := Identita.CodiceFiscale;
  Nome := Identita.Nome;
  Cognome := Identita.Cognome;
  Email := Identita.Email;
  Belfiore := Identita.Belfiore;

  // Il gateway manda il codice fiscale gia' con il prefisso TINIT-, la simulazione no
  if CodiceFiscale.StartsWith('TINIT-', True) then
    CodiceFiscale := Copy(CodiceFiscale, 7, MaxInt);

  if CodiceFiscale.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Codice fiscale obbligatorio.');

  Portale := PortaleDaUsare(Identita.Portale);

  Parametri := TParamValues.Create;
  try
    Parametri.Add('WEB_PRJ_CLIENT', Portale);

    if Belfiore.Trim.IsEmpty then
      Parametri.Add('WEB_BELFIORE', Null)
    else
      Parametri.Add('WEB_BELFIORE', Belfiore.Trim);

    Parametri.Add('WEB_LANGUAGE', LINGUA_PREDEFINITA);
    Parametri.Add('APP', AREA_CITTADINO);
    // La procedura riconosce il codice fiscale SPID dal prefisso TINIT-
    Parametri.Add('CF', 'TINIT-' + CodiceFiscale);
    Parametri.Add('RESPONSE_ID', Copy(Identita.IdRisposta, 1, 32));
    Parametri.Add('COMPUTER_NAME', NOME_POSTAZIONE);
    Parametri.Add('COMPUTER_USER_NAME', CodiceFiscale);

    // Gli altri dati SPID arrivano solo dal gateway (la simulazione non li ha): assenti = nulli
    for Indice := Low(CAMPI_SPID) to High(CAMPI_SPID) do
    begin
      Valore := '';
      if Assigned(Identita.Altri) then
        Valore := JsonStr(Identita.Altri, CAMPI_SPID[Indice, 1]).Trim;
      if Valore.IsEmpty then
        Parametri.Add(CAMPI_SPID[Indice, 0], Null)
      else
        Parametri.Add(CAMPI_SPID[Indice, 0], Valore);
    end;

    if Nome.Trim.IsEmpty then
      Parametri.Add('SPID_NOME', Null)
    else
      Parametri.Add('SPID_NOME', Nome.Trim);

    if Cognome.Trim.IsEmpty then
      Parametri.Add('SPID_COGNONOME', Null)
    else
      Parametri.Add('SPID_COGNONOME', Cognome.Trim);

    if Email.Trim.IsEmpty then
      Parametri.Add('SPID_EMAIL', Null)
    else
      Parametri.Add('SPID_EMAIL', Email.Trim);

    // Come LoginCittadino: connessione senza contesto, la sessione la crea la procedura
    Connessione := TConnectionPool.Instance.Acquire(False);
    try
      try
        Uscita := TDataService.ExecuteStoredProc(Connessione, 'WEB_CIT_LOGIN_SPID', Parametri);
      except
        on E: Exception do
        begin
          Registro.Warn(Format('Accesso SPID %s non riuscito: %s', [CodiceFiscale, E.Message]), 'CittadinoController');
          if AccessoNegato(E.Message) then
            raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
          raise;
        end;
      end;
    finally
      TConnectionPool.Instance.Release(Connessione);
    end;
  finally
    FreeAndNil(Parametri);
  end;

  try
    Esito.Clear;
    Esito.UserId := JsonInt64(Uscita, 'USER_ID');

    if Esito.UserId <= 0 then
    begin
      Registro.Warn(Format('Accesso SPID %s negato', [CodiceFiscale]), 'CittadinoController');
      raise EMVCException.Create(HTTP_STATUS.Unauthorized, 'Accesso negato.');
    end;

    Esito.Success := True;
    Esito.IdSessione := JsonInt64(Uscita, 'ID_SESSIONE');
    Esito.Nominativo := JsonStr(Uscita, 'NOMINATIVO');
    Esito.Ruolo := JsonStr(Uscita, 'RUOLO');
    Esito.AdminUser := False;
    Esito.DataScadenzaPassword := JsonDate(Uscita, 'SCADENZA_PASSWORD');
    Esito.RichiedeOtp := False;
    Esito.Aree := AreeDelCittadino(Esito.UserId);
    Esito.Area := AREA_CITTADINO;

    ScadenzaSessione := JsonDate(Uscita, 'SCADENZA_SESSIONE');
    NumeroIntestatari := JsonInt64(Uscita, 'NUM_INTESTATARI');
  finally
    FreeAndNil(Uscita);
  end;

  Minuti := DURATA_SESSIONE_MINUTI;
  if ScadenzaSessione > Now then
    Minuti := Integer(Max(Int64(1), Min(Int64(Minuti), MinutesBetween(Now, ScadenzaSessione))));

  Token := TTokenService.CreaAccessToken(Esito, CodiceFiscale, Minuti);

  Registro.Info(Format('Accesso SPID %s riuscito: %s (utente %d, sessione %d, portale %s, intestatari %d)', [Origine, Esito.Nominativo, Esito.UserId, Esito.IdSessione, Portale, NumeroIntestatari]), 'CittadinoController');

  RenderJson(TJSONObject.Create.AddPair('token', Token).AddPair('expires_in', TJSONNumber.Create(Minuti * 60)).AddPair('numero_intestatari', TJSONNumber.Create(NumeroIntestatari)));
end;

initialization
  CalcolaTabelleAes;

end.
