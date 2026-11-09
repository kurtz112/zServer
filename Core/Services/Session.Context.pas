// ---------------------------------------------------------------------------
// Copyright (c) 2026 Luca Zebro - Tutti i diritti riservati.
// Uso, copia e distribuzione non autorizzati sono vietati.
//
// Ultima modifica: 2026-09-21
// ---------------------------------------------------------------------------
unit Session.Context;

// Contesto di sessione della richiesta in corso, per il solo thread corrente.
//
// Serve a chiudere il punto Z3: in WT e in Gesty la tracciatura e il perimetro
// di visibilita vivono nel database e sono legati alla connessione fisica
// (USR_CONTEXT, USR_TMP_COMUNI, USR_TMP_AZIENDE sono tabelle temporanee
// globali, e CURRENT_USER_ID() legge una variabile di contesto della
// connessione). Un server REST prende una connessione dal raggruppamento,
// serve la richiesta e la restituisce: il contesto va quindi dichiarato a
// ogni presa di connessione, non una volta al login.
//
// Il livello dati (Connection.Pool) deve percio' sapere chi sta chiedendo,
// ma non puo' chiamare il livello web per scoprirlo. La direzione e' una
// sola: il livello web deposita i dati qui, il livello dati li legge. Questa
// unit non dipende quindi ne' da MVCFramework ne' da FireDAC.
//
// Un thread serve una richiesta alla volta: il dato e' threadvar, non
// globale, e viene azzerato all'inizio di ogni richiesta (OnRequest del
// servizio di autenticazione, OnBeforeRouting del middleware di rinnovo),
// cosi' il thread non si porta dietro l'utente della richiesta precedente.
//
// Il record contiene stringhe: Delphi non finalizza i threadvar gestiti
// quando il thread termina. I thread di Indy vivono a lungo e l'azzeramento
// riporta le stringhe a vuoto a ogni giro, quindi non c'e' una perdita che
// cresce; e' pero' il motivo per cui qui non vanno aggiunti oggetti.

interface

type
  TSessionContext = record
    UserId: Int64;
    IdSessione: Int64;
    UserName: string;
    Belfiore: string;
    IdAzienda: Int64;
    Valorizzato: Boolean;
  end;

  TSessionContextManager = class
  public
    class procedure Imposta(const UserId, IdSessione: Int64; const UserName: string);
    class procedure ImpostaAmbito(const Belfiore: string; const IdAzienda: Int64);
    class procedure Azzera;
    class function Corrente: TSessionContext;
  end;

implementation

threadvar
  ContestoDelThread: TSessionContext;

{ TSessionContextManager }

class procedure TSessionContextManager.Imposta(const UserId, IdSessione: Int64; const UserName: string);
begin
  ContestoDelThread.UserId := UserId;
  ContestoDelThread.IdSessione := IdSessione;
  ContestoDelThread.UserName := UserName;
  ContestoDelThread.Valorizzato := UserId > 0;
end;

class procedure TSessionContextManager.ImpostaAmbito(const Belfiore: string; const IdAzienda: Int64);
begin
  ContestoDelThread.Belfiore := Belfiore;
  ContestoDelThread.IdAzienda := IdAzienda;
end;

class procedure TSessionContextManager.Azzera;
begin
  ContestoDelThread.UserId := 0;
  ContestoDelThread.IdSessione := 0;
  ContestoDelThread.UserName := '';
  ContestoDelThread.Belfiore := '';
  ContestoDelThread.IdAzienda := 0;
  ContestoDelThread.Valorizzato := False;
end;

class function TSessionContextManager.Corrente: TSessionContext;
begin
  Result := ContestoDelThread;
end;

end.
