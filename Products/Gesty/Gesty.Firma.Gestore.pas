// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit Gesty.Firma.Gestore;

// Parti di Gesty dei gestori FIRMA e FIRMA-STATO della coda.
//
// Fino al 2026-10-08 questa unit conteneva tutto il gestore. Il 2026-11-07 la
// sequenza della coda (invio, ricerca per contrassegno, controllo dello
// stato, versioni FIR e RIC, registro in transazione autonoma) e' passata
// senza cambiamenti nella unit comune Firma.Gestore, usata anche da WT per
// le liberatorie dei centri del riuso. Qui restano le due cose proprie di
// Gesty, dichiarate a Firma.Gestore per il profilo GESTY:
// - i firmatari, ricavati dal tipo di documento della registrazione
//   (OBJ_FILES_FIRMA_REGISTRAZIONI.TIPO_DOCUMENTO, colonna che c'e' solo in
//   Gesty): per i contratti OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI, per gli
//   altri oggetti OBJ_FILES_FIRMA_FIRMATARI_GET;
// - il percorso del file, dalla procedura GET_FULL_FILE_NAME.
// Le costanti della coda restano anche qui, per chi le usava da questa unit
// (Gesty.Firma.Controller).

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  zDocumentale.Firma.Types,
  Firma.Gestore;

const
  TipoCodaFirma = Firma.Gestore.TipoCodaFirma;
  TipoCodaFirmaStato = Firma.Gestore.TipoCodaFirmaStato;
  PrefissoContrassegno = Firma.Gestore.PrefissoContrassegno;
  PrefissoEsitoFirma = Firma.Gestore.PrefissoEsitoFirma;

/// <summary>
/// True per i tipi di documento dei contratti (CON incarico, CDM incarico
/// di massima): i loro firmatari vengono da OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI,
/// che aggiunge il docente con firma OTP.
/// </summary>
function TipoContratto(const TipoDocumento: string): Boolean;

/// <summary>
/// Firmatari di una registrazione, con segnaposto e identificativo di firma
/// remota, letti con le procedure di Gesty: per i contratti
/// OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI (vuole la registrazione in stato A),
/// per gli altri oggetti OBJ_FILES_FIRMA_FIRMATARI_GET. Non si rileggono da
/// OBJ_FILES_FIRMA_REGISTRAZIONI_FIRMATARI, che non salva segnaposti ne'
/// identificativi: ricostruiti da li' diventerebbero tutti OTP.
/// </summary>
function LeggiFirmatari(Connessione: TFDConnection; const IdFirmaRegistrazione, Oid: Int64; const TipoDocumento: string): TArray<TzFirmaFirmatario>;

implementation

uses
  Data.DB,
  FireDAC.Stan.Param;

const
  CodiceProfiloGesty = 'GESTY';

function TipoContratto(const TipoDocumento: string): Boolean;
begin
  Result := SameText(TipoDocumento, 'CON') or SameText(TipoDocumento, 'CDM');
end;

function CreaQuery(Connessione: TFDConnection; const Testo: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := Connessione;
  Result.SQL.Text := Testo;
end;

function LeggiFirmatari(Connessione: TFDConnection; const IdFirmaRegistrazione, Oid: Int64; const TipoDocumento: string): TArray<TzFirmaFirmatario>;
var
  Query: TFDQuery;
  Firmatario: TzFirmaFirmatario;
begin
  Result := nil;

  if TipoContratto(TipoDocumento) then
  begin
    Query := CreaQuery(Connessione,
      'SELECT OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.RUOLO, OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.PLACEHOLDER, ' +
      'OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.COGNOME, OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.NOME, ' +
      'OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.EMAIL, OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.TELEFONO, ' +
      'OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI.IDENTIFICATIVO_ESTERNO ' +
      'FROM OBJ_FILES_FIRMA_CONTRATTI_FIRMATARI(:ID_FIRMA_REGISTRAZIONE)');
    Query.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := IdFirmaRegistrazione;
  end
  else
  begin
    Query := CreaQuery(Connessione,
      'SELECT OBJ_FILES_FIRMA_FIRMATARI_GET.RUOLO, OBJ_FILES_FIRMA_FIRMATARI_GET.PLACEHOLDER, ' +
      'OBJ_FILES_FIRMA_FIRMATARI_GET.COGNOME, OBJ_FILES_FIRMA_FIRMATARI_GET.NOME, ' +
      'OBJ_FILES_FIRMA_FIRMATARI_GET.EMAIL, OBJ_FILES_FIRMA_FIRMATARI_GET.TELEFONO, ' +
      'OBJ_FILES_FIRMA_FIRMATARI_GET.IDENTIFICATIVO_ESTERNO ' +
      'FROM OBJ_FILES_FIRMA_FIRMATARI_GET(:OID)');
    Query.ParamByName('OID').AsLargeInt := Oid;
  end;

  try
    Query.Open;

    while not Query.Eof do
    begin
      Firmatario.Clear;
      Firmatario.Ruolo := Query.FieldByName('RUOLO').AsString;
      Firmatario.Placeholder := Query.FieldByName('PLACEHOLDER').AsString;
      Firmatario.Cognome := Query.FieldByName('COGNOME').AsString;
      Firmatario.Nome := Query.FieldByName('NOME').AsString;
      Firmatario.Email := Query.FieldByName('EMAIL').AsString;
      Firmatario.Telefono := Query.FieldByName('TELEFONO').AsString;
      Firmatario.IdentificativoFirmaRemota := Query.FieldByName('IDENTIFICATIVO_ESTERNO').AsString;
      Result := Result + [Firmatario];
      Query.Next;
    end;
  finally
    FreeAndNil(Query);
  end;
end;

function FirmatariGesty(Connessione: TFDConnection; const Registrazione: TFirmaRegistrazione): TArray<TzFirmaFirmatario>;
var
  TipoDocumento: string;
begin
  TipoDocumento := FirmaValoreTesto(Connessione,
    'SELECT OBJ_FILES_FIRMA_REGISTRAZIONI.TIPO_DOCUMENTO FROM OBJ_FILES_FIRMA_REGISTRAZIONI ' +
    'WHERE OBJ_FILES_FIRMA_REGISTRAZIONI.ID_FIRMA_REGISTRAZIONE = :ID_FIRMA_REGISTRAZIONE',
    'ID_FIRMA_REGISTRAZIONE', Registrazione.IdFirmaRegistrazione);

  Result := LeggiFirmatari(Connessione, Registrazione.IdFirmaRegistrazione, Registrazione.Oid, TipoDocumento);
end;

function PercorsoFileGesty(Connessione: TFDConnection; const IdObjectFile: Int64): string;
begin
  Result := FirmaValoreTesto(Connessione,
    'SELECT GET_FULL_FILE_NAME.FULL_FILE_NAME FROM GET_FULL_FILE_NAME(:ID_OBJECT_FILE)',
    'ID_OBJECT_FILE', IdObjectFile);
end;

procedure RegistraProdotto;
var
  Prodotto: TFirmaProdotto;
begin
  Prodotto.LeggiFirmatari := FirmatariGesty;
  Prodotto.PercorsoFile := PercorsoFileGesty;
  TFirmaProdotti.Registra(CodiceProfiloGesty, Prodotto);
end;

initialization

RegistraProdotto;

end.
