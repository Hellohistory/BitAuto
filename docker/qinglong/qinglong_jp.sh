#!/bin/bash
set -euo pipefail

# グローバル設定
IMAGE_NAME="whyour/qinglong:latest"
CONTAINER_NAME="qinglong"
CONTAINER_PORT=5700
MAX_RETRY=3

# 有効なユーザー入力を読み取る（y/n）
read_yes_no() {
    local prompt="$1"
    local input
    while true; do
        read -p "$prompt" input
        case "$input" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "y または n を入力してください。" ;;
        esac
    done
}

# Qinglongの公開ポートを読み取る（デフォルト5700）
read_exposed_port() {
    local input_port
    read -p "Qinglongの公開ポートを入力してください (デフォルト5700): " input_port
    if [ -z "$input_port" ]; then
        EXPOSED_PORT=5700
    else
        EXPOSED_PORT=$input_port
    fi
}

# Dockerがインストールされているか確認
check_docker_installed() {
    if command -v docker &>/dev/null; then
        echo "✅ Dockerはインストール済みです"
        return 0
    else
        echo "❌ Dockerがインストールされていません。先にDockerをインストールしてください"
        echo "インストールドキュメント参照：https://docs.docker.com/engine/install/"
        return 1
    fi
}

# Dockerが実行中か確認
check_docker_running() {
    if docker info &>/dev/null; then
        echo "✅ Dockerは実行中です"
        return 0
    else
        echo "⚠️ Dockerはインストールされていますが、実行されていません"
        return 1
    fi
}

# Dockerサービスを起動（systemctlとserviceに対応）
start_docker_service() {
    echo "Dockerサービスの起動を試みています..."
    if command -v systemctl &>/dev/null; then
        if sudo systemctl start docker; then
            echo "✅ Dockerサービスの起動に成功しました（systemctl）"
            return 0
        fi
    elif command -v service &>/dev/null; then
        if sudo service docker start; then
            echo "✅ Dockerサービスの起動に成功しました（service）"
            return 0
        fi
    fi
    echo "❌ Dockerの起動に失敗しました。手動で確認してください"
    return 1
}

# プロキシアドレスのフォーマットを検証（簡易検証）
validate_proxy() {
    local proxy="$1"
    if [[ "$proxy" =~ ^https?://.+ ]]; then
        return 0
    else
        return 1
    fi
}

# Dockerプロキシを設定
set_docker_proxy() {
    local proxy
    read -p "Docker HTTP/HTTPSプロキシアドレスを入力してください（例 http://your.proxy.address:port）： " proxy
    if [ -z "$proxy" ]; then
        echo "プロキシアドレスは空にできません。プロキシ設定をキャンセルします。"
        return 1
    fi
    if ! validate_proxy "$proxy"; then
        echo "プロキシアドレスのフォーマットが正しくありません。正しいフォーマットを使用してください（例 http://your.proxy.address:port）"
        return 1
    fi
    echo "Dockerプロキシを $proxy に設定しています..."
    local proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"
    if [ -f "$proxy_conf" ]; then
        echo "既存のDockerプロキシ設定を検出しました"
        if ! read_yes_no "既存のプロキシ設定を上書きしますか？(y/n): "; then
            echo "既存のプロキシ設定を保持し、プロキシ設定をキャンセルします。"
            return 1
        fi
    fi
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo tee "$proxy_conf" > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$proxy" "HTTPS_PROXY=$proxy" "NO_PROXY=localhost,127.0.0.1"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "✅ Dockerプロキシ設定が完了し、サービスを再起動しました"
}

# イメージをプルし、自動的にQinglongコンテナを起動、Qinglongパネルのアクセスアドレスを出力
deploy_qinglong() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY ]; do
        echo "🚀 Qinglongイメージのプルを開始します（試行回数: $((retry_count+1))）..."
        if docker pull "$IMAGE_NAME"; then
            echo "✅ Qinglongイメージのプルに成功しました！"
            # 同名のコンテナが既にある場合は、古いコンテナを削除
            if [ "$(docker ps -a -q -f name="^${CONTAINER_NAME}$")" ]; then
                echo "${CONTAINER_NAME} という名前の既存コンテナを検出しました。古いコンテナを削除しています..."
                docker rm -f "$CONTAINER_NAME"
            fi
            echo "Qinglongコンテナを起動しています..."
            docker run -dit --name "$CONTAINER_NAME" -p "${EXPOSED_PORT}:${CONTAINER_PORT}" "$IMAGE_NAME"
            # パブリックIPを取得
            PUBLIC_IP=$(curl -s ifconfig.me)
            echo "✅ Qinglongコンテナの起動に成功しました！"
            echo "Qinglongパネルのアクセスアドレス: http://${PUBLIC_IP}:${EXPOSED_PORT}"
            return 0
        else
            echo "❌ イメージのプルに失敗しました（試行回数: $((retry_count+1))）。ネットワーク問題が原因かもしれません。"
            if read_yes_no "Dockerプロキシを設定して再試行しますか？(y/n): "; then
                if ! set_docker_proxy; then
                    echo "プロキシ設定に失敗したかキャンセルされました。イメージプルプロセスを終了します。"
                    return 1
                fi
            else
                echo "ユーザーがプロキシ設定を選択しませんでした。イメージプルプロセスを終了します。"
                return 1
            fi
        fi
        retry_count=$((retry_count+1))
    done
    echo "❌ 最大再試行回数を超えました。イメージのプルに失敗しました。"
    return 1
}

# メインプロセス
main() {
    echo "🔍 Docker環境を検出しています..."
    check_docker_installed || exit 1

    if ! check_docker_running; then
        if read_yes_no "Dockerが実行されていません。Dockerサービスを起動しますか？(y/n): "; then
            start_docker_service || exit 1
            if ! check_docker_running; then
                echo "❌ Dockerサービスがまだ起動していません。手動で確認してください。"
                exit 1
            fi
        else
            echo "ユーザーがDockerサービスの起動をキャンセルしました。スクリプトを終了します。"
            exit 0
        fi
    fi

    read_exposed_port
    deploy_qinglong
}

main