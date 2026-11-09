// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit Gesty.SitoWeb.Controller;

// Parte comune dei moduli pubblici dei siti (portata da
// Moduli\Gesty\dmCAPAC.pas, classe TCAPAC, framework TRoute).
//
// Qui non ci sono attributi di rotta: li mettono i controller dei singoli
// siti, che si distinguono solo per il percorso. Con gli attributi qui, ogni
// discendente registrerebbe due volte lo stesso percorso.
//
// Due moduli compilati dai visitatori del sito: richiesta di informazioni e
// invio di una candidatura con il curriculum. Arrivano senza token — chi li
// compila non ha un'utenza — e sono dichiarati fra le azioni pubbliche del
// profilo Gesty.
//
// I nomi dei campi non sono scelti qui: sono le etichette del modulo sul
// sito, e arrivano cosi' come sono, spazi e parentesi compresi. Cambiarli
// vorrebbe dire cambiare il sito.
//
// Due differenze rispetto al sorgente:
//
// 1. L'azione 'dump', che scriveva su file l'intera richiesta, non e' stata
// portata: era diagnostica di sviluppo esposta al pubblico, e scriveva un
// file per ogni chiamata. Quello che serviva a capire cosa arriva lo fa il
// registratore condiviso.
//
// 2. Il curriculum veniva scaricato da un indirizzo indicato nel modulo
// stesso. Il servizio che ospita il modulo carica il file e passa il suo
// indirizzo: lo si scarica ancora, ma solo se e' http o https e solo fino
// alla dimensione massima configurata, perche' e' un indirizzo che arriva
// dall'esterno.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  FireDAC.Comp.Client,
  Base.Controller,
  Data.Service;

type

  TSitoWebControllerBase = class(TBaseController)
  protected
    /// <summary>
    /// Campo del modulo per etichetta. I moduli del sito mandano i campi
    /// come contenuto della richiesta, con l'etichetta per nome.
    /// </summary>
    function Campo(const Etichetta: string): string; virtual;
    function PrimoCampoNonVuoto(const Etichette: array of string): string;
    function ScaricaFile(const Indirizzo: string; const NomeFileDestinazione: string): Boolean;
    function TestoDeiCampi: string;

    /// <summary>Registra la richiesta di informazioni e risponde.</summary>
    procedure RegistraRichiestaInformazioni;
    /// <summary>Registra la candidatura, scarica il curriculum e risponde.</summary>
    procedure RegistraCandidatura;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.StrUtils,
  FiredacHelper,
  App.Config;

{ TSitoWebControllerBase }

function TSitoWebControllerBase.Campo(const Etichetta: string): string;
begin
  Result := ParamByName(Etichetta);
end;

function TSitoWebControllerBase.PrimoCampoNonVuoto(const Etichette: array of string): string;
var
  Etichetta: string;
begin
  for Etichetta in Etichette do
  begin
    Result := Campo(Etichetta);

    if not Result.Trim.IsEmpty then
      Exit;
  end;

  Result := '';
end;

function TSitoWebControllerBase.TestoDeiCampi: string;
var
  Voce: TPair<string, string>;
  Righe: TStringList;
begin
  Righe := TStringList.Create;
  try
    for Voce in Context.Request.ContentFields do
      Righe.AddPair(Voce.Key, Voce.Value);

    Result := Righe.Text;
  finally
    FreeAndNil(Righe);
  end;
end;

function TSitoWebControllerBase.ScaricaFile(const Indirizzo: string; const NomeFileDestinazione: string): Boolean;
var
  Client: THTTPClient;
  Destinazione: TFileStream;
  Risposta: IHTTPResponse;
  Indirizzo_: TURI;
