#!/usr/bin/env bash
# --------------------------------------------
# 脚本名称：install_rustdesk.sh
# 功能    ：自动化安装 RustDesk hbbs + hbbr 服务
# 适用    ：CentOS/Ubuntu 及同类发行版
# --------------------------------------------
set -euo pipefail

echo "==> 安装依赖：curl、jq、unzip、firewalld"
if ! command -v curl >/dev/null; then
  (apt-get update && apt-get install -y curl) || yum install -y curl
fi
if ! command -v jq >/dev/null; then
  (apt-get update && apt-get install -y jq) || yum install -y jq
fi
if ! command -v unzip >/dev/null; then
  (apt-get update && apt-get install -y unzip) || yum install -y unzip
fi
if ! command -v firewall-cmd >/dev/null; then
  (apt-get update && apt-get install -y firewalld) || yum install -y firewalld
  systemctl enable --now firewalld
fi

echo "==> 获取最新版本号及下载 URL"
api_url="https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest"
resp=$(curl -sSL -H "Accept: application/vnd.github+json" "$api_url")
latest_version=$(jq -r '.tag_name' <<<"$resp")
asset_url=$(jq -r '.assets[]
  | select(.name | test("linux-amd64\\.(zip|tar\\.gz)$"))
  | .browser_download_url' <<<"$resp")
asset_name=$(basename "$asset_url")

echo "最新版本：$latest_version，下载文件：$asset_name"

echo "==> 下载并解压 RustDesk Server 二进制"
tmp_dir=$(mktemp -d)
curl -sSL "$asset_url" -o "$tmp_dir/$asset_name"

case "$asset_name" in
  *.zip)
    unzip -q "$tmp_dir/$asset_name" -d /opt/rustdesk ;;
  *.tar.gz)
    mkdir -p /opt/rustdesk
    tar -xzvf "$tmp_dir/$asset_name" -C /opt/rustdesk ;;
  *)
    echo "不支持的文件格式: $asset_name" >&2
    exit 1 ;;
esac

echo "==> 安装可执行文件到 /usr/local/bin"
install -m 755 /opt/rustdesk/hbbs /usr/local/bin/hbbs
install -m 755 /opt/rustdesk/hbbr /usr/local/bin/hbbr

echo "==> 创建 systemd 服务单元"
cat >/etc/systemd/system/hbbs.service <<'EOF'
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

cat >/etc/systemd/system/hbbr.service <<'EOF'
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

echo "==> 启用并启动服务"
systemctl daemon-reload
systemctl enable --now hbbs hbbr

echo "==> 配置防火墙端口"
firewall-cmd --permanent --add-port=21115/tcp \
                               --add-port=21116/tcp \
                               --add-port=21116/udp \
                               --add-port=21117/tcp
firewall-cmd --reload

echo "✅ RustDesk 服务安装完成：hbbs & hbbr 已启动并启用自启"
