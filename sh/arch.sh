#!/usr/bin/env bash

timedatectl set-ntp true
pacman -Sy --needed --noconfirm fish

curl -fLo /arch.fish https://gitlab.com/glek/scripts/raw/main/sh/arch.fish
fish /arch.fish -l
rm /arch.fish
