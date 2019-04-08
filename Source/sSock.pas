{
  sSock.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.

  Simple socket implementation for Shao
  Knows about SSL
}


unit sSock;


  {$MODE OBJFPC}
  {$H+}


interface


  uses
    Classes,
    sSockets,
    SysUtils,
    URIParser;


  type


    tSock = class( TObject )
      private
         fBuffer    : string;
         fBufferInt : string;     // Internal buffer
         fBufferMax : integer;    // Maximum length fBuffer can get
         fConnected : boolean;
         fError     : integer;
         fErrorMsg  : string;
         fPort      : integer;
         fSock      : TINetSocket;
         fTerm      : boolean;
         fTimeOut   : integer;
         fURL       : string;
         fUseSSL    : boolean;
         procedure BufferReset( i : integer );
      public
        constructor Create;
        destructor  Destroy; override;
        property    BufferLen : integer write BufferReset;
        function    Connect : boolean;
        function    Connect( addr : string; port : integer ) : boolean;
        property    Connected : boolean read fConnected;
        procedure   Disconnect;
        property    Error : integer read fError;
        procedure   ErrorClear;
        property    ErrorMsg : string read fErrorMsg;
        property    Port : integer read fPort write fPort;
        function    RecvStr( out s : string ) : boolean;
        function    Send( s : string ) : boolean;
        property    Terminate : boolean write fTerm;
        property    TimeOut : integer read fTimeOut write fTimeOut;
        property    UseSSL : boolean read fUseSSL write fUseSSL;
        property    URL : string write fURL;
      end;  // tSock


implementation


  uses
    SSLSockets;


  const
    cBufferSizeDefault = 4096;
    CR                 = #13;
    LF                 = #10;


  constructor tSock.Create;
  begin
    inherited Create;
    fBufferMax := cBufferSizeDefault * 3;
    fErrorMsg  := '';
    fTerm      := FALSE;
    fTimeOut   := 250;
    BufferReset( cBufferSizeDefault );
  end;  // tSock.Create


  destructor tSock.Destroy;
  begin
    Disconnect;
    if assigned( fSock ) then FreeAndNil( fSock );
    inherited Destroy;
  end;  // tSock.Destroy


  procedure tSock.BufferReset( i : integer );
    // Set  fBufferInt length
  begin
    fBufferInt :='';
    if i < 1024
      then setLength( fBufferInt, cBufferSizeDefault )
      else setLength( fBufferInt, i );
  end;  // tSock.BufferReset

  
  function tSock.Connect : boolean;
    // Connect to socket
  var
    s : TSocketHandler;
  begin
    if fConnected then Disconnect;
    if fUseSSL
      then s := TSSLSocketHandler.Create
      else s := TSocketHandler.Create;
    fSock := TINetSocket.Create( fURL, fPort, s );
    try
      if fTimeOut <> 0 then fSock.IOTimeout := fTimeOut;
      fSock.Connect;
    except
      on E : ESocketError do begin
        fError    := -1;
        fErrorMsg := E.Message;
        Disconnect;
      end;
    end;
    fConnected := fError = 0;
    Connect := fConnected;
  end;  // tSock.Connect


  function tSock.Connect( addr : string; port : integer ) : boolean;
    // Set fURL and fPort then Connect
  begin
    fURL   := addr;
    fPort  := port;
    Result := Self.Connect;
  end;  // tSock.Connect

  
  procedure tSock.Disconnect;
    // Shut down socks
  begin
    FreeAndNil( fSock );
    fConnected := FALSE;
  end;  // tSock.Disconnect


  procedure tSock.ErrorClear;
    // Clear error vars
  begin
    fError    := 0;
    fErrorMsg := '';
  end;  // tSock.ErrorClear


  function tSock.RecvStr( out s : string ) : boolean;
    // Receive CR or CRLF delimed string in fBuffer
    // CR or CRLF are NOT returned
    // May return t := '' for time out
  var
    i : integer;
  begin
    s := '';
    while ( pos( CR, fBuffer ) = 0 ) and ( length( fBuffer ) < fBufferMax ) and ( fError = 0 ) and not fTerm do begin
      try
        i := fSock.Read( fBufferInt[ 1 ], length( fBufferInt ) );
        if i > 0 then begin
          fBuffer := fBuffer + copy( fBufferInt, 1, i );
          BufferReset( 0 );
        end else Sleep( 20 );
      except
        on E : Exception do begin
          fError    := -1;
          fErrorMsg := E.Message;
        end;
        on E : ESocketError do begin
          fError    := -1;
          fErrorMsg := E.Message;
        end;
      end;
    end;  // while
    if ( fError = 0 ) and not fTerm then begin
      if length( fBuffer ) > fBufferMax then begin
        fError    := -1;
        fErrorMsg := 'Buffer overflow prevention';
        fBuffer   := '';
        BufferReset( 0 );
      end else begin
        i := pos( CR, fBuffer );
        s := copy( fBuffer, 1, i - 1 );
        fBuffer := copy( fBuffer, i + 1, length( fBuffer ) );
        if ( length( fBuffer ) > 0 ) and ( fBuffer[ 1 ] = LF ) then fBuffer := copy( fBuffer, 2, length( fBuffer ) );
      end;
    end;
    RecvStr := fError = 0;
  end;  // tSock.RecvStr


  function tSock.Send( s : string ) : boolean;
    // Send s
  begin
    try
      if length( s ) > 0
        then fSock.WriteBuffer( s[ 1 ], length( s ) );
    except
      on E : Exception do begin
        fError := -1;
        fErrorMsg := E.Message;
      end;
    end;
    Send := fError = 0;
  end;  // tSock.Send


end.  // sSock 
