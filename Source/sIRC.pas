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
    Classes,
    fpHTTPClient,
    fpJSON,
    sSock;

  type
  
  
    tIRC = class( TThread )
      private
         fBall8     : TStringList;
         fAPIXU     : string;
         fChannel   : string;
         fCritical  : TRTLCriticalSection;                      // Main thread may write at same time
         fHTTP      : TfpHTTPClient;
         fJoined    : integer;
         fJSON      : TJSONData;
         fOEDAppID  : string;
         fOEDKey    : string;
         fOkToEcho  : boolean;
         fOps       : TStringList;
         fNetwork   : string;
         fPassword  : string;
         fPending   : string;                                   // Message waiting for fLog.send
         fPingLast  : TDateTime;
         fPort      : string;
         fSock      : tSock;
         fTimeout   : integer;
         fVersion   : string;
         fUserName  : string;
         function  Define( s : string ) : string;
         procedure HTTPEcho( s : string );
         function  Launch : string;
         function  Wiki( s : string ) : string;
         function  Login : boolean;
         procedure Nicks( s : string );
         function  Shao( nick, para, s : string ) : string;
         function  SpaceX : string;
         function  Synonyms( s : string ) : string;
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
        property    Started : integer read fJoined;
        property    Version : string write fVersion;
        property    UserName : string write fUserName;
    end;  // tIRC


var
  fIRC : tIRC;


