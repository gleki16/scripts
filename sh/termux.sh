#!/data/data/com.termux/files/usr/bin/env bash

pkg upgrade -y
pkg install -y curl fish

curl -fLo $HOME/termux.fish https://gitlab.com/glek/uz/raw/main/scr/termux.fish
fish $HOME/termux.fish
rm $HOME/termux.fish
