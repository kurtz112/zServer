// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-06
// ---------------------------------------------------------------------------
unit Files.Signature;

// Controllo del tipo di un file sul contenuto, non solo sull'estensione.
//
// L'estensione la sceglie chi carica il file: un eseguibile rinominato in
// .pdf supera il controllo dell'elenco documenti.tipiAmmessi. Qui si
// confrontano i primi byte con la firma attesa per quell'estensione.
//
// Tre esiti, non due:
// - Conforme: i byte corrispondono all'estensione;
// - NonConforme: i byte dicono un'altra cosa, il file va rifiutato;
// - SenzaFirmaNota: l'estensione non e' in tabella. L'elenco delle estensioni
//   ammesse si allarga dal .json senza un rilascio, e rifiutare quello che
//   non si conosce vorrebbe dire rifiutare i tipi aggiunti dal cliente:
//   decide il chiamante, che oggi accetta e scrive un avviso nel registro.
//
// Per i tipi di testo (.txt, .csv, .xml) non esiste una firma: si controlla
// che il contenuto sia plausibilmente testo, cioe' che nei primi byte non ci
// siano byte nulli ne' la firma di un formato binario noto. Non si pretende
// UTF-8 valido: i .csv salvati da Excel in italiano sono in Windows-1252.
//
// Solo RTL: la unit compila anche su Linux e la puo' usare zFileServer.

interface

uses
  System.SysUtils,
  System.Classes;

type

  TEsitoFirmaFile = (efConforme, efNonConforme, efSenzaFirmaNota);

  TFirmaFile = class
  public
    /// <summary>
    /// Confronta i primi byte del contenuto con la firma attesa per
    /// l'estensione (con o senza punto, maiuscole indifferenti). La posizione
    /// dello stream non cambia.
    /// </summary>
    class function Verifica(const Estensione: string; Contenuto: TStream): TEsitoFirmaFile; static;
  end;

implementation

const
  // Byte letti dall'inizio del file. 8 KB bastano per tutte le firme e per
  // giudicare un testo, senza leggere per intero un file da decine di MB.
  ByteDaLeggere = 8192;

  // La specifica PDF ammette byte prima di %PDF-, e alcuni programmi di
  // scansione ne scrivono: si cerca l'intestazione nel primo kilobyte.
  FinestraIntestazionePdf = 1024;

type
  TCodificaTesto = (ctNessunaIndicazione, ctUtf8, ctUtf16LE, ctUtf16BE);

function IniziaCon(const Buffer: TBytes; const Letti: Integer; const Firma: array of Byte): Boolean;
var
  Indice: Integer;
begin
  Result := False;

  if Letti < Length(Firma) then
    Exit;

  for Indice := 0 to High(Firma) do
    if Buffer[Indice] <> Firma[Indice] then
      Exit;

  Result := True;
end;

function ContieneEntro(const Buffer: TBytes; const Letti, Limite: Integer; const Firma: array of Byte): Boolean;
var
  Inizio: Integer;
  Indice: Integer;
  Ultimo: Integer;
  Uguale: Boolean;
begin
  Result := False;

  Ultimo := Letti - Length(Firma);
  if Ultimo > Limite then
    Ultimo := Limite;

  for Inizio := 0 to Ultimo do
  begin
    Uguale := True;
    for Indice := 0 to High(Firma) do
      if Buffer[Inizio + Indice] <> Firma[Indice] then
      begin
        Uguale := False;
        Break;
      end;

    if Uguale then
      Exit(True);
  end;
end;

function FirmaBinariaNota(const Buffer: TBytes; const Letti: Integer): Boolean;
begin
  Result :=
    IniziaCon(Buffer, Letti, [$4D, $5A]) or                                     // eseguibile Windows (MZ)
    IniziaCon(Buffer, Letti, [$7F, $45, $4C, $46]) or                           // eseguibile Linux (ELF)
    IniziaCon(Buffer, Letti, [$25, $50, $44, $46, $2D]) or                      // PDF
    IniziaCon(Buffer, Letti, [$50, $4B, $03, $04]) or                           // zip e Office recente
    IniziaCon(Buffer, Letti, [$D0, $CF, $11, $E0, $A1, $B1, $1A, $E1]) or       // Office 97-2003
    IniziaCon(Buffer, Letti, [$89, $50, $4E, $47]) or                           // PNG
    IniziaCon(Buffer, Letti, [$FF, $D8, $FF]);                                  // JPEG
end;

function CodificaDaBom(const Buffer: TBytes; const Letti: Integer; out LunghezzaBom: Integer): TCodificaTesto;
begin
  LunghezzaBom := 0;
  Result := ctNessunaIndicazione;

  if IniziaCon(Buffer, Letti, [$EF, $BB, $BF]) then
  begin
    LunghezzaBom := 3;
    Result := ctUtf8;
  end
  else if IniziaCon(Buffer, Letti, [$FF, $FE]) then
  begin
    LunghezzaBom := 2;
    Result := ctUtf16LE;
  end
  else if IniziaCon(Buffer, Letti, [$FE, $FF]) then
  begin
    LunghezzaBom := 2;
    Result := ctUtf16BE;
  end;
end;

function TestoPlausibile(const Buffer: TBytes; const Letti: Integer): Boolean;
var
  LunghezzaBom: Integer;
  Indice: Integer;
