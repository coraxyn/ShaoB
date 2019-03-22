This file tries to explain ShaoB, small IRC bot.

ShaoB is pronounced Sh - ow - Bee.  Shao means ‘small’ in Mandarin Chinese.

In order to use ShaoB you will need:

1 - Executable is called ShaoB, currently compiled for Mac OS
2 - shao.8ball is list of snippy responses 
3 - shao.config is basic configuration data
4 - shao.ops soon to be deprecated
5 - shao.prof soon to be deprecated
6 - shao.weather is user (nick) location information

Currently these files must be placed in same directory as Shao executable.

You will also need keys from:

1 - https://developer.oxforddictionaries.com  API ID and key
2 - https://www.apixu.com API key

Both these sites offer free limited ID and/or keys

FILES:

shao.8ball contains list of CRLF delimited pithy lines to respond to .8Ball command.  Knock yourself out.

shao.config knows of the following parameters:

Network: irc.freenode.net
Port: 6667
Channel: fpc
Username: ShaoB_
Password:
OEDAppID: xxxxxxxxxx
OEDKey: xxxxxxxxxxxxxxxxxxxxxx
APIXU: xxxxxxxxxxxxxxxxxxx

In order to run ShaoB requires Network:, Channel:, OEDAppID:, OEDKey:, and APIXU: parameters
If Port: is absent 6667 is used
If Channel: is not prefixed with # then one is added
If Username: is absent then ShaoB is used
If password is absent then it is assumed none is required
OEDAppID and OEDKey are obtained from Oxford Dictionaries web site mentioned above
APIXU is obtained from APIXU site mentioned above

BUILDING ShaoB:

Ararat Synapse code library is required to build ShaoB.  This can be found at http://www.ararat.cz/synapse/doku.php/download

STARTING ShaoB:

ShaoB optionally accepts one parameter on start up: Channel.  This will override Channel: parameter in shao.config

ShaoB is console or terminal application.  It is recommended that terminal be 132 columns wide and 50 rows long, though other sizes will also work.

RUNNING ShaoB:

ShaoB clears console and write one line at top of screen with name and version number.  Bottom line is blank.  Both these lines are in inverted video.  If shao.config is correct then ShaoB connects to IRC network mentioned in Network: parameter, attempts to log in using Username: and join channel specified by Channel:
Once fully connected one can type message that will be sent to channel.  If one presses TAB key then QUIT [Y/N] message is displayed.

FPC:

Free Pascal Compiler can be found at https://www.freepascal.org

Have fun
