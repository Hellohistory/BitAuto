#!/bin/bash

# root ユーザーまたは sudo 権限で実行しているか確認
if [ "$(id -u)" != "0" ]; then
    echo "root ユーザーまたは sudo を使用してスクリプトを実行してください。"
    exit 1
fi

echo "🚀 Docker インストールスクリプト開始..."

# Docker がインストールされているか確認
if command -v docker &>/dev/null; then
    echo "Docker が既にインストールされています：$(docker --version)"
    read -p "現在の Docker をアンインストールしますか？(y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        echo "🛠 Docker をアンインストール中..."
        sudo apt remove -y docker-desktop
        rm -r $HOME/.docker/desktop 2>/dev/null || echo "不要なフォルダはありません。"
        sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "不要なファイルはありません。"
        sudo apt purge -y docker-desktop docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker /etc/docker
        echo "✅ Docker はアンインストールされました。"
    else
        echo "⏭ アンインストールをスキップします。"
    fi
fi

# パッケージリストを更新
echo "🔄 パッケージリストを更新中..."
sudo apt update

# Docker の公式リポジトリを追加
echo "🌍 Docker の公式リポジトリを追加..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Docker のインストールを試行 (公式リポジトリ)
echo "⚙️  Docker をインストール中 (公式リポジトリ)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker のインストールに成功しました！(公式リポジトリ)"
    docker --version
else
    echo "❌ 公式リポジトリでのインストールに失敗！国内ミラーを試します..."

    # 国内ミラーの選択
    echo "国内ミラーを選択してください:"
    echo "1) アリババクラウド (Aliyun)"
    echo "2) 清華大学 (TUNA)"
    read -p "選択 (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 アリババクラウドミラーを使用します..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 清華大学ミラーを使用します..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ 無効な選択です。スクリプトを終了します。"
        exit 1
    fi

    # 再度パッケージリストを更新
    echo "🔄 パッケージリストを更新中..."
    sudo apt update

    # Docker の再インストール
    echo "⚙️  Docker をインストール中 (国内ミラー)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker のインストールに成功しました！(国内ミラー)"
        docker --version
    else
        echo "❌ Docker のインストールに失敗しました。エラーログを確認してください。"
        exit 1
    fi
fi

configure_docker_proxy() {
    echo "🌍 Docker ミラーアクセラレーターの URL を入力してください（複数入力可、スペース区切り 例: https://registry.docker-cn.com https://mirror.ccs.tencentyun.com）。Enter を押すとスキップします: "
    read -r proxy_urls
    if [[ -z "$proxy_urls" ]]; then
        echo "⏭ ミラー設定をスキップします。"
        return 0
    fi

    # jq コマンドの確認
    if ! command -v jq &>/dev/null; then
        echo "🛠 jq をインストール中..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ jq のインストールに失敗しました。手動でインストールしてください。"
            return 1
        fi
    fi

    # /etc/docker ディレクトリを作成
    sudo mkdir -p /etc/docker

    # 設定ファイルの処理
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    # 入力されたプロキシ URL を JSON 配列に変換
    registry_mirrors=()
    for url in $proxy_urls; do
        registry_mirrors+=("\"$url\"")
    done
    mirrors_json="[${registry_mirrors[*]}]"

    # daemon.json を更新または作成
    if [ -f "$config_file" ]; then
        jq --argjson mirrors "$mirrors_json" '."registry-mirrors" = $mirrors' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": $mirrors_json}" | jq . > "$tmp_file"
    fi

    # ファイルを適用
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Docker サービスを再起動中..."
    sudo systemctl restart docker

    # 設定を確認
    echo "✅ 設定を確認中..."
    if sudo docker info 2>/dev/null | grep -q "$(echo "$proxy_urls" | awk '{print $1}')"; then
        echo "✅ ミラー設定が適用されました！"
    else
        echo "❌ ミラー設定が適用されていない可能性があります。以下を確認してください:"
        echo "1. 入力したミラー URL が正しいか確認"
        echo "2. 'sudo docker info' を実行して Registry Mirrors を確認"
        echo "3. /etc/docker/daemon.json の内容と権限を確認"
    fi
}

# ミラーアクセラレーターを設定するか確認
read -p "Docker ミラーアクセラレーターを設定しますか？(y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ ミラー設定をスキップします。"
fi

echo "🎉 Docker のインストールと設定が完了しました！"
exit 0
