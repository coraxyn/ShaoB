{
  sConsole.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.
}

 
unit sConsole;


  {$MODE OBJFPC}
  {$H+}


interface


  uses
    Classes;


  type
    tAttribute = ( taBlink,
                   taBold,
                   taInvBold,
                   taInverse,
                   taInvisible,
                   taLow,
                   taNormal,
                   taUnderline );  // tAttribute
                   

    tConsole = class( TObject )
      private
        fBlank     : string;
        fLog       : TStringList;
        fLogTime   : boolean;                             // If TRUE then prepends time to log entry
        fTerminate : boolean;
        fTitle     : string;
        fXCurr     : integer;
        fXMax      : integer;
        fYMax      : integer;
        procedure    Attribute( a : tAttribute );
        procedure    ClearEOL;
        procedure    Init;
        function     KeyGet : char;
        procedure    Scroll;
        procedure    Window( t, b : integer );
      public
        constructor Create( t, v : string );
        destructor  Destroy; override;
        procedure   AnyKey;
        procedure   Beep;
        property    Blank : string read fBlank;
        procedure   Clear;
        procedure   ClearLine( y : integer );
        procedure   ClearWindow;
        function    DecodeHTML( s : string ) : string;
        procedure   Display;
        function    KeyGet( out special : boolean ) : char;
        procedure   Line1( s : string );
        procedure   LineGet( var s : string );
        procedure   LineGet( x, y : integer; var s : string );
        procedure   LogShow;
        property    LogTime : boolean write fLogTime;
        function    Menu( s : string ) : char;
        procedure   Ping;
        procedure   Send( s : string );
        procedure   Send( s : string; a : tAttribute );
        procedure   Terminate;
        procedure   XY( x, y : integer );
        procedure   XYSA( x, y : integer; const s : string; a : tAttribute );
        function    YesNo( s : string ) : boolean;
        property    YMax : integer read fYMax;
      end;  // tConsole


  var
    fCon : tConsole;
    gSysBuildCPU  : string;
    gSysBuildDate : string;
    gSysBuildOS   : string;
    gSysCompiler  : string;
    gSysPWD       : string;
    gSysStartTime : TDateTime;
    gTitle        : string;                 // Program title
    gVersion      : string;                 // Program version number


