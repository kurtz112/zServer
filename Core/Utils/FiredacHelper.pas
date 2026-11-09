unit FireDACHelper;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Data.DB,
  FireDAC.Phys.FBDef,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

type
  TFieldTypeHelper = record helper for TFieldType
    function IsString: boolean;
    function IsInteger: boolean;
    function IsLargeInteger: boolean;
    function IsFloat: boolean;
    function IsNumeric: boolean;
    function IsDate: boolean;
    function IsTime: boolean;
    function IsDateTime: boolean;
    function IsBoolean: boolean;
    function IsBlob: boolean;
    function IsMemo: boolean;
  end;

  TFDAdaptedDataSetHelper = class helper for TFDAdaptedDataSet
  public
    procedure CheckEditMode;
    procedure SetFieldValue(Field: TField; Value: Variant); overload;
    procedure SetFieldValue(const FieldName: string; Value: Variant); overload;
    procedure ClearFieldValue(const FieldName: string); overload;
    procedure ClearFieldValue(Field: TField); overload;
    procedure ClearFields(FieldsToClear: string);
    procedure CopyFieldValues(Source: TDataset; DoPost: boolean);
    procedure CopyRecord(Source: TDataset; DoPost: boolean);
    procedure DeleteAll;
    function IsDetailOf(DataSet: TDataset): boolean;
    function FieldExists(const FieldName: string): boolean;
    function ForEach(proc: TProc<boolean>): boolean; overload;
    function RecordToJSON(encodeBlobs: boolean): TJSONObject;
    function DataSetToJSON(encodeBlobs: boolean): TJSONArray;
  end;

  TFDStoredProcHelper = class helper for TFDStoredProc
  public
    function DebugString: string;
    function ParamExists(const ParamName: string): boolean;
    function ParamByName(const ParamName: string): TFDParam;
    function InputParamsCount: Integer;
    function OutputParamsCount: Integer;
    function ToJSON(encodeBlobs: boolean): TJSONObject;
  end;

  TFDCommandHelper = class helper for TFDCommand
  public
    function ParamExists(const ParamName: string): boolean;
    function InputParamsCount: Integer;
    function OutputParamsCount: Integer;
    function ToJSON(encodeBlobs: boolean): TJSONObject;
  end;

  TFDParamsHelper = class helper for TFDParams
    function ParamExists(const ParamName: string): boolean;
  end;

  TFDParamHelper = class helper for TFDParam
  private
    function GetasJSONValue: TJSONValue; // Per compatibilità proprietà esistente
    procedure SetasJSONValue(const Value: TJSONValue);
  public
    function IsInputParam: boolean;
    function IsOutputParam: boolean;
    function GetAsJSON(encodeBlobs: boolean): TJSONValue;
    property asJSON: TJSONValue read GetasJSONValue write SetasJSONValue;
  end;

  TFieldHelper = class helper for TField
  private
    function GetasJSONValue: TJSONValue; // Per compatibilità proprietà esistente
    procedure SetasJSONValue(const Value: TJSONValue);
  public
    function GetAsJSON(encodeBlobs: boolean): TJSONValue;
    property asJSON: TJSONValue read GetasJSONValue write SetasJSONValue;
  end;

implementation

uses
  System.Variants,
  System.StrUtils,
  System.DateUtils,
  Data.DBConsts,
  FireDAC.Stan.Util,
  System.NetEncoding;

{ TFieldTypeHelper }

function TFieldTypeHelper.IsString: boolean;
begin
  Result := Self in [ftString, ftFixedChar, ftWideString, ftFixedWideChar];
end;

function TFieldTypeHelper.IsInteger: boolean;
begin
  Result := Self in [ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftLongWord, ftShortint, ftByte];
end;

function TFieldTypeHelper.IsLargeInteger: boolean;
begin
  Result := Self in [ftLargeint, ftLongWord];
end;

function TFieldTypeHelper.IsFloat: boolean;
begin
  // ftSingle e' il FLOAT di Firebird (coordinate): fra gli interi perdeva i decimali
  Result := Self in [ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftExtended, ftSingle];
end;

function TFieldTypeHelper.IsNumeric: boolean;
begin
  Result := Self.IsInteger or Self.IsFloat;
end;

function TFieldTypeHelper.IsDate: boolean;
begin
  Result := Self in [ftDate];
