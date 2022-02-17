sudo pacman -S --noconfirm caddy

# 增加 UDP 缓冲区大小
echo "net.core.rmem_max = 2500000" | sudo tee /etc/sysctl.d/rmem_max.conf
sudo sysctl `cat /etc/sysctl.d/rmem_max.conf | sed 's/ //g'`