begin
  Result := False;

  if Indirizzo.Trim.IsEmpty then
    Exit;

  // L'indirizzo arriva dal modulo pubblico: si accettano solo i due schemi
  // del web, altrimenti si aprirebbe la porta a file:// e simili.
  try
    Indirizzo_ := TURI.Create(Indirizzo);
  except
    on E: Exception do
    begin
      Registro.Warn(Format('Candidatura - indirizzo del curriculum non valido: %s', [Indirizzo]), 'SitoWeb');
      Exit;
    end;
  end;

  if not MatchText(Indirizzo_.Scheme, ['http', 'https']) then
  begin
    Registro.Warn(Format('Candidatura - schema non ammesso per il curriculum: %s', [Indirizzo_.Scheme]), 'SitoWeb');
    Exit;
  end;

  Destinazione := TFileStream.Create(NomeFileDestinazione, fmCreate);
  try
    Client := THTTPClient.Create;
    try
      Risposta := Client.Get(Indirizzo, Destinazione);
      Result := (Risposta.StatusCode = 200) and (Destinazione.Size > 0) and (Destinazione.Size <= TAppConfig.Instance.Documenti.DimensioneMassimaByte);

      if not Result then
        Registro.Warn(Format('Candidatura - curriculum non scaricato: esito %d, %d byte', [Risposta.StatusCode, Destinazione.Size]), 'SitoWeb');
    finally
      FreeAndNil(Client);
    end;
  finally
    FreeAndNil(Destinazione);
  end;
end;

procedure TSitoWebControllerBase.RegistraRichiestaInformazioni;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  IdRichiesta: Int64;
begin
  Registro.Info('RichiestaInformazioni dal sito', 'SitoWeb');

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, 'WEB_RICHIESTE_INFORMAZIONI_ADD');
      try
        Procedura.ParamByName('DATA_RICHIESTA').AsDate := Date;
        Procedura.ParamByName('ORA_RICHIESTA').AsTime := Now;

        ImpostaParametro(Procedura.Params.FindParam('PAGINA'), PrimoCampoNonVuoto(['Pagina precedente', 'Titolo Corso']));
        ImpostaParametro(Procedura.Params.FindParam('CODICE_FISCALE'), Campo('Codice Fiscale'));
        ImpostaParametro(Procedura.Params.FindParam('PARTITA_IVA'), Campo('Partita Iva'));
        ImpostaParametro(Procedura.Params.FindParam('COGNOME'), Campo('Cognome'));
        ImpostaParametro(Procedura.Params.FindParam('NOME'), Campo('Nome'));
        ImpostaParametro(Procedura.Params.FindParam('TELEFONO'), PrimoCampoNonVuoto(['Numero di telefono', 'Telefono']));
        ImpostaParametro(Procedura.Params.FindParam('E_MAIL'), Campo('Email'));
        ImpostaParametro(Procedura.Params.FindParam('RICHIESTA'), Campo('Richiesta informazioni per: '));
        ImpostaParametro(Procedura.Params.FindParam('MESSAGGIO'), Campo('Messaggio'));
        ImpostaParametro(Procedura.Params.FindParam('CONTENT_FIELDS'), TestoDeiCampi);

        Procedura.ExecProc;
        try
          IdRichiesta := Procedura.ParamByName('ID_RICHIESTA_INFORMAZIONI_WEB').AsLargeInt;
        finally
          Procedura.Close;
        end;
      finally
        FreeAndNil(Procedura);
      end;

      Conferma(Connessione);
      Registro.Info(Format('RichiestaInformazioni - registrata con numero %d', [IdRichiesta]), 'SitoWeb');
    except
      on E: Exception do
      begin
        Annulla(Connessione);
        raise;
      end;
    end;
  finally
    RilasciaConnessione(Connessione);
  end;

  RenderEsito(True);
end;

procedure TSitoWebControllerBase.RegistraCandidatura;
const
  ETICHETTA_CURRICULUM = 'Allega il Curricululm Vitae';
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  IndirizzoCurriculum: string;
  NomeCurriculum: string;
  NomeFileTemporaneo: string;
  Scaricato: Boolean;
  IdCandidatura: Int64;
  PercorsoDefinitivo: string;
  Cartella: string;
  Voce: TPair<string, string>;
