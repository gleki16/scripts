# 下载常用软件
winget install 7zip.7zip
winget install Klocman.BulkCrapUninstaller
winget install Microsoft.PowerToys
winget install Mozilla.Firefox

# 小鹤双拼 键位
Invoke-WebRequest https://raw.githubusercontent.com/2015WUJI01/xhup-for-win10/master/xhup.reg -OutFile "xhup.reg"
regedit /s "xhup.reg"
Remove-Item "xhup.reg"

# UTC 时间 (需要管理员权限)
Reg add HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation /v RealTimeIsUniversal /t REG_DWORD /d 1
