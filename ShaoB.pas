program ShaoB;
 
  // IRC ShaoB
  // Will only work on UNIX based OS.  Linux, Darwin, *NIX, etc.
  // Uses ARARAT SYNAPSE library for sockets and SSL/TLS.


  {$MODE OBJFPC}
  {$H+}


uses
  cThreads,
  cMem,
  Classes,
  sConsole,
  sCurl,
  sIRC,
  sNote,
  sProfile,
  sQuake,
  sWeather,
  SysUtils;


var
  err       : string;
  fAPIXU    : string;
  fChannel  : string;
  fChannels : array of string;
  fNetwork  : string;
  fOEDAppID : string;
  fOEDKey   : string;
  fPassword : string;
  fPort     : string;
  fVersion  : string;
  fUserName : string;
  i         : integer;
  s         : string;


  procedure ConfigDisplay;
    // Display config file
  begin
    fCon.Send( 'Config:', taBold );
    fCon.Send( 'APIXU: ' + fAPIXU );
    fCon.Send( 'Network: ' + fNetwork );
    fCon.Send( 'Network password: ' + fPassword );
    fCon.Send( 'Network port: ' + fPort );
    fCon.Send( 'OED application ID: ' + fOEDAppID );
    fCon.Send( 'OED key: ' + fOEDKey );
    fCon.Send( 'User name: ' + fUserName );
  end;  // ConfigDisplay


  function ConfigRead : string;
  var
    i    : integer;
    name : string;
    para : string;
    s    : string;
    t    : TStringList;
  begin
    s := '';
    t := TStringList.Create;
    t.LoadFromFile( 'shao.config' );
    for i := 0 to t.Count - 1 do begin
      name := trim( leftStr( t.Strings[ i ], pos( ':', t.Strings[ i ] + ':' ) - 1 ) );
      if pos( ':', t.Strings[ i ] ) > 0
        then para := trim( rightStr( t.Strings[ i ], length( t.Strings[ i ] ) - pos( ':', t.Strings[ i ] ) ) )
        else para := '';
      case uppercase( name ) of
        'APIXU'    : fAPIXU    := para;
        'NETWORK'  : fNetwork  := para;
        'OEDAPPID' : fOEDappID := para;
        'OEDKEY'   : fOEDKey   := para;
        'PASSWORD' : fPassword := para;
        'PORT'     : fPort     := para;
        'USERNAME' : fUsername := para;
      end;  // case
    end;  // for i
    if length( trim( fAPIXU ) ) = 0 then begin
      if length( s ) > 0 then s := s + ', ';
      s := s + 'missing APIXU:';
    end;
    if length( trim( fNetwork ) ) = 0 then begin
      if length( s ) > 0 then s := s + ', ';
      s := s + 'Missing Network:';
    end;
    if length( trim( fOEDAppID ) ) = 0 then begin
      if length( s ) > 0 then s := s + ', ';
      s := s + 'Missing OEDAppID:';
    end;
    if length( trim( fOEDKey ) ) = 0 then begin
      if length( s ) > 0 then s := s + ', ';
      s := s + 'Missing OEDKey:';
    end;
    if length( trim( fPort ) ) = 0 then begin
      fPort := '6667';
    end;
    if length( trim( fUserName ) ) = 0 then begin
      fUserName := 'ShaoB';
    end;
    ConfigRead := s;
    t.Free;
  end;  //  ConfigRead


begin
  fVersion := '2.4.0';
  err      := ConfigRead;
  fCurl    := tCurl.Create( fUserName );
  fIRC     := tIRC.Create;
  fNote    := tNote.Create;
  fProf    := tProf.Create;
  fQuake   := tQuake.Create;
  fWeather := tWeather.Create;
  fCon := tConsole.Create( fUserName, fVersion );
  fCon.Line1( 'ShaoB v' + fVersion );
  // read in channels names to connect, if any
  if paramcount > 0 then begin
    fCon.Send( 'Joining ' + inttostr( paramcount ) + ' channel(s)' );
    setlength( fChannels, paramcount );
    for i := 1 to paramcount do begin
      fChannels[ i - 1 ] := paramstr( i );
      if copy( fChannels[ i - 1 ], 1, 1 ) <> '#' then fChannels[ i - 1 ] := '#' + fChannels[ i - 1 ];
      fCon.Send( 'Channel ' + inttostr( i ) + ': ' + fChannels[ i - 1 ] );
      fIRC.ChannelsAdd( fChannels[ i - 1 ] );
    end;
  end;
  fUserName := 'ShaoBB';    // For debuging in ShaoBot channel
  with fIRC do begin
    APIXU     := fAPIXU;
    Network   := fNetwork;
    OEDAppID  := fOEDAppID;
    OEDKey    := fOEDKey;
    Password  := fPassword;
    Port      := fPort;
    UserName  := fUserName;
    Version   := fVersion;
  end;
  fWeather.APIXU := fAPIXU;
  if err = '' then begin
    fCon.Send( 'Starting ' + fNetwork + ': ' + fUserName + ' v' + fVersion, taBold );
    fIRC.Start;
    fQuake.Start;
    repeat
      s := fCon.Menu( 'Config Display Joins Type Quit' );
      case s of
        'C' : ConfigDisplay;
        'D' : fCon.Display;
        'J' : begin
                fCon.Send( 'Joined channels:', taBold );
                for i := 0 to length( fChannels ) - 1 do fCon.Send( inttostr( i ) + '-' + fChannels[ i ] );
              end;
        'T' : begin
                s := '';
                for i := 0 to length( fChannels ) - 1 do s:= s + inttostr( i  ) + '-' + fChannels[ i ] + ' ';
                s := fCon.Menu( s );
                if ( length( s ) > 0 ) and ( s[ 1 ] in [ '0'..'9' ] ) then begin
                  fChannel := fChannels[ strtoint( s[ 1 ] ) ];
                  fCon.Send( 'Now typing on ' + fChannel );
                  repeat
                    s := '';
                    fCon.LineGet( s );
                    s := trim( s );
                    if length( s ) > 0 then begin
                      fIRC.MsgChat( fChannel, s );
                      fCon.Send( fChannel + ':' + fUsername + '> ' + s, taBold );
                    end;
                  until length( s ) = 0
                end else s := '';
              end;
        'Q' : if not fCon.YesNo( 'Quit' ) then s := '';
      end;  // case
    until s = 'Q';
  end;
  if err <> '' then begin
    fCon.Send( err, taBold );
    fCon.Send( 'Please review shao.config' );
    fCon.Send( 'Requires Network: Channel: OEDAppID: OEDKey: and APIXU: parameters as minimum' );
    fCon.Send( 'If Password: is missing then it is assumed none is required' );
    fCon.Send( 'If Port: is missing then 6667 is used' );
    fCon.Send( 'If Username: is missing then ShaoB is used' );
    fCon.Beep;
    fCon.AnyKey;
  end;
  fCon.Clear;
  fCon.XY( 1,1 );
  fCon.Send( 'Shutting down' );
  fQuake.Terminate;
  fQuake.WaitFor;
  fCon.Send( 'Quake thread terminated' );
  fIRC.Shutdown;
  fIRC.WaitFor;
  fCon.Send( 'IRC thread terminated' );
  fCon.Send( 'Laters' );
  fCon.Terminate;
  try
    fNote.Free;
    fProf.Free;
    fQuake.Free;
    fWeather.Free;
    fIRC.Free;
    fCurl.Free;
    fCon.Free;
  except
  end;
  Writeln;
end.  // ShaoB
