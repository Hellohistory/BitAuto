#!/bin/bash

# root ユーザーかどうかを確認
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "root ユーザーまたは sudo を使用してスクリプトを実行してください"
        exit 1
    fi
}

# エラーハンドリング関数
handle_error() {
    echo "エラーが発生しました: $1"
    exit 1
}

# コマンドを安全に実行
execute_with_sudo() {
    # shellcheck disable=SC2145
    sudo "$@" || handle_error "コマンドの実行に失敗しました: $@"
}

# ディストリビューションを検出し、適切なパッケージマネージャを設定
get_package_manager() {
    if [ -f "/etc/debian_version" ]; then
        echo "apt"
    elif [ -f "/etc/redhat-release" ]; then
        echo "yum"
    elif [ -f "/etc/centos-release" ]; then
        echo "yum"
    elif [ -f "/etc/fedora-release" ]; then
        echo "dnf"
    elif [ -f "/etc/arch-release" ]; then
        echo "pacman"
    else
        handle_error "サポートされていない Linux ディストリビューションです"
    fi
}

# 公開 IP アドレスを取得
get_public_ip() {
    echo "公開 IP を取得中..."
    public_ip=$(curl -s http://checkip.amazonaws.com) || handle_error "公開 IP を取得できませんでした"
    echo "公開 IP: $public_ip"
}

# 内部ネットワーク IP アドレスを取得
get_local_ip() {
    echo "内部ネットワーク IP を取得中..."
    local_ip=$(hostname -I | awk '{print $1}') || handle_error "内部ネットワーク IP を取得できませんでした"
    echo "内部ネットワーク IP: $local_ip"
}

# dialog を使用してグラフィカルなメニューを作成
show_menu() {
    clear
    choice=$(dialog --title "Redis 管理ツール" --menu "操作を選択してください" 15 60 9 \
        1 "Redis をインストール" \
        2 "Redis を更新" \
        3 "Redis をアンインストール" \
        4 "Redis を起動" \
        5 "Redis を停止" \
        6 "Redis を再起動" \
        7 "Redis の設定を変更" \
        8 "現在の Redis 設定を表示" \
        9 "終了" 2>&1 > /dev/tty)

    case $choice in
        1) install_redis ;;
        2) update_redis ;;
        3) uninstall_redis ;;
        4) start_redis ;;
        5) stop_redis ;;
        6) restart_redis ;;
        7) modify_redis_config ;;
        8) view_redis_config ;;
        9) exit 0 ;;
        *) dialog --msgbox "無効な選択肢です。再度選択してください。" 6 30; show_menu ;;
    esac
}

# Redis をインストール
install_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    if dpkg -l | grep -q redis-server; then
        dialog --msgbox "Redis はすでにインストールされています。インストールをスキップします。" 6 30
    else
        dialog --msgbox "Redis をインストールしています..." 6 30
        if [ "$PACKAGE_MANAGER" == "apt" ]; then
            execute_with_sudo apt-get update
            execute_with_sudo apt-get install -y redis-server
        elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
            execute_with_sudo yum install -y redis
        elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
            execute_with_sudo pacman -S --noconfirm redis
        else
            handle_error "このディストリビューションでは Redis のインストールはサポートされていません。"
        fi
        dialog --msgbox "Redis のインストールが完了しました！" 6 30
    fi

    # 公開 IP と内部ネットワーク IP を取得して表示
    get_public_ip
    get_local_ip

    show_menu
}

# Redis を更新
update_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    dialog --msgbox "Redis を更新しています..." 6 30
    if [ "$PACKAGE_MANAGER" == "apt" ]; then
        execute_with_sudo apt-get update
        execute_with_sudo apt-get upgrade -y redis-server
    elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
        execute_with_sudo yum update -y redis
    elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
        execute_with_sudo pacman -Syu redis
    else
        handle_error "このディストリビューションでは Redis の更新はサポートされていません。"
    fi
    dialog --msgbox "Redis の更新が完了しました！" 6 30
    show_menu
}

# Redis を起動
start_redis() {
    if ! systemctl is-active --quiet redis-server; then
        dialog --msgbox "Redis を起動しています..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis は起動しました！" 6 30
    else
        dialog --msgbox "Redis はすでに実行中です。" 6 30
    fi
    show_menu
}

# Redis を停止
stop_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "Redis を停止しています..." 6 30
        execute_with_sudo systemctl stop redis-server
        dialog --msgbox "Redis は停止しました。" 6 30
    else
        dialog --msgbox "Redis サービスは実行されていません。" 6 30
    fi
    show_menu
}

# Redis を再起動
restart_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "Redis を再起動しています..." 6 30
        execute_with_sudo systemctl restart redis-server
        dialog --msgbox "Redis は再起動しました！" 6 30
    else
        dialog --msgbox "Redis サービスは実行されていません。起動します..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis は起動しました。" 6 30
    fi
    show_menu
}

# Redis 設定の変更
modify_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis 設定ファイルが存在しません。Redis がインストールされているか確認してください。" 6 30
        show_menu
    fi

    config_choice=$(dialog --title "Redis 設定の変更" --menu "変更する設定項目を選択してください" 15 60 4 \
        1 "最大接続数 (maxclients)" \
        2 "最大メモリ使用量 (maxmemory)" \
        3 "永続化の有無 (save)" \
        4 "戻る" 2>&1 > /dev/tty)

    case $config_choice in
        1) modify_maxclients ;;
        2) modify_maxmemory ;;
        3) modify_persistence ;;
        4) show_menu ;;
        *) dialog --msgbox "無効な選択肢です。再度選択してください。" 6 30; modify_redis_config ;;
    esac
}

# 最大接続数の変更
modify_maxclients() {
    maxclients=$(dialog --inputbox "新しい最大接続数 (maxclients) を入力してください:" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxclients .*/maxclients $maxclients/" /etc/redis/redis.conf
    dialog --msgbox "最大接続数は $maxclients に変更されました" 6 30
    show_menu
}

# 最大メモリ使用量の変更
modify_maxmemory() {
    maxmemory=$(dialog --inputbox "新しい最大メモリ使用量 (maxmemory) を入力してください (例: 2gb):" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxmemory .*/maxmemory $maxmemory/" /etc/redis/redis.conf
    dialog --msgbox "最大メモリ使用量は $maxmemory に変更されました" 6 30
    show_menu
}

# 永続化の有無を変更
modify_persistence() {
    enable_persistence=$(dialog --yesno "永続化を有効にしますか？" 6 30 && echo y || echo n)
    if [[ "$enable_persistence" == "y" ]]; then
        execute_with_sudo sed -i "s/^# save .*/save 900 1/" /etc/redis/redis.conf
        dialog --msgbox "永続化は有効になりました" 6 30
    else
        execute_with_sudo sed -i "s/^# save .*/# save/" /etc/redis/redis.conf
        dialog --msgbox "永続化は無効になりました" 6 30
    fi
    show_menu
}

# 現在の Redis 設定を表示
view_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis 設定ファイルが存在しません。Redis がインストールされているか確認してください。" 6 30
        show_menu
    fi

    dialog --textbox "$CONFIG_FILE" 20 80
    show_menu
}

# メニューの起動
check_root
show_menu
