#!/bin/ash
# Скрипт для автоустановки Alpine Linux с i3wm, анонимностью и визуальными эффектами
# Требует запуска с правами root

# --- Конфигурация ---
USERNAME="anonuser"
HOSTNAME="anonymous-pc"
X11_PKGS="xorg-server xf86-video-intel xf86-video-amdgpu xf86-video-nouveau xf86-video-vesa"
I3_PKGS="i3wm i3status i3lock dmenu"
ANON_PKGS="tor torsocks obfs4proxy dnscrypt-proxy openvpn wireguard-tools"
MEDIA_PKGS="mpv feh"
UI_PKGS="alacritty rofi picom"
BAR_PKGS="polybar ttf-font-awesome font-noto" 
OPTIMIZATION_PKGS="musl-dev gcc make linux-firmware"
DEP_PKGS="bash curl git"

# --- Проверка прав ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите скрипт с правами root: sudo $0" >&2
    exit 1
fi

# --- Функции ---
install_pkgs() {
    echo -e "\n\033[1;32mУстановка пакетов: $@\033[0m"
    apk add --no-cache "$@"
}

compile_xwinwrap() {
    echo -e "\n\033[1;32mКомпиляция xwinwrap\033[0m"
    git clone https://github.com/ujjwal96/xwinwrap.git
    cd xwinwrap
    make
    make install
    cd ..
    rm -rf xwinwrap
}

setup_user() {
    echo -e "\n\033[1;32mСоздание пользователя $USERNAME\033[0m"
    adduser -D -G users $USERNAME
    echo "$USERNAME:$USERNAME" | chpasswd
    addgroup $USERNAME video
    addgroup $USERNAME input
}

setup_firewall() {
    echo -e "\n\033[1;32mНастройка firewall (nftables)\033[0m"
    install_pkgs nftables
    
    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;
        
        iif lo accept
        ct state established,related accept
        icmp type echo-request accept
        
        # Разрешить Tor
        tcp dport 9001 accept
        
        counter drop
    }
    
    chain forward {
        type filter hook forward priority 0;
        drop
    }
    
    chain output {
        type filter hook output priority 0;
        accept
    }
}
EOF

    rc-update add nftables default
    nft -f /etc/nftables.conf
}

setup_tor() {
    echo -e "\n\033[1;32mНастройка Tor\033[0m"
    install_pkgs tor
    
    cat > /etc/tor/torrc << EOF
SocksPort 9050
ControlPort 9051
DNSPort 5353
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
Bridge obfs4 193.11.166.194:27025 cert=7UQFv0O7lqYrXUO5C7VfUQlYq3q7eF0XoZQe4Xl7j6RlSq3wZ0iVg4MfP2wZ0iVg4MfP2wZ0iVg iat-mode=0
EOF

    rc-update add tor default
}

setup_live_wallpaper() {
    echo -e "\n\033[1;32mУстановка живых обоев\033[0m"
    WALLPAPER_URL="https://github.com/N4chik/alpinei3wm/live-wallpaper.mp4"
    
    su $USERNAME -c "mkdir -p /home/$USERNAME/.wallpapers"
    curl -L "$WALLPAPER_URL" -o /home/$USERNAME/.wallpapers/live-wallpaper.mp4
    
    # Создаем скрипт запуска
    cat > /home/$USERNAME/livewallpaper.sh << EOF
#!/bin/ash
killall xwinwrap &> /dev/null
xwinwrap -fs -fdt -ni -b -nf -un -o 1.0 -- mpv -wid WID \\
    --loop --no-audio --no-osc --no-osd-bar \\
    --input-vo-keyboard=no --really-quiet \\
    "/home/$USERNAME/.wallpapers/live-wallpaper.mp4" &
EOF

    chmod +x /home/$USERNAME/livewallpaper.sh
    chown -R $USERNAME:users /home/$USERNAME
}

