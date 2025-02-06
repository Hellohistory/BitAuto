#!/bin/bash

# rootユーザーまたはsudo権限で実行されているか確認
if [ "$(id -u)" != "0" ]; then
    echo "rootユーザーまたはsudoを使用してスクリプトを実行してください。"
    exit 1
fi

echo "🚀 Dockerインストールスクリプト開始..."

# Dockerがインストールされているか確認
if command -v docker &>/dev/null; then
    echo "Dockerが既にインストールされています：$(docker --version)"
    read -p "現在のDockerをアンインストールしますか？(y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        echo "🛠 Dockerをアンインストール中..."
        sudo apt remove -y docker-desktop
        rm -r $HOME/.docker/desktop 2>/dev/null || echo "残存ディレクトリなし。"
        sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "残存ファイルなし。"
        sudo apt purge -y docker-desktop docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker /etc/docker
        echo "✅ Dockerがアンインストールされました。"
    else
        echo "⏭ アンインストールをスキップ。"
    fi
fi

# パッケージリストを更新
echo "🔄 パッケージリストを更新中..."
sudo apt update

# Docker公式リポジトリを追加
echo "🌍 Docker公式リポジトリを追加..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Dockerをインストール（公式リポジトリ）
echo "⚙️ Dockerをインストール中 (公式リポジトリ)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Dockerのインストール成功！（公式リポジトリ）"
    docker --version
else
    echo "❌ 公式リポジトリからのインストールに失敗！国内ミラーを試行..."

    # 国内ミラーの選択
    echo "国内ミラーを選択してください:"
    echo "1) アリババミラー"
    echo "2) 清華大学ミラー"
    read -p "選択してください (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 アリババミラーに切り替え..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 清華大学ミラーに切り替え..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ 無効な選択肢。スクリプトを終了します。"
        exit 1
    fi

    # パッケージリストを再更新
    echo "🔄 パッケージリストを更新..."
    sudo apt update

    # 再度Dockerをインストール
    echo "⚙️ Dockerをインストール中 (国内ミラー)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Dockerのインストール成功！（国内ミラー）"
        docker --version
    else
        echo "❌ Dockerのインストールに失敗しました。エラーログを確認してください。"
        exit 1
    fi
fi

configure_docker_proxy() {
    echo "🌍 DockerのミラーアクセラレーターURLを入力してください（複数の場合はスペースで区切る 例: https://registry.docker-cn.com https://mirror.ccs.tencentyun.com）。Enterキーでスキップ："
    read -r proxy_urls
    if [[ -z "$proxy_urls" ]]; then
        echo "⏭ ミラーアクセラレーターの設定をスキップ。"
        return 0
    fi

    # jqツールがあるか確認
    if ! command -v jq &>/dev/null; then
        echo "🛠 jqツールをインストール中..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ jqのインストールに失敗しました。手動でインストールしてください。"
            return 1
        fi
    fi

    # /etc/dockerディレクトリを確保
    sudo mkdir -p /etc/docker

    # 設定ファイルの処理
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    # 入力されたミラーアドレスをJSON形式に変換
    registry_mirrors=()
    for url in $proxy_urls; do
        registry_mirrors+=("\"$url\"")
    done
    mirrors_json="[${registry_mirrors[*]}]"

    # daemon.jsonの更新または作成
    if [ -f "$config_file" ]; then
        jq --argjson mirrors "$mirrors_json" '."registry-mirrors" = $mirrors' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": $mirrors_json}" | jq . > "$tmp_file"
    fi

    # 設定を適用
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Dockerサービスを再起動..."
    sudo systemctl restart docker

    # 設定の確認
    echo "✅ 設定を確認中..."
    if sudo docker info 2>/dev/null | grep -q "$(echo "$proxy_urls" | awk '{print $1}')"; then
        echo "✅ ミラーアクセラレーターの設定が適用されました！"
    else
        echo "❌ 設定が反映されていない可能性があります。以下を確認してください："
        echo "1. 入力したミラーURLが正しいか"
        echo "2. 'sudo docker info' を実行し、Registry Mirrorsを確認"
        echo "3. /etc/docker/daemon.json の権限と内容をチェック"
    fi
}

# ミラーアクセラレーターを設定するか確認
read -p "Dockerミラーアクセラレーターを設定しますか？(y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ ミラーアクセラレーターの設定をスキップ。"
fi

# Dockerの自動起動設定
read -p "Dockerを起動時に自動起動させますか？(y/N): " autostart_choice
if [[ "$autostart_choice" =~ ^[Yy]$ ]]; then
    echo "🚀 Dockerを起動時に自動起動するよう設定中..."
    if sudo systemctl enable docker; then
        echo "✅ Dockerは起動時に自動起動するよう設定されました！"
    else
        echo "❌ 自動起動の設定に失敗しました。エラーログを確認してください。"
    fi
else
    echo "⏭ 自動起動設定をスキップ。"
fi

echo "🎉 Dockerのインストールと設定が完了しました！"
exit 0
