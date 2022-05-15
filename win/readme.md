```powershell
# 允许运行脚本
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest gitlab.com/glek/scripts/raw/main/win/win.ps1 | Invoke-Expression
```
