#include <Array.au3>

#include <TCP.au3> ;Ensure this is Kip's TCP library available at (https://www.autoitscript.com/forum/topic/74325-tcp-udf-event-driven/)

Global Const $USER_FLAG_ONLINE = 1
Global Const $USER_FLAG_MUTE = 2
Global Const $USER_FLAG_ADMIN = 4
Global Const $USER_FLAG_ROOT = 8
Global Const $USER_FLAG_GHOST = 16
Global Const $USER_FLAG_AWAY = 32

ConsoleWrite("Preparing settings map..." & @CRLF)
Global $mSettings[]
$mSettings["Server IP"] = "0.0.0.0" ;The IP address to host the server on
$mSettings["Server Port"] = 100 ;The port number to host the server on
$mSettings["Server Name"] = "kSCP Server"
$mSettings["Server MoTD"] = "Welcome to " & $mSettings["Server Name"] & ", built using revision 9 of kSCP (Simple Chat Protocol) which can be found at (http://kchat.kealper.com/sourcecode/Simple%20Chat%20Protocol%20Documentation%20and%20Specification.txt)."
$mSettings["Users Maximum"] = 100 ;Maximum allowed connections at one time
$mSettings["Auth Password"] = ""

Global $mUsers[] ;Create a map for all users

ConsoleWrite("Starting server on " & $mSettings["Server IP"] & ":" & $mSettings["Server Port"] & "..." & @CRLF)
Global $hSocket = _TCP_Server_Create($mSettings["Server Port"], $mSettings["Server IP"])
If @error Then
	LogFatal("There was an error starting the server." & @CRLF)
EndIf
_TCP_RegisterEvent($hSocket, $TCP_NEWCLIENT, "AcceptClient")
_TCP_RegisterEvent($hSocket, $TCP_DISCONNECT, "LostClient")
_TCP_RegisterEvent($hSocket, $TCP_RECEIVE, "NewPacket")

While 1
	Sleep(0)
WEnd

Func AcceptClient($hClient, $iError)
	ConsoleWrite("Received a new client on socket " & $hClient & "." & @CRLF)
	If CountUsers() >= $mSettings["Users Maximum"] Then
		_TCP_Send($hClient, "KILL" & Chr(1) & "There is not enough space left on this server for more connections (the maximum is " & $mSettings["Users Maximum"] & "). Either try again now, or try again later when there may be more spaces available." & @CRLF)
		ConsoleWrite("Too many clients, disconnecting socket " & $hClient & "..." & @CRLF)
	EndIf
EndFunc
Func LostClient($hClient, $iError)
	ConsoleWrite("Lost client on socket " & $hClient & "." & @CRLF)
	If UserExists($mSettings[$hClient]) Then
		RemoveUser($mSettings[$hClient])
	EndIf
