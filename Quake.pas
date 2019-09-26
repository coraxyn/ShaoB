program Quake;

  uses
    cThreads,
    cMem,
    sCurl,
    sQuake;
    
  var
    fQuake : tQuake;
    
    
  begin
    fCurl := TCurl.Create;
    writeln( 'Quake' );
    fQuake := tQuake.Create;
    fQuake.Start;
    readln;
    fCurl.Free;
    fQuake.Free;
  end. 
