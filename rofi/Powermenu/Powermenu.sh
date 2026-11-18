#!/usr/bin/env bash

#options
lock="󰌾 Lock"
logout="󰍃 Logout"
reboot="󰜉 Reboot"
shutdown="󰐥 Shutdown"
suspend="󰤄 Suspend"

choice=$(printf '%s\n' "$lock" "$logout" "$reboot" "$shutdown" "$suspend" | rofi -dmenu -i \
	-p 󰐥 \
	-ml-row-up "" -ml-row-down "" \
	-theme ~/.config/rofi/Powermenu/Powermenu.rasi)

case "$choice" in
    *$lock)	hyprlock ;;
    *$logout)	hyprctl dispatch exit ;;
    *$reboot)	systemctl reboot ;;
    *$shutdown) systemctl poweroff ;;
    *$suspend) systemctl suspend ;;
esac