EndFunc
Func NewPacket($hClient, $sData, $iError)
	ConsoleWrite("Received packet from socket " & $hClient & ", parsing and processing..." & @CRLF)
	If Not $sData Then
		ConsoleWrite("Packet from socket " & $hClient & " was empty." & @CRLF)
		Return
	ElseIf Not StringRight($sData, 1) = @CRLF Then
		ConsoleWrite("Packet from socket " & $hClient & " was malformed." & @CRLF)
		Return
	EndIf
	$aPackets = StringSplit($sData, @CRLF)
	If Not IsArray($aPackets) Then
		ConsoleWrite("Packet from socket " & $hClient & " was malformed." & @CRLF)
		Return
	EndIf
	For $i = 1 To $aPackets[0]
		If Not $aPackets[$i] Then ContinueLoop
		ConsoleWrite("Packet #" & $i & ": " & $aPackets[$i] & @CRLF) ;This should definitely not be used if any RAW data is sent to another user
		$aPacketData = StringSplit($aPackets[$i], Chr(1))
		Switch $aPacketData[1]
			Case "JOIN"
				If $aPacketData[0] < 2 Then Return
				ConsoleWrite("Join request from socket " & $hClient & ", " & $aPacketData[2] & " | " & $aPacketData[3] & @CRLF)
				Local $sUsername = $aPacketData[2]
				If $aPacketData[0] < 3 Then
					Local $sUserAgent = "Unknown"
				Else
					Local $sUserAgent = $aPacketData[3]
				EndIf
				Local $sUserIP = _TCP_Server_ClientIP($hClient)
				Local $aData[4] ;User Agent, User Flags, User IP, User Socket
				$aData[0] = $sUserAgent
				$aData[1] = $USER_FLAG_ONLINE
				$aData[2] = $sUserIP
				$aData[3] = $hClient
				$mUsers[$sUsername] = $aData
				$mUsers[$hClient] = $sUsername
				ConsoleWrite($sUsername & ":" & $aData[0] & ":" & $aData[1] & ":" & $aData[2] & ":" & $aData[3] & @CRLF)
				TellMsg($sUsername, "Message of the Day", $mSettings["Server MoTD"])
				Broadcast("Announcement", $sUsername & " (" & $aData[0] & ") has joined the chat!")
			Case "LIST"
				Local $aUsers = MapKeys($mUsers)
				If UBound($aUsers) Then
					Local $sPacket = "LIST" & Chr(1)
					Local $iLoopCounter = 0
					For $sUsername In $aUsers
						If IsString($sUsername) Then
							If $iLoopCounter > 0 Then
								$sPacket &= Chr(1)
							EndIf
							Local $aTemp = $mUsers[$sUsername]
							$sPacket &= "["
							If BitAND($aTemp[1], $USER_FLAG_ONLINE) Then
								$sPacket &= "O"
							EndIf
							If BitAND($aTemp[1], $USER_FLAG_MUTE) Then
								$sPacket &= "M"
							EndIf
							If BitAND($aTemp[1], $USER_FLAG_ADMIN) Then
								$sPacket &= "A"
							EndIf
							If BitAND($aTemp[1], $USER_FLAG_ROOT) Then
								$sPacket &= "R"
							EndIf
							If BitAND($aTemp[1], $USER_FLAG_GHOST) Then
								$sPacket &= "G"
							EndIf
							If BitAND($aTemp[1], $USER_FLAG_AWAY) Then
								$sPacket &= "B"
							EndIf
							$sPacket &= "] " & $sUsername & " - " & $aTemp[0]
							$iLoopCounter += 1
						EndIf
					Next
					$sPacket &= @CRLF
					ConsoleWrite("Sending packet: " & $sPacket)
					_TCP_Send($hClient, $sPacket)
				EndIf
			Case "PING"
				If $aPacketData[0] > 1 Then
					_TCP_Send($hClient, "PONG" & Chr(1) & $aPacketData[2] & @CRLF)
				Else
					_TCP_Send($hClient, "PONG" & @CRLF)
				EndIf
			Case "QUIT"
				If $aPacketData[0] > 1 Then
					If $aPacketData[1] = $mUsers[$hClient] Then
						RemoveUser($mUsers[$hClient])
						Broadcast("Announcement", $aPacketData[2] & " has left the chat!")
					Else
						Kill($hClient, "You attempted to disconnect a username other than your own (" & $mUsers[$hClient] & ").")
					EndIf
				Else
					Local $sUsername = $mUsers[$hClient]
					RemoveUser($mUsers[$hClient])
					Broadcast("Announcement", $sUsername & " has left the chat!")
				EndIf
			Case "MSG"
				If $aPacketData[0] < 3 Then Return
				Local $sTemp = $mUsers[$hClient]
				If $aPacketData[2] = $sTemp Then
					If $aPacketData[3] Then
						TellMsgAllExcept($aPacketData[2], $aPacketData[3])
					EndIf
				Else
					Kill($sTemp, "Your client sent either an invalid/malformed packet or you attempted to send a message with a username other than your own (" & $sTemp & ").")
				EndIf
			Case "PM"
				If $aPacketData[0] < 3 Then Return
				Local $sTemp = $mUsers[$hClient]
				ConsoleWrite("Received PM; Source: " & $sTemp & ", Dest: " & $aPacketData[2] & ", Msg: " & $aPacketData[3] & @CRLF)
				TellPM($sTemp, $aPacketData[2], $aPacketData[3])
			Case "MOTD"
				Local $sTemp = $mUsers[$hClient]
				TellMsg($sTemp, "Message of the Day", $mSettings["Server MoTD"])
			Case "AUTH"
				If $aPacketData[0] > 1 Then
					If $aPacketData[2] = $mSettings["Auth Password"] Then
						Local $sTemp = $mUsers[$hClient]
						Local $aTemp = $mUsers[$sTemp]
						$aTemp[1] = $aTemp[1] + $USER_FLAG_ROOT
;						$aTemp[1] = BitAND($aTemp[1], $USER_FLAG_ROOT)
						TellMsg($sTemp, "Announcement", "You are now logged in as root.")
						TellMsg($sTemp, "Debug", $aTemp[1])
					Else
						Local $sTemp = $mUsers[$hClient]
						Kill($sTemp, "Incorrect root password.")
					EndIf
				Else
					Local $sTemp = $mUsers[$hClient]
					Local $aTemp = $mUsers[$sTemp]
					If BitAND($aTemp[1], $USER_FLAG_ROOT) Then
						$bUserFlags = $USER_FLAG_ONLINE
						If BitAND($aTemp[1], $USER_FLAG_MUTE) Then
							$bUserFlags = $bUserFlags + $USER_FLAG_MUTE
						EndIf
						If BitAND($aTemp[1], $USER_FLAG_GHOST) Then
							$bUserFlags = $bUserFlags + $USER_FLAG_GHOST
						EndIf
						If BitAND($aTemp[1], $USER_FLAG_AWAY) Then
							$bUserFlags = $bUserFlags + $USER_FLAG_AWAY
						EndIf
						TellMsg($sTemp, "Announcement", "You are no longer logged in as root.")
					Else
						TellMsg($sTemp, "Announcement", "You must specify a password in order to log in as root.")
					EndIf
				EndIf
			Case "RAW"
				If $aPacketData[0] < 3 Then Return
				SendRaw($aPacketData[2], $aPacketData[3])
		EndSwitch
	Next
