// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit Gesty.Capac.Controller;

// Moduli pubblici del sito CAPAC: richiesta di informazioni e candidatura.
//
// Il lavoro lo fa TSitoWebControllerBase (unit Gesty.SitoWeb.Controller):
// qui ci sono solo il percorso e le due azioni, perche' il sito Codebri usa
// gli stessi moduli con un percorso diverso.

interface

uses
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  Gesty.SitoWeb.Controller;

type

  [MVCPath('/api/gesty/capac')]
  [MVCDoc('Moduli pubblici del sito CAPAC')]
  TCapacController = class(TSitoWebControllerBase)
  public
    [MVCPath('/info')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Richiesta di informazioni dal sito')]
    procedure RichiestaInformazioni;

    [MVCPath('/cv')]
    [MVCHTTPMethod([httpPOST])]
    [MVCDoc('Invio di una candidatura con curriculum')]
    procedure InserimentoCandidatura;
  end;

implementation

{ TCapacController }

procedure TCapacController.RichiestaInformazioni;
begin
  RegistraRichiestaInformazioni;
end;

procedure TCapacController.InserimentoCandidatura;
begin
  RegistraCandidatura;
end;

end.
