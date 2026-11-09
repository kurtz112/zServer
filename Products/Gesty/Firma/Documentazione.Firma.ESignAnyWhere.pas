// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit Documentazione.Firma.ESignAnyWhere;

// Fornitore di firma eSignAnyWhere (busta) per zServer, dietro il contratto
// IzFirmaProvider di zDocumentale.
//
// Copia ripulita di Gesty_Group\_Sorgenti\MotoriDocumentali\
// Documentazione.Firma.ESignAnyWhere.pas, che resta com'e' in Gesty desktop.
// Le differenze:
// - un client TeSignAnyWhereEngine nuovo per ogni chiamata, configurato qui,
//   invece dell'oggetto globale di Gesty: gli spazi dei firmatari non passano
//   da una busta all'altra;
// - il registro della richiesta non contiene mai il token (in Gesty la riga
//   'AUTH_TOKEN length=' scriveva il token intero, R-055);
// - Contrassegno e CercaBusta: il nome della busta porta il contrassegno
//   della registrazione, e prima di inviare il gestore cerca se la busta e'
//   gia' partita (decisione 12 dell'analisi). Dal 2026-11-07 le due cose
//   passano dall'interfaccia IzFirmaRicercaBusta, con cui la coda comune
//   (Firma.Gestore) le chiede a qualunque fornitore, in Gesty e in WT.
//
// Il fornitore non tocca il database: le versioni FIR e RIC nascono dalla
// richiamata OnCreaVersione e il registro passa da OnLogRequest e
// OnLogResponse, agganciate dal gestore della coda.
//
// Firmatari negli spazi del client (limite del client, tre spazi fissi): chi
// ha l'identificativo di firma remota occupa FirmaRemota1 e FirmaRemota2,
// nell'ordine; chi non l'ha diventa FirmaOTP. Piu' di due firme remote o
// piu' di una OTP sollevano EzFirmaErrore.
//
// Firma al banco (2026-11-07, centri del riuso di WT): IzFirmaCollegamento
// restituisce il collegamento alla pagina di firma del firmatario
// (envelope/{id}/viewerlinks), che l'operatore apre sul tablet. Un firmatario
// senza e-mail (il cittadino che ha dato solo il cellulare) riceve come
// indirizzo di contatto il parametro EMAIL_FIRMA_AL_BANCO del fornitore
// (tipicamente la casella del centro): eSignAnyWhere identifica ogni
// destinatario con un indirizzo, e il codice OTP arriva comunque per SMS al
// telefono. Senza il parametro la busta parte come prima, con l'indirizzo
// vuoto: in Gesty i firmatari hanno sempre l'e-mail e niente cambia.
//
// Si registra da solo: basta includere la unit nel progetto.

interface

uses
  System.SysUtils,
  zDocumentale.Firma.Types,
  zDocumentale.Firma.Intf,
  zDocumentale.Firma.ProviderBase,
  zDocumentale.Firma.Factory,
  eSignAnyWhere;

const
  FIRMA_FORNITORE_ESIGNANYWHERE = 'ESIGNANYWHERE';

  /// <summary>
  /// Parametro del fornitore: indirizzo di contatto dei firmatari senza
  /// e-mail (firma al banco con il solo cellulare).
  /// </summary>
  PARAMETRO_EMAIL_FIRMA_AL_BANCO = 'EMAIL_FIRMA_AL_BANCO';

