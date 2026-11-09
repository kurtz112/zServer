// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit WT.Anpr.Gestore;

// Gestore del tipo ANPR della coda ZZ_CODA per WT: interroga ANPR attraverso
// Stesei e registra il risultato nelle tabelle ANPR_* di WT, con le stesse
// procedure e nello stesso ordine dell'applicazione (dmStesei,
// SaveAnagraficaANPR):
//
// ANPR_RICHIESTE_ADD           la richiesta, con l'errore se ANPR ha detto no
// ANPR_ANAGRAFICHE_ADD         residenza, con il legame preso dal nucleo
// ANPR_FAMIGLIARI_ADD          un componente del nucleo per riga
// ANPR_INDIRIZZI_DIGITALI_ADD  domicili digitali da INAD
//
// Il lavoro porta con se' l'utente che l'ha chiesto. Non e' un dettaglio:
// STESEI_CONFIG_GET usa CURRENT_USER_ID() come identificativo dell'operatore
// verso ANPR e senza utente risponde "comune non configurato", e
// ANPR_RICHIESTE_ADD lo registra in USER_ID. Il thread della coda non ha
// utente (il raggruppamento svuota il contesto delle connessioni prese fuori
// da una richiesta HTTP), quindi il gestore dichiara quello del lavoro e lo
// svuota alla fine, anche se fallisce: la connessione serve poi gli altri
// lavori dello stesso giro.
//
// Esito per la coda:
// - riuscito, con "ANPR_RICHIESTA <id>" in ZZ_CODA.ESITO, sia quando ANPR
//   ha trovato la persona sia quando ha risposto con un errore (codice
//   fiscale sconosciuto, comune non abilitato, configurazione mancante):
//   la richiesta in errore e' registrata come fa WT, e riprovare non
//   cambierebbe la risposta;
// - fallito, e quindi riprovato, solo se Stesei non e' raggiungibile o il
//   database rifiuta una scrittura.
//
// Differenza voluta rispetto a WT: le date che ANPR non manda arrivano dalle
// strutture JSON come zero, e WT le scriveva cosi' (30/12/1899). Qui
// diventano NULL.

interface

uses
  System.SysUtils;

const
  TipoCodaAnpr = 'ANPR';

  /// <summary>Prefisso dell'esito di un lavoro ANPR riuscito.</summary>
  PrefissoEsitoAnpr = 'ANPR_RICHIESTA ';

  /// <summary>
  /// Origine della richiesta (dominio STESEI_ORIGINE_RICHIESTA): W =
  /// sportello, come le richieste fatte dal portale dell'operatore.
  /// </summary>
  OrigineSportello = 'W';

/// <summary>
/// Identificativo di ANPR_RICHIESTE scritto nell'esito di un lavoro riuscito,
/// 0 se l'esito non e' di un lavoro ANPR.
/// </summary>
function IdRichiestaDaEsito(const Esito: string): Int64;

implementation

uses
  System.JSON,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  MVCFramework.Logger,
  App.Profile,
  Json.Values,
  Queue.Service,
  WT.Anpr.Stesei,
  Stesei_ST001_ANPR_LoadResidenza_Response,
  Stesei_ST006_ANPR_LoadNucleo_Response,
  Stesei_ST012_INAD_LoadIndirizziDigitali_Response;

function IdRichiestaDaEsito(const Esito: string): Int64;
begin
  Result := 0;

  if Esito.StartsWith(PrefissoEsitoAnpr) then
    Result := StrToInt64Def(Esito.Substring(Length(PrefissoEsitoAnpr)).Trim, 0);
end;

procedure ImpostaData(Parametro: TFDParam; const Valore: TDateTime);
begin
  if Valore = 0 then
    Parametro.Clear
  else
    Parametro.AsDate := Valore;
end;

function CreaProcedura(Connessione: TFDConnection; const Nome: string): TFDStoredProc;
begin
  Result := TFDStoredProc.Create(nil);
  try
    Result.Connection := Connessione;
    Result.StoredProcName := Nome;
    Result.Prepare;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// STESEI_CONFIG_GET e' selezionabile ed esce senza righe quando il comune
// non e' configurato, quando manca in ZZ_COMUNI o quando non c'e' l'utente.
function LeggiConfigurazione(Connessione: TFDConnection; const Belfiore: string): TSteseiConfigurazione;
var
  Query: TFDQuery;