implementation


  uses
    DateUtils,
    fpOPENSSL,
    OpenSSL,
    sConsole,
    sNote,
    sProfile,
    sWeather,
    httpsend,
    JSONParser,
    Process,
    synacode,
    StrUtils,
    SysUtils;


  const
    CR   : string = #13;
    LF   : string = #10;
    CRLF : string = #13 + #10;

    
  constructor tIRC.Create;
    // create IRC thread
  begin
    inherited Create( TRUE );
    fBall8     := TStringList.Create;
    fHTTP      := TfpHTTPClient.Create( NIL );
    fJoined    := 0;
    fOkToEcho  := FALSE;
    fPingLast  := Now;
    fNote      := tNote.Create;
    fOps       := TStringList.Create;
    fPending   := ''; 
    fSock      := tSock.Create;
    fTimeout   := -1;
    InitCriticalSection( fCritical );
    fHTTP.HTTPVersion    := '1.1';
    fHTTP.KeepConnection := FALSE;
    fHTTP.MaxRedirects   := 3;
  end;  //  tIRC.Create 
  
  
  destructor tIRC.Destroy;
    // Shoot down thread and frieds
  begin
    try
      fBall8.Free;
      fHTTP.Free;
      fNote.Free;
      fOps.Free;
      if assigned( fSock ) then fSock.Free;
    except
    end;
    DoneCriticalSection( fCritical );
    inherited Destroy;
  end;  // tIRC.Destroy


  procedure tIRC.Execute;
    // Main loop
  var
    Comm  : string;       // Command in server response
    Nick  : string;       // Nick in server response
    Para  : string;       // Parameter part of response
    sHost : string;
    sTime : TDateTime;
    tTime : TDateTime;
    i     : integer;
    s     : string;
    t     : string;
  begin
    randomize;
    sTime := Now;
    Login;
    while ( fSock.Error = 0 ) and not Terminated do begin           // Chat loop 
      if fSock.RecvStr( s ) then begin                              // Get stuff
        t := uppercase( s );
        if fOkToEcho and ( ( pos( 'HTTP://', t ) > 0 ) or ( pos( 'HTTPS://', t ) > 0 ) ) then HTTPEcho( s );    // HTTP echo function
        if fJoined = 2 then begin                                   // When RPL_ENDOFMOTD and  
          inc( fJoined );
          t := 'Morning, ' + fUsername + ' v' + fVersion + ' here.';
          MsgChat( t );
          fCon.Send( t, taBold );
        end;
        s := trim( ReplaceStr( s, #01, '~' ) );                     // Change CTCP marks
        s := ReplaceStr( s, CR, '' );
        s := ReplaceStr( s, LF, '' );
        if ( length( s ) > 0 ) and ( s[ length( s ) ] = '~' ) then s := copy( s, 1, length( s ) - 1 );
        if ( s <> '' ) and ( s[ 1 ] = ':' ) then begin
          s    := trim( copy( s, 2, length( s ) ) );                // Remove leading :
          Nick := trim( copy( s, 1, pos( '!', s ) - 1 ) );          // Extract Nick
          s    := copy( s, pos( ' ', s ) + 1, length( s ) );        // Remove rest of address
          Comm := uppercase( trim( copy( s, 1, pos( ' ', s ) - 1 ) ) );     // Extract command
          Para := trim( copy( s, pos( ' ', s ) + 1, length( s ) ) );        // Extract parameter
        end else begin
          Nick := '';
          Comm := trim( copy( s, 1, pos( ' ', s + ' ' ) ) );
          Para := trim( copy( s, pos( ' ', s + ' ') + 1, length( s ) ) );
        end;
        case Comm of  // process message
          '001'     : s := 'Logged in as ' + fUserName;                                     // 001 RPL_WELCOME
          '002'     : begin                                                                 // 002 RPL_YOURHOST
                        sHost := copy( s, pos( ':', s ) + 14,  length( s ) );
                        s     := 'Host: ' + sHost;
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
          '332'     : s := copy( s, pos( ':', s ) + 1, length( s ) );                       // 332 RPL_TOPIC
          '333'     : s := '';                                                              // 333 RPL_TOPICWHOTIME
          '351'     : s := '';                                                              // 351 RPL_VERSION
          '353'     : begin                                                                 // 353 RPL_NAMREPLY
                        s := copy( Para, pos( ':', Para ) + 1, length( Para ) );
                        Nicks( s );
                        s := 'Nicks: ' + s;
                      end;
          '366'     : s := '';                                                              // 366 RPL_ENDOFNAMES
          '372'     : s := trim( copy( Para, pos( ':', Para ) + 2, length( Para ) ) );      // 372 RPL_MOTD
          '373'     : s := Para;                                                            // 373 RPL_INFOSTART
          '375'     : s := '';                                                              // 375 RPL_MOTDSTART
          '376'     : begin                                                                 // 376 RPL_ENDOFMOTD
                        s := '';
                        inc( fJoined );
                      end;
          '401'     : begin                                                                 // 401 ERR_NOSUCHNICK
                        s := Nick + ' No such nick/channel';
                        MsgChat( s );
                      end;
          '433'     : begin                                                                 // ERR_NICKNAMEINUSE
                        fUserName := fUsername + '_';
                        fPending := 'Nick changed to ' + fUserName;
                        Login;
                      end;
          '486'     : s := '';                                                              // 486 
          'ERROR'   : begin
                        s := 'Socket error; closing ' + Para;
                        Self.Terminate;
                      end;
          'JOIN'    : begin
                        fCon.Send( Nick + ' joined ' + fChannel, taNormal );
                        if uppercase( Nick ) = uppercase( fUserName ) then begin
                          inc( fJoined );
                        end;
                        while fNote.Check( Nick ) do begin
                          s := fNote.Fetch( Nick );
                          if length( trim( s ) ) > 0 then MsgChat( Nick + ' ' + s );
                        end;
                        s := '';
                      end;
          'MODE'    : begin
                        s := 'Mode set to ' + copy( Para, pos( ':', Para ) + 1, length( Para ) ) ;
                        MsgSend( 'JOIN ' + fChannel );
                        fCon.Send( fUserName + '> JOIN ' + fChannel, taBold );
                      end;
          'NOTICE'  : begin
                        s := '';
                        if pos( '~TIME ', uppercase( Para ) ) > 0 then begin
                          s := Nick + ': ' + copy( Para, pos( ':', Para ) + 2, length( Para ) );
                          if pos( '~TIME ', uppercase( Para ) ) > 0 then MsgChat( s );
                        end else s := copy( Para, pos( ':', Para ) + 1, length( Para ) );
                      end;
          'PART'    : s := Nick + ' parted ' + fChannel;
          'PING'    : begin
                         fCon.Send( s, taNormal );
                         fCon.Send( fUserName + ': PONG', taBold );
                         MsgSend( 'PONG' );
                         s := '';
                      end;
          'PRIVMSG' : begin
                        Comm := trim( copy( Para, pos( ':' , Para ) + 1, length( Para ) ) );
                        Para := trim( copy( Comm, pos( ' ', Comm + ' ' ) + 1, length( Comm ) ) );
                        s    := copy( s, pos( ':', s ) + 1, length( s ) );
                        if pos( ' ', Comm ) <> 0 then Comm := copy( Comm, 1, pos( ' ', Comm ) - 1 );
                        Comm := ReplaceStr( Comm, #01, '' );                                       // Remove CTCP marks
                        Comm := uppercase( Comm );
                        if Comm[ length( Comm ) ] = ',' then Comm := copy( Comm, 1, length( Comm ) - 1 );
                        if ( length( Comm ) > 0 ) and ( Comm[ 1 ] <> '~' )
                          then fCon.Send( nick + '> ' + s , taNormal );
                        case Comm of
                          '.8BALL'    : begin
                                          s := Shao( nick, para, s );
                                          MsgChat( s );
                                          s := fUserName + '> ' + s;
                                        end;
                          '.ANAGRAM'  : begin
                                          if length( Para ) > 0 then begin
                                            if pos( ' ', Para ) > 0
                                              then Para := copy( Para, 1, pos( ' ', Para ) - 1 );
                                            try
                                              s     := fHTTP.Get( 'http://www.anagramica.com/all/' + EncodeURL( Para ) );
                                              fJSON := GetJSON( s );
                                              s     := Para + ' is ' + fJSON.FindPath( 'all[0]' ).AsString;
                                            except
                                              on E : Exception do s := 'Get real!';
                                              on E : EJSON     do s := 'Get real!';
                                            end;
                                          end else s := 'usage - .Anagram <word>';
                                          s := 'Anagram: ' + s;
                                          MsgChat( s );
                                          s := Nick  + '> ' + s;
                                        end;
                          '.DEFINE'   : begin
                                          if length( Para ) > 0 then begin
                                            s := 'Define ' + Para + ': ' + Define( Para ); 
                                          end else s := 'Define: Usage - .Define <word>';
                                          MsgChat( s );
                                          s := Nick  + '> ' + s;
                                        end;
                          '.DOF'      : begin
                                          MsgChat( 'https://www.pointsinfocus.com/tools/depth-of-field-and-equivalent-lens-calculator' );
                                          MsgChat( 'https://dofsimulator.net/en/' );
                                          s := fUserName + '> Sent DoF URLs';
                                        end;
                          '.HELP'     : begin
                                          s := 'Help https://github.com/coraxyn/ShaoB/wiki/Commands';
                                          MsgChat( s );
                                          fPending := fUsername + '> ' + s;
                                          s := Nick + '> .HELP';
                                        end;
                          '.HOST'     : begin
                                          s := Nick + '> .Host';
                                          MsgChat( 'Host: ' + sHost );
                                          fPending := fUserName + '> Host: ' + sHost;
                                        end;
                          '.LAUNCH'   : begin
                                          s := Launch;
                                          MsgChat( s );
                                          s := fUserName + '> ' + s;
                                        end;
                          '.NOTE'     : begin
                                          if length( trim( para ) ) > 0 
                                            then s := fNote.Note( Nick, para )
                                            else s := 'Usage: .Note <nick> <message>';
                                          MsgChat( s );
                                          s := fUserName + '> ' + s;
                                        end;
                          '.OPS'      : begin
                                          try
                                            fOps.LoadFromFile( 'shao.ops' );
                                            s := '';
                                            for i := 1 to fOps.Count do begin
                                              if length( s ) > 0 then s := s + ', '; 
                                              s := s + fOps.Strings[ i - 1 ];
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
                                          s := fUserName + '> ' + s;
                                        end;
                          '.SHAO'     : begin
                                          s := Shao( nick, para, s );
                                          MsgChat( s );
                                          s := fUserName + '> ' + s;
                                        end;
                          '.SPACEX'   : begin
                                          s := SpaceX;
                                          MsgChat( s );
                                          s := fUserName + '> ' + s;
                                        end;
                          '.SYNONYMS' : begin
                                          if length( Para ) > 0 
                                            then s := Synonyms( Para )
                                            else s := 'usage - .Synonyms <word>';
                                          s := 'Synonyms: ' + s;
                                          MsgChat( s ); 
                                          s := fUserName + '> ' + s;
                                        end;
                          '.TIME'     : begin
                                          if length( Para ) > 0 then begin
                                            if uppercase( Para ) = fUsername then begin
                                              DateTimeToString( s, 'ddd mmm dd ', Date );
                                              DateTimeToString( t, 'hh:mm:ss:zzz', Time );
                                              s := s + t;
                                            end else MsgSend( 'PRIVMSG ' + Para + ' :' + #01 + 'time' + #01 );
                                            MsgSend( s );
                                            fPending := fUserName + '> ' + s;
                                            s := '';
                                          end else begin
                                            MsgChat( 'Usage .Time nick' );
                                            s := fUserName + '> Usage .Time nick';
                                          end;
                                        end;
                          '.UP'       : begin
                                          tTime := Now;
                                          s := 'Up time: ' + IntToStr( DaysBetween( tTime, sTime ) ) + ' days ' + 
                                               FormatDateTime('h" hrs, "n" min, "s" sec"', tTime - sTime );
                                          MsgChat( s );
                                          s:= fUsername + '> ' + s;
                                        end;
                          '.VERSION'  : begin
                                          MsgChat( 'Version ' + fVersion );
                                          s:= fUserName + '> Version ' + fVersion;
                                        end;
                          '.WEATHER'  : begin
                                        //  if uppercase( fChannel ) <> '#PHOTOGEEKS' then begin
                                            s := fWeather.Command( nick, para );
                                            MsgChat( s );
                                            s := fUsername + '> ' + s;
                                       //   end else s := fUsername + '> hidden weather';
                                        end;
                          '.WIKI'     : begin
                                          if length( Para ) > 0 
                                            then s := 'Wiki: ' + Wiki( para )
                                            else s := 'Wiki: Usage - .Wiki <word | phrase>';
                                          MsgChat( s );
                                          s := fUserName  + '> ' + s;
                                        end;
                          '~ACTION'   : begin
                                          s := copy( s, pos( ' ', s ) + 1, length( s ) );
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
                                          MsgSend( '' );
                                          fCon.Send( fUsername + '> ' + s, taBold );
                                          s := '';
                                        end;
                          else s := '';
                        end;  // PRIVMSG case
                      end;  // PRIVMSG
          else s := Nick + '> ' + s;
       end;  // Case process messages
       if length( s ) > 0 then begin                                     // Write out normal message to console
         if copy( s, 1, length( fUsername ) ) = fUserName
           then fCon.Send( s, taBold )
           else fCon.Send( s, taNormal );
         if copy( s, 1, 6 ) = 'Nicks:' then fOkToEcho := TRUE;
       end;
       if length( fPending ) > 0                                         // Write out any pending message
         then if copy( s, 1, length( fUserName ) ) = fUserName
                then fCon.Send( fPending, taBold )
                else fCon.Send( fPending, taNormal );
       if pos( '> ', s ) > 0 then begin                                  // Write out .Note message for  
         t := leftStr( s, pos( '> ', s ) - 1 ); 
         t := fNote.Fetch( t );                                
         if length( t ) > 0 then begin
           fCon.Send( fUserName + '> ' + Nick + ' ' + t, taBold );
           MsgChat( Nick + ' ' + t );
         end;
       end;
       if ( MinutesBetween( Now, fPingLast ) > 5 ) and not ( assigned( fSock.Socket ) ) then begin // Check if still logged in
         fCon.Send( 'Login attempt', taBold );
         Login;
         fPingLast := Now;
       end;
       s := '';
       fPending := '';
      end;  // if fSock.DataWaiting
      if fSock.Error <> 0 then begin
        if fSock.ErrorMsg = 'Connection timed out'
          then fSock.ErrorClear
          else fCon.Send( fSock.ErrorMsg, taBold );
      end;
      sleep( 20 );
    end;  // while
    if fSock.Connected then MsgSend( 'QUIT Laters :)' );
    fCon.Send( 'IRC link ended', taNormal );
  end;  // tIRC.Execute
  
  
  function tIRC.Define( s : string ) : string;
  var
    i : integer; 
  begin
    try
      fHTTP.AddHeader( 'APP_ID',  fOEDAppID );
      fHTTP.AddHeader( 'APP_KEY', fOEDKey );
      s := fHTTP.Get( 'https://od-api.oxforddictionaries.com/api/v1/entries/en/' + Lowercase( EncodeURL( s ) ) );
      if fHTTP.ResponseStatusCode = 200 then begin
        fJSON := GetJSON( s );
        s := fJSON.FindPath( 'results[0].lexicalEntries[0].entries[0].senses[0].definitions[0]' ).AsString;
     end else s := 'Not found';
   except
     on E : Exception do s := 'Not found';
     on E : EJSON     do s := 'Not found';
   end;
   with fHTTP do begin
     i := IndexOfHeader( 'APP_ID' );
     if i <> -1 then RequestHeaders.Delete( i ); 
     i := IndexOfHeader( 'APP_KEY' );
     if i <> -1 then RequestHeaders.Delete( i ); 
   end;
    Result := s;
  end;  // tIRC.Define


  procedure tIRC.HTTPEcho( s : string );
    // Echo details of HTTP string in channel
  const
    Unsafe    = ' "<>#%{}|\^~[]`' + #13;
    HTMLChars = [ '0'..'9', 'a'..'z', 'A'..'Z', ' ', '!', '$', '+', '-', '(', ')', '@', '<', '>' ];
  var 
    i  : integer;
    j  : integer;
  begin
    i := pos( 'HTTPS://', uppercase( s ) );                                       // Get start in t of URL
    if i = 0 then i := pos( 'HTTP://', uppercase( s ) );                          // Find start of URL
    if i > 0 then begin
      j := i + 3;
      while ( j <= length( s ) ) and ( pos( s[ j ], Unsafe ) = 0 ) do inc( j );   // find end of URL
      try
        s := fHTTP.Get( trim( copy( s, i, j - i ) ) );                            // Get page content
writeln( s );
      except
        on E : Exception do begin
          s := '';
          fPending := fUsername + '> HTTPEcho: ' + E.Message + '/' + E.ClassName;
        end;
        on E : EHTTPClient do begin
          s := '';
          fPending := fUserName + '> HTTPEcho: ' + E.Message + '/' + E.ClassName;
        end;
      end;
      if length( s ) > 0 then begin
        i := ( pos( '<title>', s ) + 1 ) * ( pos( '<TITLE>', s ) + 1 ) + 6;       // Find <TITLE> tag
        j := ( pos( '</title>', s ) + 1 ) * ( pos( '</TITLE>', s ) + 1 ) - 1;
        s := trim( copy( s, i, j - i ) );
        if length( s ) > 130 then s := copy( s, 1, 130 );                         // <title> too long
        for i := 1 to length( s ) do if not ( s[ i ] in HTMLChars ) then s[ i ] := ' ';  // Clean out any bad chars
        if length( s ) > 0 then begin
          MsgChat( s );
          fPending := fUserName + '> ' + s;
        end else begin
          s := 'URLEcho: Invalid <title> found';
          MsgChat( s );
          fPending := fUserName +  '> ' + s;
        end;
      end else begin
        s := 'URLEcho: No <title> from URL';
        MsgChat( s );
        fPending := fUserName + '> ' + s;
      end;
    end;
  end;  // tIRC.HTTPEcho


  function tIRC.Launch : string;
    // Details next launch (world-wide). ln is launch number
  var
    s    : string;
  begin
    try
      s     := fHTTP.Get( 'https://launchlibrary.net/1.3/launch/next/1' );
      fJSON := GetJSON( s );
      s     := fJSON.FindPath( 'launches[0].name' ).AsString +
               ' on ' + fJSON.FindPath( 'launches[0].net' ).AsString +
               ' from ' + fJSON.FindPath( 'launches[0].location.name' ).AsString +
               ' : ' + fJSON.FindPath( 'launches[0].missions[0].description' ).AsString;
    except
      s := 'We have an anomoly';
    end;
    Launch := 'Launch: ' + s;
  end;  // tIRC.Launch

  
  function tIRC.Login : boolean;
    // Login
  var
    b : boolean;
    s : string;
  begin
    b := FALSE;
    if not fSock.Connected then begin
      fCon.Send( 'Logging in',taNormal );  // Log in
      if fSock.Connect( fNetwork, strToIntDef( fPort, 80 ) ) then begin
        fCon.Send( 'Connected to ' + fNetwork + ' port ' + fPort, taNormal );
        b := TRUE;
        fCon.Send( 'Waiting', taNormal );
        sleep( 2000 );
      end else fCon.Send( 'Connect error ' + fSock.ErrorMsg, taBold );
    end;
    if fSock.Connected then begin
      fCon.Line1( fUsername + ' ' + fVersion );
      s := 'NICK ' + fUserName;
      MsgSend( s );
      if b then begin
        fCon.Send( fUserName + ': ' + s, taBold );
        s := 'USER ' + fUserName + ' * * :' + fUserName;
        MsgSend( s );
        fCon.Send( fUserName + ': ' + s, taBold );
      end;
    end;
    Login := assigned( fSock.Socket );
  end;  // tIRC.Login

  
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
    fSock.Send( s + CRLF );
  end;  // tIRC.MsgSend
  

  procedure tIRC.Nicks( s : string );
    // Scan nick s on join and sends appropriate messages, if any
  var
    t : string;
    u : string;
  begin
    s := trim( s );
    while length( s ) > 0 do begin
      t := copy( s, 1, pos( ' ', s + ' '  ) - 1 );
      s := copy( s, pos( ' ', s + ' ' ) + 1, length( s ) );
      if length( t ) > 0 then begin
        if pos( t[ 1 ], '@+!' ) > 0 then t := rightStr( t, length( t ) - 1 );
        while fNote.Check( t ) do begin
          u := fNote.Fetch( t );
          if length( trim( u ) ) > 0 then begin
            MsgChat( t + ' ' + u );
            fCon.Send( fUserName + '> ' + t + ' ' + u, taBold );
          end;
        end;  // while
      end;  // if length
    end;  // while
  end;  // tIRC.Nicks


  function tIRC.Shao( nick, para, s : string ) : string;
    // .Shao and .8Ball commands
  begin
    if length( para ) > 0 then begin
      fBall8.LoadFromFile( 'shao.8ball' );
      s := fBall8[ random( fBall8.Count ) ];
      if random( 10 ) = 4 then s := s + ', ' + Nick;
    end else s := 'Need something to work with';
    Shao := s;
  end;  // fIRC.Shao


  function tIRC.SpaceX : string;
    // Returns next planned launch of SpaceX
  var
    i : integer;
    s : string;
    t : string;
  begin
    if RunCommandInDir( '', 'curl "https://api.spacexdata.com/v3/launches/next"', s ) then begin
      fJSON := GetJSON( s );
      s     := fJSON.FindPath( 'mission_name' ).AsString;
      t     := copy( fJSON.FindPath( 'launch_date_utc' ).AsString, 1, 16 );
      s     := s + ' on ' + replaceStr( t, 'T', ' ' );
      s     := s + ' from ' + fJSON.FindPath( 'launch_site.site_name_long' ).AsString;
      s     := s + ' using ' + fJSON.FindPath( 'rocket.rocket_name' ).AsString;
      s     := s + '. ' + fJSON.FindPath( 'details' ).AsString;
      i := length( s );
      if i > 400 then begin
        s := copy( s, 1, 400 );
        while ( i > 0 ) and ( s[ i ] <> '.' ) do dec( i );
        if i > 0
          then s := copy( s, 1, i )
          else s := 'We have an anomoly';
      end;
    end else s := 'We have an anomoly';
    SpaceX := 'SpaceX : ' + s;
  end;  // tIRC.SpaceX
  

  function tIRC.Synonyms( s : string ) : string;
    // Returns synonyms as comma delimited string
  var
    i    : integer;
    jDat : TJSONData;
  begin
    try
      fHTTP.AddHeader( 'APP_ID',  fOEDAppID );
      fHTTP.AddHeader( 'APP_KEY', fOEDKey );
      s     := fHTTP.Get( 'https://od-api.oxforddictionaries.com/api/v1/entries/en/' + Lowercase( EncodeURL( s ) ) + '/synonyms' );
      fJSON := GetJSON( s );
      fJSON := fJSON.FindPath( 'results[0].lexicalEntries[0].entries[0].senses[0].synonyms' );
      i     := 0;
      s     := '';
      while ( i < fJSON.Count ) and ( length( s ) < 350 ) do begin
        jDat := fJSON.Items[ i ];
        if length( s ) = 0
          then s := jDat.FindPath( 'text' ).AsString
          else s := s + ', ' + jDat.FindPath( 'text' ).AsString;
        inc( i );
      end;
      if length( s ) = 0 then s := 'Not found';
    except
      on E : Exception do s := E.Message;
      on E : EJSON     do s := 'Not found';
    end;
    with fHTTP do begin
      i := IndexOfHeader( 'APP_ID' );
      if i <> -1 then RequestHeaders.Delete( i ); 
      i := IndexOfHeader( 'APP_KEY' );
      if i <> -1 then RequestHeaders.Delete( i ); 
    end;
    Result := s;
  end;  // tIRC.Synonyms }
    

  function tIRC.Wiki( s: string ) : string;
    // Returns Wiki extract of s
  var
    i : integer;
  begin
    try
      s := fHTTP.Get( 'https://en.wikipedia.org/w/api.php?format=json&action=query&prop=extracts&exintro&explaintext&redirects=1&titles=' + EncodeURL( s ) );
      fJSON := GetJSON( s );
      fJSON := fJSON.FindPath( 'query.pages' );
      fJSON := fJSON.Items[ 0 ];
      s     := fJSON.FindPath( 'extract' ).AsString;
      s     := ReplaceStr( s, '\n\n', '' );
      s     := ReplaceStr( s, '\n', '' );
      s     := ReplaceStr( s, '#13', '' );
      if length( s ) > 350 then begin
        s := copy( s, 1, 350 );
        i := 350;
        while ( i > 0 ) and ( s[ i ] <> '.' ) do dec( i );
        s := copy( s, 1, i );
      end;
    except
      on E : EJSONParser do s := E.Message;
      on E : Exception   do s := 'Not found';
    end;
    result := s;
  end;  // tIRC.Wiki


end.  // sIRC 