type
  TzFirmaESignAnyWhereProvider = class(TzFirmaProviderBase, IzFirmaRicercaBusta, IzFirmaCollegamento)
  private
    FContrassegno: string;
    function CreaClient: TeSignAnyWhereEngine;
    function EmailDiContatto(const Firmatario: TzFirmaFirmatario): string;
    procedure ApplicaFirmatari(Client: TeSignAnyWhereEngine; const Documento: TzFirmaDocumento);
    function StatoDaEnvelopeStatus(const EnvelopeStatus: string): string;
  public
    function Nome: string; override;
    function Funzionalita: TzFirmaFunzionalitaSet; override;
    procedure TestConnessione; override;

    /// <summary>Invia la busta: Stato 'D' con l'identificativo della busta.</summary>
    function Firma(const Documento: TzFirmaDocumento): TzFirmaEsito; override;

    /// <summary>
    /// Stato della busta; se e' completata scarica firmato e audit nelle
    /// versioni FIR e RIC create con OnCreaVersione.
    /// </summary>
    function AggiornaEstremi(const Documento: TzFirmaDocumento; const IdDocumentoEsterno: string): TzFirmaEsito; override;

    /// <summary>
    /// Identificativo della busta inviata negli ultimi Giorni il cui nome
    /// contiene Contrassegno; vuoto se non c'e'.
    /// </summary>
    function CercaBusta(const Contrassegno: string; const Giorni: Integer): string;

    /// <summary>
    /// Testo messo in testa al nome della prossima busta inviata con Firma,
    /// per ritrovarla con CercaBusta.
    /// </summary>
    property Contrassegno: string read FContrassegno write FContrassegno;

    /// <summary>IzFirmaRicercaBusta: imposta Contrassegno.</summary>
    procedure ImpostaContrassegno(const Valore: string);

    /// <summary>
    /// IzFirmaCollegamento: collegamento alla pagina di firma del Firmatario
    /// nella busta. IndirizzoRitorno non si usa: eSignAnyWhere lo prende
    /// dalla busta al momento dell'invio, non dalla richiesta del
    /// collegamento.
    /// </summary>
    function CollegamentoFirma(const IdDocumentoEsterno: string; const Firmatario: TzFirmaFirmatario;
      const IndirizzoRitorno: string): string;
  end;

implementation

uses
  System.StrUtils,
  System.IOUtils,
  eSignAnyWhere.params;

function TzFirmaESignAnyWhereProvider.Nome: string;
begin
  Result := FIRMA_FORNITORE_ESIGNANYWHERE;
end;

function TzFirmaESignAnyWhereProvider.Funzionalita: TzFirmaFunzionalitaSet;
begin
  Result := [ffFirma];
end;

function TzFirmaESignAnyWhereProvider.CreaClient: TeSignAnyWhereEngine;

  function ParametroBoolean(const Chiave: string; const Default: Boolean): Boolean;
  begin
    Result := SameText(FConfigurazione.Parametro(Chiave, IfThen(Default, 'S', 'N')), 'S');
  end;

  function ParametroIntero(const Chiave: string; const Default: Integer): Integer;
  begin
    Result := StrToIntDef(FConfigurazione.Parametro(Chiave, Default.ToString), Default);
  end;

var
  Parametri: TeSignAnyWhereParams;
begin
  Result := TeSignAnyWhereEngine.Create(FConfigurazione.UrlBase, FConfigurazione.Parametro('AUTH_TOKEN'));
  try
    Parametri := Result.Params;

    Parametri.AddDocumentTimestamp := ParametroBoolean('ADD_DOCUMENT_TIMESTAMP', False);
    Parametri.ShareWithTeam := ParametroBoolean('SHARE_WITH_TEAM', False);
    Parametri.Reminder := ParametroBoolean('REMINDER', True);
    Parametri.FirstReminderInDays := ParametroIntero('FIRST_REMINDER_IN_DAYS', 1);
    Parametri.ReminderResendIntervalInDays := ParametroIntero('REMINDER_RESEND_INTERVAL_IN_DAYS', 1);
    Parametri.BeforeExpirationInDays := ParametroIntero('BEFORE_EXPIRATION_IN_DAYS', 3);
    Parametri.ExpirationInSecondsAfterSending := ParametroIntero('EXPIRATION_IN_SECONDS_AFTER_SENDING', 2419200);

    if not FConfigurazione.Parametro('EMAIL_CONFIGURATION_SUBJECT').IsEmpty then
      Parametri.EmailConfigurationSubject := FConfigurazione.Parametro('EMAIL_CONFIGURATION_SUBJECT');

    if not FConfigurazione.Parametro('EMAIL_CONFIGURATION_MESSAGE').IsEmpty then
      Parametri.EmailConfigurationMessage := FConfigurazione.Parametro('EMAIL_CONFIGURATION_MESSAGE');

    // LOG_RESPONSE non si applica: in zServer il client non scrive file.
    Result.Params := Parametri;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure TzFirmaESignAnyWhereProvider.TestConnessione;
