@ECHO OFF
dmd -shared -g -ofMarioParty2.dll plugin.d marioparty.d marioparty2.d
if NOT ["%errorlevel%"]==["0"] pause
