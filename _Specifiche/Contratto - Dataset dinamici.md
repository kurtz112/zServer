---
area: Contratto - Dataset dinamici
progetto: zServer
aggiornato: 2026-11-06
rilascio: OUT/20261106-pipa-sportello-comuni-funzioni-per-comune/003
---

# Contratto - Dataset dinamici

Questa specifica descrive cosa zServer promette ai client per i dataset dinamici: come si leggono i metadati di un dataset, come se ne leggono le righe con filtri, ricerca, ordinamento e paginazione nel formato del `CustomStore` di DevExtreme, come si inseriscono, modificano e cancellano le righe, e come si esegue una procedura esposta. Descrive il contratto, non il codice. Il codice oggi sta in `Core/Controllers/DynamicDataset.Controller.pas` (rotte sotto `/api/data`), `Core/Utils/DevExtremeHelper.pas` (lettura delle opzioni di DevExtreme, composizione della SQL, forma della risposta), `Core/Services/Data.Service.pas` e `Core/Utils/FiredacHelper.pas` (esecuzione e conversione delle righe in JSON), `Core/Controllers/Base.Controller.pas` (forma degli errori) e nei profili di prodotto `Products/WT/WT.Profile.pas` e `Products/Gesty/Gesty.Profile.pas` (perimetro). I metadati li compone il package `BASE_WEB` del database.

Tutte le rotte richiedono un token di accesso valido (`Contratto - Autenticazione`, ZSRV-AUT-002). Restano fuori da quest'area l'editor dei metadati `/api/meta/*` e le modifiche in loco dei metadati `PATCH /api/data/{dataset}/metadata/fields` e `/settings` (`Metadata.Patch.Controller.pas`).

I client che la usano oggi sono i componenti di zNg: `zPack/zNg/_Specifiche/Griglia dai metadati.md`, `Scheda dai metadati.md` e `Ricerca dai metadati.md` (requisiti `ZNG-GRI-*`, `ZNG-SCH-*`, `ZNG-RIC-*`).

**Forma leggibile dalle macchine:** `Contratto - Dataset dinamici.openapi.yaml`, nella stessa cartella, descrive rotte, parametri, corpi e risposte in OpenAPI 3.0 e porta in `x-requisito` il codice del requisito di ciascuna operazione e in `x-divergenze` i codici di questa sezione che la riguardano. Questo documento resta la fonte: gli scenari, i motivi e le eccezioni stanno solo qui. Una modifica al contratto aggiorna i due file nello stesso rilascio; se non concordano ha ragione il documento.

## ZSRV-DSD-001 Configurazione del dataset
Un dataset è una riga di `BASE_WEB_DATASETS`, identificata dalla colonna `DATASET` (nella forma `Modulo.Nome`, per esempio `Agora.ConfigTipologieCampi`). Il nome arriva nel percorso di ogni rotta (`{dataset}`) ed è legato come parametro, mai composto nel testo della SQL. Le colonne che contano per il contratto:

| Colonna | Uso |
|---|---|
| `SQL_SELECT` | SQL delle letture (obbligatoria) |
| `SQL_COUNT` | SQL del conteggio, se diversa da quella ricavata da `SQL_SELECT` |
| `RELATION_NAME` | Tabella delle scritture e del perimetro |
| `PK_FIELDS` | Campo chiave usato da modifica, cancellazione e perimetro |
| `SQL_INSERT`, `SQL_UPDATE`, `SQL_DELETE` | SQL scritte a mano; se mancano zServer genera la SQL dalla tabella |
| `CAN_INSERT`, `CAN_UPDATE`, `CAN_DELETE` | Scritture ammesse |
| `AUTHORIZATION` | Codice di autorizzazione richiesto (ZSRV-DSD-008) |

zServer rilegge la configurazione a ogni richiesta: non ne tiene una copia in memoria, quindi una modifica a `BASE_WEB_DATASETS` vale dalla richiesta successiva. Un nome che non ha la sua riga in `BASE_WEB_DATASETS` risponde 404 con `Dataset "<nome>" non trovato`, su tutte le rotte dei dataset metadati compresi.

## ZSRV-DSD-002 Metadati del dataset
`GET /api/data/{dataset}/metadata`. Prima di leggere i metadati zServer legge la configurazione del dataset e ne verifica l'autorizzazione come per le righe (ZSRV-DSD-008): la struttura di un dataset non è meno riservata delle sue righe. Risponde 200 con il JSON prodotto dalla procedura `BASE_WEB.LOAD_DATASET_METADATA`, da cui toglie le SQL del dataset; per il resto lo restituisce così com'è, controllando solo che sia un oggetto JSON valido. Il client li usa per costruire griglia, scheda e caselle di ricerca, e li tiene in una sua memoria per dataset.

