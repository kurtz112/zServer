// ---------------------------------------------------------------------------
// Copyright (c) 2026 Softline S.r.l. - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-11-07
// ---------------------------------------------------------------------------
unit WT.Firma.Gestore;

// Parti di WT dei gestori FIRMA e FIRMA-STATO della coda (Firma.Gestore),
// dichiarate per il profilo WT. Servono oggi alla firma con valore legale
// delle liberatorie e dei documenti di cessione dei centri del riuso, ma non
// sanno niente dei centri del riuso: lavorano su qualunque registrazione di
// OBJ_FILES_FIRMA_REGISTRAZIONI.
//
// - Firmatari: quelli salvati con la registrazione
//   (OBJ_FILES_FIRMA_FIRMATARI, cioe' OBJ_FILES_FIRMA_REGISTRAZIONI_FIRMATARI),
//   scritti da chi chiede la firma (in WT la procedura del database
//   CDR_BENI_DOCUMENTO_FIRMA_RICHIEDI). La tabella non ha il segnaposto: lo
//   da' il parametro SEGNAPOSTO del fornitore nella configurazione del
//   tenant (OBJ_FILES_FIRMA_CONFIG_PARAMETRI), vuoto se manca. Per
//   eSignAnyWhere un segnaposto vuoto vuol dire "tutti i campi firma del
//   documento" per il firmatario con codice via SMS (OTP).
// - Percorso del file: funzione OBJ_FILES_GET_FULL_FILE_NAME, la stessa che
//   usa WEB_OBJ_FILES_GET_FULL_FILE_NAME dopo i controlli del perimetro. Qui
//   il perimetro non serve: la registrazione l'ha gia' scelta il database.
//
// Cosa succede dopo la firma (stato della liberatoria in CDR_BENI_DOCUMENTI)
// lo fa il trigger OBJ_FILES_FIRMA_REGISTRAZIONI_CDR_AU, non zServer.

interface

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  zDocumentale.Firma.Types,
  Firma.Gestore;

const
  CodiceProfiloWT = 'WT';
  ParametroSegnaposto = 'SEGNAPOSTO';

function Segnaposto(Connessione: TFDConnection; const Registrazione: TFirmaRegistrazione): string;
var
  Query: TFDQuery;
begin
  Result := '';
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text :=
      'SELECT OBJ_FILES_FIRMA_CONFIG_PARAMETRI.VALORE FROM OBJ_FILES_FIRMA_CONFIG_PARAMETRI ' +
      'WHERE OBJ_FILES_FIRMA_CONFIG_PARAMETRI.ID_TENANT = :ID_TENANT AND ' +
      'OBJ_FILES_FIRMA_CONFIG_PARAMETRI.FORNITORE = :FORNITORE AND ' +
      'UPPER(OBJ_FILES_FIRMA_CONFIG_PARAMETRI.CHIAVE) = :CHIAVE';
    Query.ParamByName('ID_TENANT').AsLargeInt := Registrazione.IdTenant;
    Query.ParamByName('FORNITORE').AsString := Registrazione.Fornitore;
    Query.ParamByName('CHIAVE').AsString := ParametroSegnaposto;
    Query.Open;

    if not Query.IsEmpty then
      Result := Query.Fields[0].AsString.Trim;
  finally
    FreeAndNil(Query);
  end;
end;

function FirmatariWT(Connessione: TFDConnection; const Registrazione: TFirmaRegistrazione): TArray<TzFirmaFirmatario>;
var
  Query: TFDQuery;
  Firmatario: TzFirmaFirmatario;
  SegnapostoFornitore: string;
begin
  Result := nil;
  SegnapostoFornitore := Segnaposto(Connessione, Registrazione);

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connessione;
    Query.SQL.Text :=
      'SELECT OBJ_FILES_FIRMA_FIRMATARI.RUOLO, OBJ_FILES_FIRMA_FIRMATARI.COGNOME, ' +
      'OBJ_FILES_FIRMA_FIRMATARI.NOME, OBJ_FILES_FIRMA_FIRMATARI.EMAIL, ' +
      'OBJ_FILES_FIRMA_FIRMATARI.TELEFONO, OBJ_FILES_FIRMA_FIRMATARI.IDENTIFICATIVO_ESTERNO ' +
      'FROM OBJ_FILES_FIRMA_FIRMATARI(:ID_FIRMA_REGISTRAZIONE)';
    Query.ParamByName('ID_FIRMA_REGISTRAZIONE').AsLargeInt := Registrazione.IdFirmaRegistrazione;
    Query.Open;

    while not Query.Eof do
    begin
      Firmatario.Clear;
      Firmatario.Ruolo := Query.FieldByName('RUOLO').AsString;
      Firmatario.Cognome := Query.FieldByName('COGNOME').AsString;
      Firmatario.Nome := Query.FieldByName('NOME').AsString;
      Firmatario.Email := Query.FieldByName('EMAIL').AsString;
      Firmatario.Telefono := Query.FieldByName('TELEFONO').AsString;
      Firmatario.IdentificativoFirmaRemota := Query.FieldByName('IDENTIFICATIVO_ESTERNO').AsString;
      Firmatario.Placeholder := SegnapostoFornitore;
      Result := Result + [Firmatario];
      Query.Next;
    end;
  finally
    FreeAndNil(Query);
  end;
end;

function PercorsoFileWT(Connessione: TFDConnection; const IdObjectFile: Int64): string;
begin
  Result := FirmaValoreTesto(Connessione,
    'SELECT OBJ_FILES_GET_FULL_FILE_NAME(:ID_OBJECT_FILE) FROM RDB$DATABASE',
    'ID_OBJECT_FILE', IdObjectFile);
end;

procedure RegistraProdotto;
var
  Prodotto: TFirmaProdotto;
begin
  Prodotto.LeggiFirmatari := FirmatariWT;
  Prodotto.PercorsoFile := PercorsoFileWT;
  TFirmaProdotti.Registra(CodiceProfiloWT, Prodotto);
end;

initialization

RegistraProdotto;

end.
