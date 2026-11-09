unit zDocumentale.Firma.Factory;

// Factory dei provider di firma, con auto-registrazione.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  zDocumentale.Firma.Types,
  zDocumentale.Firma.Intf,
  zDocumentale.Firma.ProviderBase;

type
  TzFirmaProviderClass = class of TzFirmaProviderBase;

  TzFirmaFactory = class
  private
    class var FRegistro: TDictionary<string, TzFirmaProviderClass>;
    class function Registro: TDictionary<string, TzFirmaProviderClass>; static;
  public
    class destructor Destroy;
    class procedure Registra(const Nome: string; ProviderClass: TzFirmaProviderClass);
    class function Crea(const Nome: string): IzFirmaProvider;
    class procedure ElencoFornitori(Elenco: TStrings);
  end;

const
  FIRMA_FORNITORE_NESSUNO = 'NESSUNO';

implementation

{ TzFirmaFactory }

class function TzFirmaFactory.Registro: TDictionary<string, TzFirmaProviderClass>;
begin
  if not assigned(FRegistro) then
    FRegistro := TDictionary<string, TzFirmaProviderClass>.Create;
  result := FRegistro;
end;

class destructor TzFirmaFactory.Destroy;
begin
  FreeAndNil(FRegistro);
end;

class procedure TzFirmaFactory.Registra(const Nome: string;
  ProviderClass: TzFirmaProviderClass);
begin
  Registro.AddOrSetValue(Nome.ToUpper, ProviderClass);
end;

class function TzFirmaFactory.Crea(const Nome: string): IzFirmaProvider;
var
  providerClass: TzFirmaProviderClass;
  nomeRichiesto: string;
begin
  nomeRichiesto := Nome.Trim.ToUpper;
  if nomeRichiesto.IsEmpty then
    nomeRichiesto := FIRMA_FORNITORE_NESSUNO;

  if not Registro.TryGetValue(nomeRichiesto, providerClass) then
    if not Registro.TryGetValue(FIRMA_FORNITORE_NESSUNO, providerClass) then
      raise EzFirmaErrore.CreateFmt(
        'Nessun provider di firma registrato per "%s"', [Nome]);

  result := providerClass.Create;
end;

class procedure TzFirmaFactory.ElencoFornitori(Elenco: TStrings);
var
  nomeFornitore: string;
begin
  Assert(assigned(Elenco));
  Elenco.BeginUpdate;
  try
    Elenco.Clear;
    for nomeFornitore in Registro.Keys do
      Elenco.Add(nomeFornitore);
  finally
    Elenco.EndUpdate;
  end;
end;

end.
