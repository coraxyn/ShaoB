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
    fpJSON,
    sCurl,
    sSock;


  type
  
  
    tIRC = class( TThread )
      private
         fBall8     : TStringList;
         fAPIXU     : string;
         fChannel   : string;
         fCritical  : TRTLCriticalSection;                      // Main thread may write at same time
         fIndex     : TStringList;
         fJoined    : boolean;
         fJSON      : TJSONData;
         fOEDAppID  : string;
         fOEDKey    : string;
         fOps       : TStringList;
         fNetwork   : string;
         fNoticeOk  : boolean;                                  // If true send notices to channel ( as in .info )
         fPassword  : string;
         fPending   : string;                                   // Message waiting for fLog.send
         fPingLast  : TDateTime;
         fPort      : string;
         fSocket    : tSock;
         fTimeout   : integer;
         fVersion   : string;
         fUserName  : string;
         function  Define( s : string ) : string;
         procedure IndexMake;
         function  Launch : string;
         function  Login : boolean;
         procedure Nicks( s : string );
         function  Shao( para, nick : string ) : string;
         function  SpaceX : string;
         function  Synonyms( s : string ) : string;
         procedure URLEcho( s : string );
         function  Wiki( s : string ) : string;
         function  WikiFp(aSearch: string): string;
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
        property    Pending : string write fPending;
        property    Port : string write fPort;
        procedure   Shutdown;
        property    Started : boolean read fJoined;
        property    Version : string write fVersion;
        property    UserName : string write fUserName;
    end;  // tIRC


var
  fIRC : tIRC;