begin
  Result := Default(TSteseiConfigurazione);

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text :=
      'SELECT STESEI_CONFIG_GET.COMUNE_CONFIGURATO, STESEI_CONFIG_GET.CODICE_ISTAT, STESEI_CONFIG_GET.URL, ' +
      'STESEI_CONFIG_GET.UTENTE, STESEI_CONFIG_GET.PASSWORD_, STESEI_CONFIG_GET.ID_OPERATORE, STESEI_CONFIG_GET.ID_UFFICIO ' +
      'FROM STESEI_CONFIG_GET(:BELFIORE)';
    Query.ParamByName('BELFIORE').AsString := Belfiore;
    Query.Open;

    if Query.IsEmpty or (not Query.FieldByName('COMUNE_CONFIGURATO').AsBoolean) then
      Exit;

    Result.Configurato := True;
    Result.CodiceIstat := Query.FieldByName('CODICE_ISTAT').AsString;
    Result.Url := Query.FieldByName('URL').AsString;
    Result.Utente := Query.FieldByName('UTENTE').AsString;
    Result.Password := Query.FieldByName('PASSWORD_').AsString;
    Result.IdOperatore := Query.FieldByName('ID_OPERATORE').AsString;
    Result.IdUfficio := Query.FieldByName('ID_UFFICIO').AsInteger;
  finally
    FreeAndNil(Query);
  end;
end;

function SalvaRichiesta(Connessione: TFDConnection; const Origine, Belfiore, CodiceFiscale: string;
  const IdIntestatario: Int64; const MessaggioErrore: string): Int64;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaProcedura(Connessione, 'ANPR_RICHIESTE_ADD');
  try
    Procedura.ParamByName('ORIGINE_RICHIESTA').AsString := Origine;
    Procedura.ParamByName('BELFIORE').AsString := Belfiore;
    Procedura.ParamByName('CODICE_FISCALE').AsString := CodiceFiscale;

    if IdIntestatario > 0 then
      Procedura.ParamByName('ID_INTESTATARIO').AsLargeInt := IdIntestatario
    else
      Procedura.ParamByName('ID_INTESTATARIO').Clear;

    Procedura.ParamByName('ERRORE').AsBoolean := not MessaggioErrore.Trim.IsEmpty;
    Procedura.ParamByName('MESSAGGIO_ERRORE').AsString := MessaggioErrore.Trim;
    Procedura.ExecProc;

    Result := Procedura.ParamByName('ID_ANPR_RICHIESTA_RESULT').AsLargeInt;
  finally
    FreeAndNil(Procedura);
  end;
end;

function SalvaResidenza(Connessione: TFDConnection; const IdRichiesta: Int64; Residenza: TResidenzaResponse; Nucleo: TNucleoResponse): Int64;
var
  Procedura: TFDStoredProc;
