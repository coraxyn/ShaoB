{ 
  sQuake.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.
  
  WebSocket link for significant earthquakes
  https://www.seismicportal.eu/realtime.html
  
}


unit sQuake;


  {$MODE OBJFPC}
  {$H+}


interface


  uses
    cThreads,
    Classes,
    fpJSON;


  type


    tQuake = class( TThread )
      private
        fJSON      : TJSONData;
        fLastQuake : string;
        fRun       : boolean;
        fUserName  : string;
      protected
        procedure Execute; override;
      public
        constructor Create;
        destructor  Destroy; override;
        procedure   Run;
        property    UserName : string write fUserName;
    end;  // tQuake
 
 
  var
    fQuake : tQuake;

 
implementation


  uses
    DateUtils,
    JSONParser,
    sConsole,
    sCurl,
    sIRC,
    StrUtils,
    SysUtils;

 
  constructor tQuake.Create;
  begin
    inherited Create( TRUE );
    fLastQuake := '';
    fRun       := FALSE;
  end;  // tQuake.Create


  destructor tQuake.Destroy;
  begin
    inherited Destroy;
  end;  // tQuake.Destroy;


  procedure tQuake.Execute;
  var
    i  : integer;
    id : string;
    mg : string;
    ql : TStringList;
    s  : string;
  begin
    ql := TStringList.Create;
    while not fRun and not Terminated do sleep( 100 );                              // Wait until rest of system is running
    try
      ql.LoadFromFile( 'shao.quake' );                                              // Get previous earthquake ID
    except
    end;
    if ql.Count > 0 then fLastQuake := ql.Strings[ 0 ];
    while not Terminated do begin
      s := fCurl.Get( 'http://www.seismicportal.eu/fdsnws/event/1/query?limit=1&format=json' );
      if length( s ) > 0 then begin
        try
          fJSON := GetJSON( s );
          fJSON := fJSON.FindPath( 'features' );
          fJSON := fJSON.Items[ 0 ];
          id    := fJSON.FindPath( 'id' ).AsString;
          mg    := fJSON.FindPath( 'properties.mag' ).AsString;
          if ( StrToFloatDef( mg, 0 ) >= 5.5 ) and ( id <> fLastQuake ) then begin
            fLastQuake := id;
            ql.Clear;
            ql.Add( fLastQuake );
            ql.SaveToFile( 'shao.quake' );
            s := fJSON.FindPath( 'properties.time' ).AsString;
            s := ReplaceStr( s, 'T', ' ' );
            s := copy( s, 1, 16 ); 
            s := 'Earthquake ' + fJSON.FindPath( 'properties.flynn_region' ).AsString +
                 ' on ' + s + ' UTC' +
                 ', magnitude ' + formatFloat( '#0.0', StrToFloatDef( mg, 0 ) ) + ' ' +
                 fJSON.FindPath( 'properties.magtype' ).AsString +
                 ', depth ' + formatFloat( '##0.0', StrToFloatDef( fJSON.FindPath( 'properties.depth' ).AsString, 0 ) ) + ' km';
            fIRC.MsgChat( s );
            fCon.Send( fUserName + '> ' + s, taBold );
          end;
        except
          on E : Exception do fCon.Send( 'QUAKE > ' + E.Message + ' ' + E.ClassName, taBold );
        end;
      end;
      i := 0;
      while not Terminated and ( i < 1200 ) do begin
        Sleep( 100 );
        inc( i );
      end;
    end;
    ql.Free;
  end;  // tQuake.Execute;


  procedure tQuake.Run;
    // Set fRun to TRUE
  begin
    fRun := TRUE;
  end;  // tQuake.Run


end.  // sQuake 
