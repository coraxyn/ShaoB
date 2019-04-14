{ 
  sCurl.pas
  Copyright (c) 2019 Paul Davidson. All rights reserved.
}


unit sCurl;


  {$MODE OBJFPC}
  {$H+}
  {$LINKLIB 'libcurl.dylib'}

interface


  uses
   Classes,
   libCurl,
   SysUtils,
   UNIXType;


  type
  
  
    tCurl = class( TObject )
      private
         fCurlp  : pCurl;
         fStream : TMemoryStream;
      public
        constructor Create;
        destructor  Destroy; override;
        function    Get( s : string ) : string;
        function    Get( s : string; a : array of string ) : string;
    end;


  var
    fCurl : tCurl;


implementation


  uses
    sConsole;

  
  function DoWrite( p : pointer; s : size_t; n : size_t; d : pointer) : size_t; cdecl;
  begin
   DoWrite := TStream( d ).write( p^, s * n );
  end;  // DoWrite


  constructor tCurl.Create;
  begin
    inherited Create;
    fStream := TMemoryStream.Create;
    fCurlp:= curl_easy_init;
  end;  // tCurl.Create;
    

  destructor tCurl.Destroy;
  begin
    curl_easy_cleanup( fCurlp );
    fStream.Free;
    inherited Destroy;
  end;  // tCurl.Destroy

  
  function tCurl.Get( s : string ) : string;
    // Short version of next of next Get
  begin
    Get := Self.Get( s, [] );
  end;  // tCurl.Get

  
  function tCurl.Get( s : string; a : array of string ) : string;
    // Send HTTP request and receive content
  var
    b : pcurl_sList;
    i : integer;
    t : string;
  begin
    s := s + #00;                                                                    // Quick way to do PChar.  Remember to @s[ 1 ]
    t := '';
    try
      curl_easy_setopt( fCurlp, CURLOPT_VERBOSE, [ FALSE ] );                        // Turn verbose off
      curl_easy_setopt( fCurlp, CURLOPT_MAXFILESIZE, [ 1024 * 20 ] );                // Read maximum 20k in.  This is to eliminate DoS via long headers or content
      curl_easy_setopt( fCurlp, CURLOPT_MAXREDIRS, [ 10 ] );                         // Allow max of 10 reirects to eliminate infinite redirect DoS
      curl_easy_setopt( fCurlp, CURLOPT_CONNECTTIMEOUT, [ 3 ] );                     // Short connect timeout for hang DoS
      curl_easy_setopt( fCurlp, CURLOPT_TIMEOUT, [ 3 ] );                            // Short response timeout for hang Dos
      if length( a ) > 0 then begin                                                            // Check for any more/custom headers
        b := NIL;
        for i := 0 to length( a ) - 1 do begin
           a[ i ] := a[ i ] + #00;
           b := curl_slist_append( b, @a[ i ][ 1 ] );
        end;
        curl_easy_setopt( fCurlp, CURLOPT_HTTPHEADER, [ b ] );
      end;
      curl_easy_setopt( fCurlp, CURLOPT_URL, [ @s[ 1 ] ] );                          // Set URL
      curl_easy_setopt( fCurlp, CURLOPT_WRITEFUNCTION, [ @DoWrite ] );               // Set data transfer function
      curl_easy_setopt( fCurlp, CURLOPT_WRITEDATA, [ pointer( fStream ) ] );         // Set data transfer location
      curl_easy_perform( fCurlp );                                                   // Go for it!
      fStream.Position := 0;                                                         // Set stream to start
      SetLength( t, fStream.Size );                                                  // Set buffer size
      fStream.Read( t[ 1 ], fStream.Size );                                          // Transfer from stream
      fStream.Clear;                                                                 // Empty stream
      curl_easy_reset( fCurlp );                                                     // Reset curl to initial state
      if length( a ) > 0 then  curl_slist_free_all( b );
    except
      on E : Exception do fCon.Send( 'Curl> ' + E.Message + ' ' + E.ClassName, taBold );
    end;
    Get := t;
  end;  // tCurlGet


end.  // sCurl 