begin
  Procedura := CreaProcedura(Connessione, 'ANPR_ANAGRAFICHE_ADD');
  try
    Procedura.ParamByName('ID_ANPR_RICHIESTA').AsLargeInt := IdRichiesta;
    Procedura.ParamByName('ID_ANPR').AsString := Residenza.idANPR;
    Procedura.ParamByName('CODICE_FISCALE').AsString := Residenza.codiceFiscale;
    ImpostaData(Procedura.ParamByName('CODICE_FISCALE_VALIDITA'), Residenza.codiceFiscaleValidita);
    Procedura.ParamByName('CODICE_FISCALE_VALIDITA_FLAG').AsString := Residenza.codiceFiscaleValiditaFlag;
    Procedura.ParamByName('CODICE_FISCALE_VALIDITA_FLAG_DESCRIZIONE').AsString := Residenza.codiceFiscaleValiditaFlagDescrizione;
    Procedura.ParamByName('COGNOME').AsString := Residenza.cognome;
    Procedura.ParamByName('NOME').AsString := Residenza.nome;
    Procedura.ParamByName('SESSO').AsString := Residenza.sesso;
    Procedura.ParamByName('SENZA_COGNOME_FLAG').AsString := Residenza.senzaCognomeFlag;
    Procedura.ParamByName('SENZA_NOME_FLAG').AsString := Residenza.senzaNomeFlag;
    Procedura.ParamByName('SOGGETTO_AIRE').AsString := Residenza.soggettoAIRE;
    ImpostaData(Procedura.ParamByName('NASCITA_DATA'), Residenza.nascitaData);
    Procedura.ParamByName('NASCITA_DATA_SENZA_GIORNO').AsString := Residenza.nascitaDataSenzaGiorno;
    Procedura.ParamByName('NASCITA_DATA_SENZA_GIORNO_MESE').AsString := Residenza.nascitaDataSenzaGiornoMese;
    Procedura.ParamByName('NASCITA_COMUNE_ITALIANO').AsString := Residenza.nascitaComuneItaliano;
    Procedura.ParamByName('NASCITA_COMUNE_ITALIANO_LOCALITA').AsString := Residenza.nascitaComuneItalianoLocalita;
    Procedura.ParamByName('NASCITA_COMUNE_ITALIANO_CODICE_ISTAT').AsString := Residenza.nascitaComuneItalianoCodiceIstat;
    Procedura.ParamByName('NASCITA_COMUNE_ESTERO').AsString := Residenza.nascitaComuneEstero;
    Procedura.ParamByName('NASCITA_PROVINCIA_ITALIANA').AsString := Residenza.nascitaProvinciaItaliana;
    Procedura.ParamByName('NASCITA_PROVINCIA_ESTERA').AsString := Residenza.nascitaProvinciaEstera;
    Procedura.ParamByName('NASCITA_STATO_ESTERO').AsString := Residenza.nascitaStatoEstero;
    Procedura.ParamByName('NASCITA_STATO_ESTERO_CODICE_ISTAT').AsString := Residenza.nascitaStatoEsteroCodiceIstat;
    Procedura.ParamByName('NASCITA_LUOGO_ECCEZIONALE').AsString := Residenza.nascitaLuogoEccezionale;
    Procedura.ParamByName('DATA_DECESSO').AsString := Residenza.dataDecesso;
    Procedura.ParamByName('ID_SCHEDA_SOGGETTO').AsInteger := Residenza.idSchedaSoggetto;
    Procedura.ParamByName('ID_SCHEDA_SOGGETTO_COMUNE').AsString := Residenza.idSchedaSoggettoComune;
    Procedura.ParamByName('ID_SCHEDA_SOGGETTO_COMUNE_ISTAT').AsString := Residenza.idSchedaSoggettoComuneIstat;
    Procedura.ParamByName('ID_OPERAZIONE_ANPR').AsString := Residenza.idOperazioneANPR;
    Procedura.ParamByName('ANNO_ESPATRIO').AsString := Residenza.annoEspatrio;
    Procedura.ParamByName('RESIDENZA_TIPO_INDIRIZZO').AsString := Residenza.residenzaTipoIndirizzo;
    Procedura.ParamByName('RESIDENZA_TIPO_INDIRIZZO_DESCRIZIONE').AsString := Residenza.residenzaTipoIndirizzoDescrizione;
    Procedura.ParamByName('RESIDENZA_TOPONIMO').AsString := Residenza.residenzaToponimo;
    Procedura.ParamByName('RESIDENZA_NUMERO_CIVICO').AsString := Residenza.residenzaNumeroCivico;
    Procedura.ParamByName('RESIDENZA_PRESSO').AsString := Residenza.residenzaPresso;
    ImpostaData(Procedura.ParamByName('RESIDENZA_DATADECORRENZA'), Residenza.residenzaDataDecorrenza);
    Procedura.ParamByName('RESIDENZA_CAP_ITALIANO').AsString := Residenza.residenzaCAPItaliano;
    Procedura.ParamByName('RESIDENZA_COMUNE_ITALIANO').AsString := Residenza.residenzaComuneItaliano;
    Procedura.ParamByName('RESIDENZA_COMUNE_ITALIANO_CODICE_ISTAT').AsString := Residenza.residenzaComuneItalianoCodiceIstat;
    Procedura.ParamByName('RESIDENZA_PROVINCIA_ITALIANA').AsString := Residenza.residenzaProvinciaItaliana;
    Procedura.ParamByName('RESIDENZA_LOCALITA_ITALIANA').AsString := Residenza.residenzaLocalitaItaliana;
    Procedura.ParamByName('RESIDENZA_FRAZIONE_ITALIANA').AsString := Residenza.residenzaFrazioneItaliana;
    Procedura.ParamByName('RESIDENZA_CAP_ESTERO').AsString := Residenza.residenzaCAPEstero;
    Procedura.ParamByName('RESIDENZA_COMUNE_ESTERO').AsString := Residenza.residenzaComuneEstero;
    Procedura.ParamByName('RESIDENZA_STATO_ESTERO').AsString := Residenza.residenzaStatoEstero;
    Procedura.ParamByName('RESIDENZA_STATO_ESTERO_CODICE_ISTAT').AsString := Residenza.residenzaStatoEsteroCodiceIstat;
    Procedura.ParamByName('RESIDENZA_PROVINCIA_ESTERA').AsString := Residenza.residenzaProvinciaEstera;
    Procedura.ParamByName('RESIDENZA_CONSOLATO_CODICE').AsString := Residenza.residenzaConsolatoCodice;
    Procedura.ParamByName('RESIDENZA_CONSOLATO').AsString := Residenza.residenzaConsolato;

    // Il legame con l'intestatario della famiglia sta nella risposta del
    // nucleo, non in quella della residenza.
    Procedura.ParamByName('TIPO_LEGAME_SOGGETTO').AsString := Nucleo.tipoLegameSoggetto;
    Procedura.ParamByName('TIPO_LEGAME_SOGGETTO_DESCR').AsString := Nucleo.tipoLegameSoggettoDescr;
    ImpostaData(Procedura.ParamByName('DATA_DECORRENZA_FAMIGLIA_CONVIVENZA_SOGGETTO'), Nucleo.dataDecorrenzaFamigliaConvivenzaSoggetto);
    Procedura.ParamByName('CODICE_LEGAME_SOGGETTO').AsString := Nucleo.codiceLegameSoggetto;
    Procedura.ParamByName('CODICE_LEGAME_SOGGETTO_DESCR').AsString := Nucleo.codiceLegameSoggettoDescr;
    Procedura.ParamByName('PROGRESSIVO_COMPONENTE_SOGGETTO').AsString := Nucleo.progressivoComponenteSoggetto;
    Procedura.ParamByName('DATA_DECORRENZA_LEGAME_SOGGETTO').AsString := Nucleo.dataDecorrenzaLegameSoggetto;
    Procedura.ExecProc;

    Result := Procedura.ParamByName('ID_ANPR_ANAGRAFICA').AsLargeInt;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure SalvaNucleo(Connessione: TFDConnection; const IdAnagrafica: Int64; Nucleo: TNucleoResponse);
