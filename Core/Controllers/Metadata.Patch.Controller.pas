unit Metadata.Patch.Controller;

// ---------------------------------------------------------------------------
// TMetadataPatchController: aggiornamento parziale (PATCH) dei metadati della
// form dal menu di design di zz-form e zz-data-grid (GestyWeb).
//
//   PATCH /api/data/($idDataset)/metadata/fields    corpo: array di FieldPatch
//   PATCH /api/data/($idDataset)/metadata/settings  corpo: FormSettingsPatch
//
// Il contratto JSON del client resta quello di sempre; cambia dove finiscono
// i valori, perche' il modello di BaseWeb non ha piu' CARD_VISIBLE, COL_SPAN,
// LINEBREAK e CARD_INDEX su BASE_WEB_DATASETS_FIELDS:
//   caption, readOnly, required            -> BASE_WEB_DATASETS_FIELDS
//   visible, colSpan, lineBreak, cardIndex -> BASE_WEB_FORM_FIELDS
//   colCount, labelLocation, showColon,
//   layout, formWidth, formHeight          -> BASE_WEB_DATASETS
// Nessuna SQL: ogni riga passa dalle _LOAD/_SAVE del pacchetto attraverso
// TMetadataTransfer.SalvaUnendo, che legge la riga, vi sovrappone le sole
// proprieta' presenti e la riscrive intera (semantica di aggiornamento
// parziale senza UPDATE dinamici). BASE_WEB_DATASETS_META si rigenera da
// sola con i trigger.
// ---------------------------------------------------------------------------

interface

uses
  MVCFramework,
  MVCFramework.Commons,
  System.SysUtils,
  System.JSON,
  System.Classes,
  Base.Controller;

type

  [MVCPath('/api/data')]
  TMetadataPatchController = class(TBaseController)
  protected
    // Le due PATCH richiedono l'autorizzazione BASE_WEB_METADATI
    procedure OnBeforeAction(aContext: TWebContext; const aActionName: string; var AHandled: Boolean); override;
  public
    [MVCPath('/($idDataset)/metadata/fields')]
    [MVCHTTPMethod([httpPATCH])]
    procedure PatchFields(const idDataset: string);

    [MVCPath('/($idDataset)/metadata/settings')]
    [MVCHTTPMethod([httpPATCH])]
    procedure PatchSettings(const idDataset: string);
  end;

implementation

uses
  FireDAC.Comp.Client,
  Metadata.Editor.Controller,
  Metadata.Transfer.Service;

// Stessa autorizzazione dell'editor (BASE_WEB_METADATI): le due rotte PATCH
// modificano le stesse tabelle e prima di questo controllo erano aperte a
// qualunque utente autenticato.
procedure TMetadataPatchController.OnBeforeAction(aContext: TWebContext; const aActionName: string; var AHandled: Boolean);
begin
  RichiediAutorizzazioneMetadati;
  inherited;
end;

// Appoggio

function CorpoArray(const Contesto: TWebContext): TJSONArray;
var
  Valore: TJSONValue;
begin
  Valore := TJSONObject.ParseJSONValue(Contesto.Request.Body);
  if not(Valore is TJSONArray) then
  begin
    Valore.Free;
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'Corpo della richiesta non valido: atteso un array JSON.');
  end;
  Result := TJSONArray(Valore);
end;

// Copia nel corpo di destinazione la proprieta' del client, se presente e non
// nulla, con il nome della colonna di BaseWeb. E' il cuore della semantica
// PATCH: cio' che il client non manda non viene toccato.
procedure Travasa(Origine: TJSONObject; const NomeClient: string; Destinazione: TJSONObject; const Colonna: string);
var
  Valore: TJSONValue;
begin
  Valore := Origine.GetValue(NomeClient);
  if (Valore <> nil) and not(Valore is TJSONNull) then
    Destinazione.AddPair(Colonna, Valore.Clone as TJSONValue);
end;

// PATCH /api/data/($idDataset)/metadata/fields
// Corpo: [ { "dataField":"NOME", "caption":"Nominativo", "visible":true,
//            "readOnly":false, "required":true, "colSpan":2,
//            "lineBreak":false, "cardIndex":10 }, ... ]
// Risposta: 200 { "updated": N } con N = campi effettivamente toccati

procedure TMetadataPatchController.PatchFields(const idDataset: string);
var
  Voci: TJSONArray;
  Voce: TJSONValue;
  Patch: TJSONObject;
  CorpoCampo, CorpoForm: TJSONObject;
  NomeCampo: string;
  Aggiornati: Integer;
  Connessione: TFDConnection;
  Creato: Boolean;