end;

function TFieldTypeHelper.IsTime: boolean;
begin
  Result := Self in [ftTime];
end;

function TFieldTypeHelper.IsDateTime: boolean;
begin
  Result := Self in [ftDate, ftTime, ftDateTime, ftTimeStamp];
end;

function TFieldTypeHelper.IsBoolean: boolean;
begin
  Result := Self in [ftBoolean];
end;

function TFieldTypeHelper.IsBlob: boolean;
begin
  Result := Self in [ftBlob, ftMemo, ftGraphic, ftFmtMemo, ftWideMemo];
end;

function TFieldTypeHelper.IsMemo: boolean;
begin
  Result := Self in [ftMemo, ftFmtMemo, ftWideMemo];
end;

{ Funzioni interne }

procedure InternalSetFromJSON(const Value: TJSONValue; DataType: TFieldType; const TargetName: string; const SetString: TProc<string>; const SetInteger: TProc<Integer>; const SetLargeInt: TProc<Int64>; const SetFloat: TProc<Double>;
  const SetBoolean: TProc<boolean>; const SetDateTime: TProc<TDateTime>; const SetBlobFromBytes: TProc<TBytes>; const DoClear: TProc);
var
  StrValue: string;
begin
  if (Value = nil) or (Value is TJSONNull) then
  begin
    DoClear();
    Exit;
  end;

  if Value is TJSONBool then
    SetBoolean(TJSONBool(Value).AsBoolean)
  else
    if Value is TJSONNumber then
    begin
      if DataType.IsLargeInteger then
        SetLargeInt(TJSONNumber(Value).AsInt64)
      else
        if DataType.IsInteger then
          SetInteger(TJSONNumber(Value).AsInt)
        else
          if DataType.IsFloat then
            SetFloat(TJSONNumber(Value).AsDouble)
          else
            SetString(TJSONNumber(Value).ToString);
    end
    else
      if Value is TJSONString then
      begin
        StrValue := TJSONString(Value).Value;
        if DataType.IsDateTime then
          // Senza fuso la data e' ora locale e resta com'e' (ioNoTZIsLocal);
          // con Z o con lo scostamento viene portata all'ora locale
          SetDateTime(ISO8601ToDate(StrValue, [ioNoTZIsLocal]))
        else
          if DataType.IsBlob then
            SetBlobFromBytes(TNetEncoding.Base64.DecodeStringToBytes(StrValue))
          else
            SetString(StrValue);
      end;
end;

function InternalGetAsJSON(AIsNull: boolean; DataType: TFieldType; encodeBlobs: boolean; const GetString: TFunc<string>; const GetInteger: TFunc<Integer>; const GetLargeInt: TFunc<Int64>; const GetFloat: TFunc<Double>;
  const GetBoolean: TFunc<boolean>; const GetDateTime: TFunc<TDateTime>; const GetBlobAsBase64: TFunc<string>): TJSONValue;
begin
  if AIsNull then
    Exit(TJSONNull.Create);

  if DataType.IsString then
    Result := TJSONString.Create(GetString())
  else
    if DataType.IsLargeInteger then
      Result := TJSONNumber.Create(GetLargeInt())
    else
      if DataType.IsInteger then
        Result := TJSONNumber.Create(GetInteger())
      else
        if DataType.IsFloat then
          Result := TJSONNumber.Create(GetFloat())
        else
          if DataType.IsDateTime then
            Result := TJSONString.Create(DateToISO8601(GetDateTime(), False))
          else
            if DataType.IsBoolean then
              Result := TJSONBool.Create(GetBoolean())
            else
              if DataType.IsBlob then
              begin

                if encodeBlobs then
                  Result := TJSONString.Create(GetBlobAsBase64())
                else
                  Result := TJSONString.Create(GetString())
              end
              else
                Result := TJSONString.Create(GetString());
end;

{ TFDStoredProcHelper }

function TFDStoredProcHelper.ToJSON(encodeBlobs: boolean): TJSONObject;
var
  i: Integer;
  Param: TFDParam;
begin
  Result := TJSONObject.Create;
  try
    for i := 0 to Params.Count - 1 do
    begin
      Param := Params[i];
      if Param.IsOutputParam then
        Result.AddPair(Param.Name, Param.GetAsJSON(encodeBlobs));
    end;
  except
    Result.Free;
    raise;
  end;
