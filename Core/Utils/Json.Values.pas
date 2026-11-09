// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-10-21
// ---------------------------------------------------------------------------
unit Json.Values;

// Letture tolleranti di un valore da un TJSONObject.
//
// I risultati delle stored procedure arrivano da TFDStoredProc.ToJSON, che
// rende i numeri come numeri ma le date come stringhe ISO e i booleani a
// volte come 'T'/'F'. GetValue<T> solleva quando il tipo non combacia: qui
// ogni funzione prova le forme possibili e, se non ci riesce, restituisce il
// valore predefinito invece di far cadere la richiesta.

interface

uses
  System.SysUtils,
  System.JSON;

function JsonStr(Oggetto: TJSONObject; const Nome: string; const Predefinito: string = ''): string;
function JsonInt64(Oggetto: TJSONObject; const Nome: string; const Predefinito: Int64 = 0): Int64;
function JsonInt(Oggetto: TJSONObject; const Nome: string; const Predefinito: Integer = 0): Integer;
function JsonBool(Oggetto: TJSONObject; const Nome: string; const Predefinito: Boolean = False): Boolean;
function JsonDate(Oggetto: TJSONObject; const Nome: string; const Predefinito: TDateTime = 0): TDateTime;

implementation

uses
  System.DateUtils,
  System.StrUtils;

function ValoreDi(Oggetto: TJSONObject; const Nome: string): TJSONValue;
begin
  Result := nil;

  if not Assigned(Oggetto) then
    Exit;

  Result := Oggetto.FindValue(Nome);

  if Result is TJSONNull then
    Result := nil;
end;

function JsonStr(Oggetto: TJSONObject; const Nome: string; const Predefinito: string = ''): string;
var
  Valore: TJSONValue;
begin
  Valore := ValoreDi(Oggetto, Nome);

  if Valore = nil then
    Exit(Predefinito);

  Result := Valore.Value;
end;

function JsonInt64(Oggetto: TJSONObject; const Nome: string; const Predefinito: Int64 = 0): Int64;
var
  Valore: TJSONValue;
begin
  Valore := ValoreDi(Oggetto, Nome);

  if Valore = nil then
    Exit(Predefinito);

  if Valore is TJSONNumber then
    Result := TJSONNumber(Valore).AsInt64
  else
    Result := StrToInt64Def(Valore.Value, Predefinito);
end;

function JsonInt(Oggetto: TJSONObject; const Nome: string; const Predefinito: Integer = 0): Integer;
begin
  Result := JsonInt64(Oggetto, Nome, Predefinito);
end;

function JsonBool(Oggetto: TJSONObject; const Nome: string; const Predefinito: Boolean = False): Boolean;
var
  Valore: TJSONValue;
  Testo: string;
begin
  Valore := ValoreDi(Oggetto, Nome);

  if Valore = nil then
    Exit(Predefinito);

  if Valore is TJSONBool then
    Exit(TJSONBool(Valore).AsBoolean);

  Testo := LowerCase(Valore.Value);
  Result := MatchStr(Testo, ['t', 'true', '1', 's', 'si', 'y', 'yes']);
end;

function JsonDate(Oggetto: TJSONObject; const Nome: string; const Predefinito: TDateTime = 0): TDateTime;
var
  Valore: TJSONValue;
  Testo: string;
begin
  Valore := ValoreDi(Oggetto, Nome);

  if Valore = nil then
    Exit(Predefinito);

  Testo := Valore.Value;

  if Testo.Trim.IsEmpty then
    Exit(Predefinito);

  // ioNoTZIsLocal: una data senza fuso e' gia' ora locale e resta com'e';
  // con Z o con lo scostamento viene portata all'ora locale. Con False la
  // RTL prendeva per UTC anche le date senza fuso e le spostava avanti
  // dello scostamento (due ore in estate)
  if TryISO8601ToDate(Testo, Result, [ioNoTZIsLocal]) then
    Exit;

  if not TryStrToDateTime(Testo, Result) then
    Result := Predefinito;
end;

end.