| Campo | Contenuto |
|---|---|
| `datasetId` | Nome del dataset; il client lo usa per le rotte dei dati |
| `primaryKey` | `PK_FIELDS`; il client lo usa come chiave del `CustomStore` |
| `relationName` | Tabella delle scritture |
| `caption` | Titolo; se manca, il nome del dataset |
| `fields[]` | Un elemento per campo: `dataField`, `caption`, `dataType`, `isPrimaryKey`, `column` (proprietà della colonna di griglia), `control` (proprietà del campo nella scheda: `editorType`, `readOnly`, `required`, `editorOptions`, `dependsOn`...), `lookup` (`name`, `dataset`, `fkTable`, `valueExpr`, `displayExpr`, `params`, `mappings`, `pageSize`, `dropDownWidth`) e `picklist` (`name`, `items[]` con `value`, `text`, `icon`, `hasIcons`) |
| `gridSettings` | `editing` (`mode`, `allowAdding`, `allowUpdating`, `allowDeleting`, `allowView`, `useFormForEdit`, `confirmDelete`), `selection`, `export`, `bands`, `pageSize`, `allowedPageSizes` |
| `formSettings` | `mode`, `colCount`, `labelLocation`, `showColonAfterLabel`, `width`, `height`, `items[]` (albero di gruppi, schede e campi della scheda) |

`allowAdding`, `allowUpdating` e `allowDeleting` riflettono `CAN_INSERT`, `CAN_UPDATE` e `CAN_DELETE`: il client mostra i pulsanti di conseguenza, ma la verifica vera la fa il server sulla scrittura (ZSRV-DSD-010...012).

### Scenario: metadati già costruiti
- **Dato** un dataset con la sua riga in `BASE_WEB_DATASETS_META`
- **Quando** il client chiede i metadati
- **Allora** la risposta è 200 con il JSON salvato in quella riga

### Scenario: metadati da costruire
- **Dato** un dataset registrato che non ha ancora la riga in `BASE_WEB_DATASETS_META`
- **Quando** il client chiede i metadati
- **Allora** `LOAD_DATASET_METADATA` li costruisce con `DATASET_BUILD_META`, li salva e li restituisce
- **E** le richieste successive leggono la riga salvata: `BASE_WEB_DATASETS_META` fa da memoria dei metadati, ed è il package `BASE_WEB` a rigenerarla quando la configurazione cambia

### Scenario: permesso mancante
- **Dato** un dataset con un codice in `AUTHORIZATION`
- **Quando** un utente autenticato senza quel permesso chiede i metadati
- **Allora** la risposta è 403 con il messaggio dato da `USR_AUTHORIZATION_CHECK`, nella forma `{ success, message, status }` di ZSRV-DSD-014
- **E** `LOAD_DATASET_METADATA` non viene eseguita: i metadati non vengono né costruiti né letti

### Scenario: niente SQL nella risposta
- **Dato** un dataset con le sue SQL in `BASE_WEB_DATASETS`
- **Quando** un utente autorizzato chiede i metadati
- **Allora** la risposta non contiene `sqlSelect`, `sqlCount`, `sqlInsert`, `sqlUpdate` e `sqlDelete`, anche se `LOAD_DATASET_METADATA` li produce
- **E** il client non ne ha bisogno: costruisce griglia e scheda dai campi e legge le righe con le rotte dei dati, che prendono le SQL dalla configurazione sul server. L'editor dei metadati le legge dalle sue rotte `/api/meta/*`

### Scenario: risposte di errore
| Caso | Stato | Corpo |
|---|---|---|
| Nome vuoto | 400 | Testo semplice `datasetId obbligatorio` |
| Dataset non registrato in `BASE_WEB_DATASETS` | 404 | JSON, `message` `Dataset "<nome>" non trovato` |
| Permesso mancante | 403 | JSON, `message` di `USR_AUTHORIZATION_CHECK` |
| Dataset registrato senza metadati | 404 | Testo semplice `Nessun metadata per dataset: <nome>` |
| JSON salvato non valido | 500 | Testo semplice `JSON metadata non valido` |

