#!/data/data/com.termux/files/usr/bin/env fish

function main
    switch $argv[1]
        case a
            install_pkg
        case p
            copy_config
            write_config
        case u
            set_cfg_repo
        case '*'
            install_pkg
            set_cfg_repo
            copy_config
            write_config
            termux-reload-settings
            echo '完成！请重启 Termux。'
    end
end

# 连接内部存储。
termux-setup-storage

# 更换源
function change_source
    sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list
    sed -i 's@^\(deb.*games stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/game-packages-24 games stable@' $PREFIX/etc/apt/sources.list.d/game.list
    sed -i 's@^\(deb.*science stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/science-packages-24 science stable@' $PREFIX/etc/apt/sources.list.d/science.list
    pkg update
end

# 安装软件
function install_pkg
    pkg install -y bat clang curl fish git lf lua54 man neovim nodejs openssh rsync starship tree wget yarn zsh
end

# uz 设定
function set_cfg_repo
    set -g cfg_dir $HOME/dotfiles

    git clone --depth 1 https://gitlab.com/glek/dotfiles.git $cfg_dir

    cd $cfg_dir
    git config credential.helper store
    git config --global user.email 'rraayy246@gmail.com'
    git config --global user.name 'ray'
    git config --global pull.rebase false
    cd
end

# 复制设定
function copy_config
    # fish 设置环境变量
    fish $cfg_dir/env.fish
    # 链接配置文件
    rsync -a $cfg_dir/.config $HOME
end

# 写入设定
function write_config
	set_nvim

    # 设 fish 为默认 shell
    chsh -s fish

    # 提示符
    echo -e 'if status is-interactive\n\tstarship init fish | source\nend' > $HOME/.config/fish/config.fish

    # 下载 Ubuntu 字体
    curl -fLo $HOME/.termux/font.ttf --create-dirs https://github.com/powerline/fonts/raw/master/UbuntuMono/Ubuntu%20Mono%20derivative%20Powerline.ttf
end

function set_nvim
	git clone --depth=1 https://gitlab.com/glek/dotnvim.git ~/.config/nvim

	#nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
end

main $argv
