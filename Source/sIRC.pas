{
  sIRC.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.
}


unit sIRC;


  {$MODE OBJFPC}
  {$H+}


interface


  uses
    cthreads,
    cmem, 
    BlckSock,
    Classes;
 

  type
  
  
    tIRC = class( TThread )
      private
         fAPIXU     : string;
         fChannel   : string;
         fCritical  : TRTLCriticalSection;                      // Main thread may write at same time
         fNetwork   : string;
         fOEDAppID  : string;
         fOEDKey    : string;
         fPassword  : string;
         fPending   : string;                                   // Message waiting for fLog.send
         fPort      : string;
         fSock      : TTCPBlockSocket;
         fStarted   : boolean;
         fTimeout   : integer;
         fVersion   : string;
         fUserName  : string;
         function HTTPGet( addr, hdrs : string ) : string;
         function JSONDefine( const s : string ) : string;
         function JSONSynonyms( s : string ) : string;
         function JSONWiki( s : string ) : string;
      protected
        procedure Execute; override;
      public
        constructor Create;
        destructor  Destroy; override;
        property    Channel : string write fChannel;
        procedure   MsgChat( s : string );
        procedure   MsgSend( s : string );
        property    APIXU : string write fAPIXU;
        property    Network : string write fNetwork;
        property    OEDAppID : string write fOEDAppID;
        property    OEDKey : string write fOEDKey;
        property    Password : string write fPassword;
        property    Port : string write fPort;
        property    Started : boolean read fStarted;
        property    Version : string write fVersion;
        property    UserName : string write fUserName;
    end;  // tIRC


{   tIRCChan = class( TStringList )
     private
       fChannel  : string;
       fCountMax : integer;
     public
       constructor Create;
       constructor Destroy; override;
       property    ChannelGet : string read fChannel;
       function    Connect( s : string ) : string;
       property    CountMax : integer write fCountMax;
       function    Disconnect : string;
       procedure   Display;
   end;  // tIRCChan
}

var
  fIRC : tIRC;