var
  Client: TeSignAnyWhereEngine;
begin
  Client := CreaClient;
  try
    if not Client.Validate then
      raise EzFirmaErrore.CreateFmt('eSignAnyWhere: verifica della connessione fallita (HTTP %d)', [Client.UltimoStatoHttp]);
  finally
    FreeAndNil(Client);
  end;
end;

// L'e-mail del firmatario; se manca, quella del parametro
// EMAIL_FIRMA_AL_BANCO (vuota se il parametro non c'e', come prima).
function TzFirmaESignAnyWhereProvider.EmailDiContatto(const Firmatario: TzFirmaFirmatario): string;
begin
  Result := Firmatario.Email.Trim;

  if Result.IsEmpty then
    Result := FConfigurazione.Parametro(PARAMETRO_EMAIL_FIRMA_AL_BANCO).Trim;
end;

procedure TzFirmaESignAnyWhereProvider.ApplicaFirmatari(Client: TeSignAnyWhereEngine; const Documento: TzFirmaDocumento);

  procedure ApplicaFirmatario(var Spazio: TeSignAnyWhereEmailParams; const Firmatario: TzFirmaFirmatario);
  begin
    Spazio.PlaceHolder := Firmatario.Placeholder;
    Spazio.Cognome := Firmatario.Cognome;
    Spazio.Nome := Firmatario.Nome;

    // 2026-11-07: firma al banco con il solo cellulare. Con l'e-mail (Gesty,
    // e WT quando il cittadino l'ha data) il valore e' quello di prima.
    if Firmatario.Email.IsEmpty then
      Spazio.email := EmailDiContatto(Firmatario)
    else
      Spazio.email := Firmatario.Email;

    Spazio.Telefono := Firmatario.Telefono;
    Spazio.IdentificativoFirmaRemota := Firmatario.IdentificativoFirmaRemota;
  end;

var
  Parametri: TeSignAnyWhereParams;
  Firmatario: TzFirmaFirmatario;
  Spazio: TeSignAnyWhereEmailParams;
  IndiceRemoto: Integer;
  IndiceOtp: Integer;
begin
  Parametri := Client.Params;
  IndiceRemoto := 0;
  IndiceOtp := 0;

  for Firmatario in Documento.Firmatari do
  begin
    if not Firmatario.IdentificativoFirmaRemota.IsEmpty then
    begin
      Inc(IndiceRemoto);

      case IndiceRemoto of
        1:
          begin
            Spazio := Parametri.FirmaRemota1;
            ApplicaFirmatario(Spazio, Firmatario);
            Parametri.FirmaRemota1 := Spazio;
          end;
        2:
          begin
            Spazio := Parametri.FirmaRemota2;
            ApplicaFirmatario(Spazio, Firmatario);
            Parametri.FirmaRemota2 := Spazio;
          end;
      else
        raise EzFirmaErrore.Create('eSignAnyWhere: il client gestisce al massimo due firme remote per busta');
      end;
    end
    else
    begin
      Inc(IndiceOtp);

      if IndiceOtp > 1 then
        raise EzFirmaErrore.Create('eSignAnyWhere: il client gestisce al massimo una firma OTP per busta');

      Spazio := Parametri.FirmaOTP;
      ApplicaFirmatario(Spazio, Firmatario);
      Parametri.FirmaOTP := Spazio;
    end;
  end;

  Client.Params := Parametri;
end;

function TzFirmaESignAnyWhereProvider.Firma(const Documento: TzFirmaDocumento): TzFirmaEsito;
var
  Client: TeSignAnyWhereEngine;
  Parametri: TeSignAnyWhereParams;
  NomeBusta: string;
  IdLogRequest: Int64;
