#!/usr/bin/env bash

timedatectl set-ntp true
pacman -Sy --needed --noconfirm fish

curl -fLo /arch.fish https://gitlab.com/glek/uz/raw/main/scr/arch.fish
fish /arch.fish -l
rm /arch.fish
