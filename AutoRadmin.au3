#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=icon.ico
#AutoIt3Wrapper_Outfile=AutoRadmin.exe
#AutoIt3Wrapper_Res_Comment=AutoIt script for Radmin connection (uses local Radmin Viewer)
#AutoIt3Wrapper_Res_Description=AutoIt script for Radmin connection
#AutoIt3Wrapper_Res_Fileversion=2.0.0.0
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=p
#AutoIt3Wrapper_Res_ProductName=AutoRadmin
#AutoIt3Wrapper_Res_ProductVersion=3.5.2.1
#AutoIt3Wrapper_Res_CompanyName=https://github.com/egormkn/AutoRadmin
#AutoIt3Wrapper_Res_LegalCopyright=Egor Makarenko
#AutoIt3Wrapper_Res_Field=AutoIt Version|%AutoItVer%
#AutoIt3Wrapper_Res_Field=Build|%date%
#AutoIt3Wrapper_Run_Tidy=n
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

; ============================================================================
; AutoRadmin 2.0
;
; 作用：读取 config.ini 里的服务器参数与账号密码，直接启动本机已安装的
;       Radmin Viewer，并自动把账号密码填进 "Radmin 安全" 登录框。
;
; 与 1.0 的区别（1.0 自带便携版 Radmin，解压到 %TEMP%\AutoRadmin 运行）：
;   1. 不再解压任何东西，直接 Run 本机的 Radmin.exe，路径由 config.ini 指定
;   2. RADMINDIR 可以写目录，也可以直接写 Radmin.exe 的完整路径
;   3. 支持 %ProgramFiles(x86)% 这类环境变量
;   4. 配置为空或路径失效时，自动探测常见目录 / 注册表卸载信息
;   5. 仍然找不到时弹出文件选择框，选完把路径写回 config.ini
;   6. 安全窗口标题支持 中 / 英 / 俄 多语言，可用 WINDOWTITLE 覆盖
;   7. 用"窗口句柄差集"识别新弹出的登录框，不会误填到已存在的旧窗口
;   8. 等不到登录框时不报错退出（视为已保存凭据），只在托盘提示一次
;   9. Radmin 已在运行时的行为可配置：IFRUNNING=continue | exit
;
; 打包：只需 AutoRadmin.au3 + icon.ico，config.ini 由程序首次运行时生成。
; ============================================================================

#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include <StringConstants.au3>
#include <Misc.au3>
#include <Process.au3>

; ---------------------------- 配置变量 ----------------------------
Global $g_sArgs = ""
Global $g_sConnectUser = ""
Global $g_sConnectPass = ""
Global $g_sThroughUser = ""
Global $g_sThroughPass = ""
Global $g_sRadminDir = ""
Global $g_sExeName = "Radmin.exe"
Global $g_sWindowTitle = ""
Global $g_iWaitTimeout = 15
Global $g_sIfRunning = "continue"
Global $g_sDebug = "0"

Global $g_sProcName = "Radmin.exe"

Global Const $g_sConfigFile = @ScriptDir & "\config.ini"
Global Const $g_sLogFile = @ScriptDir & "\AutoRadmin.log"

; 认证对话框的识别规则（不再依赖窗口标题，避免中文版标题里的空字符差异）：
;   1. 窗口属于 Radmin 进程
;   2. 窗口类名是标准对话框 #32770
;   3. 里面至少有 Edit1 和 Edit2 两个输入框
Global Const $g_sDialogClass = "#32770"


; ============================================================================
; 入口
; ============================================================================
Func _Main()
	; 只允许一个 AutoRadmin 实例
	If _Singleton("AutoRadmin", 1) = 0 Then
		MsgBox($MB_ICONINFORMATION, "AutoRadmin", "AutoRadmin 已经在运行。")
		Return
	EndIf

	AutoItSetOption("WinTitleMatchMode", -2) ; 标题子串匹配，不区分大小写
	AutoItSetOption("TrayAutoPause", 0)
	AutoItSetOption("SendKeyDelay", 20)
	AutoItSetOption("SendKeyDownDelay", 20)

	If Not _LoadConfig() Then Return

	Local $sExe = _ResolveRadminExe()
	If $sExe = "" Then Return

	_Connect($sExe)
