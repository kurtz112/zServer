// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit WT.Admin.Controller;

// Portato da Moduli\WT\dmAdmin.pas (classe TAdmin, framework TRoute).
//
// Non tutto e' stato riportato, e le esclusioni sono volute:
//
// - login, logout, refresh: li fa il nucleo (Authentication.Service con il
// profilo WT, e il middleware JWT). Riscriverli qui vorrebbe dire due
// modi di entrare, con due gestioni del contesto.
//
// - cmd: eseguiva ShellExecute su un nome di file preso da un parametro
// della richiesta, senza autenticazione. E' un'esecuzione di comandi da
// remoto: non va portata, va dismessa. Vedi il documento di analisi.
//
// - api e meta: la prima elencava le azioni del TWebModule (in DMVCFramework
// non ha piu' senso: le rotte sono attributi, e Swagger le espone gia'),
// la seconda era interamente commentata nel sorgente.
//
// - firma_elettronica: riceveva un JSON, lo scriveva nel registro e
// rispondeva OK. Non faceva altro.
//
// - spid_login: chiamava USR_SPID_LOGIN con un gettone, ma quella procedura
// non esiste (verificato su WT e su SECOVAL il 2026-09-21). Esiste
// USR_LOGIN_SPID, che riceve gli attributi restituiti dal gateway SPID:
// il ritorno SPID va progettato nel canale di accesso (S1), non trascinato.
//
// - login di dominio (Active Directory): dipende da zz.ActiveDirectory, che
// e' solo Windows e farebbe cadere la compilazione per Linux, e si appoggia
// a una password condivisa che sostituisce quella dell'utente
// (ConfigProps.DominioPwd). E' una scelta di impianto da rifare, non da
// trascinare.
//
// - documento/($idGedoDoc) e upload: tolti il 2026-10-06. Il documento GeDo
// e' una riga di OBJ_FILES e si scarica con GET /api/files/{ID_OBJECT_FILE}
// (GEDO_DOCS.ID_OBJECT_FILE), che applica le stesse regole di
// WEB_GET_FILE_NAME; upload scriveva nella cartella dell'eseguibile file
// che nessuna tabella conosceva, col nome dato dal client, e si carica con
// POST /api/files/{oid}. Nessun chiamante in SRC: vedi l'analisi
// OUT\20261006-zserver-agora-anpr-firma-file-pdf.

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

  [MVCPath('/api/wt/admin')]
  [MVCDoc('Servizi di amministrazione e accesso di WinTarif')]
  TWTAdminController = class(TBaseController)
  private
    /// <summary>
    /// Esegue la procedura, spedisce il messaggio che ha preparato e
    /// conferma solo se la spedizione riesce: e' la sequenza del vecchio
    /// server, e va mantenuta perche' una registrazione confermata senza
    /// messaggio lascia l'utente senza credenziali.
    /// </summary>
    procedure EseguiConInvioMail(const NomeProcedura: string; Parametri: TParamValues; const PrefissoOggetto: string);
  public
    [MVCPath('/ping')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Verifica che il server risponda')]
    procedure Ping;

    [MVCPath('/ver')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Prodotto, profilo e compilazione')]
    procedure Ver;

    [MVCPath('/checkjwt')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Dice se il token presente nella richiesta e valido')]
    procedure VerificaToken;

    [MVCPath('/comuni-abilitati')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Comuni su cui l''utente collegato e abilitato a lavorare')]
    procedure ComuniAbilitati;

    [MVCPath('/web-config')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Configurazione del portale per la sessione corrente')]
    procedure WebConfig;

    [MVCPath('/password')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Cambio della password dell''utente collegato')]
    procedure ModificaPassword;

    [MVCPath('/recupera-username')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Invia all''indirizzo indicato il nome utente associato')]
    procedure RecuperaUsername;

    [MVCPath('/recupera-password')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Genera una nuova password e la invia all''indirizzo indicato')]
    procedure RecuperaPassword;

    [MVCPath('/registrazione')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Richiesta di registrazione di un nuovo utente')]
    procedure RichiestaRegistrazione;

    [MVCPath('/registrazione/conferma')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Conferma della registrazione tramite gettone ricevuto per posta')]
    procedure ConfermaRegistrazione;
  end;

implementation

uses
  System.Variants,
  FireDAC.Stan.Param,
  App.Profile,
  FiredacHelper,
  Json.Values,
  Mail.Sender,
  Token.Service;

{ TWTAdminController }

procedure TWTAdminController.Ping;
begin
  RenderEsito(True);
end;

procedure TWTAdminController.Ver;
var
  Risposta: TJSONObject;
begin
  // Il vecchio server leggeva qui le informazioni di versione della risorsa
  // dell'eseguibile (zz.VersionInfo): su Linux quella risorsa non esiste,
  // quindi si riportano i dati che valgono su tutte le piattaforme.
  Risposta := TJSONObject.Create;
  Risposta.AddPair('applicazione', TAppProfiles.Corrente.Codice);
  Risposta.AddPair('profilo', TAppProfiles.Corrente.Codice);
  Risposta.AddPair('applicativo', TAppProfiles.Corrente.CodiceApplicativo);
  Risposta.AddPair('build', {$IFDEF DEBUG}'DEBUG'{$ELSE}'RELEASE'{$ENDIF});

  RenderJson(Risposta);
end;

procedure TWTAdminController.VerificaToken;
var
  Risposta: TJSONObject;
  Valido: Boolean;
begin
  // Punto di ingresso pubblico: il middleware, quando trova un token su
  // un'azione che non lo richiede, lo verifica comunque e riempie LoggedUser
  // solo se e' valido. Un token scaduto o manomesso lascia quindi tutto vuoto.
  Valido := StrToInt64Def(Context.LoggedUser.CustomData[JWT_CLAIM_USER_ID], 0) > 0;

  Risposta := TJSONObject.Create;
  Risposta.AddPair('valido', TJSONBool.Create(Valido));

  if Valido then
  begin
    Risposta.AddPair('user_id', TJSONNumber.Create(StrToInt64Def(Context.LoggedUser.CustomData[JWT_CLAIM_USER_ID], 0)));
    Risposta.AddPair('nominativo', Context.LoggedUser.CustomData[JWT_CLAIM_NOMINATIVO]);
  end;

  RenderJson(Risposta);
end;

procedure TWTAdminController.ComuniAbilitati;
var
  Connessione: TFDConnection;
  Elenco: TFDQuery;
begin
  // USR_COMUNI_ABILITATI e' una procedura selezionabile e filtra per utente
  // corrente: senza il contesto della connessione non restituirebbe nulla.
  // Nel vecchio server era marcata [SkipJWT] ma poi chiamava Connect(Context),
  // cioe' pretendeva comunque il token: qui il token e' richiesto e basta.
  Connessione := PrendiConnessione;
  try
    Elenco := CreaQuery(Connessione, 'SELECT USR_COMUNI_ABILITATI.BELFIORE, USR_COMUNI_ABILITATI.COMUNE FROM USR_COMUNI_ABILITATI(:APP) ORDER BY USR_COMUNI_ABILITATI.COMUNE');
    try
      Elenco.ParamByName('APP').AsString := TAppProfiles.Corrente.CodiceApplicativo;
      Elenco.Open;
      try
        RenderDataSet(Elenco);
      finally
        Elenco.Close;
      end;
    finally
      FreeAndNil(Elenco);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TWTAdminController.WebConfig;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
begin
  Connessione := PrendiConnessione;
  try
    Procedura := CreaStoredProc(Connessione, 'WEB_CONFIG_GET');
    try
      if IdSessione > 0 then
        Procedura.ParamByName('ID_SESSIONE').AsLargeInt := IdSessione
      else
        Procedura.ParamByName('ID_SESSIONE').Clear;

      Procedura.ExecProc;
      try
        RenderStoredProc(Procedura);
      finally
        Procedura.Close;
      end;
    finally
      FreeAndNil(Procedura);
    end;
  finally
    RilasciaConnessione(Connessione);
  end;
end;

procedure TWTAdminController.ModificaPassword;
var
  Corpo: TJSONObject;
  Parametri: TParamValues;
  Esito: TJSONObject;
  PasswordVecchia: string;
  PasswordNuova: string;
begin
  Corpo := CorpoJson;
  try
    PasswordVecchia := JsonStr(Corpo, 'oldPassword');
    PasswordNuova := JsonStr(Corpo, 'newPassword');
  finally
    FreeAndNil(Corpo);
  end;

  if PasswordNuova.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Nuova password non indicata.');

  // L'utente e la sessione arrivano dal token, non dalla richiesta: nel
  // vecchio server lo USER_ID era un parametro, e chiunque potesse chiamare
  // il punto di ingresso poteva indicarne uno qualsiasi.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('ID_SESSIONE', IdSessione);
    Parametri.Add('USER_ID', UserId);
    Parametri.Add('OLD_PASSWORD', PasswordVecchia);
    Parametri.Add('NEW_PASSWORD', PasswordNuova);

    try
      Esito := TDataService.ExecuteStoredProc('USR_CAMBIA_PASSWORD', Parametri);
      FreeAndNil(Esito);
    except
      on E: Exception do
      begin
        Registro.Warn(Format('Cambio password non riuscito per utente %d: %s', [UserId, E.Message]), 'WTAdminController');
        raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Impossibile variare la password: ' + E.Message);
      end;
    end;
  finally
    FreeAndNil(Parametri);
  end;

  RenderEsito(True);
end;

procedure TWTAdminController.EseguiConInvioMail(const NomeProcedura: string; Parametri: TParamValues; const PrefissoOggetto: string);
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Messaggio: TMailMessage;
  Risultato: Int64;
  DescrizioneRisultato: string;
  Risposta: TJSONObject;
  Parametro: TFDParam;
begin
  if not TMailSenders.Disponibile then
    raise EMVCException.Create(HTTP_STATUS.ServiceUnavailable, 'Invio della posta non configurato su questo server: operazione non disponibile.');

  Risultato := 0;
  DescrizioneRisultato := '';

  Connessione := PrendiConnessione;
  try
    ApriTransazione(Connessione);
    try
      Procedura := CreaStoredProc(Connessione, NomeProcedura);
      try
        for var Voce in Parametri do
        begin
          Parametro := Procedura.Params.FindParam(Voce.Key);

          if not Assigned(Parametro) then
            Continue;

          if VarIsNull(Voce.Value) or VarIsEmpty(Voce.Value) then
            Parametro.Clear
          else
            Parametro.Value := Voce.Value;
        end;

        Procedura.ExecProc;
        try
          Messaggio.Destinatario := Procedura.ParamByName('MAIL_PER_INVIO').AsString;
          Messaggio.Mittente := Procedura.ParamByName('MAIL_PER_RISPOSTE').AsString;
          Messaggio.Oggetto := Procedura.ParamByName(PrefissoOggetto + '_OGGETTO').AsString;
          Messaggio.CorpoTesto := Procedura.ParamByName(PrefissoOggetto + '_CORPO').AsString;
          Messaggio.CorpoHtml := Procedura.ParamByName(PrefissoOggetto + '_CORPO_HTML').AsString;

          if Procedura.ParamExists('RISULTATO') then
            Risultato := Procedura.ParamByName('RISULTATO').AsLargeInt;

          if Procedura.ParamExists('DESC_RISULTATO') then
            DescrizioneRisultato := Procedura.ParamByName('DESC_RISULTATO').AsString;
        finally
          Procedura.Close;
        end;
      finally
        FreeAndNil(Procedura);
      end;

      Risposta := TJSONObject.Create;
      try
        Risposta.AddPair('success', TJSONBool.Create(True));

        if Risultato <> 0 then
        begin
          // La procedura ha respinto la richiesta: nessun messaggio da
          // spedire, e niente da confermare.
          Annulla(Connessione);
          Risposta.AddPair('risultato', TJSONNumber.Create(Risultato));
          Risposta.AddPair('descrizione', DescrizioneRisultato);
          Registro.Warn(Format('%s: risultato %d (%s)', [NomeProcedura, Risultato, DescrizioneRisultato]), 'WTAdminController');
          RenderJson(Risposta);
          Exit;
        end;

        if not TMailSenders.Invia(Messaggio, Connessione) then
        begin
          Annulla(Connessione);
          FreeAndNil(Risposta);
          raise EMVCException.Create(HTTP_STATUS.InternalServerError, 'Impossibile inviare il messaggio di conferma: operazione annullata.');
        end;

        Conferma(Connessione);
        RenderJson(Risposta);
      except
        on E: Exception do
        begin
          FreeAndNil(Risposta);
          raise;
        end;
      end;
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
end;

procedure TWTAdminController.RecuperaUsername;
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('E_MAIL', ParamObbligatorio('email'));
    Parametri.Add('INDIRIZZO_IP', Context.Request.ClientIp);

    EseguiConInvioMail('USR_RECUPERA_USER_NAME', Parametri, 'MAIL_RECUPERO_USER');
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTAdminController.RecuperaPassword;
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('USER_NAME', ParamObbligatorio('username'));
    Parametri.Add('E_MAIL', ParamObbligatorio('email'));
    Parametri.Add('INDIRIZZO_IP', Context.Request.ClientIp);

    EseguiConInvioMail('USR_RECUPERA_PASSWORD', Parametri, 'MAIL_RESET_PWD');
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTAdminController.RichiestaRegistrazione;
var
  Parametri: TParamValues;
begin
  Parametri := TParamValues.Create;
  try
    Parametri.Add('APP', TAppProfiles.Corrente.CodiceApplicativo);
    Parametri.Add('USER_NAME', ParamObbligatorio('username'));
    Parametri.Add('PASSWORD_', ParamObbligatorio('password'));
    Parametri.Add('E_MAIL', ParamObbligatorio('email'));
    Parametri.Add('BELFIORE', ParamByName('belfiore'));
    Parametri.Add('CODICE_FISCALE', ParamByName('codiceFiscale'));

    if ParamInt64('idIntestatario') > 0 then
      Parametri.Add('ID_INTESTATARIO', ParamInt64('idIntestatario'))
    else
      Parametri.Add('ID_INTESTATARIO', Null);

    EseguiConInvioMail('USR_INT_RICHIESTA_REGISTRAZIONE', Parametri, 'MAIL_REGISTRAZIONE');
  finally
    FreeAndNil(Parametri);
  end;
end;

procedure TWTAdminController.ConfermaRegistrazione;
var
  Parametri: TParamValues;
  Esito: TJSONObject;
begin
  // La conferma non manda posta: applica il gettone ricevuto e basta.
  Parametri := TParamValues.Create;
  try
    Parametri.Add('TOKEN', ParamObbligatorio('token'));
    Parametri.Add('INDIRIZZO_IP', Context.Request.ClientIp);

    Esito := TDataService.ExecuteStoredProc('USR_INT_CONFERMA_REGISTRAZIONE', Parametri);
    FreeAndNil(Esito);
  finally
    FreeAndNil(Parametri);
  end;

  RenderEsito(True);
end;

end.