begin
  // Un testo UTF-16 (l'esportazione "Testo Unicode" di Excel) e' pieno di
  // byte nulli per costruzione: con il suo BOM si accetta senza contarli.
  if CodificaDaBom(Buffer, Letti, LunghezzaBom) in [ctUtf16LE, ctUtf16BE] then
    Exit(True);

  if FirmaBinariaNota(Buffer, Letti) then
    Exit(False);

  for Indice := LunghezzaBom to Letti - 1 do
    if Buffer[Indice] = 0 then
      Exit(False);

  Result := True;
end;

function PrimoCarattereUtile(const Buffer: TBytes; const Letti: Integer): Char;
var
  Codifica: TCodificaTesto;
  LunghezzaBom: Integer;
  Indice: Integer;
  Carattere: Char;
begin
  Result := #0;
  Codifica := CodificaDaBom(Buffer, Letti, LunghezzaBom);
  Indice := LunghezzaBom;

  while Indice < Letti do
  begin
    case Codifica of
      ctUtf16LE:
        begin
          if Indice + 1 >= Letti then
            Exit;
          Carattere := Char(Buffer[Indice] or (Buffer[Indice + 1] shl 8));
          Inc(Indice, 2);
        end;
      ctUtf16BE:
        begin
          if Indice + 1 >= Letti then
            Exit;
          Carattere := Char((Buffer[Indice] shl 8) or Buffer[Indice + 1]);
          Inc(Indice, 2);
        end;
    else
      Carattere := Char(Buffer[Indice]);
      Inc(Indice);
    end;

    if not CharInSet(Carattere, [' ', #9, #10, #13]) then
      Exit(Carattere);
  end;
end;

function P7mPlausibile(const Buffer: TBytes; const Letti: Integer): Boolean;
var
  Indice: Integer;
begin
  // Busta CMS in DER: comincia con una SEQUENCE (30).
  if IniziaCon(Buffer, Letti, [$30]) then
    Exit(True);

  // Molti .p7m arrivano codificati in Base64, con o senza le righe PEM:
  // la SEQUENCE DER codificata comincia con "MI", di solito "MII".
  Indice := 0;
  while (Indice < Letti) and CharInSet(Char(Buffer[Indice]), [' ', #9, #10, #13]) do
    Inc(Indice);

  Result :=
    ((Letti - Indice >= 2) and (Buffer[Indice] = Ord('M')) and (Buffer[Indice + 1] = Ord('I'))) or
    ((Letti - Indice >= 10) and (TEncoding.ASCII.GetString(Buffer, Indice, 10) = '-----BEGIN'));
end;

{ TFirmaFile }

class function TFirmaFile.Verifica(const Estensione: string; Contenuto: TStream): TEsitoFirmaFile;
var
  Tipo: string;
  Buffer: TBytes;
  Letti: Integer;
  PosizioneIniziale: Int64;
  Conforme: Boolean;
begin
  Tipo := LowerCase(Estensione.Trim);
  if (Tipo <> '') and (Tipo[1] <> '.') then
    Tipo := '.' + Tipo;

  PosizioneIniziale := Contenuto.Position;
  try
    Contenuto.Position := 0;
    SetLength(Buffer, ByteDaLeggere);
    Letti := Contenuto.Read(Buffer, ByteDaLeggere);
  finally
    Contenuto.Position := PosizioneIniziale;
  end;

  if Tipo = '.pdf' then
    Conforme := ContieneEntro(Buffer, Letti, FinestraIntestazionePdf, [$25, $50, $44, $46, $2D])
  else if Tipo = '.p7m' then
    Conforme := P7mPlausibile(Buffer, Letti)
  else if (Tipo = '.jpg') or (Tipo = '.jpeg') then
    Conforme := IniziaCon(Buffer, Letti, [$FF, $D8, $FF])
  else if Tipo = '.png' then
    Conforme := IniziaCon(Buffer, Letti, [$89, $50, $4E, $47, $0D, $0A, $1A, $0A])
  else if (Tipo = '.tif') or (Tipo = '.tiff') then
    Conforme := IniziaCon(Buffer, Letti, [$49, $49, $2A, $00]) or IniziaCon(Buffer, Letti, [$4D, $4D, $00, $2A])
  else if (Tipo = '.doc') or (Tipo = '.xls') then
    Conforme := IniziaCon(Buffer, Letti, [$D0, $CF, $11, $E0, $A1, $B1, $1A, $E1])
  else if (Tipo = '.docx') or (Tipo = '.xlsx') or (Tipo = '.odt') or (Tipo = '.ods') or (Tipo = '.zip') then
    // Tutti archivi zip: non si apre l'archivio per distinguere un .docx da
    // un .xlsx, l'errore che si vuole fermare e' un file che zip non e'.
    Conforme := IniziaCon(Buffer, Letti, [$50, $4B, $03, $04]) or IniziaCon(Buffer, Letti, [$50, $4B, $05, $06])
  else if (Tipo = '.txt') or (Tipo = '.csv') then
    Conforme := TestoPlausibile(Buffer, Letti)
  else if Tipo = '.xml' then
    Conforme := TestoPlausibile(Buffer, Letti) and (PrimoCarattereUtile(Buffer, Letti) = '<')
  else
    Exit(efSenzaFirmaNota);

  if Conforme then
    Result := efConforme
  else
    Result := efNonConforme;
end;

end.