EndFunc


; ============================================================================
; 配置文件：读取 / 首次生成 / 回写单项
; ============================================================================
Func _LoadConfig()
	If Not FileExists($g_sConfigFile) Then
		_CreateDefaultConfig()
		MsgBox($MB_ICONINFORMATION, "AutoRadmin", _
				"已生成配置文件，请先填写 Radmin 路径与账号信息，保存后再运行本程序：" & @CRLF & @CRLF & _
				$g_sConfigFile)
		Run('notepad.exe "' & $g_sConfigFile & '"')
		Return False
	EndIf

	Local $hFile = FileOpen($g_sConfigFile, $FO_READ)
	If $hFile = -1 Then
		MsgBox($MB_ICONERROR, "AutoRadmin", "无法读取配置文件：" & @CRLF & $g_sConfigFile)
		Return False
	EndIf

	Local $sLine, $aMatch
	While True
		$sLine = FileReadLine($hFile)
		If @error <> 0 Then ExitLoop
		$sLine = StringStripWS($sLine, $STR_STRIPLEADING + $STR_STRIPTRAILING)
		If $sLine = "" Then ContinueLoop
		If StringLeft($sLine, 1) = ";" Or StringLeft($sLine, 1) = "#" Then ContinueLoop

		; KEY=VALUE，键名只允许字母、数字和下划线
		$aMatch = StringRegExp($sLine, "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", $STR_REGEXPARRAYMATCH)
		If IsArray($aMatch) Then
			_ApplyConfig(StringUpper($aMatch[0]), _Unquote($aMatch[1]))
		EndIf
	WEnd
	FileClose($hFile)

	If $g_iWaitTimeout < 1 Then $g_iWaitTimeout = 15
	If $g_sExeName = "" Then $g_sExeName = "Radmin.exe"
	If $g_sIfRunning = "" Then $g_sIfRunning = "continue"

	Return True
EndFunc


Func _ApplyConfig($sKey, $sValue)
	Switch $sKey
		Case "ARGS"
			$g_sArgs = $sValue
		Case "CONNECTUSER"
			$g_sConnectUser = $sValue
		Case "CONNECTPASS"
			$g_sConnectPass = $sValue
		Case "THROUGHUSER"
			$g_sThroughUser = $sValue
		Case "THROUGHPASS"
			$g_sThroughPass = $sValue
		Case "RADMINDIR", "RADMINPATH", "RADMINEXE", "RADMIN", "RADMINVIEWER"
			$g_sRadminDir = $sValue
		Case "EXENAME"
			$g_sExeName = $sValue
		Case "WINDOWTITLE"
			$g_sWindowTitle = $sValue
		Case "WAITTIMEOUT"
			If StringIsDigit($sValue) Then $g_iWaitTimeout = Int(Number($sValue))
		Case "IFRUNNING"
			$g_sIfRunning = StringLower($sValue)
		Case "DEBUG"
			$g_sDebug = $sValue
	EndSwitch
EndFunc