begin
  Result.Clear;

  if Documento.FullFileName.IsEmpty or not TFile.Exists(Documento.FullFileName) then
    raise EzFirmaErrore.CreateFmt('File da firmare non trovato: "%s"', [Documento.FullFileName]);

  NomeBusta := ExtractFileName(Documento.FullFileName);

  if not FContrassegno.IsEmpty then
    NomeBusta := FContrassegno + ' ' + NomeBusta;

  Client := CreaClient;
  try
    Parametri := Client.Params;
    Parametri.EnvelopeName := NomeBusta;
    Parametri.Ident := Documento.IdObjectFile.ToString;
    Client.Params := Parametri;

    ApplicaFirmatari(Client, Documento);

    IdLogRequest := LogRequest('FIRMA', Client.BaseUrl,
      Format('Busta: %s%sFile: %s%sFirmatari: %d', [NomeBusta, sLineBreak, Documento.FullFileName, sLineBreak, Length(Documento.Firmatari)]));
    try
      Result.IdDocumentoEsterno := Client.Firma(Documento.FullFileName);
    except
      on E: Exception do
      begin
        LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, E.Message);
        raise;
      end;
    end;

    LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, '');
  finally
    FreeAndNil(Client);
  end;

  Result.Ok := True;
  Result.Stato := FIRMA_STATO_IN_FIRMA;
  Result.StatoEsterno := 'Sent';
end;

procedure TzFirmaESignAnyWhereProvider.ImpostaContrassegno(const Valore: string);
begin
  FContrassegno := Valore;
end;

function TzFirmaESignAnyWhereProvider.CercaBusta(const Contrassegno: string; const Giorni: Integer): string;
var
  Client: TeSignAnyWhereEngine;
  IdLogRequest: Int64;
begin
  Client := CreaClient;
  try
    IdLogRequest := LogRequest('CERCA', Client.BaseUrl, Format('Contrassegno: %s%sGiorni: %d', [Contrassegno, sLineBreak, Giorni]));
    try
      Result := Client.CercaBusta(Contrassegno, Giorni);
    except
      on E: Exception do
      begin
        LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, E.Message);
        raise;
      end;
    end;

    LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, '');
  finally
    FreeAndNil(Client);
  end;
end;

function TzFirmaESignAnyWhereProvider.CollegamentoFirma(const IdDocumentoEsterno: string; const Firmatario: TzFirmaFirmatario;
  const IndirizzoRitorno: string): string;
var
  Client: TeSignAnyWhereEngine;
  Parametri: TeSignAnyWhereParams;
  IdLogRequest: Int64;
  Collegamenti: TArray<TeSignAnyWhereCollegamento>;
  Collegamento: TeSignAnyWhereCollegamento;
  Email: string;
begin
  Result := '';

  if IdDocumentoEsterno.IsEmpty then
    raise EzFirmaErrore.Create('eSignAnyWhere: identificativo della busta mancante');

  Email := EmailDiContatto(Firmatario);

  Client := CreaClient;
  try
    Parametri := Client.Params;
    Parametri.EnvelopeId := IdDocumentoEsterno;
    Client.Params := Parametri;

    IdLogRequest := LogRequest('COLLEGAMENTO', Client.BaseUrl, Format('Busta: %s%sFirmatario: %s', [IdDocumentoEsterno, sLineBreak, Email]));
    try
      Collegamenti := Client.CollegamentiFirma;
    except
      on E: Exception do
      begin
        LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, E.Message);
        raise;
      end;
    end;

    // Il corpo della risposta non va nel registro: i collegamenti aprono la
    // pagina di firma a chiunque li abbia.
    LogResponse(IdLogRequest, Client.UltimoStatoHttp, Format('Collegamenti: %d', [Length(Collegamenti)]), '');
  finally
    FreeAndNil(Client);
  end;

  if not Email.IsEmpty then
    for Collegamento in Collegamenti do
      if SameText(Collegamento.Email.Trim, Email) then
        Exit(Collegamento.Collegamento);

  // Un solo destinatario con la pagina di firma (le firme remote automatiche
  // non ne hanno): e' il firmatario, anche se l'indirizzo non e' riportato.
  if Length(Collegamenti) = 1 then
    Exit(Collegamenti[0].Collegamento);

  if Length(Collegamenti) > 1 then
    raise EzFirmaErrore.CreateFmt('eSignAnyWhere: la busta %s ha %d collegamenti di firma e nessuno e'' del firmatario.',
      [IdDocumentoEsterno, Length(Collegamenti)]);