begin
  if idDataset.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'idDataset obbligatorio');

  Voci := CorpoArray(Context);
  try
    Aggiornati := 0;
    Connessione := PrendiConnessione;
    try
      ApriTransazione(Connessione);
      try
        for Voce in Voci do
        begin
          if not(Voce is TJSONObject) then
            Continue;
          Patch := TJSONObject(Voce);
          NomeCampo := Trim(Patch.GetValue<string>('dataField', ''));
          if NomeCampo.IsEmpty then
            Continue;

          CorpoCampo := TJSONObject.Create;
          CorpoForm := TJSONObject.Create;
          try
            Travasa(Patch, 'caption', CorpoCampo, 'CAPTION');
            Travasa(Patch, 'readOnly', CorpoCampo, 'READONLY');
            Travasa(Patch, 'required', CorpoCampo, 'REQUIRED');
            Travasa(Patch, 'visible', CorpoForm, 'VISIBLE');
            Travasa(Patch, 'colSpan', CorpoForm, 'COL_SPAN');
            Travasa(Patch, 'lineBreak', CorpoForm, 'LINEBREAK');
            Travasa(Patch, 'cardIndex', CorpoForm, 'SORT_ORDER');

            if (CorpoCampo.Count = 0) and (CorpoForm.Count = 0) then
              Continue;

            // il campo deve esistere: la posizione nella form si puo' invece creare
            if TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('fields'), [idDataset, NomeCampo]) = nil then
              Continue;

            if CorpoCampo.Count > 0 then
              TMetadataTransfer.SalvaUnendo(Connessione, TMetadataTransfer.Tabella('fields'), [idDataset, NomeCampo], CorpoCampo, Creato);
            if CorpoForm.Count > 0 then
              TMetadataTransfer.SalvaUnendo(Connessione, TMetadataTransfer.Tabella('formFields'), [idDataset, NomeCampo], CorpoForm, Creato);
            Inc(Aggiornati);
          finally
            CorpoForm.Free;
            CorpoCampo.Free;
          end;
        end;
        Conferma(Connessione);
      except
        Annulla(Connessione);
        raise;
      end;
    finally
      RilasciaConnessione(Connessione);
    end;

    RenderJson(TJSONObject.Create.AddPair('updated', TJSONNumber.Create(Aggiornati)));
  finally
    Voci.Free;
  end;
end;

// PATCH /api/data/($idDataset)/metadata/settings
// Corpo: { "colCount": 4, "labelLocation": "left", "showColon": true,
//          "layout": "flat", "formWidth": 800, "formHeight": 600 } (tutte facoltative)
// Risposta: 200 { "updated": true } oppure { "updated": false, "message": ... }

procedure TMetadataPatchController.PatchSettings(const idDataset: string);
var
  Patch: TJSONObject;
  Corpo: TJSONObject;
  Connessione: TFDConnection;
  Creato: Boolean;
begin
  if idDataset.Trim.IsEmpty then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'idDataset obbligatorio');

  Patch := CorpoJson;
  try
    Corpo := TJSONObject.Create;
    try
      Travasa(Patch, 'colCount', Corpo, 'FORM_COL_COUNT');
      Travasa(Patch, 'labelLocation', Corpo, 'FORM_LABEL_LOC');
      Travasa(Patch, 'showColon', Corpo, 'FORM_LABEL_COLON');
      Travasa(Patch, 'layout', Corpo, 'FORM_LAYOUT');
      Travasa(Patch, 'formWidth', Corpo, 'FORM_WIDTH');
      Travasa(Patch, 'formHeight', Corpo, 'FORM_HEIGHT');

      if Corpo.Count = 0 then
      begin
        RenderJson(TJSONObject.Create.AddPair('updated', TJSONBool.Create(False)));
        Exit;
      end;

      Connessione := PrendiConnessione;
      try
        // un dataset che non esiste non si crea da una PATCH
        if TMetadataTransfer.CaricaRiga(Connessione, TMetadataTransfer.Tabella('datasets'), [idDataset]) = nil then
        begin
          RenderJson(TJSONObject.Create.AddPair('updated', TJSONBool.Create(False)).AddPair('message', 'Dataset non trovato: ' + idDataset));
          Exit;
        end;

        ApriTransazione(Connessione);
        try
          TMetadataTransfer.SalvaUnendo(Connessione, TMetadataTransfer.Tabella('datasets'), [idDataset], Corpo, Creato);
          Conferma(Connessione);
        except
          Annulla(Connessione);
          raise;
        end;
      finally
        RilasciaConnessione(Connessione);
      end;

      RenderJson(TJSONObject.Create.AddPair('updated', TJSONBool.Create(True)));
    finally
      Corpo.Free;
    end;
  finally
    Patch.Free;
  end;
end;

end.
