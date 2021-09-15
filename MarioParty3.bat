@ECHO OFF
dmd -shared -g -ofMarioParty3.dll plugin.d marioparty.d marioparty3.d
if NOT ["%errorlevel%"]==["0"] pause
