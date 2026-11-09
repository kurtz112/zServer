// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit WT.Neta.Controller;

// Portato da Moduli\WT\dmNeta.pas (classe TNeta, framework TRoute).
//
// Due operazioni verso il sistema Neta di Etra:
//
// - allineamento di una singola utenza, che passa da un servizio DataSnap
// (TWT_NetaClient, unit Neta_Proxy);
// - stampa della prenotazione, che compone un XML con la procedura
// QTA_PRENOTAZIONI_XML_ETRA_VETT e lo manda a uno StreamServer esterno che
// restituisce il PDF.
//
// L'intero controller e' compilato solo su Windows.
//
// Non e' una scelta di comodo: il collegamento a Neta e' DataSnap su DBX
// (Data.SqlExpr), e lo StreamServer e' un servizio raggiungibile dalla rete
// interna dei nodi Windows. Il sorgente d'origine aveva gia' la stampa
// dentro {$IFNDEF LINUX}: qui la condizione copre anche l'allineamento,
// perche' anche quello dipende da DataSnap.
//
// Le tre unit Neta_Proxy, Neta_StreamServer e Neta_WebService non stanno
// nella copia dei sorgenti: vivono nell'albero del vecchio server
// (cartella neta\) e vanno aggiunte ai percorsi di ricerca del progetto.
// Le chiamate qui sotto sono quelle del sorgente d'origine, invariate.

interface

{$IFDEF MSWINDOWS}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  Data.SqlExpr,
  FireDAC.Comp.Client,
  Base.Controller,
  Data.Service;

type

  [MVCPath('/api/wt/neta')]
  [MVCDoc('Integrazione con il sistema Neta')]
  TWTNetaController = class(TBaseController)
  private
    function XmlPrenotazione: string;
  public
    [MVCPath('/allineamento-singolo')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Allinea una singola utenza e restituisce l''intestatario collegato')]
    procedure AllineamentoSingolo;

    [MVCPath('/stampa-prenotazione')]
    [MVCHTTPMethod([httpGET])]
    [MVCDoc('Genera il PDF della prenotazione tramite lo StreamServer')]
    procedure StampaPrenotazione;
  end;

{$ENDIF}

implementation

{$IFDEF MSWINDOWS}

uses
  System.IOUtils,
  Data.DBXCommon,
  FireDAC.Stan.Param,
  App.Config,
  Neta_Proxy,
  Neta_StreamServer;

{ TWTNetaController }

procedure TWTNetaController.AllineamentoSingolo;
var
  Collegamento: TSQLConnection;
  Cliente: TWT_NetaClient;
  IdAziendaEtra: string;
  IdServizioEtra: string;
  IdIntestatario: Integer;
begin
  IdAziendaEtra := ParamObbligatorio('ID_AZIENDA');
  IdServizioEtra := ParamObbligatorio('ID_SERVIZIO');

  Registro.Info(Format('AllineamentoSingolo - azienda %s, servizio %s', [IdAziendaEtra, IdServizioEtra]), 'WTNetaController');

  // Il collegamento DataSnap si apre e si chiude dentro la richiesta: era
  // cosi' anche nel sorgente d'origine, e con un server a piu' richieste
  // contemporanee tenerlo aperto fra una e l'altra non e' possibile.
  Collegamento := TSQLConnection.Create(nil);
  try
    Collegamento.Connected := False;
    Collegamento.LoginPrompt := False;
    Collegamento.DriverName := 'Datasnap';
    Collegamento.Params.Values[TDBXPropertyNames.DriverName] := 'DataSnap';
    Collegamento.Params.Values[TDBXPropertyNames.HostName] := TAppConfig.Instance.Neta.Host;
    Collegamento.Params.Values[TDBXPropertyNames.Port] := TAppConfig.Instance.Neta.Porta.ToString;
    Collegamento.Connected := True;

    Cliente := TWT_NetaClient.Create(Collegamento.DBXConnection);
    try
      IdIntestatario := Cliente.AllineamentoSingolo(IdAziendaEtra, IdServizioEtra);
    finally
      FreeAndNil(Cliente);
    end;
  finally
    Collegamento.Connected := False;
    FreeAndNil(Collegamento);
  end;

  RenderJson(TJSONObject.Create.AddPair('success', TJSONBool.Create(True)).AddPair('ID_INTESTATARIO', TJSONNumber.Create(IdIntestatario)));
end;

function TWTNetaController.XmlPrenotazione: string;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;

  procedure PassaParametro(const Nome: string);
  begin
    ImpostaParametro(Procedura.Params.FindParam(Nome), ParamByName(Nome));
  end;

begin
  Connessione := PrendiConnessione;
  try
    Procedura := CreaStoredProc(Connessione, 'QTA_PRENOTAZIONI_XML_ETRA_VETT');
    try
      Procedura.ParamByName('ID_SESSIONE_WEB').AsLargeInt := IdSessione;

      PassaParametro('PARAM_ID_PRENOTAZIONE');
      PassaParametro('PARAM_STATO_PRENOTAZIONE');
      PassaParametro('PARAM_BELFIORE');
      PassaParametro('PARAM_DALLA_DATA_STAMPA');
      PassaParametro('PARAM_ALLA_DATA_STAMPA');
      PassaParametro('PARAM_MACROCAT');
      PassaParametro('PARAM_CODICE_TRASPORTATORE');
      PassaParametro('PARAM_PRENOTAZIONE_STAMPATA');
      PassaParametro('PARAM_CLASSE_PRENOTAZIONE');

      Procedura.ExecProc;
      try
        Result := Procedura.ParamByName('RESULT').AsString;
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

procedure TWTNetaController.StampaPrenotazione;
var
  Xml: string;
  NomeFileTemporaneo: string;
  NomePerIlBrowser: string;
  Contenuto: TMemoryStream;
  Esito: Integer;
begin
  Xml := XmlPrenotazione;

  if Xml.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.NotFound, 'Nessuna prenotazione da stampare con i criteri indicati.');

  NomeFileTemporaneo := ChangeFileExt(TPath.GetTempFileName, '.pdf');
  try
    Esito := TStreamServer.GeneraPdf(TAppConfig.Instance.Neta.StreamServerUrl, TAppConfig.Instance.Neta.StreamServerUri, Xml, NomeFileTemporaneo);

    if Esito <> 0 then
    begin
      Registro.Error(Format('StampaPrenotazione - StreamServer ha risposto %d', [Esito]), 'WTNetaController');
      raise EMVCException.Create(HTTP_STATUS.BadGateway, Format('Errore StreamServer. Codice %d', [Esito]));
    end;

    NomePerIlBrowser := ChangeFileExt('Prenotazione_' + ParamByName('PARAM_ID_PRENOTAZIONE'), '.pdf');
    Context.Response.CustomHeaders.Values['Content-Disposition'] := Format('attachment; filename="%s"', [NomePerIlBrowser]);

    // Il PDF viene letto in memoria e il temporaneo eliminato subito: con
    // l'invio diretto del file la risposta lo legge dopo la fine
    // dell'azione, e il temporaneo resterebbe sul disco a ogni stampa.
    Contenuto := TMemoryStream.Create;
    try
      Contenuto.LoadFromFile(NomeFileTemporaneo);
      Contenuto.Position := 0;
    except
      on E: Exception do
      begin
        FreeAndNil(Contenuto);
        raise;
      end;
    end;

    ContentType := 'application/pdf';
    SendStream(Contenuto, True, False);
  finally
    if TFile.Exists(NomeFileTemporaneo) then
      TFile.Delete(NomeFileTemporaneo);
  end;
end;

{$ENDIF}

end.
