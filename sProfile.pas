unit sProfile; 


  // maintain user profiles
  
  
  {$MODE OBJFPC}
  {$H+}


interface


  uses
    Classes,
    StrUtils,
    SysUtils;
  
  
  type

  
    tProf = class( TStringList )
      private
        fCurr : integer;
        fGod  : string;
        function Save : boolean;
      public
        constructor Create;
        destructor  Destroy; override;
        property    Current : integer read fCurr write fCurr;
        function    Display( index : integer ) : string;
        procedure   Edit( var s : string; n : string; p : integer );
        function    Help : string;
        function    Parse( nick, s : string ) : string;
        procedure   Reload;
    end;  // tProf

  
  var
    fProf : TProf;
  
implementation


  constructor tProf.Create;
  begin
    inherited;
    Clear;
    Delimiter          := ';';
    Duplicates         := dupIgnore;
    NameValueSeparator := '~';
    Sorted             := TRUE;
    SortStyle          := sslAuto;
    StrictDelimiter    := TRUE;
    fCurr              := 0;
    fGod               := 'Coraxyn';
    Reload;
  end;  // tProf.Create
  
  
  destructor tProf.Destroy;
  begin
    inherited;
  end;  // tProf.Destroy


  function tProf.Display( index : integer ) : string;
    // makes string of profile
  var
    OutP : string;
    s    : string;
  begin
    OutP := '';
    if Index >= 0 then begin
      s    := Strings[ index ];
      s    := Copy( s, Pos( '~', s ) + 1, Length( s ) );
      OutP := OutP + Copy( s, 1, Pos( ';', s ) - 1 ) + ': ';
      s    := Copy( s, Pos( ';', s ) + 1, Length( s ) );
      OutP := OutP + 'eMail: '+ Copy( s, 1, Pos( ';', s ) - 1 );    
      s    := Copy( s, Pos( ';', s ) + 1, Length( s ) );
      OutP := OutP + ' Location: ' + Copy( s, 1, Pos( ';', s ) - 1 );
      s    := Copy( s, Pos( ';', s ) + 1, Length( s ) );
      OutP := OutP + ' Name: ' + Copy( s, 1, Pos( ';', s ) - 1 );
      s    := Copy( s, Pos( ';', s ) + 1, Length( s ) );
      OutP := OutP + ' URL: ' + Copy( s, 1, Pos( ';', s ) - 1 );
    end else OutP := 'Nick not found';
    Result := OutP;
  end;  // tProf.Display
  

  procedure tProf.Edit( var s : string; n : string; p : integer );
    // Inserts s after p ;, removing previous content and saves result
  var
    i, j : integer;
  begin
    i := 0;
    for j := 1 to p do i := PosEx( ';', s, i + 1 );
    j := PosEx( ';', s, i + 1 );
    s := Copy( s, 1, i ) + n + Copy( s, j, length( s ) );
  end;  // tProf.Edit
  
  
  function tProf.Help : string;
    // Display help for profile
  begin
    Result := 'PROFILE NEW new profile DELETE delete profile HELP this. EMAIL, LOCATION, NAME, URL <string> add/edit field. Each field can contain multiple entries. Blank shows own prifile, nick shows nick profile';
  end;  // tProf.Help
  
  
  
  function tProf.Parse( nick, s : string ) : string;
    // Parse s and do stuff.  Returns output to channel
    // s - Empty returns nick's profile 
    // s - nick returns nick's profile, if any
    // s - Comm(and)
    //       DELETE: Deletes nick's profile
    //       EMAIL: Add or change email address to existing profile
    //       HELP: Returns help text
    //       LOCATION: Add or change location to existing profile
    //       NAME: Add or change nick's real name
    //       NEW: Creates empty profile for nick 
    //       RELOAD: reload .prof file.  You need to be god to do this
    //       URL: Add or change URL to exiting profile
    // Values are ordered by alphabetic meanings: EMAIL;LOCATION;NAME;URL;
  var
    Comm : string;
    Indx : integer;
    Name : string;
    OutP : string;
    Para : string;
    s1   : string;
  begin
    Name := Trim( Uppercase( nick ) );
    Indx := IndexOfName( Name );
    OutP := '';
    if Length( s ) > 0 then begin
      Comm := Uppercase( Trim( Copy( s, 1, Pos( ' ', s + ' ' ) - 1 ) ) );
      Para := Trim( Copy( s, Pos( Comm, s ) + Length( Comm ) + 1, Length( s ) ) );
      if Trim( Uppercase( Para ) ) = Comm then Para := '';
      case Comm of
        'DELETE'   : if Indx >= 0 then begin
                       Self.Delete( Indx );
                       OutP := 'Profile for ' + nick + ' deleted';
                       Save;
                     end else OutP := 'Profile not found; Delete';
        'EMAIL'    : if Indx >= 0 then begin
                       s1 := Self.Strings[ Indx ];
                       Self.Delete( Indx );
                       Edit( s1, Para, 1 );
                       Self.Add( s1 );
                       Save;
                       OutP := 'eMail changed to "' + Para + '"';
                    end else OutP := 'Profile not found; eMail';
        'HELP'     : Help;
        'LOCATION' : if Indx >= 0 then begin
                       s1 := Self.Strings[ Indx ];
                       Self.Delete( Indx );
                       Edit( s1, Para, 2 );
                       Self.Add( s1 );
                       Save;
                       OutP := 'Location changed to "' + Para + '"';
                     end else OutP := 'Profile not found; Location';
        'NAME'     : if Indx >= 0 then begin
                       s1 := Self.Strings[ Indx ];
                       Self.Delete( Indx );
                       Edit( s1, Para, 3 );
                       Self.Add( s1 );
                       Save;
                       OutP := 'Name changed to "' + Para + '"';
                     end else OutP := 'Profile not found; Name';
        'NEW'      : if Indx < 0 then begin
                       Add( Name + NameValueSeparator + nick + ';;;;;' );
                       OutP := 'Profile for ' + nick + ' created';
                       Save;
                     end else OutP := 'Profile already created';  // if IndexOf
        'RELOAD'   : if ( Indx >= 0 ) and ( Trim( Uppercase( fGod ) ) = Trim( Uppercase( Name ) ) ) then begin
                       Reload;
                       OutP := '.prof file reloaded';
                     end else OutP := 'You need to be God to do this';
        'URL'      : if Indx >= 0 then begin
                       s1 := Self.Strings[ Indx ];
                       Self.Delete( Indx );
                       Edit( s1, Para, 4 );
                       Self.Add( s1 );
                       Save;
                       OutP := 'URL changed to "' + Para + '"';
                     end else OutP := 'Profile not found; URL';
        else if Length( Comm ) > 0 then
               if IndexOfName( Name ) >= 0 
                 then OutP := Display( IndexOfName( Comm ) )
                 else OutP := 'Profile not found';
      end;  // case
    end else OutP := Display( IndexOfName( Name ) );
    if OutP = '' then OutP := 'Unknown command';
    Result := OutP;
  end;  // tProf.Parse
  
  
  procedure tProf.Reload;
    // reload profile data
  begin
    try
      LoadFromFile( 'shao.Prof' );
    except;
    end;
  end;  // tProf.Reload
  
  
  function tProf.Save : boolean;
    // Save profiles to disk
  begin
    try
      SaveToFile( 'Shao.prof' );
      Result := TRUE;
    except
      Result := FALSE;
    end;
  end;  // tProf.Save;
  
  
end.  // tProfile
  
    