implementation


  uses
    Keyboard,
    StrUtils,
    SysUtils;


  const
    cKeyWait = 50;       // Wait time between keyboard scans
    gkBS    = #08;
    gkCR    = #13;
    gkESC   = #27;
    gkLF    = #10;
    gkTAB   = #09;
    gkCRLF  = gkCR + gkLF;
    
    gkArrowUp    = #33;
    gkArrowLeft  = #35;
    gkArrowRight = #37;
    gkArrowDown  = #39;

    gkDelete     = #42;
    gkHome       = #43;
    gkEnd        = #38;


  constructor tConsole.Create( t, v : string );
    // s is app title of page
  begin
    inherited Create;
    fLog            := TStringList.Create;
    fLog.Sorted     := FALSE;
    fLogTime        := TRUE;
    fTerminate      := FALSE;
    gSysBuildCPU    := {$I %FPCTARGETCPU%};
    gSysBuildDate   := {$I %date%} + ' ' + {$I %time%};
    gSysBuildOS     := {$I %FPCTARGETOS%};
    gSysCompiler    := 'FPC ' + {$I %FPCVERSION%};
    gSysPWD         := GetCurrentDir; 
    gSysStartTime   := Now;
    gTitle          := t;
    gVersion        := v;
    InitKeyboard;
    Init;
  end;  // tConsole.Create


  destructor tConsole.Destroy;
  begin
    fLog.Free;
    DoneKeyboard;
    inherited Destroy;
  end;  // tConsole.Destroy


  procedure tConsole.AnyKey;
    // Hit any key to continue
  var
    b : boolean;
  begin
    ClearLine( fYMax );
    XYSA( 2, fYMax, 'Hit any key to continue', taInvBold );
    XY( 26, fYMax );
    KeyGet( b );
  end;  // tConsole.AnyKey


  procedure tConsole.Attribute( a : tAttribute );
    // Set text attribute
  begin
    case a of
      taBlink     : write( gkESC, '[0m', gkESC, '[5m' );
      taBold      : write( gkESC, '[0m', gkESC, '[1m' );
      taInvBold   : write( gkESC, '[0m', gkESC, '[40m', gkESC, '[1;32m' );
      taInverse   : write( gkESC, '[0m', gkESC, '[7m' );
      taInvisible : write( gkESC, '[0m', gkESC, '[8m' );
      taLow       : write( gkESC, '[0m', gkESC, '[2m' );
      taNormal    : write( gkESC, '[0m', gkESC, '[m' );
      taUnderline : write( gkESC, '[0m', gkESC, '[4m' );
  	end;  // case
  end;  // tConsole.Attribute


  procedure tConsole.Beep;
    // Make noise
  begin
    write( #7 );
  end;  // tConsole.Beep;

  
  procedure tConsole.Clear;
    // Clear entire screen
  begin
    Window( 1, fYMax );
    Attribute( taNormal );
    write( gkESC, '[2J' );
    XYSA( 1, 1, fBlank, taNormal );
  end;  // tConsole.Clear


  procedure tConsole.ClearEOL;
    // Clear end of line
  begin
    write( gkESC, '[K' );
  end;  // tConsole.ClearEOL


  procedure tConsole.ClearLine( y : integer );
    //  Clear line y
  var
    a : tAttribute;
  begin
    if ( y = 1 ) or ( y = fYMax )
      then a := taInvBold
      else a := taNormal;
    XYSA( 1, y, fBlank, a );
  end;  // 


  procedure tConsole.ClearWindow;
    //  Clears scroll window
  var
    i : integer;  
  begin
    Attribute( taNormal );
    for i := 2 to fYMax do begin
      XY( 1, i );
      ClearEOL;
    end;
  end;  // tConsole.ClearWindow;    


  function tConsole.DecodeHTML( s : string ) : string;
    // Replaces #&nnn strings with char
  begin
    result := StringsReplace( s, [ '&#039;', '&#8216;', '&#8217;', '&amp;', '&lt;', '&gt;', '&quot;', '&apos;', '' ], [  '''', '''', '`', '&', '<', '>', '"', #39, #39 ], [ rfReplaceAll] );
  end;  //  tConsole.DecodeHTML
  
  
  procedure tConsole.Display;
    // Display selected globals on screen
  begin
    fCon.Send( 'Global parameters:', taBold );
    fCon.Send( '  Target CPU: ' + gSysBuildCPU, taNormal );
    fCon.Send( '  Build date: ' + gSysBuildDate, taNormal );
    fCon.Send( '    Compiler: ' + gSysCompiler, taNormal );
    fCon.Send( '   Directory: ' + gSysPWD, taNormal );
    fCon.Send( '  Start time: ' + FormatDateTime( 'YYYY/MM/DD HH:nn:SS', gSysStartTime ), taNormal );
  end;  // tConsole.Display


  procedure tConsole.Init;
    // Initialize console
  begin
    Attribute( taNormal );
    Clear; 
    fXMax := 132;
    fYMax := 50;
    Window( 1, fYMax );                                               // Remove scroll window
    SetLength( fBlank, fXMax );                                       // Make fBlank line
    Fillchar( fBlank[ 1 ], fXMax, ' ' );                              // Fill fBlank with blanks
    XYSA( 1, 1,         fBlank, taInvBold );                          // Write inverted blank line at top of console                            
    XYSA( 1, fYMax,     fBlank, taInverse );                          // Write inverted blank line at bottum of console
    fXCurr := 2;                                                      // Sett fXCurr
  end;  // tConsole.Init


  function tConsole.KeyGet( out special : boolean ) : char;
    // Get key from terminal without having to press return
  var
    c : char;
    e : integer;
    k : TKeyEvent;
  begin
    special := FALSE;
    repeat
      Sleep( 50 );
    until KeyPressed or fTerminate;
    if not fTerminate then begin
      k := GetKeyEvent;
      k := TranslateKeyEvent( k );
      c := GetKeyEventChar( k );
      e := GetKeyEventCode( k ) shr 8;
      if e = $ff then begin
        special := TRUE;
        c       := char( k and $ff );
      end else begin
        case k of
          $010d : c := gkCR;
          $011B : c := gkESC;
          $0e08 : c := gkBS;
          $0f09 : c := gkTAB;
        end;
      end;
    end else c := #00;
// writeln( BoolToStr( special ) + ' '+ IntToHex( GetKeyEventCode( k ), 4 ) + ' ' + intToStr( ord( c ) ) + ' :' + c + ':' );
    KeyGet := c;
  end;  // tConsole.KeyGet  }


  function tConsole.KeyGet : char;
  var
    b : boolean;
  begin
    KeyGet := Self.KeyGet( b );
  end;  // tConsole.KeyGet

  
  procedure tConsole.Line1( s : string );
    // Write top line
  begin
    fTitle := s;
    XYSA( 1, 1, fBlank, taInvBold );
    XYSA( ( fXMax - Length( fTitle ) ) div 2, 1, fTitle, taInvBold );
  end;  // tConsole.Line1

  
  procedure tConsole.LineGet( var s : string );
    // Bottom line
  begin
    LineGet( 2, fYMax, s );
  end;  // tConsole.LineGet

  
  procedure tConsole.LineGet( x, y : integer; var s : string );
    // Gets line from keyboard
    // xOffset is offset, if any from left most screen
  var
    a : tAttribute;
    b : boolean;
    c : char;
  begin
    if ( y = 1 ) or ( y = fYMax ) 
      then a := taInvBold
      else a := taNormal;
    XYSA( x, y, ' ', a );
    ClearEOL;
    XY( x, y );
    fXCurr := x;
    repeat
      c := KeyGet( b );
      if not fTerminate then begin
        if not b and ( c >= ' ' ) and ( c <= '~' ) then begin
          if fXcurr - 1 > length( s )
            then s := s + c
            else s[ fXCurr - x + 1 ] := c;
          XYSA( fXCurr, y, c, a );
          if fXCurr + 1 < fXMax then Inc( fXCurr );
          XY( fXCurr, fYMax );
        end else case c of
          gkArrowLeft  : if fXCurr > x then begin
                           dec( fXCurr );
                           XY( fXCurr, fYMax );
                         end;
          gkArrowRight : if fXCurr - x + 1 < length( s ) then begin
                           inc( fXCurr );
                           XY( fXCurr, fYMax );
                         end;
          gkBS         : if fXCurr > x then begin
                           dec( fXCurr );
                           s := s + ' ';
                           delete( s, fXCurr - x + 1, 1 );
                           XYSA( x, y, s, a );
                           XY( fXCurr, y );
                         end;
        end;  // case c
      end;  // if not fTerminate
    until fTerminate or ( c = gkCR );  // repeat
    XY( x, y );
  end;  // tConsole.LineGet


  procedure tConsole.LogShow;
    // Draw log content
  var
    a : tAttribute;
    i : integer;
    j : integer;
  begin
    ClearWindow;
    j := fYMax - 1;
    for i := fLog.Count - 1 downto 0 do begin
      a := taNormal;
      case fLog.Strings[ i ][ 1 ] of
        '0' : a := taBlink;
        '1' : a := taBold;
        '2' : a := taInvBold;
        '3' : a := taInvBold;
        '4' : a := taInvisible;
        '5' : a := taLow;
        '6' : a := taNormal;
        '7' : a := taUnderline;
      end;
      XYSA( 1, j, copy( fLog.Strings[ i ], 2, length( fLog.Strings[ i ] ) ), a );
      dec( j );
    end;
  end;  // tConsole.LogShow


  function  tConsole.Menu( s : string ) : char;
    // Displays menu.  CAPITAL letters in items are valid reponses
  var
    b    : boolean;
    c    : string;
    caps : string;
    i    : integer;
  begin
    b    := TRUE;
    caps := '';                                                         // This will hold valid responses
    XYSA( 1, fYMax, fBlank, taInverse );                                // Blank out last line
    for i := 1 to length( s ) do begin                                  // Loop through each character of menu
      if b and ( s[ i ] in [ '0'..'9', 'A'..'Z' ] ) then begin                              // If char is uppercase 
        caps := caps + uppercase( s[ i ] );                             // Remember it
        XYSA( i + 1, fYMax, s[ i ], taInvBold );                        // Write out bold
        b := FALSE;
      end else XYSA( I + 1, fYMax, s[ i ], taInverse );                 // Or not
      if s[ i ] = ' ' then b := TRUE;
    end;
    fXCurr := length( s ) + 3;
    repeat                                                              // Wait for key
      XY( fXCurr, fYMax );                                              // Park cursor
      c := uppercase( KeyGet );
    until ( Pos( c, caps ) > 0 ) or ( c = gkESC ) or fTerminate;        // Stop looping when valid response is found
    XYSA( fXCurr, fYMax, c, taInverse );                                // write out key
    Menu := c[ 1 ];
  end;  // tConsole.Menu


  procedure tConsole.Ping;
    // Puts ping time on line one
  var
    s : string;
  begin
    DateTimeToString( s, 'HH:MM ', Now );
    XYSA( 2, 1, 'Ping: ' + s, taInvBold );
    XY( 1, fYMax );
  end;  // tConsole.Ping

  
  procedure tConsole.Scroll;
    // Scroll main window up one line
  begin
    XY( 1, 2 );
    write( gkESC, '[1M'  );
  end;  // tConsole.Scroll

 
  procedure tConsole.Send( s : string );
    // Send with taNormal attribute
  begin
    Self.Send( s, taNormal );
  end;  // tConsole.Send

  
  procedure tConsole.Send( s : string; a : tAttribute );
    // Writes a line of text to the screen.  Only printable characters please
  const
    delim = ' ,.:;' + gkCR;
  var
    blk   : string;    // Blank, same length as time
    blkln : integer;   // tab length
    out   : string;    // Current output line
    stop  : integer;   // 
    time  : string;    // Now
  begin
    blk   := '';
    blkln := 0;
    out   := '';
    time  := '';
    Attribute ( a );                          
    Window( 2, fYMax - 1 );                                                    // Make the middle window active
    XY( 1, fYMax - 1 );
    if fLogTime then begin
      DateTimeToString( time, 'HH:MM ', Now );                                 // Get current time
      blk   := copy( fBlank, 1, length( time ) );                              // Make tab same length as time for multi line s
      blkln := length( blk );
    end;
    repeat                                                                     // Start to parse out line
      if length( out ) = 0
        then out := time                                                       //   Add time leader
        else out := blk;                                                       //   Or add blanks 
      if length( s ) + blkln > fXMax then begin                                // Is line too long?
        stop := fXMax - blkln;
        while ( stop > 0 ) and ( Pos( s[ stop ], delim ) = 0 ) do dec( stop ); // Find nice place to chop line
        if stop > 0 then begin
          out := out + copy( s, 1, stop );
          s   := copy( s, stop + 1, length( s ) );
        end else begin
          out := out + copy( s, 1, fXMax - blkln );
          s   := copy( s, fXMax - blkln + 1, length( s ) );
        end;
      end else begin
        out := out + s;
        s   := '';
      end;
      Scroll;
      XY( 1, fYMax - 1 );
      write( out );
      if fLog.Count = fYMax - 2 then fLog.Delete( 0 );
      fLog.Add( intToStr( ord( a ) ) + copy( out, blkln + 1, length( out ) ) );
    until length( s ) = 0;
    Window( 1, fYMax );
    XY( 2, fYMax );
  end;  // tConsole.Send


  procedure TConsole.Terminate;
    // Signals keyboard loop to terminate 
  begin
    fTerminate := TRUE;
  end;  // tConsole.Terminate


  procedure tConsole.Window( t, b : integer );
    // Create Window region for top line t to bottom line b
  begin
    write( gkESC, '[', t, ';', b, 'r' );
  end;  // tConsole.Window

  
  procedure tConsole.XY( x, y : integer );
    // Position cursor at X, Y with 1,1 as upper left origin
  begin
    write( gkESC, '[', y, ';', x, 'H' );
  end;  // tConsole.XY


  procedure tConsole.XYSA( x, y : integer; const s : string; a : tAttribute );
  begin
    XY( x, y );
    Attribute( a );
    write( s );
  end;  // tConsole.XYSA


  function tConsole.YesNo( s : string ) : boolean;
    // Asks yes/question and awaits Y, y, N, n response.  No RETURN is needed
  var
    c : string;
  begin
    XYSA( 1, fYMax, fBlank , taInverse );
    XYSA( 2, fYMax, s + '[ / ]', taInverse );
    XYSA( length( s ) + 3, fYMax, 'Y', taInvBold );
    XYSA( length( s ) + 5, fYMax, 'N', taInvBold );
    fXCurr := length( s ) + 8;
    XY( fXCurr, fYMax );
    repeat
      c := KeyGet;
    until ( Pos( c, 'yYnN' ) > 0 ) or fTerminate;
    if c[ 1 ] in [ 'y', 'Y' ] then begin
      XYSA( length( s ) + 8, fYMax, 'Y', taInvBold );
      YesNo := TRUE;
    end else begin
      XYSA( length( s ) + 8, fYMax, 'N', taInvBold );
      YesNo := FALSE;
    end;
  end; // tConsole.YesNo


end.  // sConsole 
