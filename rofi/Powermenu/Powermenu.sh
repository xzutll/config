#!/usr/bin/env bash

#options
lock="󰌾 Lock"
logout="󰍃 Logout"
reboot="󰜉 Reboot"
shutdown="󰐥 Shutdown"

choice=$(printf '%s\n' "$lock" "$logout" "$reboot" "$shutdown" | rofi -dmenu -i \
	-p 󰐥 \
	-ml-row-up "" -ml-row-down "" \
	-theme ~/.config/rofi/Powermenu/Powermenu.rasi)

case "$choice" in
    *$lock)	hyprlock ;;
    *$logout)	hyprctl dispatch exit ;;
    *$reboot)	systemctl reboot ;;
    *$shutdown) systemctl poweroff ;;
esac