## ZSRV-DSD-003 Lettura delle righe
`GET /api/data/{dataset}` con le opzioni di DevExtreme nella riga dell'indirizzo (ZSRV-DSD-004, 005) ed eventuali parametri propri del dataset (ZSRV-DSD-006). Risponde 200 con:

| Campo | Contenuto |
|---|---|
| `data` | Elenco delle righe; ogni riga ha per chiavi i nomi delle colonne della `SELECT` come li restituisce Firebird (di norma in maiuscolo) |
| `totalCount` | Solo se richiesto con `requireTotalCount=true` (ZSRV-DSD-005) |
| `groupCount` | Solo con il raggruppamento, se c'è almeno un gruppo |

L'intestazione `X-Total-Count` porta lo stesso conteggio, oppure `-1` se non è stato richiesto.

Valori nelle righe: i numeri come numeri JSON, i booleani come `true`/`false`, `NULL` come `null`, date e ore come testo ISO 8601 con lo scostamento del fuso del server (`2026-10-30T10:15:00.000+01:00`; una colonna `TIME` ha la data `1899-12-30`), i `BLOB` e i `MEMO` codificati in Base64.

### Scenario: raggruppamento
- **Dato** una richiesta con `group` (elenco di DevExtreme)
- **Quando** zServer ha letto le righe della pagina
- **Allora** le raggruppa in memoria sul **solo primo** selettore e risponde con `data` fatto di oggetti `{ "key": "<valore come testo>", "items": [...], "count": N }`
- **E** `totalCount` è il numero di righe della pagina letta, non il totale del dataset; i riepiloghi (`summary`) non vengono mai calcolati

zNg non chiede il raggruppamento al server (`grouping: false` nelle operazioni remote della griglia). Il parametro `select` viene letto ma ignorato: la risposta porta sempre tutte le colonne della `SELECT`.

## ZSRV-DSD-004 Filtri e ricerca
Il filtro arriva in `filter` come JSON nel formato di DevExtreme; la ricerca delle caselle a discesa in `searchExpr`, `searchOperation` e `searchValue`. Ogni valore diventa un parametro legato (`:P1`, `:P2`...), mai testo nella SQL. Il nome di un campo deve essere una colonna della `SELECT` del dataset; nel `WHERE` zServer usa l'espressione che produce la colonna (`TABELLA.CAMPO`, `COALESCE(...)`), così un nome presente in due tabelle unite non è ambiguo.

| Operatore DevExtreme | SQL |
|---|---|
| `=`, `<>`, `>`, `>=`, `<`, `<=` | Confronto diretto; numeri e booleani legati con il loro tipo |
| `contains`, `notcontains` | `UPPER(campo) [NOT] LIKE UPPER('%valore%')` |
| `startswith`, `endswith` | `UPPER(campo) LIKE UPPER('valore%')` o `('%valore')` |
| `["!", [...]]` | `NOT (...)` |
| `[[...], "and", [...]]` | Condizioni unite da `AND` o `OR`; in uno stesso livello vale l'ultimo operatore logico letto |

### Scenario: ricerca di una casella a discesa
- **Dato** `searchExpr` con un nome (`NOME` o `"NOME"`) o un elenco JSON (`["COGNOME","NOME"]`) e un `searchValue` non vuoto
- **Quando** il client legge le righe
- **Allora** zServer aggiunge una condizione per campo, unite da `OR` (da `AND` per `notcontains` e `<>`)
- **E** `searchOperation` accetta `contains` (predefinito, anche per un valore sconosciuto), `notcontains`, `startswith`, `endswith`, `=`, `<>`; un `searchValue` vuoto non filtra niente

### Scenario: campo o operatore non ammesso
- **Dato** un filtro, una ricerca o un ordinamento su un nome che non è una colonna della `SELECT`, che contiene caratteri diversi da lettere, cifre e `_`, o con un operatore fuori tabella
- **Quando** il client legge le righe
- **Allora** la risposta è 500 con il messaggio generico di ZSRV-DSD-014
- **E** un `filter` che non è un elenco JSON viene ignorato e la lettura prosegue senza filtro

## ZSRV-DSD-005 Ordinamento, paginazione e conteggio
`sort` è l'elenco di DevExtreme `[{ "selector": "CAMPO", "desc": false }]`; ogni selettore deve essere una colonna della `SELECT` e diventa `ORDER BY CAMPO ASC|DESC`, che sostituisce l'ordinamento della SQL del dataset. `skip` e `take` diventano `ROWS skip+1 TO skip+take`; senza `take` e con `skip` le righe vanno da `skip+1` alla fine; senza nessuno dei due arrivano tutte.