end;

// ... (altri metodi TFDStoredProcHelper invariati)

function TFDStoredProcHelper.DebugString: string;
var
  Param: TFDParam;
  indent: string;
  i, pCount, outputIdx: Integer;
begin
  Result := 'EXECUTE PROCEDURE ' + StoredProcName;
  pCount := InputParamsCount;
  if pCount > 0 then
  begin
    Result := Result + '(';
    indent := ''.PadLeft(Result.Length, ' ');
    outputIdx := 0;
    for i := 0 to ParamCount - 1 do
    begin
      Param := Params[i];
      if Param.IsInputParam then
      begin
        if Param.IsNull then
          Result := Result + 'NULL'
        else
          if Param.DataType.IsNumeric then
            Result := Result + Param.AsString.Replace(',', '.')
          else
            Result := Result + AnsiQuotedStr(Param.AsString, #39);

        Inc(outputIdx);
        if outputIdx < pCount then
          Result := Result + ', ' + sLineBreak + indent;
      end;
    end;
    Result := Result + ');';
  end;
end;

function TFDStoredProcHelper.InputParamsCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Params.Count - 1 do
    if Params[i].IsInputParam then
      Inc(Result);
end;

function TFDStoredProcHelper.OutputParamsCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Params.Count - 1 do
    if Params[i].IsOutputParam then
      Inc(Result);
end;

function TFDStoredProcHelper.ParamByName(const ParamName: string): TFDParam;
begin
  Result := Params.ParamByName(ParamName);
end;

function TFDStoredProcHelper.ParamExists(const ParamName: string): boolean;
begin
  Result := Params.ParamExists(ParamName);
end;

{ TFDCommandHelper }

function TFDCommandHelper.ToJSON(encodeBlobs: boolean): TJSONObject;
var
  i: Integer;
  Param: TFDParam;
begin
  Result := TJSONObject.Create;
  try
    for i := 0 to Params.Count - 1 do
    begin
      Param := Params[i];
      if Param.ParamType in [ptOutput, ptInputOutput] then
        Result.AddPair(Param.Name, Param.GetAsJSON(encodeBlobs));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFDCommandHelper.ParamExists(const ParamName: string): boolean;
begin
  Result := Assigned(Params.FindParam(ParamName));
end;

function TFDCommandHelper.InputParamsCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Params.Count - 1 do
    if Params[i].ParamType in [ptInput, ptInputOutput] then
      Inc(Result);
end;

function TFDCommandHelper.OutputParamsCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Params.Count - 1 do
    if Params[i].ParamType in [ptOutput, ptInputOutput] then
      Inc(Result);
end;

{ TFDAdaptedDataSetHelper }

function TFDAdaptedDataSetHelper.RecordToJSON(encodeBlobs: boolean): TJSONObject;
var
  i: Integer;
begin
  Result := TJSONObject.Create;
  try
    for i := 0 to FieldCount - 1 do
      Result.AddPair(Fields[i].FieldName, Fields[i].GetAsJSON(encodeBlobs));
  except
    Result.Free;
    raise;
  end;
end;

function TFDAdaptedDataSetHelper.DataSetToJSON(encodeBlobs: boolean): TJSONArray;
var
  Bm: TBookmark;
begin
  Result := TJSONArray.Create;
  try
    if not Active then
      Exit;
    DisableControls;
    try
      Bm := GetBookmark;
      try
        First;
        while not EOF do
        begin
          Result.AddElement(RecordToJSON(encodeBlobs));
          Next;
        end;
      finally
        if BookmarkValid(Bm) then
          GotoBookmark(Bm);
        FreeBookmark(Bm);
      end;
    finally
      EnableControls;
    end;
  except
    Result.Free;
    raise;
  end;
end;

// ... (altri metodi TFDAdaptedDataSetHelper invariati)

procedure TFDAdaptedDataSetHelper.CheckEditMode;
begin
  if Active and not(State in dsEditModes) then
    Edit;
end;

procedure TFDAdaptedDataSetHelper.CopyRecord(Source: TDataset; DoPost: boolean);
begin
  CopyFieldValues(Source, DoPost);
end;

procedure TFDAdaptedDataSetHelper.CopyFieldValues(Source: TDataset; DoPost: boolean);
var
  i: Integer;
begin
  if not(State in dsEditModes) then
    Append;
  for i := 0 to Source.FieldCount - 1 do
    if not SameText(Source.Fields[i].FieldName, UpdateOptions.KeyFields) then
      if Assigned(FindField(Source.Fields[i].FieldName)) then
        if not Source.Fields[i].IsNull then
          try
            FieldByName(Source.Fields[i].FieldName).Value := Source.Fields[i].Value;
          except
          end;
  if DoPost then
    CheckBrowseMode;
end;

procedure TFDAdaptedDataSetHelper.DeleteAll;
begin
  Cancel;
  if RecordCount = 0 then
    Exit;
  First;
  while not EOF do
    Delete;
end;

function TFDAdaptedDataSetHelper.FieldExists(const FieldName: string): boolean;
begin
  Result := Assigned(FindField(FieldName));
end;

function TFDAdaptedDataSetHelper.IsDetailOf(DataSet: TDataset): boolean;
begin
  Result := Assigned(DataSource) and Assigned(DataSource.DataSet) and (DataSource.DataSet = DataSet);
end;

procedure TFDAdaptedDataSetHelper.ClearFields(FieldsToClear: string);
var
  i: Integer;
  Str: TStringList;
begin
  if Trim(FieldsToClear) = '' then
    Exit;
  CheckEditMode;
  Str := TStringList.Create;
  try
    Str.Delimiter := ';';
    Str.DelimitedText := FieldsToClear;
    for i := 0 to Str.Count - 1 do
      if Str[i] <> '' then
        ClearFieldValue(Str[i]);
  finally
    Str.Free;
  end;
end;

procedure TFDAdaptedDataSetHelper.ClearFieldValue(const FieldName: string);
var
  Field: TField;
begin
  Field := FindField(FieldName);
  if Assigned(Field) then
    ClearFieldValue(Field);
end;

procedure TFDAdaptedDataSetHelper.ClearFieldValue(Field: TField);
begin
  SetFieldValue(Field, Null);
end;

function TFDAdaptedDataSetHelper.ForEach(proc: TProc<boolean>): boolean;
var
  Cancel: boolean;
begin
  Assert(Assigned(proc));
  Result := False;
  if not Active then
    Exit;
  DisableControls;
  try
    Cancel := False;
    First;
    while not EOF do
    begin
      proc(Cancel);
      if Cancel then
        Exit(False);
      Next;
    end;
    Result := True;
  finally
    EnableControls;
  end;
end;

procedure TFDAdaptedDataSetHelper.SetFieldValue(const FieldName: string; Value: Variant);
begin
  SetFieldValue(FieldByName(FieldName), Value);
end;

procedure TFDAdaptedDataSetHelper.SetFieldValue(Field: TField; Value: Variant);
var
  WasCheckReadOnly: boolean;
begin
  WasCheckReadOnly := UpdateOptions.CheckReadOnly;
  UpdateOptions.CheckReadOnly := False;
  try
    CheckEditMode;
    if VarIsNull(Value) then
      Field.Clear
    else
      Field.Value := Value;
  finally
    UpdateOptions.CheckReadOnly := WasCheckReadOnly;
  end;
end;

{ TFDParamsHelper }

function TFDParamsHelper.ParamExists(const ParamName: string): boolean;
begin
  Result := Assigned(FindParam(ParamName));
end;

{ TFDParamHelper }

function TFDParamHelper.IsInputParam: boolean;
begin
  Result := ParamType in [ptInput, ptInputOutput];
end;

function TFDParamHelper.IsOutputParam: boolean;
begin
  Result := ParamType in [ptOutput, ptInputOutput];
end;

function TFDParamHelper.GetAsJSON(encodeBlobs: boolean): TJSONValue;
begin
  Result := InternalGetAsJSON(Self.IsNull, Self.DataType, encodeBlobs,
    function: string
    begin
      Result := Self.AsString
    end,
    function: Integer
    begin
      Result := Self.AsInteger
    end,
    function: Int64
    begin
      Result := Self.AsLargeInt
    end,
    function: Double
    begin
      Result := Self.AsFloat
    end,
    function: boolean
    begin
      Result := Self.AsBoolean
    end,
    function: TDateTime
    begin
      Result := Self.AsDateTime
    end,
    function: string
    var
      Stream: TStream;
      Bytes: TBytes;
    begin
      Stream := Self.AsStream;
      try
        Stream.Position := 0;
        SetLength(Bytes, Stream.Size);
        if Stream.Size > 0 then
          Stream.ReadBuffer(Bytes[0], Stream.Size);
        Result := TNetEncoding.Base64.EncodeBytesToString(Bytes).Replace(sLineBreak, '', [rfReplaceAll]);
      finally
        Stream.Free;
      end;
    end);
end;

function TFDParamHelper.GetasJSONValue: TJSONValue;
begin
  Result := GetAsJSON(True);
end;

procedure TFDParamHelper.SetasJSONValue(const Value: TJSONValue);
begin
  InternalSetFromJSON(Value, Self.DataType, Self.Name,
    procedure(S: string)
    begin
      Self.AsString := S
    end,
    procedure(V: Integer)
    begin
      Self.AsInteger := V
    end,
    procedure(V: Int64)
    begin
      Self.AsLargeInt := V
    end,
    procedure(V: Double)
    begin
      Self.AsFloat := V
    end,
    procedure(V: boolean)
    begin
      Self.AsBoolean := V
    end,
    procedure(V: TDateTime)
    begin
      Self.AsDateTime := V
    end,
    procedure(B: TBytes)
    var
      Stream: TBytesStream;
    begin
      Stream := TBytesStream.Create(B);
      try
        Self.AsStream := Stream;
      finally
        Stream.Free;
      end;
    end,
    procedure
    begin
      Self.Clear
    end);
end;

{ TFieldHelper }

function TFieldHelper.GetAsJSON(encodeBlobs: boolean): TJSONValue;
var
  FieldRef: TField;
begin
  FieldRef := Self;
  Result := InternalGetAsJSON(FieldRef.IsNull, FieldRef.DataType, encodeBlobs,
    function: string
    begin
      Result := FieldRef.AsString
    end,
    function: Integer
    begin
      Result := FieldRef.AsInteger
    end,
    function: Int64
    begin
      Result := FieldRef.AsLargeInt
    end,
    function: Double
    begin
      Result := FieldRef.AsFloat
    end,
    function: boolean
    begin
      Result := FieldRef.AsBoolean
    end,
    function: TDateTime
    begin
      Result := FieldRef.AsDateTime
    end,
    function: string
    var
      Stream: TStream;
      Bytes: TBytes;
    begin
      Stream := FieldRef.DataSet.CreateBlobStream(FieldRef, bmRead);
      try
        Stream.Position := 0;
        SetLength(Bytes, Stream.Size);
        if Stream.Size > 0 then
          Stream.ReadBuffer(Bytes[0], Stream.Size);
        Result := TNetEncoding.Base64.EncodeBytesToString(Bytes).Replace(sLineBreak, '', [rfReplaceAll]);
      finally
        Stream.Free;
      end;
    end);
end;

function TFieldHelper.GetasJSONValue: TJSONValue;
begin
  Result := GetAsJSON(True);
end;

procedure TFieldHelper.SetasJSONValue(const Value: TJSONValue);
var
  WasReadOnly: boolean;
  FieldRef: TField;
begin
  FieldRef := Self;
  WasReadOnly := FieldRef.ReadOnly;
  FieldRef.ReadOnly := False;
  try
    InternalSetFromJSON(Value, FieldRef.DataType, FieldRef.FieldName,
      procedure(S: string)
      begin
        FieldRef.AsString := S
      end,
      procedure(V: Integer)
      begin
        FieldRef.AsInteger := V
      end,
      procedure(V: Int64)
      begin
        FieldRef.AsLargeInt := V
      end,
      procedure(V: Double)
      begin
        FieldRef.AsFloat := V
      end,
      procedure(V: boolean)
      begin
        FieldRef.AsBoolean := V
      end,
      procedure(V: TDateTime)
      begin
        FieldRef.AsDateTime := V
      end,
      procedure(B: TBytes)
      var
        Stream: TBytesStream;
      begin
        Stream := TBytesStream.Create(B);
        try
          (FieldRef as TBlobField).LoadFromStream(Stream);
        finally
          Stream.Free;
        end;
      end,
      procedure
      begin
        FieldRef.Clear
      end);
  finally
    FieldRef.ReadOnly := WasReadOnly;
  end;
end;

end.
