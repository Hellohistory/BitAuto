#!/usr/bin/env bash
# --------------------------------------------
# 脚本名称：install_rustdesk.sh
# 功能    ：自动化安装 RustDesk hbbs + hbbr 服务
# 适用    ：CentOS/Ubuntu/Debian/Rocky Linux 等
# 作者    ：Hellohistory
# --------------------------------------------
set -euo pipefail

# 检测操作系统类型
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=$ID
  OS_VERSION_ID=$VERSION_ID
else
  echo "无法检测操作系统类型：缺少 /etc/os-release 文件。"
  exit 1
fi

echo "检测到操作系统：$PRETTY_NAME"

# 安装依赖项
echo "==> 安装依赖项：curl、jq、unzip、firewalld"
case "$OS_ID" in
  ubuntu|debian)
    sudo apt update
    sudo apt install -y curl jq unzip firewalld
    ;;
  centos|rhel|rocky|almalinux)
    sudo yum install -y curl jq unzip firewalld
    ;;
  *)
    echo "不支持的操作系统：$PRETTY_NAME"
    exit 1
    ;;
esac

# 启动并启用 firewalld
sudo systemctl enable --now firewalld

# 获取最新版本号及下载链接
echo "==> 获取最新版本号及下载链接"
api_url="https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest"
resp=$(curl -sSL -H "Accept: application/vnd.github+json" "$api_url")
latest_version=$(jq -r '.tag_name' <<<"$resp")
asset_url=$(jq -r '.assets[] | select(.name | test("linux-amd64\\.(zip|tar\\.gz)$")) | .browser_download_url' <<<"$resp")
asset_name=$(basename "$asset_url")

echo "最新版本：$latest_version，下载文件：$asset_name"

# 下载并解压 RustDesk Server
echo "==> 下载并解压 RustDesk Server"
tmp_dir=$(mktemp -d)
curl -sSL "$asset_url" -o "$tmp_dir/$asset_name"

mkdir -p /opt/rustdesk

case "$asset_name" in
  *.zip)
    unzip -q "$tmp_dir/$asset_name" -d /opt/rustdesk
    ;;
  *.tar.gz)
    tar -xzvf "$tmp_dir/$asset_name" -C /opt/rustdesk
    ;;
  *)
    echo "不支持的文件格式: $asset_name"
    exit 1
    ;;
esac

# 安装可执行文件
echo "==> 安装可执行文件到 /usr/local/bin"
sudo install -m 755 /opt/rustdesk/hbbs /usr/local/bin/hbbs
sudo install -m 755 /opt/rustdesk/hbbr /usr/local/bin/hbbr

# 创建 systemd 服务文件
echo "==> 创建 systemd 服务文件"

sudo tee /etc/systemd/system/hbbs.service > /dev/null <<EOF
[Unit]
Description=RustDesk hbbs (信令 & 心跳)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hbbs
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/hbbr.service > /dev/null <<EOF
[Unit]
Description=RustDesk hbbr (中继)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hbbr
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 启动并启用服务
echo "==> 启动并启用 hbbs 和 hbbr 服务"
sudo systemctl daemon-reload
sudo systemctl enable --now hbbs
sudo systemctl enable --now hbbr

# 配置防火墙
echo "==> 配置防火墙规则"
sudo firewall-cmd --permanent --add-port=21115/tcp
sudo firewall-cmd --permanent --add-port=21116/tcp
sudo firewall-cmd --permanent --add-port=21116/udp
sudo firewall-cmd --permanent --add-port=21117/tcp
sudo firewall-cmd --reload

# 显示公钥
echo "==> RustDesk 服务安装完成！"
echo "请在客户端配置中使用以下公钥："
if [ -f /opt/rustdesk/id_ed25519.pub ]; then
  cat /opt/rustdesk/id_ed25519.pub
else
  echo "未找到公钥文件，请检查 /opt/rustdesk 目录。"
fi