var
  Procedura: TFDStoredProc;
  Soggetto: TSoggetto;
begin
  Procedura := CreaProcedura(Connessione, 'ANPR_FAMIGLIARI_ADD');
  try
    for Soggetto in Nucleo.soggetto do
    begin
      Procedura.ParamByName('ID_ANPR_ANAGRAFICA').AsLargeInt := IdAnagrafica;
      Procedura.ParamByName('ID_ANPR').AsString := Soggetto.idANPR;
      Procedura.ParamByName('CODICE_FISCALE').AsString := Soggetto.codiceFiscale;
      ImpostaData(Procedura.ParamByName('CODICE_FISCALE_VALIDITA'), Soggetto.codiceFiscaleValidita);
      Procedura.ParamByName('CODICE_FISCALE_VALIDITA_FLAG').AsString := Soggetto.codiceFiscaleValiditaFlag;
      Procedura.ParamByName('CODICE_FISCALE_VALIDITA_FLAG_DESCRIZIONE').AsString := Soggetto.codiceFiscaleValiditaFlagDescrizione;
      Procedura.ParamByName('COGNOME').AsString := Soggetto.cognome;
      Procedura.ParamByName('NOME').AsString := Soggetto.nome;
      Procedura.ParamByName('SESSO').AsString := Soggetto.sesso;
      Procedura.ParamByName('SENZA_COGNOME_FLAG').AsString := Soggetto.senzaCognomeFlag;
      Procedura.ParamByName('SENZA_NOME_FLAG').AsString := Soggetto.senzaNomeFlag;
      Procedura.ParamByName('SOGGETTO_AIRE').AsString := Soggetto.soggettoAIRE;
      ImpostaData(Procedura.ParamByName('NASCITA_DATA'), Soggetto.nascitaData);
      Procedura.ParamByName('NASCITA_DATA_SENZA_GIORNO').AsString := Soggetto.nascitaDataSenzaGiorno;
      Procedura.ParamByName('NASCITA_DATA_SENZA_GIORNO_MESE').AsString := Soggetto.nascitaDataSenzaGiornoMese;
      Procedura.ParamByName('NASCITA_COMUNE_ITALIANO').AsString := Soggetto.nascitaComuneItaliano;
      Procedura.ParamByName('NASCITA_COMUNE_ITALIANO_LOCALITA').AsString := Soggetto.nascitaComuneItalianoLocalita;
      Procedura.ParamByName('NASCITA_COMUNE_ITALIANO_CODICE_ISTAT').AsString := Soggetto.nascitaComuneItalianoCodiceIstat;
      Procedura.ParamByName('NASCITA_COMUNE_ESTERO').AsString := Soggetto.nascitaComuneEstero;
      Procedura.ParamByName('NASCITA_PROVINCIA_ITALIANA').AsString := Soggetto.nascitaProvinciaItaliana;
      Procedura.ParamByName('NASCITA_PROVINCIA_ESTERA').AsString := Soggetto.nascitaProvinciaEstera;
      Procedura.ParamByName('NASCITA_STATO_ESTERO').AsString := Soggetto.nascitaStatoEstero;
      Procedura.ParamByName('NASCITA_STATO_ESTERO_CODICE_ISTAT').AsString := Soggetto.nascitaStatoEsteroCodiceIstat;
      Procedura.ParamByName('NASCITA_LUOGO_ECCEZIONALE').AsString := Soggetto.nascitaLuogoEccezionale;
      Procedura.ParamByName('DATA_DECESSO').Clear;
      Procedura.ParamByName('ID_SCHEDA_SOGGETTO').AsInteger := Soggetto.idSchedaSoggetto;
      Procedura.ParamByName('ID_SCHEDA_SOGGETTO_COMUNE').AsString := Soggetto.idSchedaSoggettoComune;
      Procedura.ParamByName('ID_SCHEDA_SOGGETTO_COMUNE_ISTAT').AsString := Soggetto.idSchedaSoggettoComuneIstat;
      Procedura.ParamByName('ID_OPERAZIONE_ANPR').Clear;
      Procedura.ParamByName('ANNO_ESPATRIO').AsString := Soggetto.annoEspatrio;
      Procedura.ParamByName('TIPO_LEGAME_SOGGETTO').AsString := Soggetto.tipoLegameSoggetto;
      Procedura.ParamByName('TIPO_LEGAME_SOGGETTO_DESCR').AsString := Soggetto.tipoLegameSoggettoDescr;
      ImpostaData(Procedura.ParamByName('DATA_DECORRENZA_FAMIGLIA_CONVIVENZA_SOGGETTO'), Soggetto.dataDecorrenzaFamigliaConvivenzaSoggetto);
      Procedura.ParamByName('CODICE_LEGAME_SOGGETTO').AsString := Soggetto.codiceLegameSoggetto;
      Procedura.ParamByName('CODICE_LEGAME_SOGGETTO_DESCR').AsString := Soggetto.codiceLegameSoggettoDescr;
      Procedura.ParamByName('PROGRESSIVO_COMPONENTE_SOGGETTO').AsString := Soggetto.progressivoComponenteSoggetto;
      Procedura.ParamByName('DATA_DECORRENZA_LEGAME_SOGGETTO').AsString := Soggetto.dataDecorrenzaLegameSoggetto;
      Procedura.ExecProc;
    end;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure SalvaIndirizziDigitali(Connessione: TFDConnection; const IdAnagrafica: Int64; IndirizziDigitali: TST012_LoadIndirizziDigitali_Response);
