#!/bin/bash

# rootユーザーまたはsudo権限で実行されているか確認
if [ "$(id -u)" != "0" ]; then
    echo "このスクリプトをrootユーザーとして、またはsudoを使用して実行してください。"
    exit 1
fi

echo "🚀 Docker インストールスクリプトを開始します..."

# Dockerが既にインストールされているか確認
if command -v docker &>/dev/null; then
    echo "Docker がインストールされています：$(docker --version)"
    read -p "現在のDockerをアンインストールしますか？(y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        echo "🛠 Dockerをアンインストール中..."
        sudo apt remove -y docker-desktop
        rm -r $HOME/.docker/desktop 2>/dev/null || echo "残りのディレクトリはありません。"
        sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "残りのファイルはありません。"
        sudo apt purge -y docker-desktop docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker /etc/docker
        echo "✅ Dockerがアンインストールされました。"
    else
        echo "⏭ アンインストール手順をスキップします。"
    fi
fi

# パッケージインデックスを更新
echo "🔄 パッケージインデックスを更新中..."
sudo apt update

# Docker公式リポジトリを追加
echo "🌍 Docker公式リポジトリを追加中..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Dockerをインストール（公式リポジトリ）
echo "⚙️  Dockerをインストール中（公式リポジトリ）..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Dockerのインストールに成功しました！（公式リポジトリ）"
    docker --version
else
    echo "❌ 公式リポジトリからのインストールに失敗しました。国内リポジトリに切り替えます..."

    # 国内ミラーリポジトリを選択
    echo "国内ミラーリポジトリを選択してください："
    echo "1) アリミラー"
    echo "2) 清華ミラー"
    read -p "オプションを入力してください（1/2）： " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 アリミラーに切り替え中..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 清華ミラーに切り替え中..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ 無効なオプションです。スクリプトを終了します。"
        exit 1
    fi

    # パッケージインデックスを再更新
    echo "🔄 パッケージインデックスを更新中..."
    sudo apt update

    # 再度Dockerをインストール
    echo "⚙️  Dockerをインストール中（国内リポジトリ）..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Dockerのインストールに成功しました！（国内リポジトリ）"
        docker --version
    else
        echo "❌ Dockerのインストールに失敗しました。エラーログを確認してください。"
        exit 1
    fi
fi

# Dockerイメージアクセラレーターを設定
configure_docker_proxy() {
    echo "🌍 DockerのイメージアクセラレーターのURLを入力してください（例：https://registry.docker-cn.com）。スキップするにはEnterを押してください："
    read proxy_url
    if [[ -z "$proxy_url" ]]; then
        echo "⏭ プロキシ設定をスキップします。"
        return 0
    fi

    # jqツールがインストールされているか確認
    if ! command -v jq &>/dev/null; then
        echo "🛠 jqツールをインストール中..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ jqを自動的にインストールできません。手動でインストールしてから再試行してください。"
            return 1
        fi
    fi

    # /etc/dockerディレクトリが存在することを確認
    sudo mkdir -p /etc/docker

    # 設定ファイルを処理
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    if [ -f "$config_file" ]; then
        jq --arg url "$proxy_url" '."registry-mirrors" = [$url]' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": [\"$proxy_url\"]}" | jq . > "$tmp_file"
    fi

    # 目標ファイルが存在することを確認
    sudo touch "$config_file"

    # 設定を適用
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Dockerサービスを再起動中..."
    sudo systemctl restart docker

    # 設定を検証
    echo "✅ 設定を検証中..."
    if sudo docker info 2>/dev/null | grep -q "$proxy_url"; then
        echo "✅ プロキシ設定の検証に成功しました！"
    else
        echo "❌ プロキシ設定が有効でない可能性があります。以下を確認してください："
        echo "1. 入力したイメージURLが正しいことを確認してください。"
        echo "2. 'sudo docker info'を手動で実行してRegistry Mirrorsを確認してください。"
        echo "3. /etc/docker/daemon.jsonファイルの権限と内容を確認してください。"
    fi
}

# ユーザーにDockerイメージアクセラレーターの設定を促す
read -p "Dockerのイメージアクセラレーターを設定しますか？(y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ イメージアクセラレーターの設定をスキップします。"
fi

echo "🎉 Dockerのインストールと設定が完了しました！"
exit 0