Func _CreateDefaultConfig()
	Local $hFile = FileOpen($g_sConfigFile, $FO_OVERWRITE + $FO_UTF8)
	If $hFile = -1 Then Return

	FileWriteLine($hFile, "; ============================================================")
	FileWriteLine($hFile, "; AutoRadmin 配置文件")
	FileWriteLine($hFile, "; 改完保存，再运行 AutoRadmin.exe 即可")
	FileWriteLine($hFile, "; ============================================================")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; Radmin Viewer 的安装目录，也可以直接写 Radmin.exe 的完整路径")
	FileWriteLine($hFile, "; 支持环境变量，例如 %ProgramFiles(x86)%\Radmin Viewer 3")
	FileWriteLine($hFile, "; 留空则自动探测常见安装位置")
	FileWriteLine($hFile, "RADMINDIR=C:\Program Files (x86)\Radmin Viewer 3")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 主程序文件名，一般不用改")
	FileWriteLine($hFile, "EXENAME=Radmin.exe")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 传给 Radmin Viewer 的命令行参数")
	FileWriteLine($hFile, "; 常用：/connect:目标地址[:端口]  /through:中继服务器[:端口]  /fullstretch  /nocursor  /sendclipboard")
	FileWriteLine($hFile, "ARGS=/connect:desktop.example.com:4899 /fullstretch")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 目标服务器的登录账号；两项都留空表示使用 Radmin 已保存的凭据")
	FileWriteLine($hFile, "CONNECTUSER=Alice")
	FileWriteLine($hFile, "CONNECTPASS=12345678")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 中继服务器（/through）的认证账号，不用中继可留空")
	FileWriteLine($hFile, "THROUGHUSER=")
	FileWriteLine($hFile, "THROUGHPASS=")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 登录窗口标题关键字，留空则用内置值（含中文版 Radmin安全性）")
	FileWriteLine($hFile, "; 若提示找不到登录窗口，用窗口探测工具查到标题后填在这里，填一段特征子串即可")
	FileWriteLine($hFile, "WINDOWTITLE=")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 等待安全窗口出现的超时秒数")
	FileWriteLine($hFile, "WAITTIMEOUT=15")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; Radmin Viewer 已在运行时：continue=继续新建连接，exit=直接退出")
	FileWriteLine($hFile, "IFRUNNING=continue")
	FileWriteLine($hFile, "")
	FileWriteLine($hFile, "; 排查问题时设为 1，会在同目录生成 AutoRadmin.log 记录每一步")
	FileWriteLine($hFile, "DEBUG=0")

	FileClose($hFile)
EndFunc


; 把单个键写回 config.ini（用于自动探测/手选到路径后记住它）
Func _SaveConfigValue($sKey, $sValue)
	Local $aLines[1] = [""], $i, $hFile, $bFound = False, $iCount = 0

	If FileExists($g_sConfigFile) Then
		$aLines = FileReadToArray($g_sConfigFile)
		If @error = 0 Then $iCount = UBound($aLines)
	EndIf

	$hFile = FileOpen($g_sConfigFile, $FO_OVERWRITE + $FO_UTF8)
	If $hFile = -1 Then Return False

	For $i = 0 To $iCount - 1
		If StringRegExp($aLines[$i], "(?i)^\s*" & $sKey & "\s*=") Then
			FileWriteLine($hFile, $sKey & "=" & $sValue)
			$bFound = True
		Else
			FileWriteLine($hFile, $aLines[$i])
		EndIf
	Next
	If Not $bFound Then FileWriteLine($hFile, $sKey & "=" & $sValue)

	FileClose($hFile)
	Return True
EndFunc


; ============================================================================
; 解析 Radmin.exe 的实际路径
; ============================================================================
Func _ResolveRadminExe()
	Local $sRaw = _Unquote(_ExpandEnv($g_sRadminDir))
	Local $sExe = ""

	; 1. 配置里写了路径
	If $sRaw <> "" Then
		$sExe = _ToExePath(_MakeAbsolute($sRaw))
	EndIf

	; 2. 自动探测
	If $sExe = "" Then
		$sExe = _ToExePath(_AutoDetectRadmin())
	EndIf

	; 3. 让用户手选，选完写回配置
	If $sExe = "" Then
		Local $sPick = FileOpenDialog("请选择 Radmin Viewer 主程序 (Radmin.exe)", @ProgramFilesDir, "程序 (*.exe)", 1)
		If @error = 0 And $sPick <> "" Then
			$sExe = _ToExePath($sPick)
			If $sExe <> "" Then _SaveConfigValue("RADMINDIR", $sExe)
		EndIf
	EndIf

	If $sExe = "" Then
		MsgBox($MB_ICONERROR, "AutoRadmin", _
				"未找到 Radmin Viewer 主程序。" & @CRLF & @CRLF & _
				"请在 config.ini 中正确设置 RADMINDIR，例如：" & @CRLF & _
				"C:\Program Files (x86)\Radmin Viewer 3" & @CRLF & @CRLF & _
				"配置文件位置：" & @CRLF & $g_sConfigFile)
		Return ""
	EndIf

	Return $sExe
EndFunc