var
  Procedura: TFDStoredProc;
  Indirizzo: TIndirizzoDigitale;
begin
  // INAD in errore (nessun domicilio digitale) non ha indirizzi da salvare.
  if (not Assigned(IndirizziDigitali)) or IndirizziDigitali.errore.errore then
    Exit;

  Procedura := CreaProcedura(Connessione, 'ANPR_INDIRIZZI_DIGITALI_ADD');
  try
    for Indirizzo in IndirizziDigitali.response.indirizziDigitali do
    begin
      Procedura.ParamByName('ID_ANPR_ANAGRAFICA').AsLargeInt := IdAnagrafica;
      Procedura.ParamByName('INDIRIZZO_DIGITALE').AsString := Indirizzo.indirizzoDigitale;
      Procedura.ParamByName('PROFESSIONE').AsString := Indirizzo.professione;
      ImpostaData(Procedura.ParamByName('DATA_FINE_VALIDITA'), Indirizzo.dataFineValidita);
      Procedura.ParamByName('MOTIVAZIONE_CESSAZIONE').AsString := Indirizzo.motivazioneCessazione;
      Procedura.ExecProc;
    end;
  finally
    FreeAndNil(Procedura);
  end;
end;

// Esegue la ricerca con il contesto utente gia' dichiarato sulla connessione.
function CercaERegistra(Connessione: TFDConnection; Contenuto: TJSONObject): Int64;
var
  Belfiore: string;
  CodiceFiscale: string;
  Origine: string;
  Motivo: string;
  IdIntestatario: Int64;
  Configurazione: TSteseiConfigurazione;
  Ricerca: TSteseiRicercaAnagrafe;
  IdAnagrafica: Int64;
