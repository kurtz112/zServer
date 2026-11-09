unit Data.Service;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Stan.Intf,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.DApt,
  FireDACHelper;

type
  TParamValues = TDictionary<string, Variant>;

  TDatasetConfig = record
    DatasetId: string;
    TableName: string;
    PrimaryKeyField: string;
    SelectSQL: string;
    CountSQL: string;
    InsertSQL: string;
    UpdateSQL: string;
    DeleteSQL: string;
    AllowInsert: Boolean;
    AllowUpdate: Boolean;
    AllowDelete: Boolean;
    Authorization: string; // Z6: codice di autorizzazione richiesto dal dataset (BASE_WEB_DATASETS.AUTHORIZATION)
    // 2026-11-06: modulo del dataset (BASE_WEB_DATASETS.MODULO, solo WT); vuoto = nessun controllo di modulo
    Modulo: string;
  end;

  TDataService = class
  private
    /// <summary>
    /// Applica i parametri dal dizionario alla TFDQuery.
    /// Inferisce automaticamente il tipo FireDAC dal Variant:
    /// varString/varUString/varOleStr → ftString
    /// varSmallInt/varInteger/varShortInt/varByte/varWord → ftInteger
    /// varInt64                                           → ftLargeint
    /// varBoolean                                         → ftBoolean
    /// varDouble/varSingle/varCurrency                    → ftFloat
    /// varDate                                            → ftDateTime
    /// varNull/varEmpty                                   → Clear (NULL)
    /// </summary>
    class procedure ApplyParams(FDParams: TFDParams; const Params: TParamValues); static;

    /// <summary>
    /// Assegna il valore a un parametro. Un numero decimale (Double) per un parametro NUMERIC
    /// o DECIMAL (ftBCD, ftFMTBcd) passa da un valore BCD costruito con il punto decimale:
    /// assegnarlo con Value farebbe convertire il numero a FireDAC passando dal testo con il
    /// separatore decimale della lingua del sistema, e con la virgola italiana la conversione
    /// fallisce ("1008.5 is not a valid BCD value").
    /// </summary>
    class procedure AssegnaValoreParametro(Parametro: TFDParam; const Valore: Variant); static;
  public
    class function GetFieldNames(const SQL: string): string;

    // ═══ ExecuteSQL (DML generico) ═══
    class function ExecuteSQL(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true; CommandKind: TFDCommandKind = skUnknown): TJSONObject; overload; static;
    class function ExecuteSQL(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true; CommandKind: TFDCommandKind = skUnknown): TJSONObject; overload; static;

    // ═══ ExecuteQuery (SELECT → TJSONArray) ═══
    class function ExecuteQuery(Connection: TFDConnection; const SQL: string; encodeBlobs: Boolean = true): TJSONArray; overload; static;
    class function ExecuteQuery(const SQL: string; encodeBlobs: Boolean = true): TJSONArray; overload; static;
    class function ExecuteQuery(Connection: TFDConnection; const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONArray; overload; static;
    class function ExecuteQuery(const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONArray; overload; static;

    // ═══ ExecuteQuerySingleRow (SELECT → TJSONObject, prima riga) ═══
    class function ExecuteQuerySingleRow(Connection: TFDConnection; const SQL: string; encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteQuerySingleRow(const SQL: string; encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteQuerySingleRow(Connection: TFDConnection; const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteQuerySingleRow(const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONObject; overload; static;

    // ═══ ExecuteScalar (SELECT → valore scalare) ═══
    class function ExecuteScalar(Connection: TFDConnection; const SQL: string): Int64; overload; static;
    class function ExecuteScalar(const SQL: string): Int64; overload; static;
    class function ExecuteScalar(Connection: TFDConnection; const SQL: string; const Params: TParamValues): Int64; overload; static;
    class function ExecuteScalar(const SQL: string; const Params: TParamValues): Int64; overload; static;

    // ═══ ExecuteInsert ═══
    class function ExecuteInsert(Connection: TFDConnection; const SQL: string; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteInsert(const SQL: string; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteInsert(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteInsert(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject; overload; static;

    // ═══ ExecuteUpdate ═══
    class function ExecuteUpdate(Connection: TFDConnection; const SQL: string; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteUpdate(const SQL: string; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteUpdate(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject; overload; static;
    class function ExecuteUpdate(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject; overload; static;

    // ═══ ExecuteDelete ═══
    class function ExecuteDelete(Connection: TFDConnection; const SQL: string): TJSONObject; overload; static;
    class function ExecuteDelete(const SQL: string): TJSONObject; overload; static;
    class function ExecuteDelete(Connection: TFDConnection; const SQL: string; const Params: TParamValues): TJSONObject; overload; static;
    class function ExecuteDelete(const SQL: string; const Params: TParamValues): TJSONObject; overload; static;

    // ═══ Stored Procedures ═══
    // RegistraEsito = false toglie la riga di DEBUG sulla chiamata riuscita:
    // serve a chi chiama a ripetizione, come il prelievo della coda a ogni
    // giro, e coprirebbe il resto del registro. Gli errori si registrano
    // sempre.
    class function ExecuteStoredProc(Connection: TFDConnection; const ProcName: string; const Params: TParamValues; encodeBlobs: Boolean = true; RegistraEsito: Boolean = true): TJSONObject; overload; static;
    class function ExecuteStoredProc(const ProcName: string; const Params: TParamValues; encodeBlobs: Boolean = true; RegistraEsito: Boolean = true): TJSONObject; overload; static;
  end;

implementation

uses
  System.SyncObjs,
  System.Diagnostics,
  System.Variants,
  Data.FMTBcd,
  System.TypInfo,
  System.DateUtils,
  System.NetEncoding,
  MVCFramework,
  MVCFramework.Logger,
  App.Config,
  Connection.Pool,
  System.StrUtils;

const
  // 2026-11-06: oltre questo numero di SQL diverse la memoria dei nomi dei campi si svuota
  MassimoNomiCampiInMemoria = 300;

var
  CriticalSection: TCriticalSection;
  // 2026-11-06: nomi dei campi gia' letti, per testo della SQL; il Prepare della SQL intera
  // costa secondi sulle SELECT con UNION (Cdr.Anagrafiche: 4,9 s su 4,9 s di richiesta)
  NomiCampiPerSql: TDictionary<string, string>;
  BloccoNomiCampi: TCriticalSection;

  { ═══════════════════════════════════════════════════════════════════════════════
    ApplyParams — Applica TStoredProcParams a una TFDQuery con type inference
    ═══════════════════════════════════════════════════════════════════════════════ }

  // class procedure TDataService.ApplyParams(FDParams: TFDParams; const Params: TParamValues);
  // var
  // Pair: TPair<string, Variant>;
  // Param: TFDParam;
  // VT: TVarType;
  // begin
  // for Pair in Params do
  // begin
  // Param := FDParams.FindParam(Pair.Key);
  // if Param = nil then
  // begin
  // // Il parametro non esiste nello SQL: crearlo automaticamente
  // // (utile quando SQL ha :NOME ma Prepare non è stato chiamato)
  // Param := FDParams.Add;
  // Param.Name := Pair.Key;
  // end;
  //
  // VT := VarType(Pair.Value) and varTypeMask;
  //
  // if VarIsNull(Pair.Value) or VarIsEmpty(Pair.Value) then
  // begin
  // Param.DataType := ftString;
  // Param.Clear;
  // end
  // else
  // Param.Value := Pair.Value;
  // // case VT of
  // // varString, varUString, varOleStr:
  // // begin
  // // Param.DataType := ftString;
  // // Param.AsString := VarToStr(Pair.Value);
  // // end;
  // //
  // // varSmallInt, varInteger, varShortInt, varByte, varWord:
  // // begin
  // // Param.DataType := ftInteger;
  // // Param.AsInteger := Pair.Value;
  // // end;
  // //
  // // varInt64:
  // // begin
  // // Param.DataType := ftLargeint;
  // // Param.AsLargeInt := Pair.Value;
  // // end;
  // //
  // // varBoolean:
  // // begin
  // // Param.DataType := ftBoolean;
  // // Param.AsBoolean := Pair.Value;
  // // end;
  // //
  // // varDouble, varSingle, varCurrency:
  // // begin
  // // Param.DataType := ftFloat;
  // // Param.AsFloat := Pair.Value;
  // // end;
  // //
  // // varDate:
  // // begin
  // // Param.DataType := ftDateTime;
  // // Param.AsDateTime := VarToDateTime(Pair.Value);
  // // end;
  // // else
  // // // Fallback: tratta come stringa
  // // Param.DataType := ftString;
  // // Param.AsString := VarToStr(Pair.Value);
  // // end;
  // end;
  // end;
class procedure TDataService.AssegnaValoreParametro(Parametro: TFDParam; const Valore: Variant);
var
  TipoVariante: TVarType;
  TestoNumero: string;
  NumeroBcd: TBcd;
  Convertito: Boolean;
begin
  // ZC 04.11.2026: prima si assegnava sempre Parametro.Value. Un numero con decimali per un
  // parametro NUMERIC (per esempio ORE_100) veniva convertito da FireDAC con il separatore
  // decimale della lingua del sistema: con la virgola italiana "1008.5" dava l'errore
  // "is not a valid BCD value" (500 sulla stored procedure), mentre gli interi passavano.
  // Il valore arriva come Double oppure, dalle chiamate /api/data/sp (ParseStoredProcParams),
  // come testo con il punto decimale del JSON. In entrambi i casi diventa un valore BCD
  // costruito qui, indipendente dalla lingua del sistema.
  if Parametro.DataType in [ftBCD, ftFMTBcd] then
  begin
    TipoVariante := VarType(Valore) and varTypeMask;
    TestoNumero := '';

    if (TipoVariante = varDouble) or (TipoVariante = varSingle) then
      TestoNumero := FloatToStr(Double(Valore), TFormatSettings.Invariant)
    else if (TipoVariante = varString) or (TipoVariante = varUString) or (TipoVariante = varOleStr) then
      TestoNumero := Trim(VarToStr(Valore));

    if TestoNumero <> '' then
    begin
      // Con la virgola il testo e' scritto alla maniera della lingua del sistema: si prova prima
      // quella; altrimenti il punto e' il separatore decimale.
      if Pos(',', TestoNumero) > 0 then
        Convertito := TryStrToBcd(TestoNumero, NumeroBcd, TFormatSettings.Create) or TryStrToBcd(TestoNumero, NumeroBcd, TFormatSettings.Invariant)
      else
        Convertito := TryStrToBcd(TestoNumero, NumeroBcd, TFormatSettings.Invariant);

      if Convertito then
      begin
        Parametro.Value := VarFMTBcdCreate(NumeroBcd);
        Exit;
      end;
    end;
  end;

  Parametro.Value := Valore;
end;

class procedure TDataService.ApplyParams(FDParams: TFDParams; const Params: TParamValues);
var
  Pair: TPair<string, Variant>;
  Param: TFDParam;
  StrVal: string;
  VT: TVarType;

  function TryISOToDateTime(const AStr: string; out AValue: TDateTime): Boolean;
  var
    FS: TFormatSettings;
    S: string;
  begin
    // Ora locale come il resto di zServer: senza fuso resta com'e', con Z o
    // con lo scostamento viene convertita (prima restituiva UTC, due ore
    // indietro in estate per le date scritte dal browser con la Z)
    result := TryISO8601ToDate(AStr, AValue, [ioNoTZIsLocal]);
    // // Rimuovi il suffisso Z e sostituisci T con spazio
    // S := AStr.Replace('T', ' ').TrimRight(['Z']);
    // // Tronca i millisecondi se presenti
    // var
    // DotPos := S.LastIndexOf('.');
    // if DotPos > 0 then
    // S := S.Substring(0, DotPos);
    //
    // FS := TFormatSettings.Create;
    // FS.DateSeparator := '-';
    // FS.TimeSeparator := ':';
    // FS.ShortDateFormat := 'yyyy-MM-dd';
    // FS.ShortTimeFormat := 'hh:nn:ss';
    //
    // Result := TryStrToDateTime(S, AValue, FS);
  end;

begin
  for Pair in Params do
  begin
    Param := FDParams.FindParam(Pair.Key);
    if Param = nil then
    begin
      Param := FDParams.Add;
      Param.Name := Pair.Key;
    end;

    if VarIsNull(Pair.Value) or VarIsEmpty(Pair.Value) then
    begin
      Param.Clear;
      Continue;
    end;

    // Se il Prepare ha determinato il tipo del parametro,
    // e il valore arriva come stringa, convertiamo esplicitamente

    VT := VarType(Pair.Value) and varTypeMask;
    if (VT = varString) or (VT = varUString) or (VT = varOleStr) then
    begin
      StrVal := VarToStr(Pair.Value);
      case Param.DataType of
        ftSmallint, ftInteger, ftWord, ftShortint:
          begin
            var
              IntVal: integer;
            // Assegnare con Value e non con AsInteger: AsInteger cambia il tipo del
            // parametro (SMALLINT diventa INTEGER) e FireDAC risponde con l'errore -338
            if TryStrToInt(StrVal, IntVal) then
              Param.Value := IntVal
            else
              Param.Clear;
          end;

        ftLargeint:
          begin
            var
              Int64Val: Int64;
            if TryStrToInt64(StrVal, Int64Val) then
              Param.AsLargeInt := Int64Val
            else
              Param.Clear;
          end;

        ftFloat, ftCurrency, ftBCD, ftFMTBcd, TFieldType.ftSingle, TFieldType.ftExtended:
          begin
            var
              FloatVal: Double;
            // Value e non AsFloat, per non cambiare il tipo dedotto da Firebird (NUMERIC, DECIMAL)
            if TryStrToFloat(StrVal, FloatVal) then
              AssegnaValoreParametro(Param, FloatVal)
            else
              Param.Clear;
          end;

        ftDate:
          begin
            var
              DateVal: TDateTime;
            if TryISOToDateTime(StrVal, DateVal) or TryStrToDate(StrVal, DateVal) then
              Param.AsDate := DateVal
            else
              Param.Clear;
          end;

        ftTime:
          begin
            var
              TimeVal: TDateTime;
            if TryISOToDateTime(StrVal, TimeVal) or TryStrToTime(StrVal, TimeVal) then
              Param.AsTime := TimeVal
            else
              Param.Clear;
          end;

        ftDateTime, ftTimeStamp:
          begin
            var
              DTVal: TDateTime;
            // Value e non AsDateTime: AsDateTime porta il parametro da ftTimeStamp (tipo
            // dedotto da Firebird per TIMESTAMP) a ftDateTime e FireDAC risponde con l'errore -338
            if TryISOToDateTime(StrVal, DTVal) or TryStrToDateTime(StrVal, DTVal) then
              Param.Value := DTVal
            else
              Param.Clear;
          end;

        ftBoolean:
          Param.AsBoolean := MatchStr(LowerCase(StrVal), ['true', '1', 'yes']);
      else
        begin

          if Param.Size <= 0 then
            Param.AsString := StrVal
          else
            Param.AsString := StrVal.Substring(0, Param.Size);
        end;
      end;
    end
    else
    begin
      // tutti gli altri casi [vedi Metadata.Patch.Controller]
      AssegnaValoreParametro(Param, Pair.Value);
    end;
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteQuery — SELECT multi-riga
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteQuery(Connection: TFDConnection; const SQL: string; encodeBlobs: Boolean = true): TJSONArray;
var
  Query: TFDQuery;
begin
  result := nil;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Open;
    result := Query.DataSetToJSON(encodeBlobs);
    LogD(Format('Query eseguita: %d record recuperati', [result.Count]));
  finally
    FreeAndNil(Query);
  end;
end;

class function TDataService.ExecuteQuery(const SQL: string; encodeBlobs: Boolean = true): TJSONArray;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteQuery(Connection, SQL, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteQuery(Connection: TFDConnection; const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONArray;
var
  Query: TFDQuery;
begin
  result := nil;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Prepare;
    ApplyParams(Query.Params, Params);
    Query.Open;
    result := Query.DataSetToJSON(encodeBlobs);
    LogD(Format('Query parametrica eseguita: %d record recuperati', [result.Count]));
  finally
    FreeAndNil(Query);
  end;
end;

class function TDataService.ExecuteQuery(const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONArray;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteQuery(Connection, SQL, Params, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteQuerySingleRow — SELECT prima riga
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteQuerySingleRow(Connection: TFDConnection; const SQL: string; encodeBlobs: Boolean = true): TJSONObject;
var
  Query: TFDQuery;
begin
  result := nil;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Open;
    result := Query.RecordToJSON(encodeBlobs);
    LogD('Query single row eseguita con successo');
  finally
    FreeAndNil(Query);
  end;
end;

class function TDataService.ExecuteQuerySingleRow(const SQL: string; encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteQuerySingleRow(Connection, SQL, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteQuerySingleRow(Connection: TFDConnection; const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONObject;
var
  Query: TFDQuery;
begin
  result := nil;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Prepare;
    ApplyParams(Query.Params, Params);
    Query.Open;
    result := Query.RecordToJSON(encodeBlobs);
    LogD('Query single row parametrica eseguita con successo');
  finally
    FreeAndNil(Query);
  end;
end;

class function TDataService.ExecuteQuerySingleRow(const SQL: string; const Params: TParamValues; encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteQuerySingleRow(Connection, SQL, Params, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteScalar
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteScalar(Connection: TFDConnection; const SQL: string): Int64;
var
  Query: TFDQuery;
begin
  result := 0;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Open;
    if not Query.Eof then
      result := Query.Fields[0].AsLargeInt;
    LogD(Format('ExecuteScalar: risultato = %d', [result]));
  finally
    Query.Free;
  end;
end;

class function TDataService.ExecuteScalar(const SQL: string): Int64;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteScalar(Connection, SQL);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteScalar(Connection: TFDConnection; const SQL: string; const Params: TParamValues): Int64;
var
  Query: TFDQuery;
begin
  result := 0;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := SQL;
    Query.Prepare;
    ApplyParams(Query.Params, Params);
    Query.Open;
    if not Query.Eof then
      result := Query.Fields[0].AsLargeInt;
    LogD(Format('ExecuteScalar parametrico: risultato = %d', [result]));
  finally
    Query.Free;
  end;
end;

class function TDataService.ExecuteScalar(const SQL: string; const Params: TParamValues): Int64;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteScalar(Connection, SQL, Params);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteSQL — DML generico (INSERT/UPDATE/DELETE)
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteSQL(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true; CommandKind: TFDCommandKind = skUnknown): TJSONObject;
var
  command: TFDCommand;
begin
  result := nil;
  command := TFDCommand.Create(nil);
  try
    command.Connection := Connection;
    command.CommandKind := CommandKind;
    command.CommandText.Text := SQL;

    command.Prepare();

    if assigned(Params) then
      ApplyParams(command.Params, Params);

    command.Execute();
    result := command.ToJSON(encodeBlobs);
    LogD(Format('SQL eseguito: %s', [result.Format(4)]));
  finally
    FreeAndNil(command);
  end;
end;

class function TDataService.ExecuteSQL(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true; CommandKind: TFDCommandKind = skUnknown): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteSQL(Connection, SQL, Params, encodeBlobs, CommandKind);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteInsert / ExecuteUpdate / ExecuteDelete — con parametri
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteInsert(Connection: TFDConnection; const SQL: string; const encodeBlobs: Boolean = true): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, nil, encodeBlobs, skInsert);
end;

class function TDataService.ExecuteInsert(const SQL: string; const encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteInsert(Connection, SQL, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteInsert(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, Params, encodeBlobs, skInsert);
end;

class function TDataService.ExecuteInsert(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteInsert(Connection, SQL, Params, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteUpdate(Connection: TFDConnection; const SQL: string; const encodeBlobs: Boolean = true): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, nil, encodeBlobs, skUpdate);
end;

class function TDataService.ExecuteUpdate(const SQL: string; const encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteUpdate(Connection, SQL, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteUpdate(Connection: TFDConnection; const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, Params, encodeBlobs, skUpdate);
end;

class function TDataService.ExecuteUpdate(const SQL: string; const Params: TParamValues; const encodeBlobs: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteUpdate(Connection, SQL, Params, encodeBlobs);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteDelete(Connection: TFDConnection; const SQL: string): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, nil, false, skDelete);
end;

class function TDataService.ExecuteDelete(const SQL: string): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteDelete(Connection, SQL);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.ExecuteDelete(Connection: TFDConnection; const SQL: string; const Params: TParamValues): TJSONObject;
begin
  result := ExecuteSQL(Connection, SQL, Params, false, skDelete);
end;

class function TDataService.ExecuteDelete(const SQL: string; const Params: TParamValues): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteDelete(Connection, SQL, Params);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

{ ═══════════════════════════════════════════════════════════════════════════════
  ExecuteStoredProc
  ═══════════════════════════════════════════════════════════════════════════════ }

class function TDataService.ExecuteStoredProc(Connection: TFDConnection; const ProcName: string; const Params: TParamValues; encodeBlobs: Boolean = true; RegistraEsito: Boolean = true): TJSONObject;
var
  StoredProc: TFDStoredproc;
  FDParam: TFDParam;
  spParam: TPair<string, Variant>;
begin
  result := TJSONObject.Create;
  StoredProc := TFDStoredproc.Create(nil);
  try
    try
      StoredProc.Connection := Connection;
      StoredProc.StoredProcName := ProcName;
      StoredProc.Prepare;

      for spParam in Params do
      begin
        FDParam := StoredProc.Params.FindParam(spParam.Key);
        if assigned(FDParam) then
          AssegnaValoreParametro(FDParam, spParam.Value);
      end;

      StoredProc.ExecProc;
      result := StoredProc.ToJSON(encodeBlobs);

      Connection.Commit;
      if RegistraEsito then
        LogD(Format('Stored proc %s eseguita con successo', [ProcName]));
    except
      on E: Exception do
      begin
        Connection.Rollback;
        FreeAndNil(result);
        LogE(Format('Errore stored proc %s: %s', [ProcName, E.Message]));
        raise;
      end;
    end;
  finally
    StoredProc.Free;
  end;
end;

class function TDataService.ExecuteStoredProc(const ProcName: string; const Params: TParamValues; encodeBlobs: Boolean = true; RegistraEsito: Boolean = true): TJSONObject;
var
  Connection: TFDConnection;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  try
    result := ExecuteStoredProc(Connection, ProcName, Params, encodeBlobs, RegistraEsito);
  finally
    TConnectionPool.Instance.Release(Connection);
  end;
end;

class function TDataService.GetFieldNames(const SQL: string): string;
var
  Connection: TFDConnection;
  Query: TFDQuery;
  FieldNames: TStringList;
  Cronometro: TStopwatch;
  MillisecondiPrepare: Int64;
  InMemoria: Boolean;
  IndiceCampo: Integer;
begin
  result := '';

  // 2026-11-06: i nomi dei campi di una SQL non cambiano finche' il testo e' lo stesso
  BloccoNomiCampi.Enter;
  try
    InMemoria := NomiCampiPerSql.TryGetValue(SQL, result);
  finally
    BloccoNomiCampi.Leave;
  end;
  if InMemoria then
    Exit;

  Cronometro := TStopwatch.StartNew;
  Connection := TConnectionPool.Instance.GetConnection;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Connection;
      Query.SQL.Text := SQL;
      Query.Prepare;
      MillisecondiPrepare := Cronometro.ElapsedMilliseconds;

      // 2026-11-06: Query.GetFieldNames apre il dataset ed esegue la SELECT intera, non filtrata
      // (Cdr.Anagrafiche: Prepare 3 ms, GetFieldNames 3.845 ms). I nomi si leggono dalle
      // definizioni dei campi dopo il Prepare, senza eseguire la query (come CampiDellaSelect
      // di Metadata.Editor.Controller).
      FieldNames := TStringList.Create;
      try
        Query.FieldDefs.Updated := False;
        Query.FieldDefs.Update;
        for IndiceCampo := 0 to Query.FieldDefs.Count - 1 do
          FieldNames.Add(Query.FieldDefs[IndiceCampo].Name);
        result := FieldNames.Text;
      finally
        FreeAndNil(FieldNames);
      end;
    finally
      FreeAndNil(Query);
    end;
  finally
    TConnectionPool.Instance.Release(Connection);
  end;

  LogD(Format('GetFieldNames - Prepare: %d ms, nomi dei campi: %d ms (SQL di %d caratteri)',
    [MillisecondiPrepare, Cronometro.ElapsedMilliseconds - MillisecondiPrepare, Length(SQL)]));

  BloccoNomiCampi.Enter;
  try
    if NomiCampiPerSql.Count >= MassimoNomiCampiInMemoria then
      NomiCampiPerSql.Clear;
    NomiCampiPerSql.AddOrSetValue(SQL, result);
  finally
    BloccoNomiCampi.Leave;
  end;
end;

initialization

CriticalSection := TCriticalSection.Create;
BloccoNomiCampi := TCriticalSection.Create;
NomiCampiPerSql := TDictionary<string, string>.Create;

finalization

FreeAndNil(NomiCampiPerSql);
FreeAndNil(BloccoNomiCampi);
FreeAndNil(CriticalSection);

end.