; 目录 -> 目录\Radmin.exe；已经是 exe 路径则原样返回
Func _ToExePath($sPath)
	Local $sDir, $sTry, $hSearch, $sFound

	If $sPath = "" Then Return ""

	If StringLower(StringRight($sPath, 4)) = ".exe" Then
		If FileExists($sPath) Then Return $sPath
		Return ""
	EndIf

	$sDir = $sPath
	While StringRight($sDir, 1) = "\" Or StringRight($sDir, 1) = "/"
		$sDir = StringTrimRight($sDir, 1)
	WEnd
	If $sDir = "" Then Return ""

	$sTry = $sDir & "\" & $g_sExeName
	If FileExists($sTry) Then Return $sTry

	; 目录里没有预期文件名时，找 Radmin*.exe
	$hSearch = FileFindFirstFile($sDir & "\Radmin*.exe")
	If $hSearch <> -1 Then
		$sFound = FileFindNextFile($hSearch)
		FileClose($hSearch)
		If IsString($sFound) And $sFound <> "" Then Return $sDir & "\" & $sFound
	EndIf

	Return ""
EndFunc


Func _AutoDetectRadmin()
	Local $aTry[6], $sPF, $sPF64, $i, $sReg

	$sPF = @ProgramFilesDir
	$sPF64 = StringReplace($sPF, " (x86)", "")

	$aTry[0] = $sPF & "\Radmin Viewer 3"
	$aTry[1] = $sPF64 & "\Radmin Viewer 3"
	$aTry[2] = $sPF64 & " (x86)\Radmin Viewer 3"
	$aTry[3] = "C:\Program Files (x86)\Radmin Viewer 3"
	$aTry[4] = "C:\Program Files\Radmin Viewer 3"
	$aTry[5] = EnvGet("ProgramW6432")
	If $aTry[5] <> "" Then $aTry[5] &= "\Radmin Viewer 3"

	For $i = 0 To UBound($aTry) - 1
		If $aTry[$i] = "" Then ContinueLoop
		If FileExists($aTry[$i] & "\" & $g_sExeName) Then Return $aTry[$i]
	Next

	; 注册表卸载信息
	$sReg = _FindRadminInRegistry()
	If $sReg <> "" Then Return $sReg

	Return ""
EndFunc


Func _FindRadminInRegistry()
	Local $aRoots[2], $i, $iIdx, $sSub, $sName, $sLoc, $sIcon, $sPath

	$aRoots[0] = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
	$aRoots[1] = "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

	For $i = 0 To 1
		$iIdx = 1
		While True
			$sSub = RegEnumKey($aRoots[$i], $iIdx)
			If @error <> 0 Then ExitLoop
			$iIdx += 1

			$sName = RegRead($aRoots[$i] & "\" & $sSub, "DisplayName")
			If StringInStr($sName, "Radmin") = 0 Then ContinueLoop

			$sLoc = _Unquote(RegRead($aRoots[$i] & "\" & $sSub, "InstallLocation"))
			If $sLoc <> "" Then
				$sPath = _ToExePath($sLoc)
				If $sPath <> "" Then Return $sPath
			EndIf

			$sIcon = RegRead($aRoots[$i] & "\" & $sSub, "DisplayIcon")
			$sPath = _ToExePath(_SplitIconPath($sIcon))
			If $sPath <> "" Then Return $sPath
		WEnd
	Next

	; App Paths
	$sPath = RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Radmin.exe", "")
	If $sPath <> "" Then
		$sPath = _ToExePath(_Unquote($sPath))
		If $sPath <> "" Then Return $sPath
	EndIf

	Return ""
EndFunc


; DisplayIcon 形如 "C:\...\Radmin.exe,0" 或 C:\...\Radmin.exe
Func _SplitIconPath($sText)
	Local $s = _Unquote($sText)
	Local $iComma

	If StringLeft($s, 1) = '"' Then
		$s = StringMid($s, 2)
		$iComma = StringInStr($s, '"')
		If $iComma > 0 Then Return StringLeft($s, $iComma - 1)
		Return ""
	EndIf

	$iComma = StringInStr($s, ",")
	If $iComma > 0 Then Return StringLeft($s, $iComma - 1)
	Return $s
EndFunc


; ============================================================================
; 启动 Radmin Viewer 并填表
; ============================================================================
Func _Connect($sExe)
	Local $sWorkDir = _ParentDir($sExe)
	Local $sCmd, $aBefore, $hWin

	$g_sProcName = _FileName($sExe)

	Local $bThrough = (StringInStr($g_sArgs, "/through:", 0) > 0)
	Local $bConnect = (StringInStr($g_sArgs, "/connect:", 0) > 0)

	_Log("---- 启动 ----")
	_Log("exe = " & $sExe)
	_Log("args = " & $g_sArgs)

	If ProcessExists($g_sProcName) And $g_sIfRunning <> "continue" Then
		MsgBox($MB_ICONWARNING, "AutoRadmin", _
				"Radmin Viewer 已经在运行。" & @CRLF & @CRLF & _
				"当前配置 IFRUNNING=" & $g_sIfRunning & "，已退出。" & @CRLF & _
				"改成 IFRUNNING=continue 可直接新建连接。")
		Return
	EndIf

	; 记录启动前已存在的认证框，之后只认新出现的那个
	$aBefore = _ListSecurityWindows()
	_Log("启动前已存在的认证框：" & $aBefore[0] & " 个")

	$sCmd = '"' & $sExe & '"'
	If $g_sArgs <> "" Then $sCmd &= " " & $g_sArgs

	If Run($sCmd, $sWorkDir) = 0 Then
		MsgBox($MB_ICONERROR, "AutoRadmin", "无法启动 Radmin Viewer：" & @CRLF & $sCmd)
		Return
	EndIf
	_Log("已启动，等待认证框（超时 " & $g_iWaitTimeout & " 秒）")

	; ---- 第一关：中继服务器认证 ----
	If $bThrough And ($g_sThroughUser <> "" Or $g_sThroughPass <> "") Then
		$hWin = _WaitNewSecurityDialog($aBefore, $g_iWaitTimeout)
		If $hWin <> 0 Then
			_FillSecurityDialog($hWin, $g_sThroughUser, $g_sThroughPass)
			_SubmitSecurityDialog($hWin)
			WinWaitClose($hWin, "", 5)
			Sleep(400)
		EndIf
		$aBefore = _ListSecurityWindows()
	EndIf

	; ---- 第二关：目标服务器认证 ----
	If $bConnect And ($g_sConnectUser <> "" Or $g_sConnectPass <> "") Then
		$hWin = _WaitNewSecurityDialog($aBefore, $g_iWaitTimeout)
		If $hWin <> 0 Then
			_FillSecurityDialog($hWin, $g_sConnectUser, $g_sConnectPass)
			_SubmitSecurityDialog($hWin)
		Else
			TrayTip("AutoRadmin", "未检测到 Radmin 登录窗口，可能已用保存的凭据直接连接。", 5)
		EndIf
	EndIf
EndFunc


; 找出 Radmin 的认证对话框，返回句柄数组（第 0 个元素是数量）
; 识别规则：同进程 + 标准对话框类 #32770 + 至少两个输入框
; 不再依赖窗口标题，中文版标题里 "Radmin" 与 "安全性" 之间的空格数量不影响判断
Func _ListSecurityWindows()
	Local $aResult[1] = [0]
	Local $aAll = WinList()
	Local $aProcs = ProcessList() ; [n][2]：进程名、PID
	Local $hWnd, $sClass, $sProc, $sTitle, $iState, $i

	For $i = 1 To $aAll[0][0]
		$hWnd = $aAll[$i][1] ; WinList：[$i][0] 是标题，[$i][1] 是句柄
		If $hWnd = 0 Then ContinueLoop

		$iState = WinGetState($hWnd)
		If @error <> 0 Then ContinueLoop
		If BitAND($iState, 2) = 0 Then ContinueLoop ; 只要可见窗口

		$sClass = _WindowClassName($hWnd)
		If $sClass <> $g_sDialogClass Then ContinueLoop ; 先按类名快速筛掉绝大多数窗口

		$sProc = _WindowProcessName($hWnd, $aProcs)
		If StringLower($sProc) <> StringLower($g_sProcName) Then ContinueLoop

		; 认证框至少有两个输入框（用户名 + 密码）
		If ControlGetHandle($hWnd, "", "[CLASS:Edit; INSTANCE:2]") = 0 Then ContinueLoop

		; 可选：配置了 WINDOWTITLE 就再叠加一次标题过滤
		If $g_sWindowTitle <> "" Then
			$sTitle = $aAll[$i][0]
			If StringInStr($sTitle, $g_sWindowTitle, 0) = 0 Then ContinueLoop
		EndIf

		$aResult[0] += 1
		ReDim $aResult[$aResult[0] + 1]
		$aResult[$aResult[0]] = $hWnd
	Next

	Return $aResult
EndFunc


Func _WaitNewSecurityDialog($aBefore, $iTimeoutSec)
	Local $aNow[1] = [0]
	Local $i, $iElapsed = 0, $iLimit = $iTimeoutSec * 1000

	While $iElapsed < $iLimit
		$aNow = _ListSecurityWindows()
		For $i = 1 To $aNow[0]
			If Not _ArrayHas($aBefore, $aNow[$i]) Then
				_Log("捕获认证框 hwnd=" & $aNow[$i])
				Return $aNow[$i]
			EndIf
		Next
		Sleep(250)
		$iElapsed += 250
	WEnd

	_Log("等待认证框超时，当前可见认证框 " & $aNow[0] & " 个")
	Return 0
EndFunc


Func _FillSecurityDialog($hWnd, $sUser, $sPass)
	If Not WinActive($hWnd) Then WinActivate($hWnd)
	Sleep(200)

	If $sUser <> "" Then _SetEditText($hWnd, 1, $sUser, "用户名")
	If $sPass <> "" Then _SetEditText($hWnd, 2, $sPass, "密码")

	Sleep(120)
EndFunc


; 三级填充：ControlSend -> ControlSetText -> 激活后真实键盘
; 每次都先清空再写，所以重复尝试不会造成密码叠加
Func _SetEditText($hWnd, $iIndex, $sText, $sName)
	Local $sCtl = "[CLASS:Edit; INSTANCE:" & $iIndex & "]"
	Local $sGot

	ControlSend($hWnd, "", $sCtl, "^a")
	ControlSend($hWnd, "", $sCtl, "{DEL}")
	ControlSend($hWnd, "", $sCtl, $sText, 1)
	Sleep(120)

	$sGot = ControlGetText($hWnd, "", $sCtl)
	If $sGot = $sText Then
		_Log($sName & " 填写成功（ControlSend）")
		Return True
	EndIf

	ControlSetText($hWnd, "", $sCtl, $sText)
	Sleep(120)
	$sGot = ControlGetText($hWnd, "", $sCtl)
	If $sGot = $sText Then
		_Log($sName & " 填写成功（ControlSetText）")
		Return True
	EndIf

	; 最后兜底：模拟真实键盘，要求窗口在前台
	If Not WinActive($hWnd) Then WinActivate($hWnd)
	Sleep(150)
	ControlFocus($hWnd, "", $sCtl)
	Sleep(120)
	Send("^a")
	Send("{DEL}")
	Send($sText, 1)
	Sleep(150)

	$sGot = ControlGetText($hWnd, "", $sCtl)
	If $sGot = $sText Then
		_Log($sName & " 填写成功（Send）")
		Return True
	EndIf

	; 密码框常见读不回内容（被掩码），此时无法用读回值校验；
	; 上面三种方式都已写过一遍，且每次写前都清空过，按已填写处理
	If $sGot = "" And $sText <> "" Then
		_Log($sName & " 内容读不回（可能被掩码），已依次写入 3 次，按已填写处理")
		Return True
	EndIf

	_Log($sName & " 填写失败，读回长度=" & StringLen($sGot))
	Return False
EndFunc


; 按按钮文本找"确定"再点，避免中文版按钮顺序与俄语版不同时点到"取消"
Func _ClickOkButton($hWnd)
	Local $i, $hCtl, $sText

	For $i = 1 To 12
		$hCtl = ControlGetHandle($hWnd, "", "[CLASS:Button; INSTANCE:" & $i & "]")
		If @error <> 0 Then ExitLoop
		$sText = StringUpper(StringStripWS(StringReplace(ControlGetText($hWnd, "", $hCtl), "&", ""), $STR_STRIPALL))
		If StringInStr($sText, "确定") = 1 Or StringInStr($sText, "OK") = 1 Or StringInStr($sText, "ОК") = 1 Then
			ControlClick($hWnd, "", $hCtl)
			Return True
		EndIf
	Next

	Return False
EndFunc


Func _SubmitSecurityDialog($hWnd)
	; 首选：点文本为"确定/OK"的按钮
	If _ClickOkButton($hWnd) Then
		_Log("已点击确定按钮")
		If WinWaitClose($hWnd, "", 3) <> 0 Then Return True
		_Log("点击后窗口未关闭，改发回车")
	EndIf

	; 回退：单行输入框里按回车会触发对话框的默认按钮（通常就是"确定"）
	If Not WinActive($hWnd) Then WinActivate($hWnd)
	Sleep(200)
	ControlSend($hWnd, "", "[CLASS:Edit; INSTANCE:2]", "{ENTER}")
	If WinWaitClose($hWnd, "", 3) <> 0 Then Return True

	_Log("提交失败，窗口仍然存在")
	Return False
EndFunc


; ============================================================================
; 小工具
; ============================================================================
Func _Log($sMsg)
	Local $hLog

	If $g_sDebug <> "1" Then Return

	$hLog = FileOpen($g_sLogFile, $FO_APPEND + $FO_UTF8)
	If $hLog = -1 Then Return
	FileWriteLine($hLog, @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & "  " & $sMsg)
	FileClose($hLog)
EndFunc


Func _WindowClassName($hWnd)
	Local $tBuf = DllStructCreate("wchar[256]")
	Local $aRet = DllCall("user32.dll", "int", "GetClassNameW", "hwnd", $hWnd, "struct*", $tBuf, "int", 256)

	If @error <> 0 Then Return ""
	If $aRet[0] <= 0 Then Return ""
	Return DllStructGetData($tBuf, 1)
EndFunc


Func _WindowProcessName($hWnd, $aProcs)
	Local $iPid = WinGetProcess($hWnd)
	Local $i

	If @error <> 0 Then Return ""
	If $iPid <= 0 Then Return ""

	For $i = 1 To $aProcs[0][0]
		If $aProcs[$i][1] = $iPid Then Return $aProcs[$i][0]
	Next

	Return ""
EndFunc


Func _ArrayHas($aArr, $v)
	Local $i
	For $i = 1 To $aArr[0]
		If $aArr[$i] = $v Then Return True
	Next
	Return False
EndFunc


Func _Unquote($sText)
	Local $s = StringStripWS($sText, $STR_STRIPLEADING + $STR_STRIPTRAILING)
	If StringLen($s) < 2 Then Return $s
	If (StringLeft($s, 1) = '"' And StringRight($s, 1) = '"') _
			Or (StringLeft($s, 1) = "'" And StringRight($s, 1) = "'") Then
		$s = StringMid($s, 2, StringLen($s) - 2)
	EndIf
	Return $s
EndFunc


Func _ExpandEnv($sText)
	Local $aHit, $sResult, $sVal, $i

	If StringInStr($sText, "%") = 0 Then Return $sText

	$aHit = StringRegExp($sText, "%([^%]+)%", 3)
	If Not IsArray($aHit) Then Return $sText
	If UBound($aHit) = 0 Then Return $sText

	$sResult = $sText
	For $i = 0 To UBound($aHit) - 1
		$sVal = EnvGet($aHit[$i])
		If $sVal <> "" Then
			$sResult = StringReplace($sResult, "%" & $aHit[$i] & "%", $sVal, 0, 0)
		EndIf
	Next

	Return $sResult
EndFunc


Func _MakeAbsolute($sPath)
	If StringInStr($sPath, ":") > 0 Then Return $sPath
	If StringLeft($sPath, 1) = "\" Then Return $sPath
	Return @ScriptDir & "\" & $sPath
EndFunc


Func _FileName($sPath)
	Local $iPos = StringInStr($sPath, "\", 0, -1)
	If $iPos = 0 Then Return $sPath
	Return StringMid($sPath, $iPos + 1)
EndFunc


Func _ParentDir($sFile)
	Local $iPos = StringInStr($sFile, "\", 0, -1)
	If $iPos <= 1 Then Return @ScriptDir
	Return StringLeft($sFile, $iPos - 1)
EndFunc


_Main()
