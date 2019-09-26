{ 
  sWeather.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.


  Implements .weather command for IRC bot

  Commands
    .weather                       Displays weather or status
    .weather delete                Deletes entry
    .weather help                  Display help URL
    .weather location              Display location information
    .weather location <location>   Edit location
    .weather new                   New nick only
    .weather new <location>        New nick and location for weather

    <location> can be <city> or <city, country> or <city, state/province> or <city, state/province, country>
    <country> can be name or ISO country code
}


unit sWeather;


  {$MODE OBJFPC}
  {$H+}


interface


  uses
    Classes,
    fpJSON,
    JSONParser,
    sConsole;


  type


    tWeather = class( TStringList )
    private
      fAPIXU    : string;
      fFileName : string;
      fJSON     : TJSONData;
      procedure LocationParse( sIn : string; var sCity, sProv, sCountry : string );
    public
     constructor Create;
     destructor  Destroy; override;
     property    APIXU : string write fAPIXU;
     function    Command( nick : string; para : string ) : string;
     function    Conditions( sCity, sProvince, sCountry : string ) : string;
    end;  // tWeather


  var
    fWeather : tWeather;


implementation


  uses
    sCurl,
    SysUtils;


  const
    CRLF = #13 + #10;


  constructor tWeather.Create;
  begin
    inherited Create;
    Duplicates         := dupError;
    LineBreak          := CRLF;
    OwnsObjects        := TRUE;
    NameValueSeparator := '~';
    Sorted             := TRUE;
    fFileName          := 'shao.weather';
    try
      LoadFromFile( fFileName );
    except
    end;
 end;  // tWeather.Create


  destructor tWeather.Destroy;
  begin
    inherited Destroy;
  end;  // tWeather.Destroy


  function tWeather.Command( nick : string; para : string ) : string;
    // Executes .weather commands
  var
    idx : integer;
    p1  : string;
    p2  : string;
    res : string;
    sCo : string;
    sCt : string;
    sPr : string;
  begin
    para := trim( para );
    p1   := uppercase( copy( para, 1, pos( ' ', para + ' ' ) - 1 ) );
    if pos( ' ', para ) > 0
      then begin
        p2 := copy( para, pos( ' ', para ), length( para ) );
        LocationParse( p2, sCt, sPr, sCo );
      end else p2 := '';
    case p1 of
      ''         : begin
                     idx := IndexOfName( uppercase( nick ) );
                     if idx >= 0 then begin
                       p2 := ValueFromIndex[ idx ];
                       LocationParse( p2, sCt, sPr, sCo );
                       if length( sCt ) > 0
                         then res := Conditions( sCt, sPr, sCo )
                         else res := 'Please use .weather location <location> to set your location'
                     end else res := 'Unknown nick ' + nick + '. Try .weather help';
                   end;
      'DELETE'   : begin
                     idx := IndexOfName( uppercase( nick ) );
                     if idx >= 0 then begin
                       Delete( idx );
                       SaveToFile( fFileName );
                       res := 'Nick ' + nick + ' deleted from .Weather';
                     end else res := 'Unknown nick ' + nick + '. Try .weather help';
                   end;
      'HELP'     : res := 'Help https://github.com/coraxyn/ShaoB/wiki/Commands';
      'LOCATION' : begin
                     idx := IndexOfName( uppercase( nick ) );
                     if idx >= 0 then begin
                       if length( sCt ) = 0 then begin
                         GetNameValue( idx, p1, p2 );
                         LocationParse( p2, sCt, sPr, sCo );
                         res := 'Location ' + sCt;
                         if length( sPr ) > 0 then res := res + ', ' + sPr;
                         if length( sCo ) > 0 then res := res + ', ' + sCo;
                       end else begin
                         try
                           Sorted := FALSE;
                           Strings[ idx ] := uppercase( nick ) + '~' + sCt + ',' + sPr + ',' + sCo;
                           Sorted := TRUE;
                           Sort;
                           res := 'Location data saved for ' + nick;
                           SaveToFile( fFileName );
                         except
                           on E: Exception do res := 'Weather ' + E.Message + ' ' + E.ClassName;
                           on E: EStreamError do res := 'Weather ' + E.Message + ' ' + E.ClassName;
                         end;
                       end;
                     end else res := 'Unknown nick ' + nick + '. Try .weather help';
                   end;
      'NEW'      : begin
                     idx := IndexOfName( uppercase( nick ) );
                     if idx < 0 then begin
                       Add( uppercase( nick ) + '~' + sCt + ',' + sPr + ',' + sCo );
                       SaveToFile( fFileName );
                       res := 'New entry created for ' + nick;
                     end else res := nick + ' is already registered';
                   end;
       else        begin
                     p2  := p1 + ' ' + p2;
                     LocationParse( p2, sCt, sPr, sCo );
                     res := Conditions( sCt, sPr, sCo );
                   end;
    end;  // case p1
    Command := res;
  end;  // tWeather.Command


  function tWeather.Conditions( sCity, sProvince, sCountry : string ) : string;
    // Get weather conditions from apixu.com
  var
    res  : string;
    s    : string;
    t    : string;
  begin
    if length( sCity ) > 0 then begin
      s := 'https://api.apixu.com/v1/current.json?key=' + fAPIXU + '&q=' + sCity;
      if length( sProvince ) > 0 then s := s + ',' + sProvince;
      if length( sCountry ) > 0 then s := s + ',' + sCountry;
      s := StringReplace( s, ' ', '+', [ rfReplaceAll ] );
      try
        s     := fCurl.Get( s );
        fJSON := GetJSON( s );
        res   := '';
        s     := '';
        s := fJSON.FindPath( 'location.name' ).AsString;
        if length( s ) > 0 then res := res + s + ', ';
        s := fJSON.FindPath( 'location.region' ).AsString;
        if length( s ) > 0 then res := res + s + ', ' ;
        s := fJSON.FindPath( 'location.country' ).AsString;
        if length( s ) > 0 then res := res + s + ', ';
        s := fJSON.FindPath( 'current.condition.text' ).AsString;
        if length( s ) > 0 then res := res + s + ', ';
        s := fJSON.FindPath( 'current.temp_c' ).AsString;
        t := s;
        if length( s ) > 0 then res := res + FormatFloat( '##0.0', strToFloat( s ) ) + 'C ';
        s := fJSON.FindPath( 'current.feelslike_c' ).AsString;
        if ( length( s ) > 0 ) and ( s <> t ) then res := res + 'as ' + FormatFloat( '##0.0', strToFloat( s ) ) + 'C, ';
        s := fJSON.FindPath( 'current.wind_kph' ).AsString;
        if ( length( s ) > 0 ) and ( strToFloatDef( s, 0.0 ) > 0.0 ) then res := res + 'wind ' + FormatFloat( '##0.0', strToFloat( s ) ) + ' km/h ';
        s := fJSON.FindPath( 'current.wind_dir' ).AsString;
        if length( s ) > 0 then res := res + s + ', ';
        s := fJSON.FindPath( 'current.precip_mm' ).AsString;
        if ( length( s ) > 0 ) and ( strToFloatDef( s, 0.0 ) > 0.0 ) then res := res + 'precip ' + FormatFloat( '###0.0', strToFloat( s ) ) + ' mm, ';
        s := fJSON.FindPath( 'current.pressure_mb' ).AsString;
        if length( s ) > 0 then res := res + 'pressure ' + FormatFloat( '000.0', strToFloat( s ) ) + ' hPa, ';
        s := fJSON.FindPath( 'current.humidity' ).AsString;
        if length( s ) > 0 then res := res + 'humidity ' + s + '%';
        s := fJSON.FindPath( 'current.uv' ).AsString;
        if ( length( s ) > 0 ) and ( strToFloatDef( s, 0.0 ) > 0.0 ) then res := res + ', uv ' + FormatFloat( '#0', strToFloat( s ) );
    except
        on E : Exception do if E.ClassName = 'EAccessViolation'
                              then res := 'Not found'
                              else res := 'Define Exception: ' + E.Message + ' ' + E.ClassName;
        on E : EJSON     do res := res + ' JSON error: '        + E.Message + ' ' + E.ClassName;
      end;
    end;
    Conditions := res;
  end;  // tWeather.Conditions


  procedure tWeather.LocationParse( sIn : string; var sCity, sProv, sCountry : string );
    // parses sIn into city, province, and state
  begin
    sCity    := '';
    sProv    := '';
    sCountry := '';
    sIn      := trim( sIn );
    if length( sIn ) > 0 then begin
      sCity := trim( copy( sIn, 1, pos( ',', sIn + ',' ) - 1 ) );
      sIn   := trim( copy( sIn, pos( ',', sIn + ',' ) + 1, length( sIn ) ) );
      if length( sIn ) > 0 then begin
        sProv := trim( copy( sIn, 1, pos( ',', sIn + ',' ) - 1 ) );
        sIn   := trim( copy( sIn, pos( ',', sIn + ',' ) + 1, length( sIn ) ) );
        if length( sIn ) > 0
          then sCountry := trim( sIn )
          else begin
            sCountry := sProv;
            sProv    := '';
          end;
      end;
    end;
  end;  // tWeather.LocationParse


end. //  sWeather
