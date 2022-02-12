#! /bin/fish

function main
    switch_to_wg_dir

    echo 输入 a 安装 wg0
    echo 输入 b 增减成员
    echo 输入 c 查看成员配置
    read -p 'echo "> "' ans
    switch $ans
        case a
            wg0_setting
        case b
            member_changes
        case c
            member_config
    end
end

function switch_to_wg_dir
    set --global wg_dir $HOME/.wireguard/

    mkdir -p $wg_dir
    cd $wg_dir || begin
        echo 切换目录失败，程序退出
        exit
    end
end

function generate_member_config
    set ip $argv[1]
    set port $argv[2]
    set member_number $argv[3]

    echo "\
[Interface]
PrivateKey = "(cat pri"$member_number")"
Address = 10.10.10."$member_number"

[Peer]
PublicKey = "(cat pub1)"
Endpoint = "$ip":"$port"
AllowedIPs = 0.0.0.0/0
" > wg"$member_number".conf

end

function wg0_setting
    set interface (ip -o -4 route show to default | awk '{print $5}')
    set ip (ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    set port 51820

    set i (sudo wg)
    if test -n "$i"
        sudo wg-quick down wg0
    end
    rm -rf $wg_dir/*

    # 打开流量转发
    if not test -e /etc/sysctl.d/ip_forward.conf
        echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/ip_forward.conf
        sudo sysctl (bat /etc/sysctl.d/ip_forward.conf | sed 's/ //g')
    end

    # 生成密钥，分别用作服务器和客户端使用
    wg genkey | tee pri1 | wg pubkey >pub1
    wg genkey | tee pri2 | wg pubkey >pub2
    # 设置密钥访问权限
    chmod 600 pri1
    chmod 600 pri2

    # 生成服务端配置文件
    echo "\
[Interface]
PrivateKey = "(cat pri1)"
Address = 10.10.10.1/32
ListenPort = "$port"
PostUp   = nft add rule inet nat postrouting oifname "$interface" masquerade
PostDown = nft flush ruleset; nft -f /etc/nftables.conf

[Peer]
PublicKey = "(cat pub2)"
AllowedIPs = 10.10.10.2/32
" | sudo tee /etc/wireguard/wg0.conf

    # 生成客户端配置文件
    generate_member_config $ip $port 2


    sudo wg-quick up wg0 || begin
        echo 启动wireguard失败，请检查/etc/wireguard/wg0.conf是否存在错误
        exit
    end

    # 开机自启
    sudo systemctl enable wg-quick@wg0

    echo "安装完成！"

    member_changes
end

function member_changes
    set interface (ip -o -4 route show to default | awk '{print $5}')
    set ip (ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    set port (sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=ListenPort = )\d+')

    while true
        set member_list (sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=\.)\d+(?=\/)')

        echo
        echo 已存在成员：
        echo $member_list

        echo 输入成员数字（存在则删除，不存在则创建）
        read -p 'echo "> "' i
        if string match -qr '^[1-9][0-9]*$' $i && test "$i" -ge 2 -a "$i" -le 254
            if echo $成员 | grep -qE '(^| )'$i'($| )'
                sudo wg set wg0 peer (cat pub"$i") remove
                sudo wg-quick save wg0
                rm wg"$i".conf pub"$i" pri"$i"
            else
                wg genkey | tee pri"$i" | wg pubkey >pub"$i"
                chmod 600 pri"$i"
                sudo wg set wg0 peer (cat pub"$i") allowed-ips 10.10.10."$i"/32
                sudo wg-quick save wg0
                generate_member_config $ip $port $i
            end
        else
            break
        end
    end

    member_config
end

function member_config
    set member_list (sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=\.)\d+(?=\/)')

    while true
        echo
        echo 已存在成员：
        echo $member_list

        echo 输入成员数字（查看配置）
        read -p 'echo "> "' i
        if string match -qr '^[0-9]+$' $i && test "$i" -ge 2 -a "$i" -le 254
            echo
            echo
            echo 'echo "\\'
            cat wg"$i".conf
            echo '" | sudo tee /etc/wireguard/wg'$i'.conf'
            echo
            echo
            qrencode -t ansiutf8 <wg"$i".conf
            echo
        else
            break
        end
    end
end

main $argv