end;

function TzFirmaESignAnyWhereProvider.StatoDaEnvelopeStatus(const EnvelopeStatus: string): string;
begin
  if SameText(EnvelopeStatus, 'Completed') then
    Result := FIRMA_STATO_FIRMATA
  else
    if SameText(EnvelopeStatus, 'Rejected') or SameText(EnvelopeStatus, 'Canceled') then
      Result := FIRMA_STATO_RESPINTA
    else
      if SameText(EnvelopeStatus, 'Expired') then
        Result := FIRMA_STATO_SCADUTA
      else
        Result := FIRMA_STATO_IN_FIRMA;
end;

function TzFirmaESignAnyWhereProvider.AggiornaEstremi(const Documento: TzFirmaDocumento; const IdDocumentoEsterno: string): TzFirmaEsito;
var
  Client: TeSignAnyWhereEngine;
  Parametri: TeSignAnyWhereParams;
  IdLogRequest: Int64;
  VersioneFirmata: TzFirmaVersioneCreata;
  VersioneAudit: TzFirmaVersioneCreata;
  NomeBase: string;
begin
  Result.Clear;

  if IdDocumentoEsterno.IsEmpty then
    raise EzFirmaErrore.Create('eSignAnyWhere: identificativo della busta mancante');

  Client := CreaClient;
  try
    Parametri := Client.Params;
    Parametri.EnvelopeId := IdDocumentoEsterno;
    Client.Params := Parametri;

    IdLogRequest := LogRequest('STATO', Client.BaseUrl, IdDocumentoEsterno);
    try
      Result.StatoEsterno := Client.EnvelopeStatus;
    except
      on E: Exception do
      begin
        LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, E.Message);
        raise;
      end;
    end;

    LogResponse(IdLogRequest, Client.UltimoStatoHttp, '', '');

    Result.Ok := True;
    Result.IdDocumentoEsterno := IdDocumentoEsterno;
    Result.Stato := StatoDaEnvelopeStatus(Result.StatoEsterno);

    if Result.Stato <> FIRMA_STATO_FIRMATA then
      Exit;

    // Busta completata: le versioni nascono dalla richiamata (identificativo
    // e percorso dal database), poi lo scarico scrive i byte nei percorsi
    // definitivi.
    NomeBase := TPath.GetFileNameWithoutExtension(Documento.FullFileName);
    VersioneFirmata := CreaVersione(Documento.IdObjectFile, 'FIR', NomeBase + '_firmato.pdf', '_firmato');
    VersioneAudit := CreaVersione(VersioneFirmata.IdObjectFile, 'RIC', NomeBase + '_audit.pdf', '_audit');

    IdLogRequest := LogRequest('DOWNLOAD', Client.BaseUrl, IdDocumentoEsterno);
    try
      Client.DownloadFiles(VersioneFirmata.FullFileName, VersioneAudit.FullFileName);
    except
      on E: Exception do
      begin
        LogResponse(IdLogRequest, Client.UltimoStatoHttp, Client.UltimoContenuto, E.Message);
        raise;
      end;
    end;

    LogResponse(IdLogRequest, Client.UltimoStatoHttp, '', '');

    Result.IdObjectFileFirmato := VersioneFirmata.IdObjectFile;
    Result.IdObjectFileAudit := VersioneAudit.IdObjectFile;
  finally
    FreeAndNil(Client);
  end;
end;

initialization

TzFirmaFactory.Registra(FIRMA_FORNITORE_ESIGNANYWHERE, TzFirmaESignAnyWhereProvider);

end.
