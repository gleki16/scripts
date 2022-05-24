# 下载常用软件
winget install 7zip.7zip
winget install Git.Git
winget install Klocman.BulkCrapUninstaller
winget install Microsoft.PowerToys
winget install Mozilla.Firefox
winget install VideoLAN.VLC

# 安装 Scoop
if(-not(test-path ~/scoop)) {
    Invoke-WebRequest get.scoop.sh | Invoke-Expression
}
