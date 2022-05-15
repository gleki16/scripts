#  安装 Scoop
if(-not(test-path ~/scoop)) {
    Invoke-WebRequest get.scoop.sh | Invoke-Expression
}

# 下载默认软件
winget install 7zip.7zip
winget install VideoLAN.VLC

# 添加软件源
scoop bucket add extras

# 下载常用软件
scoop install git powertoys firefox bulk-crap-uninstaller