### Scenario: conteggio richiesto
- **Dato** `requireTotalCount=true`
- **Quando** il client legge una pagina
- **Allora** `totalCount` è il numero di righe che soddisfano filtri e ricerca, ignorando ordinamento e paginazione
- **E** se il dataset ha `SQL_COUNT`, il conteggio parte da quella SQL, con gli stessi segnaposto, perimetro, filtri e ricerca della lettura; altrimenti da `SQL_SELECT`

### Scenario: conteggio non richiesto
- **Dato** una richiesta senza `requireTotalCount`
- **Quando** il client legge
- **Allora** la risposta non ha `totalCount` e `X-Total-Count` vale `-1`

## ZSRV-DSD-006 Parametri della richiesta e segnaposto di sessione
La SQL di un dataset può chiedere chi sta leggendo e per quale ambito, e può avere parametri suoi.

| Nella SQL | Valore |
|---|---|
| `:##USER_ID` | Utente del token |
| `:##ID_SESSIONE` | Sessione del token |
| `:##BELFIORE` | Parametro `belfiore` della richiesta, verificato fra i comuni abilitati dell'utente (`USR_TMP_COMUNI`); vuoto = `NULL` |
| `:##ID_AZIENDA` | Parametro `idAzienda`, verificato fra le aziende abilitate (`USR_TMP_AZIENDE`); assente o 0 = `NULL` |
| `:NOME` qualunque | Parametro `NOME` della richiesta (riga dell'indirizzo, poi campi del modulo), senza distinzione fra maiuscole e minuscole, solo se non vuoto; altrimenti resta `NULL` |

I segnaposto valgono anche nelle `SQL_INSERT`, `SQL_UPDATE` e `SQL_DELETE`; i parametri propri (`:NOME`) solo nelle letture e nel conteggio. Il client manda i parametri propri come parametri dell'indirizzo (`extraParams` di `createDataStore`, evento `beforeLoad` dei componenti).

### Scenario: parametri riservati
- **Dato** una richiesta che porta `ID_SESSIONE`, `ID_SESSIONE_WEB`, `USER_ID`, `USER_NAME`, `ID_RISORSA`, `ID_INTESTATARIO`, `ID_AZIENDA` o `BELFIORE` come parametro dell'indirizzo
- **Quando** la SQL ha un parametro con quel nome
- **Allora** zServer non lo lega al valore della richiesta: chi chiede i dati lo dice il token, non il browser
- **E** restano esclusi anche i nomi che cominciano con `CTX_` e quelli nella forma `P<numero>`, riservati a segnaposto e filtri

### Scenario: comune o azienda non abilitati
- **Dato** una SQL con `:##BELFIORE` o `:##ID_AZIENDA`
- **Quando** la richiesta porta un comune o un'azienda fuori dagli abilitati dell'utente
- **Allora** la risposta è 403 con `Comune o azienda di lavoro non fra quelli abilitati.`
- **E** con un ambito ammesso zServer lo registra anche nel contesto della sessione prima di eseguire la SQL

## ZSRV-DSD-007 Lettura di una riga sola
zServer non ha una rotta `GET /api/data/{dataset}/{chiave}`: una riga si legge con `GET /api/data/{dataset}` e il filtro `[campo chiave, "=", valore]`, di solito con `take=1`. Passa così dalle stesse verifiche di tutte le letture (autorizzazione, perimetro, segnaposto). La vecchia rotta di lettura per le caselle a discesa è stata tolta: le caselle usano la lettura normale con la ricerca di ZSRV-DSD-004.

## ZSRV-DSD-008 Autorizzazione per dataset
Se il dataset ha un codice in `AUTHORIZATION`, metadati (ZSRV-DSD-002), lettura, inserimento, modifica e cancellazione chiedono a `USR_AUTHORIZATION_CHECK` se l'utente ha quel permesso, con i permessi dell'applicazione (WT o Gesty): non esiste un secondo sistema di ruoli. Un codice vuoto non chiede niente.

### Scenario: permesso mancante
- **Dato** un dataset con un codice in `AUTHORIZATION` che l'utente non ha
- **Quando** il client ne chiede i metadati, lo legge o lo scrive
- **Allora** la risposta è 403 con il messaggio dato da `USR_AUTHORIZATION_CHECK`
- **E** la verifica viene prima di qualunque lettura del corpo o esecuzione della SQL del dataset

### Scenario: scrittura non ammessa dal dataset
| Caso | Stato | Testo di `message` |
|---|---|---|
| `CAN_INSERT` falso | 403 | `Inserimento non consentito per questo dataset` |
| `CAN_UPDATE` falso | 403 | `Aggiornamento non consentito per questo dataset` |
| `CAN_DELETE` falso | 403 | `Eliminazione non consentita per questo dataset` |

## ZSRV-DSD-009 Perimetro del prodotto
Su WT, se la tabella del dataset (`RELATION_NAME`) ha la colonna `BELFIORE`, zServer aggiunge a letture e conteggi la condizione `BELFIORE IN (SELECT BELFIORE FROM USR_TMP_COMUNI)` e la applica anche alle scritture. Su Gesty, o su una tabella senza `BELFIORE`, il perimetro è vuoto e le verifiche qui sotto non cambiano niente.

### Scenario: modifica o cancellazione fuori perimetro
- **Dato** una chiave di una riga di un comune non abilitato per l'utente
- **Quando** il client la modifica o la cancella
- **Allora** la risposta è 404 con `Record non trovato.`: con 403 chi prova le chiavi in sequenza saprebbe quali esistono

### Scenario: inserimento senza comune
- **Dato** un dataset per comune
- **Quando** il client inserisce una riga senza `BELFIORE`
- **Allora** la risposta è 400 con `Il dataset e' per comune: il campo BELFIORE e' obbligatorio.`: una riga senza comune non si vedrebbe mai dalle letture

### Scenario: comune o azienda del corpo non abilitati
- **Dato** un dataset per comune
- **Quando** il corpo di un inserimento o di una modifica porta un `BELFIORE` o un `ID_AZIENDA` non abilitati
- **Allora** la risposta è 403 con `Comune o azienda non fra quelli abilitati per l'utente.`
- **E** una modifica senza `BELFIORE` nel corpo è ammessa: la riga resta nel suo comune

## ZSRV-DSD-010 Inserimento
`POST /api/data/{dataset}` con il corpo JSON della riga, le chiavi con i nomi delle colonne. Risponde 201 con l'intestazione `Location: /api/data/{dataset}` e un oggetto con i soli parametri di uscita del comando: `{}`, salvo una `SQL_INSERT` con `RETURNING`.

### Scenario: dataset senza SQL di inserimento
- **Dato** un dataset senza `SQL_INSERT`
- **Quando** il client manda la riga intera, compresi i campi che la `SELECT` prende da altre tabelle o calcola
- **Allora** zServer toglie dal corpo i campi che non sono colonne scrivibili di `RELATION_NAME` (colonne calcolate escluse) e genera `INSERT INTO "TABELLA" ("CAMPO", ...) VALUES (:CAMPO, ...)`
- **E** i nomi delle colonne sono fra doppi apici, quindi devono arrivare come li scrive Firebird (in maiuscolo)

### Scenario: dataset con SQL di inserimento
- **Dato** un dataset con `SQL_INSERT`
- **Quando** il client inserisce
- **Allora** zServer esegue quella SQL legando ogni `:CAMPO` al campo omonimo del corpo e risolvendo i segnaposto di ZSRV-DSD-006; il corpo non viene sfoltito

### Scenario: corpo non valido
- **Dato** un corpo che non è un oggetto JSON (anche un elenco)
- **Quando** il client inserisce o modifica
- **Allora** la risposta è 400 con `Corpo della richiesta non valido: atteso un oggetto JSON.`

Conversione dei valori del corpo: `null` diventa `NULL`; numeri e booleani passano con il loro tipo; un testo nella forma `AAAA-MM-GG` o `AAAA-MM-GGThh:mm...` diventa data e ora (senza fuso è ora locale, con `Z` o con lo scostamento viene portato all'ora locale); ogni altro testo resta testo.

## ZSRV-DSD-011 Modifica
`PUT /api/data/{dataset}/{chiave}` con il corpo JSON dei campi. La chiave è un valore solo, confrontato con il campo `PK_FIELDS`. Risponde 200 con l'intestazione `Location: /api/data/{dataset}` e l'oggetto dei parametri di uscita (`{}`, salvo `RETURNING`).

### Scenario: dataset senza SQL di modifica
- **Dato** un dataset senza `SQL_UPDATE`
- **Quando** il client manda la riga
- **Allora** zServer toglie i campi che non sono colonne della tabella, come per l'inserimento, e genera `UPDATE "TABELLA" SET "CAMPO" = :CAMPO, ... WHERE "PK" = :KEY`, escludendo dal `SET` il campo chiave
- **E** un corpo con il solo campo chiave fa rispondere 500

### Scenario: dataset con SQL di modifica
- **Dato** un dataset con `SQL_UPDATE`
- **Quando** il client modifica
- **Allora** zServer esegue quella SQL con i campi del corpo e `:KEY` legato alla chiave del percorso

### Scenario: chiave inesistente
- **Dato** una chiave che non corrisponde a nessuna riga, fuori dal caso di ZSRV-DSD-009
- **Quando** il client modifica
- **Allora** la risposta è comunque 200: zServer non controlla quante righe sono state modificate

## ZSRV-DSD-012 Cancellazione
`DELETE /api/data/{dataset}/{chiave}`. Esegue `SQL_DELETE` con `:KEY` legato alla chiave, oppure, senza `SQL_DELETE`, `DELETE FROM "TABELLA" WHERE "PK" = :KEY`. Risponde 204 senza corpo, anche quando la chiave non corrisponde a nessuna riga (fuori dal caso di ZSRV-DSD-009, che risponde 404).

## ZSRV-DSD-013 Procedure esposte
`POST /api/data/sp/{procedura}` con il corpo `{ "inputParams": [ { "name": "...", "value": ... } ] }`. Si esegue solo una procedura elencata in `BASE_WEB_PROCEDURE` con `ATTIVA` vera; se la riga ha un codice in `AUTHORIZATION`, si verifica come per i dataset (ZSRV-DSD-008). Il nome è un identificatore Firebird senza virgolette, oppure `PACKAGE.PROCEDURA`. Ogni valore arriva alla procedura come testo; un parametro con valore `null` (o senza `value`) viene saltato, e la procedura usa il suo valore predefinito (prima arrivava come il testo "null" e una procedura con un parametro numerico rispondeva 500); un parametro che la procedura non ha viene ignorato; `outputParams` e `dataType`, che zNg manda, non vengono letti. Risponde 200 con un oggetto che ha per chiavi i parametri di uscita della procedura; l'esecuzione è confermata con un commit.

### Scenario: procedura non esposta
- **Dato** un nome non valido, una procedura non elencata, non attiva o senza il permesso richiesto
- **Quando** il client la chiama
- **Allora** la risposta è 403: `Procedura non disponibile.` nei primi tre casi, il messaggio di `USR_AUTHORIZATION_CHECK` nell'ultimo
- **E** una procedura che non esiste risponde come una non autorizzata, così chi prova i nomi non scopre quali esistono

### Scenario: parametri riservati nel corpo
- **Dato** un corpo con `ID_SESSIONE`, `ID_SESSIONE_WEB`, `USER_ID`, `USER_NAME`, `ID_RISORSA`, `ID_INTESTATARIO`, `ID_AZIENDA` o `BELFIORE` fra gli `inputParams` (senza distinguere maiuscole e minuscole)
- **Quando** il client chiama la procedura
- **Allora** la risposta è 400 e zServer annota il tentativo nel registro con procedura, parametro e utente: chi chiede lo dice il token, non il corpo
- **E** se la procedura dichiara `ID_SESSIONE`, `ID_SESSIONE_WEB` o `USER_ID`, zServer li lega alla sessione e all'utente del token, come per `:##ID_SESSIONE` e `:##USER_ID` dei dataset

## ZSRV-DSD-015 Moduli (solo WT, dal 2026-11-06)
Un dataset o una procedura possono appartenere a un modulo: colonna `MODULO` di `BASE_WEB_DATASETS` e `BASE_WEB_PROCEDURE` (script `WT-MODULI-01`). Senza modulo, e su Gesty che non ha la colonna, niente cambia. Con il modulo, dopo autorizzazione e area, zServer legge i moduli dell'utente (`USR_UTENTE_MODULI_WEB`, come in `Contratto - Autenticazione`, ZSRV-AUT-015) e:

| Operazione | Regola |
|---|---|
| Lettura, conteggio, metadati | L'utente deve avere il modulo in almeno un comune, consulta (`R`) o lavora (`W`) |
| Inserimento, modifica, cancellazione | Serve il modulo in scrittura (`W`) in almeno un comune |
| Procedura esposta | Serve il modulo in scrittura in almeno un comune |
| Perimetro della richiesta | `USR_TMP_COMUNI` perde i comuni in cui l'utente non ha il modulo (per le scritture e le procedure: non l'ha in scrittura) |

Il perimetro si restringe in `USR_TMP_COMUNI`, e non con una condizione aggiunta alla SQL, perché i dataset dello sportello sono procedure selezionabili che filtrano il comune al loro interno (`WTWEB_SPORTELLO_PERIMETRO`, `USR_TMP_COMUNI`). Così valgono per i comuni del modulo, senza altre modifiche, la condizione di ZSRV-DSD-009, il comune di lavoro di ZSRV-DSD-006, il comune del corpo delle scritture e le verifiche delle procedure del database (`WTWEB_SPORTELLO_RICHIESTA_*`). La tabella è temporanea della connessione e il contesto si dichiara di nuovo a ogni richiesta: la restrizione dura la sola richiesta.

### Scenario: modulo mancante
- **Dato** un dataset con il modulo `Comune.Giri`
- **Quando** lo chiede un utente che non ha `Comune.Giri` in nessun comune (o non l'ha in scrittura, per una scrittura)
- **Allora** la risposta è 403 `Funzione non disponibile per questo utente.` e il registro annota dataset, modulo e utente

### Scenario: delega su comuni diversi
- **Dato** un utente nei gruppi "Riuso, comune A" e "Consegne, comune B"
- **Quando** legge un dataset di `Comune.Consegne`
- **Allora** riceve le sole righe del comune B, anche se il comune A è fra i suoi comuni
- **E** se indica come comune di lavoro A la risposta è 403 `Comune o azienda di lavoro non fra quelli abilitati.`

### Scenario: modulo in sola consultazione in un comune
- **Dato** un utente con `Comune.Richieste` in scrittura nel comune A e in consultazione nel comune B
- **Quando** modifica o cancella una riga del comune B
- **Allora** la modifica o la cancellazione di un dataset con `BELFIORE` risponde 404 `Record non trovato.`, un inserimento con `BELFIORE` = B risponde 403 `Comune o azienda non fra quelli abilitati per l'utente.`, e una procedura dello sportello risponde con il suo errore di richiesta fuori dai comuni dell'utente

### Limite noto
Una presa di connessione annidata dentro la stessa richiesta (rara: `Connection.Pool` ne apre una nuova solo se quella della richiesta è già in mano a qualcuno) dichiara il contesto da capo e vede il perimetro intero.

## ZSRV-DSD-014 Errori
Ogni errore ha il corpo `{ "success": false, "message": "...", "status": <stato> }`, salvo i tre casi in testo semplice della rotta dei metadati (ZSRV-DSD-002).

| Causa | Stato | `message` |
|---|---|---|
| Errore di Firebird (vincolo, eccezione di una procedura o di un trigger, SQL non valida) | 400 | Messaggio tradotto; in modalità di sviluppo con il dettaglio tecnico |
| Errori previsti dei requisiti precedenti | 400, 403, 404 | Il testo indicato nel requisito |
| Sessione scaduta | 401 | `Sessione scaduta, effettuare nuovamente il login` |
| Qualunque altro errore | 500 | `Si è verificato un errore imprevisto` |

## Divergenze note

Punti in cui client e server non concordano, o in cui zServer non mantiene ciò che dichiara. Quando la stessa divergenza compare in una specifica di zNg, il codice dell'altra è indicato fra parentesi. Si correggono nella voce R-177 di `Attivita Rinviate.md`; con la correzione il requisito si aggiorna e questa sezione si accorcia.

| Codice | Divergenza | Conseguenza |
|---|---|---|
| DIV-DSD-1 (DIV-RIC-1) | Il componente `zz-lookup` di zNg legge da `GET /api/data/lk/{dataset}` e `GET /api/data/lk/{dataset}/{chiave}` (`zz-lookup.component.ts:206`, `:236`); zServer non ha queste rotte: la lettura dedicata alle caselle è stata tolta (`DynamicDataset.Controller.pas:139-142`) e per `/{dataset}/{chiave}` esistono solo `PUT` e `DELETE` | Una casella `zz-lookup` non carica righe e non ritrova la riga scelta. Le caselle generate dai metadati (`LookupHelperService`) usano invece la lettura normale e funzionano |
| DIV-DSD-2 (DIV-GRI-4) | La scheda di zNg gestisce una chiave composta: con `primaryKey` "A,B" manda `PUT /api/data/{dataset}/v1,v2` (`zz-form.component.ts:453-456`). zServer tratta `PK_FIELDS` come un campo solo: `WHERE "A,B" = :KEY` (`DevExtremeHelper.pas:1258`, `:1278`) e `TABELLA.A,B = :KEY` nella verifica del perimetro (`DynamicDataset.Controller.pas:430`) | Modifica e cancellazione di un dataset con chiave composta e SQL generata falliscono con un errore di Firebird (400); funzionano solo con una `SQL_UPDATE`/`SQL_DELETE` scritta a mano che sappia leggere `:KEY` |
| DIV-DSD-3 | Il client si aspetta dall'inserimento la riga inserita (`zserver.service.ts:215-216`, tipo `RigaZServer`); zServer restituisce solo i parametri di uscita del comando (`DynamicDataset.Controller.pas:842-846`, `FiredacHelper.pas:343-354`), cioè `{}` senza `RETURNING` | Il `CustomStore` non riceve la chiave generata; la griglia si rilegge e non se ne accorge, ma un chiamante che usa il risultato dell'inserimento trova un oggetto vuoto |
| DIV-DSD-4 (DIV-RIC-3) | Il modello dei metadati di zNg dichiara campi che `BASE_WEB` non emette mai, né su Gesty né su WT: `lookup.columns` e `lookup.filter` (`metadata.models.ts:123`, `:126`), `control.validation` (`:79`), `masterDetail` (`:15`), `formSettings.resizable` (`:180`), `column.linebreak` (`:62`; il server manda `lineBreak` dentro `control`). Le chiavi emesse sono in `BUILD_ARRAY_FIELDS`, `BUILD_OBJ_GRID` e `BUILD_OBJ_FORM` del package `BASE_WEB` | Ogni casella di ricerca registra l'avviso "Configurazione colonne mancante" (`lookup.helper.service.ts:47-48`), cerca e ordina sul solo `displayExpr` e non applica filtri fissi; le regole di validazione e il dettaglio collegato non arrivano mai dai metadati |
| DIV-DSD-5 | I metadati applicano le personalizzazioni di `BASE_WEB_DATASETS_CUSTOM` (SQL, `PK_FIELDS`, `CAN_*`, titolo: `COALESCE(C..., D...)` in `BASE_WEB.pkg:477` e `:1601`); le rotte dei dati leggono solo `BASE_WEB_DATASETS` (`DynamicDataset.Controller.pas:207`, `:217-226`) | Con una personalizzazione, il client vede pulsanti che il server non applica: per esempio `allowAdding` vero e inserimento rifiutato con 403. Le SQL personalizzate non arrivano più al client (ZSRV-DSD-002), ma restano diverse da quelle eseguite |
| DIV-DSD-7 | Tre errori della rotta dei metadati sono testo semplice (nome vuoto, dataset senza metadati, JSON non valido: `Render(HTTP_STATUS..., '...')` in `GetMetadata`), mentre tutte le altre risposte di errore sono `{ success, message, status }` (`Base.Controller.pas:161`), che è la forma letta dall'intercettore degli errori di zNg (`error.interceptor.ts:185`). Il 403 e il 404 del dataset sconosciuto sono già in JSON | Su quei tre errori il client non trova `message` e non può mostrare il testo del server |
| DIV-DSD-8 | Le letture codificano in Base64 anche i `MEMO` di testo (`FiredacHelper.pas:164`, `:244-245`; `ExecuteQuery` con `encodeBlobs` vero, `DynamicDataset.Controller.pas:764`); zNg converte solo le date (`zserver.service.ts:241-283`) e non decodifica niente | Un campo `MEMO` (note, descrizioni lunghe) arriva a griglia e scheda come testo Base64 illeggibile, salvo che la SQL del dataset lo converta in `VARCHAR` |
| DIV-DSD-9 | zNg manda `select` (`zserver.service.ts:169`); zServer lo legge (`DevExtremeHelper.pas:899`) e non lo usa | La risposta porta sempre tutte le colonne: nessun errore, solo dati in più |
> Specifica ricavata dalla copia di `SRC` letta il 2026-10-30 (zServer e zNg) e dalla fotografia dei metadati del database GESTY del 2026-10-30 13:19 per il package `BASE_WEB`; le chiavi citate in DIV-DSD-4 mancano anche nella fotografia di WT dello stesso giorno.
