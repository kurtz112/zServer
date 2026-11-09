// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-15
// ---------------------------------------------------------------------------
unit Gesty.Codebri.Controller;

// Portato da Moduli\Gesty\dmCodebri.pas (classe TCodebri, framework TRoute).
//
// Nel sorgente d'origine le tre azioni chiamavano tutte 'Dump': scrivevano
// su file quello che arrivava e rispondevano OK, senza registrare niente.
// Era un modulo lasciato a meta'.
//
// Verificato sul database CODEBRI il 2026-09-15: le procedure
// WEB_RICHIESTE_INFORMAZIONI_ADD e WEB_CANDIDATURE_ADD ci sono, con la
// stessa firma di CAPAC. I moduli del sito sono gli stessi, quindi il
// comportamento e' lo stesso e sta in TSitoWebControllerBase: qui cambia
// solo il percorso, perche' il sito che chiama e' un altro.
//
// Se le etichette dei campi del sito Codebri fossero diverse, basta
// sovrascrivere il metodo Campo della classe base.

interface

uses
  MVCFramework,
  MVCFramework.Commons,
  MVCFramework.Serializer.Commons,
  MVCFramework.Swagger.Commons,
  Gesty.SitoWeb.Controller;

type

  [MVCPath('/api/gesty/codebri')]
  [MVCDoc('Moduli pubblici del sito Codebri')]
  TCodebriController = class(TSitoWebControllerBase)
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

{ TCodebriController }

procedure TCodebriController.RichiestaInformazioni;
begin
  RegistraRichiestaInformazioni;
end;

procedure TCodebriController.InserimentoCandidatura;
begin
  RegistraCandidatura;
end;

end.
