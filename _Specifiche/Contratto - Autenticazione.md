---
area: Contratto - Autenticazione
progetto: zServer
aggiornato: 2026-11-06
rilascio: OUT/20261106-pipa-sportello-comuni-funzioni-per-comune/003
---

# Contratto - Autenticazione

Questa specifica descrive cosa zServer promette ai client per l'accesso, il rinnovo, l'uscita e il cambio password: rotte, corpi, risposte e contenuto dei token. Descrive il contratto, non il codice. Il codice oggi sta in `Core/Middleware/JWTRefresh.Middleware.pas` (che intercetta rinnovo e uscita prima dell'instradamento), `Core/Services/Authentication.Service.pas`, `Core/Services/Token.Service.pas`, `Core/Services/RefreshToken.Service.pas` e `Core/Controllers/Auth.Controller.pas`.

Il client che lo usa oggi è zNg: `zPack/zNg/_Specifiche/Accesso.md` (requisiti `ZNG-ACC-*`).

**Forma leggibile dalle macchine:** `Contratto - Autenticazione.openapi.yaml`, nella stessa cartella, descrive rotte, corpi e risposte in OpenAPI 3.0 e porta in `x-requisito` il codice del requisito di ciascuna operazione. Questo documento resta la fonte: gli scenari, i motivi e le eccezioni stanno solo qui. Una modifica al contratto aggiorna i due file nello stesso rilascio; se non concordano ha ragione il documento.

## ZSRV-AUT-001 Login
`POST /api/auth/login` con il corpo JSON `{ "jwtusername": "...", "jwtpassword": "...", "area": "..." }`; `area` è facoltativa. La verifica la fa la procedura `USR_LOGIN` del prodotto (WT o Gesty), che apre anche una sessione in `USR_SESSIONI`.

### Scenario: scelta dell'area (solo WT, dal 2026-11-02)
- **Dato** un utente con una o più aree web (app di `USR_APPS` con `TIPO_APP = 'W'` dei suoi gruppi, esclusa `WTWEB_CITTADINO` salvo la deroga di sviluppo più sotto, lette con `USR_UTENTE_AREE_WEB`)
- **Quando** il client chiama il login
- **Allora** zServer chiama `USR_LOGIN` con l'area chiesta se è fra quelle dell'utente, altrimenti con `WTWEB_SPORTELLO` se l'utente la ha, altrimenti con la prima sua area in ordine alfabetico
- **E** fascia oraria e secondo fattore sono quelli dell'area con cui si entra, perché li verifica `USR_LOGIN` per quell'app
- **E** un client che non manda `area` (Agorà) entra nello sportello come prima

### Scenario: deroga di sviluppo per WTWEB_CITTADINO (temporanea, dal 2026-11-02)
- **Dato** un utente del gruppo `SOFTLINE` con `WTWEB_CITTADINO` fra le app del gruppo
- **Quando** il client chiama il login o il cambio d'area
- **Allora** `USR_UTENTE_AREE_WEB` restituisce anche `WTWEB_CITTADINO`, e l'utente può sceglierla e aprirla come le altre aree
- **E** per ogni altro gruppo `WTWEB_CITTADINO` resta esclusa, come nello scenario precedente
- **Perché** durante lo sviluppo di Pipa servono tutte le aree nello stesso accesso per provare le pagine del cittadino, e il suo canale di accesso non esiste ancora. La deroga è mirata (un solo gruppo, una sola area) e si toglie ripristinando la condizione `USR_APPS.APP <> 'WTWEB_CITTADINO'` nella procedura, quando il cittadino avrà il suo accesso e l'area non dovrà più stare nel token di un operatore

### Scenario: utente senza aree web
- **Dato** un utente sconosciuto, non attivo o senza aree web
- **Quando** il client chiama il login
- **Allora** zServer chiama `USR_LOGIN` con `WTWEB_SPORTELLO` e la risposta è quella di prima: le aree si leggono prima della password, ma non cambiano né la risposta né la riga in `USR_EVENTI_SICUREZZA`

### Scenario: credenziali accettate
- **Dato** un utente attivo con le credenziali corrette
- **Quando** il client chiama il login
- **Allora** la risposta è 200 con `{ "token": "<access token>", "refresh_token": "<token di rinnovo>" }`
- **E** il token di rinnovo è registrato in `USR_REFRESH_TOKENS` con l'utente, la sessione, il browser (`User-Agent`) e l'indirizzo IP

### Scenario: token di rinnovo non registrabile
- **Dato** un login riuscito
- **Quando** la registrazione del token di rinnovo fallisce
- **Allora** la risposta è 200 con il solo `token`: il login non si blocca, ma la sessione non si potrà rinnovare

### Scenario: credenziali rifiutate
- **Dato** credenziali sbagliate o un utente non attivo
- **Quando** il client chiama il login
- **Allora** la richiesta è rifiutata dal middleware JWT di DMVCFramework e nessun token viene emesso

## ZSRV-AUT-002 Contenuto del token di accesso
Il token di accesso ha **gli stessi claim al login e al rinnovo**: li crea un punto solo (`TTokenService`). Prima non era così, e un token rinnovato perdeva `user_id` e i ruoli.

| Claim | Contenuto |
|---|---|
| `iss`, `aud` | Emittente e destinatario dalla configurazione |
| `sub`, `user_id` | Identificativo dell'utente |
| `id_sessione` | Sessione aperta dal login in `USR_SESSIONI`; le procedure che vogliono `ID_SESSIONE_WEB` la leggono da qui |
| `username` | Nome utente; nome richiesto da DMVCFramework |
| `roles` | Ruoli separati da virgola: sempre `user`, poi il ruolo del prodotto se c'è, poi `admin` se l'utente è amministratore; nome richiesto da DMVCFramework |
| `nominativo` | Cognome e nome da mostrare |
| `ruolo` | Ruolo del prodotto (`A`, `D`, `U`, `X`...) |
| `tipo_user` | Stesso valore di `ruolo`, emesso per il portale di Gesty che lo legge con questo nome |
| `admin_user` | `True` o `False` |
| `data_scadenza_password` | Data in formato ISO 8601 |
| `host_ldap` | Server LDAP dell'utente, se c'è |
| `otp` | `True` se l'utente deve completare l'accesso con un codice temporaneo |
| `aree` | Solo WT: codici delle aree web dell'utente separati da virgola (`WTWEB_GERA,WTWEB_RIUSO`). Assente nei prodotti senza aree |
| `area` | Solo WT: area della sessione (`USR_SESSIONI.APP`). Informativa per il client: zServer decide sull'area leggendo la sessione, non il token |
| `iat`, `nbf`, `exp` | Emissione; validità da cinque minuti prima dell'emissione; scadenza dopo `expirationMinutes` della configurazione (predefinito 480) |

Il token **non** contiene `displayname` né `role`.

## ZSRV-AUT-003 Rinnovo
`POST /api/auth/refresh` con il corpo `{ "refresh_token": "..." }`. Il token di accesso non serve, perché di solito è proprio scaduto. A ogni rinnovo il token di rinnovo viene **sostituito**: quello vecchio non vale più.

### Scenario: rinnovo riuscito
- **Dato** un token di rinnovo valido di un utente attivo
- **Quando** il client chiama il rinnovo
- **Allora** la risposta è 200 con `{ "token": "...", "refresh_token": "..." }`, entrambi nuovi
- **E** il token di accesso nuovo ha gli stessi claim del login (ZSRV-AUT-002), con la stessa sessione
- **E** `aree` e `area` si rileggono dal database: dopo un cambio d'area (ZSRV-AUT-009) il token rinnovato porta l'area nuova

### Scenario: risposte di errore
| Caso | Stato | Testo di `error` |
|---|---|---|
| Corpo non JSON | 400 | `Body JSON non valido` |
| `refresh_token` mancante | 400 | `refresh_token obbligatorio` |
| Token di rinnovo sconosciuto | 401 | `Refresh token non valido` |
| Token di rinnovo scaduto | 401 | `Sessione scaduta, effettua nuovamente il login` |
| Token di rinnovo già usato | 401 | `Sessione invalidata per motivi di sicurezza, effettua nuovamente il login` |
| Utente non più attivo | 403 | `Utente non attivo` |
| Errore imprevisto | 500 | `Errore interno di autenticazione` |

### Scenario: token di rinnovo usato due volte
- **Dato** un token di rinnovo già sostituito da un rinnovo precedente
- **Quando** qualcuno lo usa di nuovo
- **Allora** zServer lo considera un possibile furto e revoca **tutti** i token di rinnovo dell'utente
- **E** risponde 401: tutte le sessioni dell'utente dovranno rifare il login

Per questo il client non deve mai mandare due rinnovi con lo stesso token (ZNG-ACC-004).

### Scenario: sessione nel token rinnovato
- **Dato** un token di rinnovo registrato con la sua sessione (colonna `ID_SESSIONE` di `USR_REFRESH_TOKENS`)
- **Quando** il client rinnova
- **Allora** il token nuovo porta la stessa `id_sessione`
- **E** in un'installazione senza quella colonna la sessione si prende dal token di accesso scaduto, se il client lo manda ancora nell'intestazione; senza nessuno dei due il token nuovo resta senza sessione e zServer lo annota nel registro

## ZSRV-AUT-004 Uscita
`POST /api/auth/logout` con il corpo `{ "refresh_token": "..." }`. Risponde sempre 200 con `{ "message": "Logout effettuato" }`: un'uscita non deve fallire.

### Scenario: uscita completa
- **Dato** un client con il token di rinnovo e il token di accesso nell'intestazione, anche scaduto
- **Quando** chiama l'uscita
- **Allora** il token di rinnovo viene revocato
- **E** la sessione del token di accesso viene chiusa con `USR_LOGOUT`

### Scenario: corpo vuoto o senza intestazione
- **Dato** un client che manda un corpo vuoto o non manda il token di accesso
- **Quando** chiama l'uscita
- **Allora** zServer fa quello che può (revoca o chiusura della sessione) e risponde comunque 200

## ZSRV-AUT-005 Uscita da tutti i dispositivi
`POST /api/auth/logout-all` con un token di accesso valido nell'intestazione. Revoca tutti i token di rinnovo dell'utente e risponde 200. Senza token, con un token non valido o senza `user_id`, risponde 401. Nessuna applicazione lo usa ancora.

## ZSRV-AUT-006 Verifica del token
`GET /api/auth/validate` con il token di accesso. Se il token è valido risponde 200 con `success`, `user_id`, `id_sessione`, `username`, `nominativo` e `ruolo`; altrimenti 401.

## ZSRV-AUT-007 Contesto della richiesta
Rinnovo, uscita e uscita da tutti i dispositivi non arrivano a un controller, quindi azzerano da sé il contesto del thread prima di lavorare. Senza questo azzeramento `USR_LOGOUT` verrebbe eseguito a nome dell'utente dell'ultima richiesta servita da quel thread.

## ZSRV-AUT-008 Cambio password
`POST /api/auth/password` con un token di accesso valido e il corpo `{ "oldPassword": "...", "newPassword": "..." }`. Vale per WT e per Gesty: la procedura `USR_CAMBIA_PASSWORD` ha la stessa firma nei due prodotti. Utente e sessione si prendono dal token, mai dal corpo: si cambia solo la propria password. La rotta `POST /api/wt/admin/password` di WT resta per i client che la usano già.

### Scenario: cambio riuscito
- **Dato** un utente collegato che conosce la propria password
- **Quando** il client manda la password attuale e la nuova
- **Allora** la risposta è 200 con `{ "success": true }`
- **E** la nuova password vale dal login successivo, con la scadenza ricalcolata da `CONFIG.GIORNI_DURATA_PASSWORD`; la sessione e i token già emessi restano validi

### Scenario: risposte di errore
| Caso | Stato | Testo di `message` |
|---|---|---|
| Corpo non JSON | 400 | `Corpo della richiesta non valido: atteso un oggetto JSON.` |
| `oldPassword` vuota | 400 | `Password attuale non indicata.` |
| `newPassword` vuota | 400 | `Nuova password non indicata.` |
| Password attuale sbagliata | 400 | `La password attuale non e' corretta.` |
| Utente inesistente o non attivo | 400 | `Utente non valido o non attivo.` |
| Utente con `PWD_METODO_VERIFICA = 'D'` (dominio) | 400 | `La tua password e' quella del dominio aziendale: si cambia dal computer o con l'amministratore di rete, non dal portale.` |
| Utente con `PWD_METODO_VERIFICA = 'N'` (nessuna verifica) | 400 | `Per il tuo utente la password non viene controllata: chiedi al tuo ente di attivarne la verifica prima di cambiarla.` |
| Token assente o non valido | 401 | dal middleware JWT |

Le regole sulla nuova password (lunghezza, caratteri) le applica il client: le procedure non ne hanno.

Il rifiuto per i metodi `D` e `N` lo fa zServer prima di chiamare la procedura: `USR_VERIFICA_PASSWORD` per quei metodi risponde sempre vero, quindi la procedura accetterebbe qualunque password attuale e il cambio non servirebbe a niente.

## ZSRV-AUT-009 Cambio d'area
`POST /api/auth/area` con un token di accesso valido e il corpo `{ "area": "WTWEB_GERA" }`. Solo WT; negli altri prodotti risponde 400 `Questo prodotto non ha aree.`. La sessione si prende dal token: si cambia solo la propria. La risposta non porta un token: il client chiama subito il rinnovo (ZSRV-AUT-003), che rilegge l'area dalla sessione.

### Scenario: cambio riuscito
- **Dato** un utente collegato con più aree web
- **Quando** il client chiede un'area dei suoi gruppi, dentro la sua fascia oraria
- **Allora** `USR_SESSIONE_APP_SET` porta `USR_SESSIONI.APP` all'area nuova e la risposta è 200 con `{ "success": true, "area": "WTWEB_GERA" }`
- **E** da quel momento dataset e procedure si verificano sull'area nuova (ZSRV-AUT-010), anche con il token emesso prima del cambio

### Scenario: risposte di errore
| Caso | Stato | Testo di `message` |
|---|---|---|
| `area` mancante o vuota | 400 | `Area non indicata.` |
| Area non fra quelle dei gruppi dell'utente | 400 | `Area non abilitata per il tuo utente.` |
| Fuori dalla fascia oraria dell'area | 400 | `Accesso a questa area non consentito in questa fascia oraria.` |
| L'area chiede il secondo fattore e la sessione non l'ha verificato | 400 | `Questa area chiede il codice di verifica: esci e rifai l'accesso scegliendola.` |
| Sessione chiusa o di un altro utente | 400 | `Sessione non valida o chiusa: rifai l'accesso.` |
| Token assente o non valido | 401 | dal middleware JWT |

## ZSRV-AUT-010 Dataset e procedure dell'area
Solo WT. Dopo l'autorizzazione (`AUTHORIZATION` di `BASE_WEB_DATASETS` e `BASE_WEB_PROCEDURE`), zServer chiede a `BASE_WEB_AREA_AMMESSO` se il dataset o la procedura appartengono all'area della sessione.

| Area della sessione | Regola |
|---|---|
| `WTWEB_SPORTELLO` (Agorà), app non web | Come prima: nessun controllo dell'area |
| Altre aree web (`WTWEB_GERA`, `WTWEB_RIUSO`, `WTWEB_COMUNE`...) | Il dataset deve avere la riga in `BASE_WEB_DATASETS_AREE`, la procedura in `BASE_WEB_PROCEDURE_AREE`, per quell'area |

### Scenario: fuori dall'area
- **Dato** un utente nell'area `WTWEB_GERA`
- **Quando** chiede un dataset o una procedura senza la riga per `WTWEB_GERA`
- **Allora** la risposta è 403 `Non disponibile in questa area.`, anche se l'autorizzazione del gruppo c'è

## ZSRV-AUT-015 Moduli dell'utente (dal 2026-11-06)
`GET /api/auth/moduli` restituisce i moduli dell'utente del token, ciascuno con i comuni in cui lo può usare:

```json
{ "success": true,
  "moduli": [ { "modulo": "Comune.Giri", "scrittura": true,
                "comuni": [ { "belfiore": "A123", "scrittura": true },
                            { "belfiore": "B456", "scrittura": false } ] } ] }
```

Su WT le righe vengono da `USR_UTENTE_MODULI_WEB` (script `WT-MODULI-01`): la coppia modulo-comune si forma dentro ogni gruppo dell'utente e solo dopo si uniscono i gruppi, quindi un utente in due gruppi di delega non vede un modulo in un comune che nessuno dei due gli ha dato. `scrittura` del comune è vero se almeno un gruppo che porta quella coppia ha `ACCESS` `W`; `scrittura` del modulo è vero se lo è in almeno un comune. Su Gesty, e su WT senza lo script, l'elenco è vuoto.

I moduli non stanno nel token: con molti comuni lo allungherebbero a ogni rinnovo, e una modifica di gruppi o contratti vale dalla richiesta successiva. La rotta serve al client per il menu; la protezione la fanno le rotte dei dati (`Contratto - Dataset dinamici`, ZSRV-DSD-015), che rileggono i moduli a ogni richiesta.

### Scenario: utente senza moduli
- **Dato** un utente senza righe in `USR_UTENTE_MODULI_WEB`, o un prodotto senza moduli
- **Quando** il client chiede i moduli
- **Allora** la risposta è 200 con `"moduli": []`

## ZSRV-AUT-011 Accesso del cittadino (solo WT, dal 2026-11-03)
`POST /api/auth/login-cittadino` con il corpo JSON `{ "username": "...", "password": "...", "portale": "...", "belfiore": "..." }` (anche `jwtusername` e `jwtpassword`, come il login ordinario); `portale` (nome di configurazione in `WEB_CIT_PORTALI`) e `belfiore` sono facoltativi. È raggiungibile senza token. Esegue `WEB_CIT_LOGIN` del portale del cittadino così com'è: apre la sessione con `USR_LOGIN` per l'app `WTWEB_CITTADINO`, scrive il registro degli accessi del portale e la riga di `WEB_CIT_PORTALI_SESSIONI`, di cui le procedure di richiesta del cittadino hanno bisogno.

### Scenario: accesso riuscito
- **Dato** un utente il cui gruppo ha l'app `WTWEB_CITTADINO` (i cittadini; gli utenti del gruppo `SOFTLINE` finché dura la deroga di sviluppo)
- **Quando** il client chiama la rotta con credenziali corrette
- **Allora** la risposta è 200 con `{ "token": "...", "expires_in": 3600 }`
- **E** il token porta come area e come elenco delle aree la sola `WTWEB_CITTADINO`, il ruolo `user` senza `admin`, e scade dopo 60 minuti (o prima, se `WEB_CIT_LOGIN` indica una scadenza della sessione più vicina)
- **E** la risposta non ha il token di rinnovo: la sessione del cittadino non si rinnova, alla scadenza si rifà l'accesso

### Scenario: risposte di errore
- **Dato** una richiesta con utente o password mancanti, un `portale` che non esiste, oppure senza `portale` su un'installazione con più portali
- **Allora** la risposta è 400
- **E** con credenziali sbagliate, utente non attivo o non abilitato al portale (un operatore senza il gruppo del cittadino) la risposta è 401 `Credenziali non valide.`, senza dire quale delle due cause

### Scenario: perimetro del token del cittadino
- **Dato** un token emesso da questa rotta
- **Quando** il client chiama dataset e procedure
- **Allora** valgono le regole di `ZSRV-AUT-010` per l'area `WTWEB_CITTADINO`, e la sessione e l'intestatario vengono dal token e dal database, mai dal corpo (`ZSRV-DSD-013`)

## ZSRV-AUT-012 Accesso del cittadino con SPID simulato (solo WT, dal 2026-11-04)
`POST /api/auth/login-spid` con il corpo JSON `{ "fiscalNumber": "...", "name": "...", "familyName": "...", "email": "...", "portale": "...", "belfiore": "..." }`; solo `fiscalNumber` è obbligatorio. È raggiungibile senza token. Esegue `WEB_CIT_LOGIN_SPID` del portale del cittadino: la procedura riconosce l'identità dal codice fiscale (zServer aggiunge il prefisso `TINIT-`), apre la sessione per l'app `WTWEB_CITTADINO` e, se l'identità ha un solo intestatario, lo seleziona da sola.

### Scenario: configurazione di sviluppo
- **Dato** `"development": true` nella configurazione di zServer
- **Quando** il client chiama la rotta con un codice fiscale
- **Allora** la risposta è 200 con `{ "token": "...", "expires_in": 3600, "numero_intestatari": n }`; il token è quello del cittadino (ZSRV-AUT-011): sola area `WTWEB_CITTADINO`, nessun rinnovo, 60 minuti
- **E** con `numero_intestatari` maggiore di uno il client fa scegliere l'intestatario con `WEB_CIT_LOGIN_CF_SCELTA_INTEST`; con zero, il cittadino entra senza intestatario

### Scenario: configurazione di produzione
- **Dato** `"development"` falso o assente
- **Allora** la risposta è 403 `Accesso SPID non attivo.`
- **Perché** i dati dell'identità arrivano in chiaro dal browser, quindi chiunque potrebbe dichiararsi un altro cittadino. Fuori dallo sviluppo si entra solo con il gateway SPID (`ZSRV-AUT-013`)

### Scenario: risposte di errore
- Codice fiscale mancante, o `portale` non valido: 400
- Accesso rifiutato dalla procedura: 401 `Accesso negato.`

## ZSRV-AUT-013 Accesso del cittadino con il gateway SPID (solo WT, dal 2026-11-04)
`POST /api/auth/login-spid-gateway` con il corpo JSON `{ "data": "...", "portale": "...", "belfiore": "..." }`; `portale` e `belfiore` sono facoltativi. È raggiungibile senza token. Il browser del cittadino torna dal gateway alla pagina di accesso di Pipa con `?data=...`; la pagina manda a zServer il valore così com'è. `data` è `base64(IV da 16 byte + HMAC-SHA256 da 32 byte + testo cifrato)`, come nel portale PHP (`login-cf.php`): il testo è il JSON dell'identità (`fiscalNumber`, `responseId`, `name`, `familyName`, `email`, ...) cifrato con AES-128-CBC. Chiave: la voce `spid.chiaveCifratura` del file di configurazione di zServer, la stessa del gateway (`encKey`); AES usa i primi 16 caratteri, l'HMAC la chiave intera. La chiave non sta mai nel `config.json` del sito, che il browser può leggere.

### Scenario: dati autentici
- **Dato** `spid.chiaveCifratura` valorizzata e una risposta del gateway mai usata
- **Quando** il client manda `data`
- **Allora** zServer verifica l'HMAC (confronto a tempo costante) prima di decifrare, poi esegue lo stesso accesso di `ZSRV-AUT-012` e risponde 200 con `{ "token": "...", "expires_in": 3600, "numero_intestatari": n }`

### Scenario: risposta già usata
- **Dato** un identificativo di risposta (`responseId`) già presente in `USR_SPID_AUTHORIZATIONS.RESPONSE_ID`
- **Allora** 401 `Accesso negato.`
- **Perché** l'indirizzo di ritorno non deve poter essere riusato per entrare di nuovo; il portale PHP non lo controllava

### Scenario: chiave non configurata
- **Dato** `spid.chiaveCifratura` vuota o assente
- **Allora** 403 `Accesso SPID non attivo.`

### Scenario: risposte di errore
- `data` mancante: 400
- Firma HMAC errata, dati non decifrabili, JSON non valido, codice fiscale o identificativo della risposta mancanti: 401 `Accesso negato.`, con una riga nel registro
- **Limite noto:** i dati del gateway non portano un orario, quindi non si può controllare la scadenza: vale solo il divieto di riuso

### Nota: CIE (dal 2026-11-05)
L'accesso con la CIE passa dallo stesso gateway e dalla stessa rotta: il ritorno ha lo stesso formato e la stessa chiave (`spid.chiaveCifratura`). Pipa ha due indirizzi di partenza separati in `config.json` (`spidGatewayUrl`, `cieGatewayUrl`), ma `/api/auth/login-spid-gateway` non distingue l'origine. L'accreditamento della CIE spetta al cliente, non si prova senza le sue credenziali.

## ZSRV-AUT-014 Secondo fattore: app di autenticazione e codice via mail (WT e Gesty, dal 2026-11-05)
Se `USR_LOGIN` risponde `OTP` vero (utente con `USR_UTENTI.OTP` e area con `USR_APPS.OTP`), il token nasce con il claim `otp` a `True` e la sessione resta **in attesa**: ogni richiesta con contesto fallisce con `Sessione in attesa del secondo fattore: verificare prima il codice.` finché una delle rotte seguenti non la completa con `USR_SESSIONE_COMPLETA`. La procedura `USR_TOTP_VERIFICA` riconosce solo la sessione aperta dalla connessione corrente, ma zServer usa una connessione diversa a ogni richiesta: `USR_WEB_SESSIONE_ADOTTA` (script `WT-AUTH-01`) porta la sessione web in attesa (solo di app con `TIPO_APP = 'W'`) sulla connessione della richiesta, e a fine richiesta la lascia.

Rotte a sessione **in attesa** (token con `otp`; connessione senza contesto):

| Rotta | Corpo | Esito |
|---|---|---|
| `GET /api/auth/otp/stato` | - | `{ "totpAttivo": bool, "mailDisponibile": bool }` |
| `POST /api/auth/otp/totp` | `{ "codice": "123456" }` (o un codice di recupero) | 200 `{ "success": true, "codiceRecuperoUsato": bool, "codiciRecuperoRestanti": n }`; sessione completata |
| `POST /api/auth/otp/mail` | - | 200 `{ "success": true }`; il codice parte con la posta di zServer (`TMailSenders`) e si conferma solo se la mail parte; 503 se la posta non è configurata; 400 se l'utente non ha `OTP_MAIL` |
| `POST /api/auth/otp/mail/verifica` | `{ "codice": "123456" }` | 200 `{ "success": true }`; sessione completata |

Rotte a sessione **valida** (connessione ordinaria), per registrare l'app:

| Rotta | Corpo | Esito |
|---|---|---|
| `GET /api/auth/totp/stato` | - | `{ "disponibile", "registrato", "attivo", "codiciRecuperoRestanti", "secondiBlocco", "modalita", "otpUtente", "attivazioneConsentita", "disattivazioneConsentita", "registrazioneObbligatoria" }`; le ultime cinque vengono da `USR_TOTP_REGOLE` (modalità vuota e nessun obbligo se il database non ha ancora lo script delle regole) |
| `POST /api/auth/totp/registra` | - | `{ "otpauth": "otpauth://totp/...", "segreto": "BASE32" }`; il segreto (20 byte dal generatore del sistema) lo crea zServer, la procedura lo cifra; l'app resta in sospeso |
| `POST /api/auth/totp/attiva` | `{ "codice": "123456" }` | `{ "success": true, "codiciRecupero": [10 codici] }`; attivazione e codici nella stessa transazione, i codici si vedono una volta sola |
| `POST /api/auth/totp/codici-recupero` | - | `{ "success": true, "codiciRecupero": [...] }`; quelli di prima non valgono più |
| `POST /api/auth/totp/disattiva` | `{ "codice": "123456" }` (o un codice di recupero) | `{ "success": true }`; cancella app e codici di recupero e spegne `USR_UTENTI.OTP`; 400 se il codice è errato o già usato (conta per il blocco), se l'utente è bloccato, se non ha l'app attiva o se le regole non lo consentono |

### Regole nel database (dal 2026-11-05, script `WT-AUTH-03` e `GESTY-AUTH-01`)
- Ogni area (`USR_APPS`) ha una modalità `OTP_MODALITA`: `N` non previsto, `F` facoltativo, `O` obbligatorio. `USR_APPS.OTP` resta come riflesso («il secondo fattore è previsto»), tenuto allineato da un trigger. Le aree che avevano `OTP` vero diventano `F`: il comportamento di prima.
- Il codice si chiede se la modalità è `O`, oppure `F` con `USR_UTENTI.OTP` vero; con `N` mai (`USR_OTP_RICHIESTO`, usata da `USR_LOGIN` e `USR_SESSIONE_APP_SET`). Le app desktop restano `N`.
- **Attivazione:** `USR_TOTP_ATTIVA` imposta anche `USR_UTENTI.OTP` se almeno un'area lo prevede.
- **Disattivazione:** consentita solo se l'area della sessione è `F` e nessuna area abilitata all'utente è `O`; serve un codice valido. Evento di sicurezza `TOTP_DISATTIVATO`. L'azzeramento da amministratore (`USR_TOTP_AZZERA`) resta fuori dalle rotte.
- **Area `O` senza app:** l'accesso passa dal codice via mail; il client impone poi la registrazione (`registrazioneObbligatoria`). L'obbligo è del client: il server non blocca le altre rotte.
- **Gesty:** non ha aree, la modalità è quella della riga `GESTY` di `USR_APPS` e vale anche per Gesty desktop; `USR_WEB_SESSIONE_ADOTTA` riconosce le sessioni di zServer dal nome della postazione.

### Scenario: codice dell'app giusto
- **Dato** un utente con l'app attiva e il token del login con `otp` vero
- **Quando** manda a `/api/auth/otp/totp` il codice corrente
- **Allora** 200, e dalla richiesta successiva il token vale come uno ordinario (stesso `id_sessione`)

### Scenario: codice errato, già usato, utente bloccato
- 400 con il testo della procedura (`Codice non valido.`, `Codice gia' usato: attendere il codice successivo dell'app.`, `Utente bloccato per troppi tentativi errati: ...`); il rifiuto si conferma, perché il blocco conta i tentativi scritti. Soglia e durata: `ACCESSO_MAX_TENTATIVI` e `ACCESSO_MINUTI_BLOCCO`

### Scenario: prima registrazione senza app
- **Dato** un utente con `OTP` vero e senza app
- **Quando** chiede il codice via mail e lo verifica
- **Allora** la sessione si completa e il client propone la registrazione dell'app (`/totp/registra`, `/totp/attiva`), come fa WT desktop

### Scenario: azzeramento
- L'azzeramento dell'app di un utente (`USR_TOTP_AZZERA`) resta all'amministratore di WT desktop: non ha rotte.

## Configurazione
Le voci `expirationMinutes`, `leewaySeconds`, `refreshTokenDays` e `refreshTokenCleanupDays` della sezione JWT della configurazione (`App.Config.pas`) regolano la durata del token di accesso, la tolleranza sulle date e la durata e la pulizia dei token di rinnovo.

> Specifica ricavata dalla copia di `SRC` del 2026-10-28 16:40, verificata il 2026-10-30: in produzione zServer non era cambiato dopo quella data.
