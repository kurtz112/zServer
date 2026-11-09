unit FirebirdExceptions;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  FireDAC.Phys.IBWrapper,
  FireDAC.Phys.IBCli;

function TranslateFirebirdException(E: EIBNativeException; const Detailed: boolean): string;
// Zebro 04.11.2026: ripara il testo di un errore di Firebird arrivato con la codifica doppia.
function RiparaCodificaMessaggio(const Testo: string): string;

implementation

// Zebro 04.11.2026: il testo dei messaggi delle eccezioni di Firebird (EXCEPTION E 'testo' nelle
// procedure) arriva a FireDAC con i byte UTF-8 grezzi e FireDAC li legge come Windows-1252: una
// "a" accentata esce come due caratteri ("A" con la tilde e uno spazio non divisibile). Si rifa'
// il percorso inverso: si riportano i caratteri ai byte di Windows-1252 e si leggono come UTF-8.
// Se il testo e' gia' corretto (caratteri oltre U+00FF) o i byte non sono UTF-8 valido, resta com'e'.
function RiparaCodificaMessaggio(const Testo: string): string;
var
  Posizione: Integer;
  PresenteSospetto: Boolean;
  Codifica1252: TEncoding;
  Byte1252: TBytes;
  Riletto: string;
begin
  Result := Testo;
  PresenteSospetto := False;
  for Posizione := 1 to Length(Testo) do
  begin
    if Ord(Testo[Posizione]) > $FF then
      Exit;
    if (Ord(Testo[Posizione]) >= $C2) and (Ord(Testo[Posizione]) <= $F4) then
      PresenteSospetto := True;
  end;
  if not PresenteSospetto then
    Exit;
  // GetEncoding crea un oggetto nuovo da liberare (TEncoding.UTF8 e' condiviso, no).
  Codifica1252 := TEncoding.GetEncoding(1252);
  try
    try
      Byte1252 := Codifica1252.GetBytes(Testo);
      Riletto := TEncoding.UTF8.GetString(Byte1252);
    finally
      Codifica1252.Free;
    end;
  except
    // Un carattere senza corrispondenza in Windows-1252, o byte che non sono UTF-8 valido: il testo
    // non e' una codifica doppia e si tiene l'originale.
    on EEncodingError do
      Exit;
  end;
  // Un carattere di sostituzione dice, come l'eccezione, che i byte non erano UTF-8.
  if Pos(#$FFFD, Riletto) = 0 then
    Result := Riletto;
end;

function TranslateFirebirdException(E: EIBNativeException; const Detailed: boolean): string;
var
  SQLCode: Integer;
  Msg: string;
begin
  SQLCode := 0;
  Msg := '';
  if E.ErrorCount > 0 then
  begin
    SQLCode := E.Errors[0].SQLCode;
    Msg := LowerCase(RiparaCodificaMessaggio(E.Errors[0].Message));
  end;

  case SQLCode of
    - 803:
      Result := 'Violazione di unicità: esiste già un record con gli stessi dati chiave.';
    -530:
      Result := 'Impossibile completare l''operazione: il record è collegato ad altri dati.';
    -625:
      Result := 'Errore di validazione: uno o più campi contengono valori non ammessi.';
    -902:
      Result := 'Errore di connessione al database. Verificare che il server sia raggiungibile.';
    -904:
      Result := 'Il database è temporaneamente non disponibile. Riprovare tra qualche istante.';
    -901:
      Result := 'Errore di comunicazione con il database.';
    -551, -552:
      Result := 'Permessi insufficienti per eseguire questa operazione.';
    -413:
      Result := 'Errore di conversione dati: tipo non compatibile.';
    -204:
      Result := 'Riferimento a un oggetto del database non valido o inesistente.';
    -206:
      Result := 'Colonna o campo non trovato nella tabella.';
    -607:
      Result := 'L''oggetto del database è già esistente o non può essere modificato.';
    -105:
      Result := 'Errore di sintassi nella query.';
    -817:
      Result := 'Operazione non supportata in questo contesto.';
  else
    if Pos('lock conflict', Msg) > 0 then
      Result := 'Il record è attualmente in uso da un altro utente. Riprovare tra qualche istante.'
    else
      if Pos('deadlock', Msg) > 0 then
        Result := 'Conflitto di accesso simultaneo. Riprovare l''operazione.'
      else
        if Pos('arithmetic exception', Msg) > 0 then
          Result := 'Errore di calcolo: possibile divisione per zero o overflow numerico.'
        else
          if Pos('null', Msg) > 0 then
            Result := 'Un campo obbligatorio non è stato compilato.'
          else
            Result := Format('Errore del database (codice %d).', [SQLCode]);
  end;

  if Detailed then
  begin
    Result := Result + sLineBreak + sLineBreak + '--- Dettaglio tecnico ---';
    for var I := 0 to E.ErrorCount - 1 do
      Result := Result + sLineBreak + Format('[SQL: %d, IB: %d] %s', [E.Errors[I].SQLCode, E.Errors[I].ErrorCode, RiparaCodificaMessaggio(E.Errors[I].Message)]);
  end;
end;

end.
