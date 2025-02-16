# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "ルートユーザーでスクリプトを実行してください。または sudo を使用してください。"
    exit 1
fi

# 交互式获取端口号和安装目录
echo "EasyImage の実行ポート番号を入力してください (デフォルト: 8090):"
read -r user_port
EASYIMAGE_PORT=${user_port:-8090}

echo "EasyImage のインストールディレクトリを入力してください (デフォルト: /etc/docker/easyimage):"
read -r user_dir
EASYIMAGE_DIR=${user_dir:-/etc/docker/easyimage}

# 是否启用开机自启
echo "自動起動を有効にしますか？(y/n, デフォルト: y)"
read -r enable_autostart
ENABLE_AUTOSTART=${enable_autostart:-y}

# 检测 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo "Docker がインストールされていません。以下のコマンドで Docker をインストールしてください:"
    echo "bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/docker/install_docker/docker_zh.sh)"
    echo "または"
    echo "bash <(curl -sSL https://gitee.com/hellohistory/BitAuto/raw/main/docker/install_docker/docker_zh.sh)"
    exit 1
fi

# 确保 Docker 运行正常
if ! systemctl is-active --quiet docker; then
    echo "Docker が実行されていません。Docker を起動中..."
    systemctl start docker
fi

# 检测 Docker Compose（支持新版 `docker compose`）
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Docker Compose がインストールされていません。インストール中..."
    apt update && apt install -y docker-compose
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 端口检测
if ss -tuln | grep -q ":$EASYIMAGE_PORT"; then
    echo "警告: ポート $EASYIMAGE_PORT はすでに使用されています。スクリプトを再実行し、新しいポート番号を入力してください。"
    exit 1
fi

# 创建并进入数据文件夹
mkdir -p "$EASYIMAGE_DIR"
cd "$EASYIMAGE_DIR" || { echo "ディレクトリ $EASYIMAGE_DIR に移動できません"; exit 1; }

# 显示 EasyImage-docker-compose.yaml 配置
echo "EasyImage-docker-compose.yaml 設定ファイルが作成されました:"
cat EasyImage-docker-compose.yaml

# 启动 EasyImage
echo "EasyImage を起動しています..."
$DOCKER_COMPOSE_CMD -f EasyImage-docker-compose.yaml up -d

# 设置 Docker Compose 服务开机自启（用户可选）
if [ "$ENABLE_AUTOSTART" = "y" ]; then
    echo "EasyImage の自動起動サービスを作成中..."
    systemctl enable easyimage.service
    systemctl start easyimage.service
    echo "EasyImage の自動起動設定が完了しました！"
fi

# 检查容器运行状态
docker ps | grep easyimage

# 自动开放防火墙端口
if systemctl is-active --quiet firewalld; then
    firewall-cmd --add-port="${EASYIMAGE_PORT}"/tcp --permanent
    firewall-cmd --reload
    echo "ファイアウォールのポートを開放しました: ${EASYIMAGE_PORT}"
elif command -v iptables &> /dev/null; then
    iptables -I INPUT -p tcp --dport "${EASYIMAGE_PORT}" -j ACCEPT
    echo "iptables のポートを開放しました: ${EASYIMAGE_PORT}"
fi

# 获取服务器 IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "EasyImage のインストールと設定が完了しました！ アクセス URL: http://${SERVER_IP}:${EASYIMAGE_PORT}"
