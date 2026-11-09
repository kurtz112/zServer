// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit Gesty.Questionari.Controller;

// Portato da Moduli\Gesty\dmQuestionari.pas (classe TQuestionari, framework
// TRoute).
//
// Due operazioni:
//
// - lettura del questionario da compilare, identificato da un gettone
// (IDENTIFICATIVO, un GUID): titolo, sezioni, voci di ogni sezione e
// risposte possibili di ogni voce;
// - salvataggio delle risposte, che arrivano come un JSON con la stessa
// forma restituita dalla lettura.
//
// Due differenze rispetto al sorgente:
//
// 1. La gerarchia sezioni/voci/risposte era ottenuta con due TDataSource e
// il legame padre-figlio di FireDAC, con un solo giro di serializzazione
// annidata. Qui le tre interrogazioni si fanno in sequenza e il JSON si
// compone a mano: con i componenti posati sul DataModule due richieste
// contemporanee sullo stesso questionario si sarebbero pestate i piedi.
//
// 2. Il sorgente leggeva il corpo della richiesta come ASCII
// (TEncoding.ASCII.GetBytes) e ne salvava una copia su file accanto
// all'eseguibile a ogni chiamata. Con ASCII le lettere accentate delle
// risposte aperte diventavano '?': qui il corpo si legge come UTF-8, e la
// copia su file non c'e' piu' — il JSON viene comunque conservato dalla
// procedura, che lo riceve nel parametro JSON.

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

  [MVCPath('/api/gesty/questionari')]
  [MVCDoc('Questionari di gradimento: lettura e salvataggio delle risposte')]
  TQuestionariController = class(TBaseController)
  private
    function LeggiSezioni(Connessione: TFDConnection; const Identificativo: string): TJSONArray;
    function LeggiVoci(Connessione: TFDConnection; const IdSezione: Int64): TJSONArray;
    function LeggiRispostePossibili(Connessione: TFDConnection; const IdVoce: Int64): TJSONArray;
    procedure SalvaVoci(Connessione: TFDConnection; const IdRisposta: Int64; Sezioni: TJSONArray);
  public
    [MVCPath('/questionario')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Restituisce il questionario da compilare')]
    procedure GetQuestionario;

    [MVCPath('/risposte')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Salva le risposte del questionario')]
    procedure SetRisposte;
  end;

implementation

uses
  FiredacHelper,
  Json.Values;

const
  SQL_QUESTIONARIO = 'SELECT * FROM QUESTIONARI_GET(:IDENTIFICATIVO) ORDER BY QUESTIONARI_GET.TITOLO_QUESTIONARIO';
  SQL_SEZIONI = 'SELECT * FROM QUESTIONARI_GET_SEZIONI(:IDENTIFICATIVO) ORDER BY QUESTIONARI_GET_SEZIONI.ORDINE';
  SQL_VOCI = 'SELECT * FROM QUESTIONARI_GET_SEZIONI_VOCI(:ID_SEZIONE) ORDER BY QUESTIONARI_GET_SEZIONI_VOCI.ORDINE';
  SQL_VOCI_ITEMS = 'SELECT * FROM QUESTIONARI_GET_SEZ_VOCI_ITEMS(:ID_VOCE)';

{ TQuestionariController }

function TQuestionariController.LeggiRispostePossibili(Connessione: TFDConnection; const IdVoce: Int64): TJSONArray;
var
  Elenco: TFDQuery;
begin
  Elenco := CreaQuery(Connessione, SQL_VOCI_ITEMS);
  try
    Elenco.ParamByName('ID_VOCE').AsLargeInt := IdVoce;
    Elenco.Open;
    try
      Result := Elenco.DataSetToJSON(True);
    finally
      Elenco.Close;
    end;
  finally
    FreeAndNil(Elenco);
  end;
end;

function TQuestionariController.LeggiVoci(Connessione: TFDConnection; const IdSezione: Int64): TJSONArray;
var
  Elenco: TFDQuery;
  Voce: TJSONObject;
  i: Integer;
begin
  Elenco := CreaQuery(Connessione, SQL_VOCI);
  try
    Elenco.ParamByName('ID_SEZIONE').AsLargeInt := IdSezione;
    Elenco.Open;
    try
      Result := Elenco.DataSetToJSON(True);
    finally
      Elenco.Close;
    end;
  finally
    FreeAndNil(Elenco);
  end;

  try
    for i := 0 to Result.Count - 1 do
    begin
      Voce := Result.Items[i] as TJSONObject;
      Voce.AddPair('VociItems', LeggiRispostePossibili(Connessione, JsonInt64(Voce, 'ID_VOCE')));
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

function TQuestionariController.LeggiSezioni(Connessione: TFDConnection; const Identificativo: string): TJSONArray;
var
  Elenco: TFDQuery;
  Sezione: TJSONObject;
  i: Integer;
begin
  Elenco := CreaQuery(Connessione, SQL_SEZIONI);
  try
    Elenco.ParamByName('IDENTIFICATIVO').AsString := Identificativo;
    Elenco.Open;
    try
      Result := Elenco.DataSetToJSON(True);
    finally
      Elenco.Close;
    end;
  finally
    FreeAndNil(Elenco);
  end;

  try
    for i := 0 to Result.Count - 1 do
    begin
      Sezione := Result.Items[i] as TJSONObject;
      Sezione.AddPair('Voci', LeggiVoci(Connessione, JsonInt64(Sezione, 'ID_SEZIONE')));
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Result);
      raise;
    end;
  end;
end;

procedure TQuestionariController.GetQuestionario;
var
  Connessione: TFDConnection;
  Questionario: TFDQuery;
  Identificativo: string;
  Risposta: TJSONObject;
begin
  Identificativo := ParamObbligatorio('IDENTIFICATIVO');

  Registro.Info(Format('GetQuestionario - gettone %s', [Identificativo]), 'QuestionariController');

  Risposta := TJSONObject.Create;
  try
    Connessione := PrendiConnessione;
    try
      Questionario := CreaQuery(Connessione, SQL_QUESTIONARIO);
      try
        Questionario.ParamByName('IDENTIFICATIVO').AsString := Identificativo;
        Questionario.Open;
        try
          if Questionario.IsEmpty then
            raise EMVCException.Create(HTTP_STATUS.NotFound, 'Questionario non trovato o non piu'' disponibile.');

          Risposta.AddPair('Questionario', Questionario.DataSetToJSON(True));
        finally
          Questionario.Close;
        end;
      finally
        FreeAndNil(Questionario);
      end;

      Risposta.AddPair('Sezioni', LeggiSezioni(Connessione, Identificativo));
    finally
      RilasciaConnessione(Connessione);
    end;
  except
    on E: Exception do
    begin
      FreeAndNil(Risposta);
      raise;
    end;
  end;

  RenderJson(Risposta);
end;

// Una voce puo' essere valutata con un punteggio (VALUTAZIONE) oppure con
// una o piu' risposte fra quelle possibili (VociItems, ciascuna con CHECKED):
// e' la distinzione che fa il sorgente d'origine, e le due forme non
// convivono sulla stessa voce.
procedure TQuestionariController.SalvaVoci(Connessione: TFDConnection; const IdRisposta: Int64; Sezioni: TJSONArray);
var
  Procedura: TFDStoredProc;
  Sezione: TJSONObject;
  Voce: TJSONObject;
  Item: TJSONObject;
  Voci: TJSONArray;
  Items: TJSONArray;
  ValoreSezione: TJSONValue;
  ValoreVoce: TJSONValue;
  ValoreItem: TJSONValue;
  Valutazione: Integer;
  IdDocente: Int64;
begin
  Procedura := CreaStoredProc(Connessione, 'QUESTIONARI_RISPOSTE_SAVE_VOCE');
  try
    Procedura.ParamByName('ID_RISPOSTA').AsLargeInt := IdRisposta;

    for ValoreSezione in Sezioni do
    begin
      Sezione := ValoreSezione as TJSONObject;

      Procedura.ParamByName('ID_QUESTIONARIO').AsLargeInt := JsonInt64(Sezione, 'ID_QUESTIONARIO');
      Procedura.ParamByName('ID_SEZIONE').AsLargeInt := JsonInt64(Sezione, 'ID_SEZIONE');

      IdDocente := JsonInt64(Sezione, 'ID_DOCENTE', -1);

      if IdDocente > 0 then
        Procedura.ParamByName('ID_DOCENTE').AsLargeInt := IdDocente
      else
        Procedura.ParamByName('ID_DOCENTE').Clear;

      if not Sezione.TryGetValue<TJSONArray>('Voci', Voci) then
        Continue;

      for ValoreVoce in Voci do
      begin
        Voce := ValoreVoce as TJSONObject;

        Procedura.ParamByName('ID_VOCE').AsLargeInt := JsonInt64(Voce, 'ID_VOCE');

        if Voce.TryGetValue<Integer>('VALUTAZIONE', Valutazione) then
        begin
          Procedura.ParamByName('RISPOSTA').Clear;
          Procedura.ParamByName('VALORE').AsInteger := Valutazione;
          Procedura.ExecProc;
          Continue;
        end;

        if not Voce.TryGetValue<TJSONArray>('VociItems', Items) then
          Continue;

        for ValoreItem in Items do
        begin
          Item := ValoreItem as TJSONObject;

          Procedura.ParamByName('RISPOSTA').AsString := JsonStr(Item, 'RISPOSTA');

          if JsonBool(Item, 'CHECKED') then
            Procedura.ParamByName('VALORE').AsInteger := 1
          else
            Procedura.ParamByName('VALORE').AsInteger := 0;

          Procedura.ExecProc;
        end;
      end;
    end;
  finally
    FreeAndNil(Procedura);
  end;
end;

procedure TQuestionariController.SetRisposte;
var
  Connessione: TFDConnection;
  Procedura: TFDStoredProc;
  Corpo: TJSONObject;
  Questionario: TJSONObject;
  Contenitore: TJSONObject;
  Sezioni: TJSONArray;
  Identificativo: string;
  Suggerimenti: string;
  IdRisposta: Int64;
  TestoOriginale: string;
begin
  TestoOriginale := Context.Request.Body;

  Corpo := CorpoJson;
  try
    Identificativo := JsonStr(Corpo, 'IDENTIFICATIVO');

    if Identificativo.Trim.IsEmpty then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Identificativo del questionario non indicato.');

    if not Corpo.TryGetValue<TJSONObject>('QUESTIONARIO', Questionario) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Struttura della risposta non valida: manca QUESTIONARIO.');

    Suggerimenti := JsonStr(Questionario, 'SUGGERIMENTI');

    if not Corpo.TryGetValue<TJSONObject>('SEZIONI', Contenitore) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Struttura della risposta non valida: manca SEZIONI.');

    if not Contenitore.TryGetValue<TJSONArray>('data', Sezioni) then
      raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Struttura della risposta non valida: manca SEZIONI.data.');

    Registro.Info(Format('SetRisposte - gettone %s, %d sezioni', [Identificativo, Sezioni.Count]), 'QuestionariController');

    Connessione := PrendiConnessione;
    try
      // Prima transazione: la testata della risposta. Il sorgente d'origine
      // la confermava prima di salvare le voci, e la sequenza si mantiene
      // perche' la procedura delle voci pretende la testata gia' registrata.
      ApriTransazione(Connessione);
      try
        Procedura := CreaStoredProc(Connessione, 'QUESTIONARI_RISPOSTE_SAVE');
        try
          Procedura.ParamByName('IDENTIFICATIVO').AsString := Identificativo;
          ImpostaParametro(Procedura.Params.FindParam('SUGGERIMENTI'), Suggerimenti);
          Procedura.ParamByName('JSON').AsString := TestoOriginale;
          Procedura.ExecProc;
          try
            IdRisposta := Procedura.ParamByName('ID_RISPOSTA').AsLargeInt;
          finally
            Procedura.Close;
          end;
        finally
          FreeAndNil(Procedura);
        end;

        Conferma(Connessione);
      except
        on E: Exception do
        begin
          Annulla(Connessione);
          raise;
        end;
      end;

      // ID_RISPOSTA a -1 significa che la procedura ha rifiutato il
      // salvataggio (gettone gia' usato, questionario chiuso): non e' un
      // errore, e le voci non vanno salvate.
      if IdRisposta <= 0 then
      begin
        Registro.Warn(Format('SetRisposte - gettone %s rifiutato dalla procedura', [Identificativo]), 'QuestionariController');
        RenderEsito(True);
        Exit;
      end;

      // Seconda transazione: le voci e il completamento.
      ApriTransazione(Connessione);
      try
        SalvaVoci(Connessione, IdRisposta, Sezioni);

        Procedura := CreaStoredProc(Connessione, 'QUESTIONARI_RISPOSTE_SAVE_DONE');
        try
          Procedura.ParamByName('ID_RISPOSTA').AsLargeInt := IdRisposta;
          Procedura.ExecProc;
        finally
          FreeAndNil(Procedura);
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
    FreeAndNil(Corpo);
  end;

  RenderEsito(True);
end;

end.
