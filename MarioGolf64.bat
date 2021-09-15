@ECHO OFF
dmd -shared -g -ofMarioGolf64.dll plugin.d mariogolf.d
if NOT ["%errorlevel%"]==["0"] pause