implementation


  uses
    DateUtils,
    fpJSON,
    JSONParser,
    OpenSSL,
    sConsole,
    sProfile,
    sWeather,
    httpsend,
    ssl_openssl,
    ssl_openssl_lib,
    synacode,
    StrUtils,
    SysUtils;


  const
    CRLF     : string = #13 + #10;

    
  constructor tIRC.Create;
    // create IRC thread
  begin
    inherited Create( TRUE );
    fPending := ''; 
    fStarted := FALSE;
    fTimeout := 500;
    InitCriticalSection( fCritical );
  end;  //  tIRC.Create 
  
  
  destructor tIRC.Destroy;
    // Shoot down thread and frieds
  begin
    try
      fSock.CloseSocket;
      fSock.Free;
    except
    end;
    DoneCriticalSection( fCritical );
    inherited Destroy;
  end;  // tIRC.Destroy


  procedure tIRC.Execute;
    // Main loop
  var
    Ball8 : TStringList;
    Comm  : string;       // Command in server response
    Nick  : string;       // Nick in server response
    Ops   : TStringList;  // Ops list
    Para  : string;       // Parameter part of response
    sHost : string;
    sTime : TDateTime;
    tTime : TDateTime;
    i     : integer;
    s     : string;
    t     : string;
  begin
    Randomize;
    Ball8     := TStringList.Create;
    Ops       := TStringList.Create;
    STime     := Now;
    fSock     := TTCPBlockSocket.Create;
    fSock.Connect( fNetwork, fPort );
    if fSock.LastError = 0
      then fCon.Send( 'Connected to ' + fNetwork + ' port ' + fPort, taNormal )
      else fCon.Send( 'Connect error ' + fSock.LastErrorDesc, taNormal );
    fCon.Send( 'Waiting', taNormal );
    sleep( 2000 );
    fCon.Send( 'Logging in',taNormal );  // Log in
    s := 'NICK ' + fUserName;
    MsgSend( s );
    fCon.Send( fUserName + ': ' + s, taBold );
    s := 'USER ' + fUserName + ' * * :' + fUserName;
    MsgSend( s );
    fCon.Send( fUserName + ': ' + s, taBold );
    while ( fSock.LastError = 0 ) and not Terminated do begin       // Chat loop 
      if fSock.WaitingData > 0 then begin                           // Read line from IRC server
        s := trim( fSock.RecvString( fTimeOut ) );
        s := ReplaceStr( s, #01, '~' );                             // Change CTCP marks
        if ( s <> '' ) and ( s[ 1 ] = ':' ) then begin
          s    := copy( s, 2, length( s ) );                        // Remove leaning :
          Nick := trim( copy( s, 1, pos( '!', s ) - 1 ) );          // Extract Nick
          s    := copy( s, pos( ' ', s ) + 1, length( s ) );        // Remove rest of address
          Comm := Uppercase( copy( s, 1, Pos( ' ', s ) - 1 ) );     // Extract command
          Para := Copy( s, Pos( ' ', s ) + 1, Length( s ) );        // Extract parameter
        end else begin
          Comm := Trim( Copy( s, 1, Pos( ' ', s + ' ' ) ) );
          Para := Trim( Copy( s, Pos( ' ', s + ' ') + 1, Length( s ) ) );
        end;
        case Comm of  // process message
          '001'     : s := 'Logged in as ' + fUserName;                                     // 001 RPL_WELCOME
          '002'     : begin                                                                 // 002 RPL_YOURHOST
                        sHost := Copy( s, Pos( ':', s ) + 1,  Length( s ) );
                        s     := 'Host: ' + s;
                      end;
          '003'     : s := '';                                                              // 003 RPL_CREATED
          '004'     : s := '';                                                              // 004 RPL_MYINFO
          '005'     : s := '';                                                              // 005 RPL_ISUPPORT
          '250'     : s := '';                                                              // 250 
          '251'     : s := '';                                                              // 251 RPL_LUSERCLIENT
          '252'     : s := '';                                                              // 252 RPL_LUSEROP
          '253'     : s := '';                                                              // 253 RPL_LUSERUNKNOWN
          '254'     : s := '';                                                              // 254 RPL_LUSERCHANNELS
          '255'     : s := '';                                                              // 255 RPL_LUSERME
          '265'     : s := '';                                                              // 265 RPL_LOCALUSERS
          '266'     : s := '';                                                              // 266 RPL_GLOBALUSERS
          '332'     : s := Copy( s, Pos( ':', s ) + 1, Length( s ) );                       // 332 RPL_TOPIC
          '333'     : s := '';                                                              // 333 RPL_TOPICWHOTIME
          '351'     : s := '';                                                              // 351 RPL_VERSION
          '353'     : s := 'Nicks: ' + Copy( Para, Pos( ':', Para ) + 1, Length( Para ) );  // 353 RPL_NAMREPLY
          '366'     : s := '';                                                              // 366 RPL_ENDOFNAMES
          '372'     : s := Trim( Copy( Para, Pos( ':', Para ) + 2, Length( Para ) ) );      // 372 RPL_MOTD
          '373'     : s := Para;                                                            // 373 
          '375'     : s := '';                                                              // 375 RPL_MOTDSTART
          '376'     : s := '';                                                              // 376 RPL_ENDOFMOTD
          '401'     : begin                                                                 // 401 ERR_NOSUCHNICK
                        s := Nick + ' No such nick/channel';
                        MsgChat( s );
                      end;
          '486'     : s := '';                                                              // 486 
          'ERROR'   : begin
                        s := 'Socket error; closing ' + Para;
                        Self.Terminate;
                      end;
          'JOIN'    : begin
                        fCon.Send( Nick + ' joined ' + fChannel, taNormal );
                        s := '';
                        if Uppercase( Nick ) = Uppercase( fUserName ) then begin
                          fStarted := TRUE;
                          MsgChat( 'Morning' );
                          fCon.Send( fUsername + '> Morning', taBold );
                          s := '';
                        end;
                      end;
          'MODE'    : begin
                        s := 'Mode set to  ' + copy( Para, Pos( ':', Para ) + 1, Length( Para ) ) ;
                        MsgSend( 'JOIN ' + fChannel );
                        fCon.Send( fUserName + '> JOIN ' + fChannel, taBold );
                      end;
          'NOTICE'  : begin
                        s := '';
                        if pos( '~TIME ', uppercase( Para ) ) > 0 then begin
                          s := Nick + ': ' + copy( Para, Pos( ':', Para ) + 2, length( Para ) );       //  <-  here 1 to 2
                          if pos( '~TIME ', uppercase( Para ) ) > 0 then MsgChat( s );
                        end else s := copy( Para, Pos( ':', Para ) + 1, length( Para ) );
                      end;
          'PART'    : s := Nick + ' parted ' + fChannel;
          'PING'    : begin
                         fCon.Send( s, taNormal );
                         fCon.Send( fUserName + ': PONG', taBold );
                         MsgSend( 'PONG' );
                         s := '';
                      end;
          'PRIVMSG' : begin
                        Comm := Copy( Para, Pos( ':' , Para ) + 1, Length( Para ) );
                        Para := Trim( Copy( Comm, Pos( ' ', Comm + ' ' ) + 1, Length( Comm ) ) );
                        s    := Copy( s, Pos( ':', s ) + 1, Length( s ) );
                        if Pos( ' ', Comm ) <> 0 then Comm := Copy( Comm, 1, Pos( ' ', Comm ) - 1 );
                        Comm := ReplaceStr( Comm, #01, '' );                                       // Remove CTCP marks
                        Comm := Uppercase( Comm );
                        case Comm of
                          '.8BALL'    : if length( para ) > 0 then begin
                                          Ball8.LoadFromFile( 'shao.8ball' );
                                          s := Ball8[ Random( Ball8.Count ) ];
                                          if Random( 10 ) = 4 then s := s + ', ' + Nick;
                                          MsgChat( s );
                                          s := Nick + '> ' + s;
                                        end else begin
                                          s := 'Need something to work with';
                                          MsgChat( s );
                                          s := nick + '> ' + s;
                                        end;
                          '.DEFINE'   : if length( Para ) > 0 then begin
                                          fCon.Send( Nick + '> .Define ' + Para, taNormal );
                                          s := 'APP_ID: ' + fOEDAppID + CRLF + 'APP_KEY: ' + fOEDKey + CRLF;
                                          s := HTTPGet( 'https://od-api.oxforddictionaries.com:443/api/v1/entries/en/' + Lowercase( EncodeURL( Para ) ), s );
                                          if copy( s, 1, 3 ) <> 'GET' then s := JSONDefine( s );
                                          s := 'Define ' + Uppercase( Para ) + ': ' + s;
                                          MsgChat( s ); 
                                          fCon.Send( fUserName + '> ' + s, taBold );
                                          s := '';
                                        end else begin
                                          s := 'Define usage - .Define <word>';
                                          MsgChat( s );
                                          s := Nick  + '> ' + s;
                                        end;
                          '.DOF'      : begin
                                          MsgChat( 'https://www.pointsinfocus.com/tools/depth-of-field-and-equivalent-lens-calculator' );
                                          MsgChat( 'https://dofsimulator.net/en/' );
                                          s := fUserName + '> Sent DoF URLs';
                                        end;
                          '.HELP'     : begin
                                          s := 'Help: https://fieldmacro.wordpress.com/2019/03/04/shao/';
                                          MsgChat( s );
                                          fCon.Send( s, taNormal );
                                          s := Nick + '> .HELP';
                                        end;
                          '.HOST'     : begin
                                          s := Nick + '> .Host';
                                          MsgChat( sHost );
                                          fPending := Nick + '> Host: ' + sHost;
                                        end;
                          '.OPS'      : begin
                                          try
                                            Ops.LoadFromFile( 'shao.ops' );
                                            s := '';
                                            for i := 1 to Ops.Count do begin
                                              if Length( s ) > 0 then s := s + ', '; 
                                              s := s + Ops.Strings[ i - 1 ];
                                            end;
                                            s := 'OPS: ' + s;
                                          except
                                            s := 'Ops list not available';
                                          end;
                                          MsgChat( s );
                                          s := fUsername + '> ' + s;
                                        end;
                          '.PROFILE'  : begin
                                          s := Nick + '> ' + fProf.Parse( Nick, Para );
                                          MsgChat( s );
                                          s := Nick + '> ' + s;
                                        end;
                          '.QUIT'     : begin
                                          s := 'Quit yourself, ' + Nick;
                                          MsgChat( s );
                                          fCon.Send( fUserName + '> ' + s, taBold );
                                          s := '';
                                        end;
                          '.SYNONYMS' : if Length( Para ) > 0 then begin
                                          fCon.Send( Nick + '> .Synonyms ' + Para, taNormal );
                                          s := 'APP_ID: ' + fOEDAppID + CRLF + 'APP_KEY: ' + fOEDKey + CRLF;
                                          s := HTTPGet( 'https://od-api.oxforddictionaries.com:443/api/v1/entries/en/' + Lowercase( EncodeURL( Para ) ) + '/synonyms', s );
                                          if Pos( '404 Not Found', s ) > 0
                                            then s := 'not found'
                                            else if copy( s, 1, 3 ) <> 'GET' 
                                                   then s := JSONSynonyms( s );
                                          s := 'Synonyms ' + Uppercase( Para ) + ': ' + s;
                                          MsgChat( s ); 
                                          fCon.Send( fUserName + '> ' + s, taBold );
                                          s := '';
                                        end else begin
                                          s := 'Synonyms usage - .Synonyms <word>';
                                          MsgChat( s );
                                          s := Nick  + '> ' + s;
                                        end;
                          '.TIME'     : begin
                                          if length( Para ) > 0 then begin
                                            if Uppercase( Para ) = fUsername then begin
                                              DateTimeToString( s, 'ddd mmm dd ', Date );
                                              DateTimeToString( t, 'hh:mm:ss:zzz', Time );
                                              s := s + t;
                                              MsgChat( s );
                                              fPending := fUsername + '> ' + s;
                                            end else begin
                                              s := 'PRIVMSG ' + Para + ' :' + #01 + 'time' + #01;
                                              MsgSend( s );
                                              fPending := fUserName + '> ' + s;
                                            end;
                                          end else MsgChat( 'Usage .Time nick' );
                                          s := Nick + '> .Time ' + Para;
                                        end;
                          '.UP'       : begin
                                         fCon.Send( nick + '> .up', taNormal );
                                          tTime := Now;
                                          s := 'Up time: ' + IntToStr( DaysBetween( tTime, sTime ) ) + ' days ' + 
                                               FormatDateTime('h" hrs, "n" min, "s" sec"', tTime - sTime );
                                          MsgChat( s );
                                          fCon.Send( fUsername + '> ' + s, taBold );
                                          s := '';
                                        end;
                          '.VERSION'  : begin
                                          MsgChat( 'Version ' + fVersion );
                                          fCon.Send( fUserName + '> Version ' + fVersion, taBold );
                                          s := '';
                                        end;
                          '.WEATHER'  : begin
                                          fCon.Send( nick + '> .weather ' + para, taNormal );
                                          if uppercase( fChannel ) <> '#PHOTOGEEKS' then begin
                                            s := fWeather.Command( nick, para );
                                            MsgChat( s );
                                            fCon.Send( fUsername + '> ' + s, taBold );
                                            s := '';
                                          end else s := fUsername + '> hidden weather';
                                        end;
                          '.WIKI'     : if Length( Para ) > 0 then begin
                                          fCon.Send( Nick + '> .Wiki ' + Para, taNormal );
                                          s := HTTPGet( 'https://en.wikipedia.org/w/api.php?format=json&action=query&prop=extracts&exintro&explaintext&redirects=1&titles=' + EncodeURL( Para ), '' );
                                          if copy( s, 1, 3 ) <> 'GET' then s := JSONWIKI( s );
                                          if Trim( s ) = '' then s := 'Multiple entries.  Please be more specific.';
                                          s := 'Wiki ' + Uppercase( Para ) + ': ' + s;
                                          MsgChat( s );
                                          fCon.Send(  fUserName + '> ' + s, taBold );
                                          s := '';
                                        end else begin
                                          s := 'Wiki usage - .Wiki <word | phrase>';
                                          MsgChat( s );
                                          s := Nick  + '> ' + s;
                                        end;
                          '~ACTION'   : begin
                                          s := Copy( s, Pos( ' ', s ) + 1, Length( s ) );
                                          s := Nick + '> ' + s;
                                        end;
                          '~TIME'     : begin
                                          DateTimeToString( s, 'ddd mmm dd ', Date );
                                          DateTimeToString( t, 'hh:mm:ss:zzz', Time );
                                          s := s + t;
                                          MsgChat( s );
                                          fCon.Send( fUsername + '> ' + s, taBold );
                                        end;
                          '~VERSION'  : begin
                                          fCon.Send( 'VERSION', taNormal );
                                          s := 'VERSION '+ fUserName + ' v.' + fVersion;
                                          MsgSend( s );
                                          fCon.Send( fUsername + '> ' + s, taBold );
                                          s := '';
                                        end;
                          else s := Nick + '>  ' + s;
                        end;  // PRIVMSG case
                      end;  // PRIVMSG
          else s := Nick + '> ' + s;
       end;  // Case process messages
       if Length( s ) > 0 then fCon.Send( s, taNormal );
       if Length( fPending ) > 0 then fCon.Send( fPending, taNormal );
       s := '';
       fPending := '';
      end ;  // if fSock.DataWaiting
      sleep( 5 );
    end;  // while
    MsgSend( 'QUIT Laters :)' );
    Ball8.Free;
    Ops.Free;
    fCon.Send( 'IRC link ended', taNormal );
  end;  // tIRC.Execute
  
  
  function  tIRC.HTTPGet( addr, hdrs : string ) : string;
    // get response string from page at addr
    // hdrs is string of extra headers delimited with CRLF (INCLUDING LAST ONE!!!)
  var
    HTTP : THTTPSend;
    i    : integer;
    s    : string;
    str  : TStringList;
  begin
    HTTP := THTTPSend.Create;
    str  := TStringList.Create;
    s     := '';
    HTTP.Clear;
    HTTP.KeepAlive := FALSE;
    HTTP.sock.ResetLastError;
    HTTP.TargetPort := '443';
    HTTP.Protocol := '1.1';
    while Length( hdrs ) > 0 do begin
      HTTP.Headers.Add( Copy( hdrs, 1, Pos( CRLF, hdrs ) ) );
      hdrs := Copy( hdrs, pos( CRLF, hdrs ) + 2, Length( HDRS ) );
    end;
 	try
	  if http.HTTPMethod( 'GET', addr ) then begin
	    str.LoadFromStream( http.Document );
	    for i := 0 to str.Count - 1 do
	      s := s + str[ i ];
	  end else s := 'GET error: ' + http.sock.GetErrorDescEx;
	  http.Clear;
	  str.Clear;
	finally
	  http.Free;
	  str.Free;
	end;
	Result := s;
  end;  // tIRC.Get


  function tIRC.JSONDefine( const s : string ) : string;
  var
   jDat : TJSONData;
    t   : string;
  begin
    try
      jDat := GetJSON( s );
      t    := jDat.AsJSON;  
      t    := Copy( t, Pos( 'definitions" : [', t ) + 17, Length( t ) ); 
      t    := Copy( t, 1, Pos( '"', t ) - 1 );
    except
      t := 'Not found';
    end;
    Result := t;
  end;  // tIRC.JSONDefine
  
  
  function tIRC.JSONSynonyms( s : string ) : string;
    // returns synonyms as comma delimited string
  var
    i    : integer;
    jDat : TJSONData;
    t    : string;
  begin
    i := 0;
    t := '';
    jDat := GetJSON( s );
    s := jDAT.AsJSON;
    s:= Copy( s, Pos( '"synonyms"', s ) + 11, Length( s ) );
    while ( Length( s ) > 0 ) and ( Length( t ) < 200 ) do begin
      s := Copy( s, Pos( '"id"', s ) + 8, Length( s ) );
      i := Pos( '"', s ) - 1;
      if Length( t ) > 0
        then t := t + ', ' + Copy( s, 1, i )
        else t := Copy( s, 1, i );
      s := Copy( s, Pos( '"', s ), Length( s ) );
    end;  // while
    Result := t;
  end;  // tIRC.JSONSynonyms
    
    
    function tIRC.JSONWiki( s: string ) : string;
      // returns content of field expr in JSON string s
    var
      t    : string;
      u    : string;
      v    : string;
    begin
      v := '';
      t := Copy( s, Pos( '"extract":', s ) + 11, Length( s ) );
      if pos( '"missing"', t ) = 0 then begin
        repeat
          if Pos( '.', t ) > 0 
            then u := Copy( t, 1, Pos( '.', t ) )
            else u := Copy( t, 1, Pos( '"}}}', t ) - 1 );
          if Length( v ) + length( u ) <= 400
            then v := v + u
            else t := '';
          if Length( t ) > 0 then t := Copy( t, Length( u ) + 1, Length( t ) );
          if Copy( t, 1, 7 ) = '"}}}' then t := '';
        until t = '';
      end else v := 'Not found';
      v := StringReplace( v, '\n\n', '\n', [rfReplaceAll] );
      v := StringReplace( v, '\n', ' -', [rfReplaceAll] );
      if Length( v ) = 0 then v := 'Not found';
      result := v;
    end;  // tIRC.JSONGet
  
  
    procedure tIRC.MsgChat( s : string );
      // send message to chat window
    begin
      EnterCriticalSection( fCritical );
      s := 'PRIVMSG ' + fChannel + ' :' + s;
      MsgSend( s );
      LeaveCriticalSection( fCritical );
    end;  // tIRC.MsgChat
      
    
    procedure tIRC.MsgSend( s : string );
      // Send message to channel
    begin
      EnterCriticalSection( fCritical );
      fSock.SendString( s + CRLF );
      if fSock.LastError <> 0  then fCon.Send( 'Send error: ' + fSock.LastErrorDesc, taBold );
      LeaveCriticalSection( fCritical );
    end;  // tIRC.MsgSend
  
end.  // sIRC 