EndFunc

Func LogFatal($sMsg)
	ConsoleWrite($sMsg)
	While 1
		;Do nothing until we're closed off
	WEnd
EndFunc
Func Broadcast($sUsername, $sMsg)
	_TCP_Server_Broadcast("MSG" & Chr(1) & $sUsername & Chr(1) & $sMsg & @CRLF)
EndFunc
Func TellMsg($sUsername, $sFakeUser, $sMsg)
	Local $aTemp = $mUsers[$sUsername]
	_TCP_Send($aTemp[3], "MSG" & Chr(1) & $sFakeUser & Chr(1) & $sMsg & @CRLF)
EndFunc
Func TellPM($sSourceUsername, $sDestUsername, $sMsg)
	If UserExists($sDestUsername) Then
		If UserMuted($sSourceUsername) Then
			Local $aTemp = $mUsers[$sDestUsername]
			If BitAND($aTemp[1], $USER_FLAG_ADMIN) Or BitAND($aTemp[1], $USER_FLAG_ROOT) Then
				ConsoleWrite("Sending PM; Source: " & $sSourceUsername & ", Dest: " & $sDestUsername & ", Msg: " & $sMsg & @CRLF)
				_TCP_Send($aTemp[3], "PM" & Chr(1) & $sSourceUsername & Chr(1) & $sMsg & @CRLF)
			Else
				TellMsg($sSourceUsername, "Announcement", "You are muted, and thus you may only private messages an administrator or root user.")
			EndIf
		Else
			Local $aTemp = $mUsers[$sDestUsername]
			ConsoleWrite("Sending PM; Source: " & $sSourceUsername & ", Dest: " & $sDestUsername & ", Msg: " & $sMsg & @CRLF)
			_TCP_Send($aTemp[3], "PM" & Chr(1) & $sSourceUsername & Chr(1) & $sMsg & @CRLF)
		EndIf
	Else
		TellMsg($sSourceUsername, "Announcement", $sDestUsername & " is not online.")
	EndIf
EndFunc
Func TellMsgAllExcept($sExceptedUsername, $sMsg)
	If UserMuted($sExceptedUsername) Then
		TellMsg($sExceptedUsername, "Announcement", "You are muted, and thus you have no permission to speak.")
	Else
		Local $aUsers = MapKeys($mUsers)
		If UBound($aUsers) Then
			For $sUsername In $aUsers
				If IsString($sUsername) And $sUsername <> $sExceptedUsername Then
					Local $aTemp = $mUsers[$sUsername]
					_TCP_Send($aTemp[3], "MSG" & Chr(1) & $sUsername & Chr(1) & $sMsg & @CRLF)
				EndIf
			Next
		EndIf
	EndIf
EndFunc
Func SendRaw($sUsername, $sRaw)
	Local $aTemp = $mUsers[$sUsername]
	_TCP_Send($aTemp[3], "RAW" & Chr(1) & $sUsername & Chr(1) & $sRaw & @CRLF)
EndFunc
Func UserExists($sUsername)
	If MapExists($mUsers, $sUsername) Then
		Return True
	Else
		Return False
	EndIf
EndFunc
Func UserMuted($sUsername)
	If UserExists($sUsername) Then
		Local $aTemp = $mUsers[$sUsername]
		If BitAND($aTemp[1], $USER_FLAG_MUTE) Then
			Return True
		Else
			Return False
		EndIf
	Else
		Return False
	EndIf
EndFunc
Func RemoveUser($sUsername)
	If UserExists($sUsername) Then
		Local $aTemp = $mUsers[$sUsername]
		MapRemove($mUsers, $aTemp[3])
		MapRemove($mUsers, $sUsername)
	EndIf
EndFunc
Func CountUsers()
	Local $aUsers = MapKeys($mUsers)
	Local $iUserCount = 0
	If UBound($aUsers) Then
		For $sUsername In $aUsers
			If IsString($sUsername) Then
				$iUserCount += 1
			EndIf
		Next
	EndIf
	Return $iUserCount
EndFunc
Func Kill($sUsername, $sMsg)
	If UserExists($sUsername) Then
		Local $aTemp = $mUsers[$sUsername]
		_TCP_Send($aTemp[3], "KILL" & Chr(1) & $sMsg & @CRLF)
		_TCP_Server_DisconnectClient($aTemp[3])
		RemoveUser($sUsername)
		Broadcast("Announcement", $sUsername & " has been kicked from the server.")
	EndIf
EndFunc