begin
  Belfiore := JsonStr(Contenuto, 'belfiore').Trim.ToUpper;
  CodiceFiscale := JsonStr(Contenuto, 'codiceFiscale').Trim.ToUpper;
  Origine := JsonStr(Contenuto, 'origine', OrigineSportello);
  Motivo := JsonStr(Contenuto, 'motivo', 'Ricerca Anagrafe');
  IdIntestatario := JsonInt64(Contenuto, 'idIntestatario');

  Configurazione := LeggiConfigurazione(Connessione, Belfiore);

  if not Configurazione.Configurato then
    Exit(SalvaRichiesta(Connessione, Origine, Belfiore, CodiceFiscale, IdIntestatario,
      Format('Collegamento ad ANPR (Stesei) non configurato per il comune %s.', [Belfiore])));

  Ricerca := TSteseiRicercaAnagrafe.Create(Configurazione);
  try
    // Stesei non raggiungibile solleva: il lavoro fallisce e si riprova.
    if not Ricerca.Cerca(CodiceFiscale, Motivo) then
      Exit(SalvaRichiesta(Connessione, Origine, Belfiore, CodiceFiscale, IdIntestatario, Ricerca.Errore));

    Result := SalvaRichiesta(Connessione, Origine, Belfiore, CodiceFiscale, IdIntestatario, '');
    IdAnagrafica := SalvaResidenza(Connessione, Result, Ricerca.Residenza.response, Ricerca.Nucleo.response);
    SalvaNucleo(Connessione, IdAnagrafica, Ricerca.Nucleo.response);
    SalvaIndirizziDigitali(Connessione, IdAnagrafica, Ricerca.IndirizziDigitali);
  finally
    FreeAndNil(Ricerca);
  end;
end;

function GestisciAnpr(Contenuto: TJSONObject; Connessione: TFDConnection; out Messaggio: string): Boolean;
var
  UserId: Int64;
  IdSessione: Int64;
  UserName: string;
  IdRichiesta: Int64;
begin
  UserId := JsonInt64(Contenuto, 'userId');
  IdSessione := JsonInt64(Contenuto, 'idSessione');
  UserName := JsonStr(Contenuto, 'userName');

  // Senza utente STESEI_CONFIG_GET non restituisce la configurazione e
  // ANPR_RICHIESTE resterebbe senza autore: il lavoro e' malformato, e lo
  // dice invece di registrare una richiesta senza padrone.
  if (UserId <= 0) or (IdSessione <= 0) then
  begin
    Messaggio := 'Lavoro ANPR senza utente o senza sessione: va accodato da una richiesta autenticata.';
    Exit(False);
  end;

  if JsonStr(Contenuto, 'belfiore').Trim.IsEmpty or JsonStr(Contenuto, 'codiceFiscale').Trim.IsEmpty then
  begin
    Messaggio := 'Lavoro ANPR senza comune o senza codice fiscale.';
    Exit(False);
  end;

  TAppProfiles.Corrente.ImpostaContesto(Connessione, UserId, IdSessione, UserName);
  try
    IdRichiesta := CercaERegistra(Connessione, Contenuto);
  finally
    // In caso di errore l'elaboratore annulla le scritture, ma la variabile
    // di contesto USER_ID non segue le transazioni: va svuotata comunque.
    try
      TAppProfiles.Corrente.AzzeraContesto(Connessione);
    except
      on E: Exception do
        LogE('ANPR: contesto utente non svuotato sulla connessione della coda: ' + E.Message);
    end;
  end;

  Messaggio := PrefissoEsitoAnpr + IdRichiesta.ToString;
  Result := True;
end;

initialization

TCodaGestori.Registra(TipoCodaAnpr, GestisciAnpr);

end.