begin
  Registro.Info('InserimentoCandidatura dal sito', 'SitoWeb');

  // L'etichetta del campo del curriculum contiene la descrizione dei limiti
  // e cambia con il testo del modulo: si cerca per inizio, non per uguaglianza.
  IndirizzoCurriculum := '';
  for Voce in Context.Request.ContentFields do
    if Voce.Key.StartsWith(ETICHETTA_CURRICULUM, True) then
    begin
      IndirizzoCurriculum := Voce.Value;
      Break;
    end;

  NomeCurriculum := '';
  if not IndirizzoCurriculum.Trim.IsEmpty then
    NomeCurriculum := IndirizzoCurriculum.Substring(IndirizzoCurriculum.LastIndexOf('/') + 1);

  NomeFileTemporaneo := TPath.GetTempFileName;
  try
    Scaricato := ScaricaFile(IndirizzoCurriculum, NomeFileTemporaneo);

    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        Procedura := CreaStoredProc(Connessione, 'WEB_CANDIDATURE_ADD');
        try
          Procedura.ParamByName('DATA_CANDIDATURA').AsDate := Date;
          Procedura.ParamByName('ORA_CANDIDATURA').AsTime := Now;

          ImpostaParametro(Procedura.Params.FindParam('CODICE_FISCALE'), Campo('Codice Fiscale'));
          ImpostaParametro(Procedura.Params.FindParam('COGNOME'), Campo('Cognome'));
          ImpostaParametro(Procedura.Params.FindParam('NOME'), Campo('Nome'));
          ImpostaParametro(Procedura.Params.FindParam('E_MAIL'), Campo('Email'));
          ImpostaParametro(Procedura.Params.FindParam('AREA_DI_INTERESSE'), Campo('Area di interesse'));
          ImpostaParametro(Procedura.Params.FindParam('AREA_DI_INSEGNAMENTO'), PrimoCampoNonVuoto(['Area di insegnamento']));
          ImpostaParametro(Procedura.Params.FindParam('ALTRO'), PrimoCampoNonVuoto(['da compliare solo se hai selezionato "Altro"', 'Altro']));
          ImpostaParametro(Procedura.Params.FindParam('URL_CV'), IndirizzoCurriculum);
          ImpostaParametro(Procedura.Params.FindParam('FILE_NAME_CV'), NomeCurriculum);
          ImpostaParametro(Procedura.Params.FindParam('CONTENT_FIELDS'), TestoDeiCampi);

          Procedura.ExecProc;
          try
            IdCandidatura := Procedura.ParamByName('ID_CANDIDATURA_WEB').AsLargeInt;
            PercorsoDefinitivo := Procedura.ParamByName('FULL_FILE_NAME').AsString;
          finally
            Procedura.Close;
          end;
        finally
          FreeAndNil(Procedura);
        end;

        if Scaricato and (not PercorsoDefinitivo.Trim.IsEmpty) then
        begin
          Cartella := ExpandUNCFileName(ExcludeTrailingPathDelimiter(ExtractFilePath(PercorsoDefinitivo)));

          if not ForceDirectories(Cartella) then
            raise EMVCException.Create(HTTP_STATUS.InternalServerError, Format('Impossibile creare la cartella di destinazione %s.', [Cartella]));

          TFile.Copy(NomeFileTemporaneo, PercorsoDefinitivo, True);
          Registro.Info(Format('Candidatura %d - curriculum salvato in %s', [IdCandidatura, PercorsoDefinitivo]), 'SitoWeb');
        end;

        Conferma(Connessione);
      except
        on E: Exception do
        begin
          Annulla(Connessione);
          raise;
        end;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;
  finally
    if TFile.Exists(NomeFileTemporaneo) then
      TFile.Delete(NomeFileTemporaneo);
  end;

  RenderEsito(True);
end;

end.