setup_polybar() {
    echo -e "\n\033[1;32mНастройка Polybar\033[0m"
    su $USERNAME -c "mkdir -p /home/$USERNAME/.config/polybar"
    
    # Основной конфиг
    cat > /home/$USERNAME/.config/polybar/config.ini << EOF
[colors]
background = #2a2a37
background-alt = #444444
foreground = #f8f8f2
primary = #bd93f9
secondary = #f1fa8c
alert = #ff5555

[bar/main]
width = 100%
height = 24
offset-x = 0
offset-y = 0
fixed-center = true
background = \${colors.background}
foreground = \${colors.foreground}
font-0 = Noto Sans:size=10;2
font-1 = Font Awesome 6 Free Solid:size=10
modules-left = i3
modules-center = date
modules-right = cpu memory pulseaudio network

[module/i3]
type = internal/i3
format = <label-state> <label-mode>
label-focused = %name%
label-focused-foreground = \${colors.primary}
label-unfocused = %name%
label-urgent = %name%!

[module/date]
type = internal/date
interval = 1
date = %H:%M
label =  %date%
date-alt = %Y-%m-%d

[module/cpu]
type = internal/cpu
interval = 1
label =  %percentage%%

[module/memory]
type = internal/memory
interval = 1
label =  %percentage_used%%

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
label-volume =  %percentage%%
label-muted =  muted

[module/network]
type = internal/network
interface = eth0
interval = 1
label-connected =  %essid%
label-disconnected =  offline
EOF

    # Скрипт запуска
    cat > /home/$USERNAME/.config/polybar/launch.sh << EOF
#!/bin/ash
killall polybar
polybar main -c ~/.config/polybar/config.ini &
EOF

    chmod +x /home/$USERNAME/.config/polybar/launch.sh
    chown -R $USERNAME:users /home/$USERNAME/.config
}

setup_i3() {
    echo -e "\n\033[1;32mНастройка i3wm\033[0m"
    su $USERNAME -c "mkdir -p /home/$USERNAME/.config/i3"
    
    cat > /home/$USERNAME/.config/i3/config << EOF
# Автозапуск
exec --no-startup-id /home/$USERNAME/livewallpaper.sh
exec --no-startup-id picom --config /home/$USERNAME/.config/picom.conf
exec --no-startup-id ~/.config/polybar/launch.sh

# Сочетания клавиш
floating_modifier Mod4
bindsym Mod4+Return exec alacritty
bindsym Mod4+d exec rofi -show drun
bindsym Mod4+Shift+q kill

# Оформление
gaps inner 15
gaps outer 5
for_window [class="^.*"] border pixel 2
EOF
}

setup_picom() {
    echo -e "\n\033[1;32mНастройка Picom\033[0m"
    su $USERNAME -c "mkdir -p /home/$USERNAME/.config"
    
    cat > /home/$USERNAME/.config/picom.conf << EOF
animations = true;
animation-window-mass = 0.5;
animation-stiffness = 200;
animation-dampening = 25;

# Эффекты
corner-radius = 10;
rounded-corners-exclude = [
  "class_g = 'i3-frame'"
];

# Производительность
backend = "glx";
vsync = true;
glx-no-stencil = true;
EOF
}

setup_xinit() {
    echo -e "\n\033[1;32mНастройка .xinitrc\033[0m"
    cat > /home/$USERNAME/.xinitrc << EOF
#!/bin/ash
setxkbmap us,ru -option grp:alt_shift_toggle
xset r rate 300 50
exec i3
EOF
    chown $USERNAME:users /home/$USERNAME/.xinitrc
}

optimize_system() {
    echo -e "\n\033[1;32mОптимизация системы\033[0m"
    # Параметры ядра
    cat > /etc/sysctl.d/10-optimizations.conf << EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
kernel.sched_migration_cost_ns=5000000
EOF
    
    # Отключение ненужных сервисов
    rc-update del acpid
    rc-update del hwdrivers
}

# --- Основной процесс установки ---
echo -e "\n\033[1;36mНачало установки Alpine Linux\033[0m"

# Включение community репозитория
echo "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community" >> /etc/apk/repositories

# Установка базовых пакетов
install_pkgs $X11_PKGS $I3_PKGS $ANON_PKGS $MEDIA_PKGS $UI_PKGS $BAR_PKGS $OPTIMIZATION_PKGS $DEP_PKGS

# Компиляция необходимых компонентов
compile_xwinwrap

# Настройка системы
setup_user
setup_firewall
setup_tor
setup_live_wallpaper
setup_polybar 
setup_i3
setup_picom
setup_xinit
optimize_system

# Установка завершена
echo -e "\n\033[1;32mУстановка завершена!\033[0m"
echo "Хост: $HOSTNAME"
echo "Пользователь: $USERNAME (пароль: $USERNAME)"
echo "Что сделать дальше:"
echo "1. Перезагрузить систему"
echo "2. Войти под пользователем $USERNAME"
echo "3. Запустить Xorg: startx"
echo "4. Заменить видео обоев: /home/$USERNAME/.wallpapers/live-wallpaper.mp4"
echo "5. Настроить Tor: /etc/tor/torrc"
echo "6. удачи))))))"
exit 0