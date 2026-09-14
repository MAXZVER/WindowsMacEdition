' Runs the startup check with no console window flashing at logon.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\mishmax\projects\WindowsMacEdition\startup\Ensure-MacSetup.ps1""", 0, False