implementation


  uses
    DateUtils,
    JSONParser,
    sConsole,
    sNote,
    sProfile,
    sQuake,
    sWeather,
    StrUtils,
    SysUtils;


  const
    CR   : string = #13;
    LF   : string = #10;
    CRLF : string = #13 + #10;


  type
    tIndex = ( id8Ball, idAnagram, idAurora, idDefine, idDoF, idHelp, idHost, idInfo, idLaunch, idNote, idOps, idPodcast,
               idProfile, idQuit, idRAP, idShao, idSpacex, idSunspots, idSynonyms, idTime, idTopic, idUp, idVersion, idWeather, idWiki, idWikiFp,
               idCAction, idCTime, idCVersion,
               id001, id002, id003, id004, id005, id250, id251, id252, id253, id254, id255, 
               id265, id266, id328, id332, id333, id351, id353, id366, id372, id373, id375, 
               id376, id401, id433, id451, id486,
               idError, idJoin, idMode, idNotice, idPart, idPing, idPrivMsg, idSQuit );

    
  function URLEncode( s : string ) : string;
    //  Make sure URL has safe chars
  const
    SafeChars = ['A'..'Z', '0'..'9', 'a'..'z', '*', '@', '.', '_', '-'];
  var
    i : integer;
    t : string;
  begin
    t := '';
    for i := 1 to Length( s ) do begin
      if s[ i ] in SafeChars 
        then  t := t + s [ i ]
        else if s[ i ]= ' ' 
              then t := t + '+'
              else t := t + '%' + intToHex( ord( s [ i ] ), 2 );
    end;
    URLEncode := t;
  end;  // URLEncode

  
  constructor tIRC.Create;
    // create IRC thread
  begin
    inherited Create( TRUE );
    fBall8     := TStringList.Create;
    fIndex     := TStringList.Create;
    fJoined    := FALSE;
    fNoticeOk  := FALSE;
    fPingLast  := Now;
    fOps       := TStringList.Create;
    fPending   := ''; 
    fSocket    := tSock.Create;
    fTimeout   := -1;
    InitCriticalSection( fCritical );
    IndexMake;
  end;  //  tIRC.Create 
  
  
  destructor tIRC.Destroy;
    // Shoot down thread and frieds
  begin
    try
      fBall8.Free;
      fIndex.Free;
      fOps.Free;
      if assigned( fSocket) then fSocket.Free;
    except
    end;
    DoneCriticalSection( fCritical );
    inherited Destroy;
  end;  // tIRC.Destroy


  procedure tIRC.Execute;
    // Main loop
  var
    Comm    : string;       // Command in server response
    CommIdx : integer;      // Index number of command
    Nick    : string;       // Nick in server response
    Para    : string;       // Parameter part of response
    sHost   : string;       // Host actually connected to
    sTime   : TDateTime;    // Date & time Shao woke up
    tTime   : TDateTime;
    i       : integer;
    sRecv   : string;
    t       : string;
  begin
    randomize;
    sTime := Now;
    Login;
    while ( fSocket.Error = 0 ) and not Terminated do begin         // Chat loop
      fSocket.RecvStr( sRecv );                                     // Get stuff
      sRecv := trim( sRecv );
      if length( sRecv ) > 0 then begin
        sRecv := trim( ReplaceStr( sRecv , #01, '/' ) );            // Change CTCP marks
        sRecv := ReplaceStr( sRecv , CR, '' );
        sRecv := ReplaceStr( sRecv , LF, '' );
        if ( length( sRecv  ) > 0 ) and ( sRecv [ length( sRecv  ) ] = '/' ) then sRecv  := copy( sRecv , 1, length( sRecv  ) - 1 );
        if ( sRecv  <> '' ) and ( sRecv [ 1 ] = ':' ) then begin   
          sRecv     := trim( copy( sRecv , 2, length( sRecv  ) ) );                              // Remove leading :
          Nick := trim( copy( sRecv , 1, pos( '!', sRecv  ) - 1 ) );                             // Extract Nick
          sRecv     := copy( sRecv , pos( ' ', sRecv  ) + 1, length( sRecv  ) );                 // Remove rest of address
          Comm := uppercase( trim( copy( sRecv , 1, pos( ' ', sRecv  ) - 1 ) ) );                // Extract command
          Para := trim( copy( sRecv , pos( ' ', sRecv  ) + 1, length( sRecv  ) ) );              // Extract parameter
        end else begin
          Nick := '';
          Comm := trim( copy( sRecv , 1, pos( ' ', sRecv  + ' ' ) ) );
          Para := trim( copy( sRecv , pos( ' ', sRecv  + ' ') + 1, length( sRecv  ) ) );
        end;
        if fIndex.Find( Comm, CommIdx ) then case tIndex( CommIdx ) of  // process message
          id001     : sRecv  := 'Logged in as ' + fUserName;                                     // 001 RPL_WELCOME
          id002     : begin                                                                      // 002 RPL_YOURHOST
                        sHost := copy( sRecv , pos( ':', sRecv  ) + 14,  length( sRecv  ) );
                        sRecv      := 'Host: ' + sHost;
                      end;
          id003     : sRecv  := '';                                                              // 003 RPL_CREATED
          id004     : sRecv  := '';                                                              // 004 RPL_MYINFO
          id005     : sRecv  := '';                                                              // 005 RPL_ISUPPORT
          id250     : sRecv  := '';                                                              // 250 
          id251     : sRecv  := '';                                                              // 251 RPL_LUSERCLIENT
          id252     : sRecv  := '';                                                              // 252 RPL_LUSEROP
          id253     : sRecv  := '';                                                              // 253 RPL_LUSERUNKNOWN
          id254     : sRecv  := '';                                                              // 254 RPL_LUSERCHANNELS
          id255     : sRecv  := '';                                                              // 255 RPL_LUSERME
          id265     : sRecv  := '';                                                              // 265 RPL_LOCALUSERS
          id266     : sRecv  := '';                                                              // 266 RPL_GLOBALUSERS
          id328     : sRecv  := '';
          id332     : if fJoined then begin                                                                      // 332 RPL_TOPIC
                        sRecv  := copy( sRecv , pos( ':', sRecv  ) + 1, length( sRecv  ) );
                        MsgChat( sRecv  );
                        sRecv  := fUserName + '> ' + sRecv ;
                      end;
          id333     : sRecv  := '';                                                              // 333 RPL_TOPICWHOTIME
          id351     : sRecv  := '';                                                              // 351 RPL_VERSION
          id353     : begin                                                                      // 353 RPL_NAMREPLY
                        sRecv  := copy( Para, pos( ':', Para ) + 1, length( Para ) );
                        Nicks( sRecv  );
                        sRecv  := 'Nicks: ' + sRecv ;
                      end;
          id366     : begin                                                                      // 366 RPL_ENDOFNAMES
                        sleep( 1000 ); // because.....
                        sRecv  := '';
                        fJoined := TRUE;
                        t := 'Morning, ' + fUsername + ' v' + fVersion;
                        MsgChat( t );
                        fCon.Send( fUserName + '> ' + t, taBold );
                        fQuake.Run;
                      end;
          id372     : sRecv  := trim( copy( Para, pos( ':', Para ) + 2, length( Para ) ) );      // 372 RPL_MOTD
          id373     : sRecv  := Para;                                                            // 373 RPL_INFOSTART
          id375     : sRecv  := '';                                                              // 375 RPL_MOTDSTART
          id376     : sRecv  := '';
          id401     : begin                                                                      // 401 ERR_NOSUCHNICK
                        sRecv  := Nick + ' No such nick/channel';
                        MsgChat( sRecv  );
                      end;
          id433     : begin                                                                      // 433 ERR_NICKNAMEINUSE
                        fUserName := fUsername + '_';
                        fPending := 'Nick changed to ' + fUserName;
                        Login;
                      end;
          id451     : sRecv  := 'Not registered';
          id486     : sRecv  := '';                                                              // 486 
          idError   : begin                                                                      // ERROR
                        sRecv  := 'Socket error; closing ' + Para;
                        Self.Terminate;
                      end;
          idInfo    : begin
                        sRecv  := '';
                      end;
          idJoin    : begin                                                                      // JOIN
                        fCon.Send( Nick + ' joined ' + fChannel, taNormal );
                        while fNote.Check( Nick ) do begin
                          sRecv  := fNote.Fetch( Nick );
                          if length( trim( sRecv  ) ) > 0 then MsgChat( Nick + ' ' + sRecv  );
                        end;
                        sRecv  := '';
                      end;
          idMode    : begin                                                                      // MODE
                        sRecv  := 'Mode set to ' + copy( Para, pos( ':', Para ) + 1, length( Para ) ) ;
                        MsgSend( 'JOIN ' + fChannel );
                        fCon.Send( fUserName + '> JOIN ' + fChannel, taBold );
                      end;
          idNotice  : begin                                                                      // NOTICE
                        if pos( '/TIME ', uppercase( Para ) ) > 0 then begin
                          sRecv  := Nick + ': ' + copy( Para, pos( ':', Para ) + 2, length( Para ) );
                          if pos( '/TIME ', uppercase( Para ) ) > 0 then MsgChat( sRecv  );
                        end else sRecv  := copy( Para, pos( ':', Para ) + 1, length( Para ) );
                        if fJoined and fNoticeOk then begin
                          sRecv  := 'Notice: ' + sRecv ;
                          if pos( '***', sRecv  ) = 0 
                            then MsgChat( sRecv  )
                            else fNoticeOk := FALSE;
                        end else sRecv := '';
                      end;
          idPart    : sRecv  := Nick + ' parted ' + fChannel;                                    // PART
          idPing    : begin                                                                      // PING
                         fCon.Ping;
                         MsgSend( 'PONG' );
                         sRecv  := '';
                      end;
          idPrivMsg : begin                                                                      // PRIVMSG
                        Comm := trim( copy( Para, pos( ':' , Para ) + 1, length( Para ) ) );     // Extract command
                        Para := trim( copy( Comm, pos( ' ', Comm + ' ' ) + 1, length( Comm ) ) );// extract parameters
                        sRecv     := copy( sRecv , pos( ':', sRecv  ) + 1, length( sRecv  ) );                               // s now contains line minus source address
                        if pos( ' ', Comm ) <> 0 then Comm := copy( Comm, 1, pos( ' ', Comm ) - 1 );     // clean up command
                        Comm := ReplaceStr( Comm, #01, '' );                                             // Remove CTCP marks
                        Comm := uppercase( Comm );
                        if Comm[ length( Comm ) ] = ',' then Comm := copy( Comm, 1, length( Comm ) - 1 );// There may be comma at end of cammand
                        if ( length( Comm ) > 0 ) and ( Comm[ 1 ] <> '/' )
                          then sRecv  := nick + '> ' + sRecv ;
                        t := uppercase( sRecv  );
                        if fJoined and ( ( pos( 'HTTP://', t ) > 0 ) or ( pos( 'HTTPS://', t ) > 0 ) ) then URLEcho( sRecv  );    // HTTP echo function
                        if fIndex.Find( Comm, CommIdx ) then case tIndex( CommIdx ) of
                          id8Ball      : begin  // .8Ball
                                           t := Shao( para, Nick );
                                           MsgChat( t );
                                           fPending := fUserName + '> ' + t;
                                        end;
                          idAnagram   : begin  // .Anagram
                                          if length( Para ) > 0 then begin
                                            if pos( ' ', Para ) > 0
                                              then Para := copy( Para, 1, pos( ' ', Para ) - 1 );
                                            t  := fCurl.Get( 'http://www.anagramica.com/all/' + URLEncode( Para ) );
                                            try
                                              fJSON := GetJSON( t );
                                              t     := Para + ' is ' + fJSON.FindPath( 'all[0]' ).AsString;
                                            except
                                              on E : Exception do sRecv  := 'Get real!';
                                            end;
                                          end else sRecv  := 'usage - .Anagram <word>';
                                          MsgChat( 'Anagram: ' + t  );
                                          fPending := Nick  + '>Anagram: ' + t;
                                        end;
                          idAurora    : begin
                                          MsgChat( 'Northern hemisphere: https://services.swpc.noaa.gov/images/aurora-forecast-northern-hemisphere.jpg' );
                                          MsgChat( 'Southern hemisphere: https://services.swpc.noaa.gov/images/aurora-forecast-southern-hemisphere.jpg' );
                                          fPending := fUserName + ' Aurora URLs sent to channel';
                                        end;
                          idDefine    : begin  // .Define
                                          if length( Para ) > 0 then begin
                                            t := 'Define ' + Para + ': ' + Define( Para ); 
                                          end else t := 'Define: Usage - .Define <word>';
                                          MsgChat( t );
                                          fPending := fUserName + '> ' + t;
                                        end;
                          idDoF       : begin  // .DOF
                                          MsgChat( 'https://www.pointsinfocus.com/tools/depth-of-field-and-equivalent-lens-calculator' );
                                          MsgChat( 'https://dofsimulator.net/en/' );
                                          fPending := fUserName + '> Sent DoF URLs';
                                        end;
                          idHelp      : begin  // .Help
                                          t := 'Help https://github.com/coraxyn/ShaoB/wiki/Commands';
                                          MsgChat( t );
                                          fPending := fUsername + '> ' + t;
                                        end;
                          idHost      : begin  // .Host
                                          sRecv  := Nick + '> .Host';
                                          MsgChat( 'Host: ' + sHost );
                                          fPending := fUserName + '> Host: ' + sHost;
                                        end;
                          idInfo      : if length( para ) > 0 then begin
                                          fNoticeOk := TRUE;
                                          sRecv := Nick + '> .info ' + Para; 
                                          MsgSend( 'nickserv info ' + para );
                                        end else MsgChat( 'Usage: .Info <nick>' );
                          idLaunch    : begin // .Launch
                                          t := Launch;
                                          MsgChat( t );
                                          fPending := fUserName + '> ' + t;
                                        end;
                          idNote      : begin  // .Note
                                          if length( trim( para ) ) > 0 
                                            then t := fNote.Note( Nick, para )
                                            else t := 'Usage: .Note <nick> <message>';
                                          MsgChat( t  );
                                          fPending := fUserName + '> ' + t;
                                        end;
                          idOps       : begin  // .Ops
                                          try
                                            fOps.LoadFromFile( 'shao.ops' );
                                            sRecv  := '';
                                            for i := 1 to fOps.Count do begin
                                              if length( sRecv  ) > 0 then sRecv  := sRecv  + ', '; 
                                              sRecv  := sRecv  + fOps.Strings[ i - 1 ];
                                            end;
                                            sRecv  := 'OPS: ' + sRecv ;
                                          except
                                            sRecv  := 'Ops list not available';
                                          end;
                                          MsgChat( sRecv  );
                                          sRecv  := fUsername + '> ' + sRecv ;
                                        end;
                          idPodcast   : begin
                                          MsgChat( 'Podcast at Apple: https://podcasts.apple.com/us/podcast/beyond-our-world/id1463292550' );
                                          MsgChat( 'Podcast at Google: https://play.google.com/music/listen#/ps/Iufhvi55u2xb5lzbptbzluwowzi' );
                                          MsgChat( 'Podcast at iHeart: https://www.iheart.com/podcast/269-beyond-our-world-46371700/' );
                                          MsgChat( 'Podcast at Spotify: https://open.spotify.com/show/5kZlYkt7npWhuBibl450ah' );
                                          fPending := fUserName + '> Podcast URLs sent to channel';
                                        end;
                          idProfile   : begin  // .Profile
                                          t  := Nick + '> ' + fProf.Parse( Nick, Para );
                                          MsgChat( t  );
                                          fPending := Nick + '> ' + t;
                                        end;
                          idQuit      : begin  // .Quit
                                          t := 'Quit yourself, ' + Nick;
                                          MsgChat( t );
                                          fPending := fUserName + '> ' + t;
                                        end;
                          idRAP       : begin
                                          MsgChat( 'Random Astronomical Picture: https://apod.nasa.gov/apod/random_apod.html' );
                                          fPending := fUserName + '> RAP URL sent to channel';
                                        end;
                          idShao      : begin  // .Shao
                                           t := Shao( para, Nick );
                                           MsgChat( t );
                                           fPending := fUserName + '> ' + t;
                                        end;
                          idSpaceX    : begin  // .SpaceX
                                          t := SpaceX;
                                          MsgChat( t );
                                          fPending := fUserName + '> ' + t;
                                        end;
                          idSunSpots  : begin
                                          MsgChat( 'Sunspot activity: https://services.swpc.noaa.gov/images/solar-cycle-sunspot-number.gif' );
                                          fPending := fUsername + '> Sunspot data sRecv ent to channel';
                                        end;
                          idSynonyms  : begin  // .Synonyms
                                          if length( Para ) > 0 
                                            then sRecv  := Synonyms( Para )
                                            else sRecv  := 'usage - .Synonyms <word>';
                                          sRecv  := 'Synonyms: ' + sRecv ;
                                          MsgChat( sRecv  ); 
                                          sRecv  := fUserName + '> ' + sRecv ;
                                        end;
                          idTime      : begin  // .Time
                                          if length( Para ) > 0 then begin
                                            if uppercase( Para ) = fUsername then begin
                                              DateTimeToString( sRecv , 'ddd mmm dd ', Date );
                                              DateTimeToString( t, 'hh:mm:ss:zzz', Time );
                                              sRecv  := sRecv  + t;
                                            end else MsgSend( 'PRIVMSG ' + Para + ' :' + #01 + 'time' + #01 );
                                            MsgSend( sRecv  );
                                            fPending := fUserName + '> ' + sRecv ;
                                            sRecv  := '';
                                          end else begin
                                            MsgChat( 'Usage .Time nick' );
                                            sRecv  := fUserName + '> Usage .Time nick';
                                          end;
                                        end;
                          idTopic     : begin  // .Topic
                                          MsgSend( 'TOPIC ' + fChannel );
                                          fPending := fUsername + '> Toppic requested';
                                        end;
                          idUp        : begin  // .Up
                                           tTime := Now;
                                          t := 'Up time: ' + IntToStr( DaysBetween( tTime, sTime ) ) + ' days ' + 
                                          FormatDateTime('h" hrs, "n" min, "s" sec"', tTime - sTime );
                                          MsgChat( t );
                                          fPending := fUsername + '> ' + t;
                                        end;
                          idVersion  :  begin  // .Version
                                          MsgChat( 'Version ' + fVersion );
                                          fPending := fUserName + '> Version ' + fVersion;
                                        end;
                          idWeather   : begin  // .Weather
                                       //  if uppercase( fChannel ) <> '#PHOTOGEEKS' then begin
                                         t := fWeather.Command( nick, para );
                                         MsgChat( t );
                                         fPending  := fUsername + '> ' + t;
                                       //   end else sRecv  := fUsername + '> hidden weather';
                                       end;
                          idWiki     : begin  // .Wiki
                                         if length( Para ) > 0 
                                           then t := 'Wiki: ' + Wiki( para )
                                           else t := 'Wiki: Usage - .Wiki <word | phrase>';
                                         MsgChat( t );
                                         fPending := fUserName  + '> ' + t;
                                       end;
                          idWikiFp   : begin  // .WikiFp
                                         if length( Para ) > 0
                                           then t := 'WikiFp: ' + WikiFp( para )
                                           else t := 'WikiFp: Usage - .WikiFp <word | phrase>';
                                         MsgChat( t );
                                         fPending := fUserName  + '> ' + t;
                                       end;
                          idCAction :  begin  // /Action
                                         t := copy( sRecv , pos( ' ', sRecv  ) + 1, length( sRecv  ) );
                                         fPending := fUserName + '> ' + t;
                                       end;
                          idCTime    : begin  // /Time
                                         DateTimeToString( sRecv , 'ddd mmm dd ', Date );
                                         DateTimeToString( t, 'hh:mm:ss:zzz', Time );
                                         sRecv  := sRecv  + t;
                                         MsgChat( sRecv  );
                                         fCon.Send( fUsername + '> ' + sRecv , taBold );
                                       end;
                          idCVersion : begin  // /Version
                                    //     MsgSend( #01 + 'VERSION ' + fUserName + #01 );
                                    //     fCon.Send( fUsername + '> ' + 'Version', taBold );
                                         fPending := 'VERSION';
                                       end;
                          else sRecv  := '';
                        end;  // PRIVMSG case
                      end;  // PRIVMSG
          idSQuit : fPending := fUsername + '> ' + Comm + ' ' + Para;
          else sRecv  := Nick + '> ' + sRecv ;
       end;  // Case process messages
       if length( sRecv  ) > 0 then                                           // Write out normal message to console
         if copy( sRecv , 1, length( fUsername ) ) = fUserName
           then fCon.Send( sRecv , taBold )
           else fCon.Send( sRecv , taNormal );
       if length( fPending ) > 0 then begin                                   // Write out any pending message
         if copy( fPending , 1, length( fUserName ) ) = fUserName
           then fCon.Send( fPending, taBold )
           else fCon.Send( fPending, taNormal );
       end;
       if pos( '> ', sRecv  ) > 0 then begin                                  // Write out .Note message for  
         t := leftStr( sRecv , pos( '> ', sRecv  ) - 1 ); 
         t := fNote.Fetch( t );                                
         if length( t ) > 0 then begin
           fCon.Send( fUserName + '> ' + Nick + ' ' + t, taBold );
           MsgChat( Nick + ' ' + t );
         end;
       end;
       if not ( assigned( fSocket.Socket ) ) then begin                       // Check if still logged in
         fCon.Send( 'Login attempt', taBold );
         Login;
         fPingLast := Now;
       end;
       sRecv  := '';
       fPending := '';
      end;  // if length( sRecv  ) > 0
      if fSocket.Error <> 0 then begin
        if fSocket.ErrorMsg = 'Connection timed out'
          then fSocket.ErrorClear
          else fCon.Send( fSocket.ErrorMsg, taBold );
      end;
      sleep( 2 );
    end;  // while
    fCon.Send( fUserName + '> Laters :)', taBold );
    fCon.Send( 'IRC link ended', taNormal );
    fSocket.Free;
  end;  // tIRC.Execute
  
  
  function tIRC.Define( s : string ) : string;
  var
    a : array of string;
  begin
    setLength( a, 2 );
    try
      a[ 0 ] := 'APP_ID: '  + fOEDAppID;
      a[ 1 ] := 'APP_KEY: ' + fOEDKey;
      s := fCurl.Get( 'https://od-api.oxforddictionaries.com/api/v2/entries/en-us/' + lowercase( URLEncode( s ) ), a );
      if length( s ) > 0 then begin
        fJSON := GetJSON( s );
        s := fJSON.FindPath( 'results[0].lexicalEntries[0].entries[0].senses[0].definitions[0]' ).AsString;
      end else s := 'Not found';
    except
      on E:Exception do begin
        s := 'Error occured';
        fCon.Send( 'Define> ' + E.Message + ' ' + E.ClassName, taBold );
      end;
      on E:EJSON do begin
        s := 'Error occured';
        fCon.Send( 'Define> ' + E.Message + ' ' + E.ClassName, taBold );
      end;
    end;
    Result := s;
  end;  // tIRC.Define


  procedure tIRC.IndexMake;
    // Set up TStringList for main case search
//  var
//    i : integer;
  begin
    with fIndex do begin
      CaseSensitive   := TRUE;
      Sorted          := TRUE;
      StrictDelimiter := TRUE;
      CommaText       := '.8BALL,.ANAGRAM,.AURORA,.DEFINE,.DOF,.HELP,.HOST,.INFO,.LAUNCH,.NOTE,.OPS,.PODCAST,.PROFILE,.QUIT,.RAP,.SHAO,.SPACEX,.SUNSPOTS,.SYNONYMS,.TIME,.TOPIC,.UP,.VERSION,.WEATHER,.WIKI,.WIKIFP,' +
                         '/ACTION,/TIME,/VERSION,' +
                         '001,002,003,004,005,250,251,252,253,254,255,265,266,328,332,333,351,353,366,372,373,375,376,401,433,451,486,' +
                         'ERROR,JOIN,MODE,NOTICE,PART,PING,PRIVMSG,QUIT';
      Sort;      
    end;
//    for i := 0 to fIndex.Count - 1 do writeln( i, ' ', fIndex.Strings[ i ] );
  end;  // tIRC.IndexMake


  function tIRC.Launch : string;
    // Details next launch (world-wide). ln is launch number
  var
    s    : string;
  begin
    try
      s     := fCurl.Get( 'https://launchlibrary.net/1.3/launch/next/1' );
      fJSON := GetJSON( s );
      s     := fJSON.FindPath( 'launches[0].name' ).AsString +
               ' on ' + fJSON.FindPath( 'launches[0].net' ).AsString +
               ' from ' + fJSON.FindPath( 'launches[0].location.name' ).AsString +
               ' : ' + fJSON.FindPath( 'launches[0].missions[0].description' ).AsString;
    except
      on E : Exception do begin
        fCon.Send( 'Launch: ' + E.Message + ' ' + E.ClassName, taBold );
        s := 'We have an anomoly';
      end;
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
    fSocket.Disconnect;
    fSocket.ErrorClear;
    if not fSocket.Connected then begin
      fCon.Send( 'Logging in' );  // Log in
      if fSocket.Connect( fNetwork, strToIntDef( fPort, 80 ) ) then begin
        fCon.Send( 'Connected to ' + fNetwork + ' port ' + fPort );
        b := TRUE;
        fCon.Send( 'Waiting' );
        sleep( 2000 );
      end else fCon.Send( 'Connect error ' + fSocket.ErrorMsg, taBold );
    end;
    if fSocket.Connected then begin
      fCon.Line1( fUsername + ' ' + fVersion );
      s := 'NICK ' + fUserName;
      MsgSend( s );
      if b then begin
        fCon.Send( fUserName + ': ' + s, taBold );
        s := 'USER ' + fUserName + ' * * :' + fUserName;
        MsgSend( s );
        fCon.Send( fUserName + ': ' + s, taBold );
        fCon.Send( fUserName + ': Sending password', taBold );
        MsgSend( 'nickserv identify ' + fPassword );
      end;
    end;
    Login := assigned( fSocket.Socket );
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
    if assigned( fSocket.Socket ) then fSocket.Send( s + CRLF );
  end;  // tIRC.MsgSend
  

  procedure tIRC.Nicks( s : string );
    // Scan nick s on join and sends appropriate sNote messages, if any
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


  function tIRC.Shao( para, nick : string ) : string;
    // .Shao and .8Ball commands
  var
    s : string;
  begin
    if length( para ) > 0 then begin
      fBall8.LoadFromFile( 'shao.8ball' );
      s := fBall8[ random( fBall8.Count ) ];
      if random( 10 ) = 4 then s := s + ', ' + nick;
    end else s := 'Need something to work with';
    Shao := s;
  end;  // fIRC.Shao


  procedure tIRC.Shutdown;
    // Prepare IRC to shut down
  begin
    if fSocket.Connected then begin
      MsgChat( 'Laters :)' );
      sleep( 500 );
      MsgSend( 'QUIT Laters :)' );
    end;
    fSocket.Terminate;
    sleep( 500 );
    Self.Terminate;
  end;  // tIRC.Shutdown;

  
  function tIRC.SpaceX : string;
    // Returns next planned launch of SpaceX
  var
    i : integer;
    s : string;
    t : string;
  begin
    s := '';
    try
      s     := fCurl.Get( 'https://api.spacexdata.com/v3/launches/next' );
      fJSON := GetJSON( s );
      s     := fJSON.FindPath( 'mission_name' ).AsString;
      t     := copy( fJSON.FindPath( 'launch_date_utc' ).AsString, 1, 16 );
      s     := s + ' on ' + replaceStr( t, 'T', ' ' );
      s     := s + ' from ' + fJSON.FindPath( 'launch_site.site_name_long' ).AsString;
      s     := s + ' using ' + fJSON.FindPath( 'rocket.rocket_name' ).AsString;
      try  // details night be null
        s     := s + '. ' + fJSON.FindPath( 'details' ).AsString;
      except
      end;
      i := length( s );
      if i > 400 then begin
        s := copy( s, 1, 400 );
        while ( i > 0 ) and ( s[ i ] <> '.' ) do dec( i );
        if i > 0
          then s := copy( s, 1, i )
          else s := 'We have an anomoly';
      end;
    except
      on E : Exception do begin
        fCon.Send( 'SPACEX> ' + E.Message + ' ' + E.ClassName, taBold );
        s := 'We have an anomoly';
      end;
    end;
    SpaceX := 'SpaceX : ' + s;
  end;  // tIRC.SpaceX


  function tIRC.Synonyms( s : string ) : string;
    // Returns synonyms as comma delimited string
  var
    a    : array of string;
    i    : integer;
    jDat : TJSONData;
  begin
    setLength( a, 2 );
    try
      a[ 0 ] := 'APP_ID: '  + fOEDAppID;
      a[ 1 ] := 'APP_KEY: ' + fOEDKey;
      s     := fCurl.Get( 'https://od-api.oxforddictionaries.com/api/v1/entries/en/' + lowercase( URLEncode( s ) ) + '/synonyms', a );
      if length( s ) > 0 then begin
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
      end;
      if length( s ) = 0 then s := 'Not found';
    except
      on E : Exception do begin
        fCon.Send( 'Synonyms ' + E.Message + ' ' + E.ClassName, taBold );
        s := 'Not found';
      end;
    end;
    Result := s;
  end;  // tIRC.Synonyms }
    

  procedure tIRC.URLEcho( s : string );
    // Echo details of HTTP string in channel
  const
    Unsafe    = ' "<>#%{}|\^~[]`' + #13;
  var
    c : char;
    i : integer;
    j : integer;
    k : integer;
  begin
    i := pos( 'HTTPS://', uppercase( s ) );                                       // Get start in t of URL
    if i = 0 then i := pos( 'HTTP://', uppercase( s ) );                          // Find start of URL
    if ( i > 0 ) and not ( ( pos( '.jpg', lowercase( s ) ) > 0 ) or ( pos( '.png', lowercase( s ) ) > 0 ) ) then begin
      j := i;
      while ( j <= length( s ) ) and ( pos( s[ j ], Unsafe ) = 0 ) do inc( j );   // find end of URL
      try
        s := fCurl.Get( trim( copy( s, i, j - i ) ) );                            // Get page content
      except
        on E : Exception do begin
          s := '';
          fPending := 'URLEcho: ' + E.Message + ' ' + E.ClassName;
        end;
      end;
      if length( s ) > 0 then begin
        i := pos( '<title', lowercase( s ) );       // Find <TITLE> tag
        if i > 0 then begin
          i := PosEx( '>', s, i ) + 1;
          j := PosEx( '</title>', lowercase( s ), i );
          if ( i > 0 ) and ( j <> 0 ) and ( j - i <= 250  )
            then s := trim( copy( s, i, j - i ) )
            else s := '';
        end;
        if ( i = 0 ) and ( length( s ) > 0 ) then begin
          i := pos( '<h1', lowercase ( s ) );           // Find <H1> tag
          if i > 0 then begin
            i := PosEx( '>', s, i ) + 1;
            j := PosEx( '</h1>', lowercase( s ), i );
            if ( i > 0 ) and ( j <> 0 ) and ( j - i <= 250 )
              then s := trim( copy( s, i, j - i ) )
              else s := '';
          end else s := '';
        end;
        if length( s ) > 250 then s := copy( s, 1, 250 );
        i := 1;
        while i < length( s ) do begin                                            // translate &NAME; and &#NUMBER; entities
          j := 0;
          if ( s[ i ] = '&' ) and ( i + 1 < length( s ) ) then begin
            if ( s[ i + 1 ] = '#' ) and ( i + 2 < length( s ) ) then begin        // handle numeric entites
              k := posex( ';', s, i );
              if k > 0 then begin
                j := strToIntDef( copy( s, i + 2, k - i + 1 ), -1 );
                case j of
                    34 : c := '"';
                    35 : c := '#';
                    36 : c := '$';
                    37 : c := '%';
                    38 : c := '&';
                    39 : c := '''';
                    40 : c := '(';
                    41 : c := ')';
                    42 : c := '*';
                    43 : c := '+';
                    44 : c := ',';
                    45 : c := '-';
                    46 : c := '.';
                    47 : c := '/';
                    58 : c := ':';
                    59 : c := ';';
                    60 : c := '<';
                    61 : c := '=';
                    62 : c := '>';
                    63 : c := '?';
                    64 : c := '@';
                    91 : c := '[';
                    92 : c := '\';
                    93 : c := ']';
                    94 : c := '^';
                    95 : c := '_';
                    96 : c := '`';
                   123 : c := '{';
                   124 : c := '|';
                   125 : c := '}';
                   126 : c := '~';
                  else   c := '.';
                end;  // case
                delete( s, i, k - i + 1 );
                insert( c, s, i );
              end; 
            end else begin  // Handle named entities
              k := PosEx( ';', s, i );
              if k > i then begin
                case lowercase( copy( s, i, k - i + 1 ) ) of
                    '&quot;' : c := '"';
                     '&num;' : c := '#';
                  '&dollar;' : c := '$';
                  '$percnt;' : c := '%';
                     '&amp;' : c := '&';
                    '&apos;' : c := '''';
                    '&lpar;' : c := '(';
                    '&rpar;' : c := ')';
                     '&ast;' : c := '*';
                    '&plus;' : c := '+';
                   '&comma;' : c := ',';
                   '&minus;' : c := '-';
                  '&period;' : c := '.';
                     '&sol;' : c := '/';
                   '&colon;' : c := ':';
                    '&semi;' : c := ';';
                      '&lt;' : c := '<';
                  '&equals;' : c := '=';
                      '&gt;' : c := '>';
                   '&quest;' : c := '?';
                  '&commat;' : c := '@';
                    '&lsqb;' : c := '[';
                    '&bsol;' : c := '\';
                    '&rsqb;' : c := ']';
                     '&hat;' : c := '^';
                  '&lowbar;' : c := '_';
                   '&grave;' : c := '`';
                    '&lcub;' : c := '{';
                  '&verbar;' : c := '|';
                    '&rcub;' : c := '}';
                   '&tilde;' : c := '~';
                       else    c := '.';
                end;  // case
                delete( s, i, k - i + 1 );
                insert( c, s, i );
              end;
            end;
          end;
          inc( i );
        end;  // while
//        for i := 1 to length( s ) do if not ( s[ i ] in HTMLChars ) then s[ i ] := ' ';  // Clean out any bad chars
        if length( s ) > 0 then begin
          MsgChat( s );
          fPending := fUserName + '> ' + s;
        end else begin
          s := 'URLEcho: Invalid or no <title> or <h1> found';
          fPending := fUserName +  '> ' + s;
        end;
      end;
    end;
  end;  // tIRC.URLEcho


  function tIRC.Wiki( s: string ) : string;
    // Returns Wiki extract of s
  var
    i : integer;
  begin
    try
      s := fCurl.Get( 'https://en.wikipedia.org/w/api.php?format=json&action=query&prop=extracts&exintro&explaintext&redirects=1&titles=' + URLEncode( s ) );
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
      on E : EJSONParser do s := 'Wiki ' + E.Message + E.ClassName;
      on E : Exception   do s := 'Not found';
    end;
    result := s;
  end;  // tIRC.Wiki


  function tIRC.WikiFp(aSearch: string): string;
    // Returns Freepascal Wiki search results of search
  var
    i       : integer;
    langSep : string;
    s       : string;
    title   : string;
    vJSON   : TJSONEnum;
  begin
    try
      s     := fCurl.Get( 'https://wiki.freepascal.org/api.php?action=query&list=search&format=json&srsearch=' + URLEncode( aSearch ) );
      fJSON := GetJSON( s );
      fJSON := fJSON.FindPath( 'query.search' );
      s     := '';
      if fJSON.Count = 0 then begin
        s := 'No Title Match';
        exit( s ); // no page title matched search so show nothing
      end;
      for vJSON in fJSON do begin
        title := vJSON.Value.FindPath( 'title' ).AsString;
        if CompareText( aSearch, title ) = 0 then begin
          s := title + ' ~ https://wiki.lazarus.freepascal.org/index.php?go=go&search=' + URLEncode( aSearch );
          exit( s ); // equal to so set result to url with go param.
        end;
        langSep := title[ length( title ) - 2 ];
        if CompareText( langSep, '/' ) <> 0 then begin // do not add language specific page titles
          if length( s ) <> 0
            then s := s + ', ';
          s := s + '' + title + '';
        end;
      end;
      if length( s ) > 350 then begin
        s := copy( s, 1, 350 );
        i := 350;
        while ( i > 0 ) and ( s[ i ] <> '.' ) do dec( i );
        s := copy( s, 1, i );
      end;
      s := s + ' ~ https://wiki.lazarus.freepascal.org/index.php?search=' + URLEncode( aSearch );
    except
      on E : EJSONParser do s := 'Freepascal Wiki ' + E.Message + E.ClassName;
      on E : Exception   do s := 'Not found';
    end;
    result := s;
  end;  // tIRC.WikiFp


end.  // sIRC 
