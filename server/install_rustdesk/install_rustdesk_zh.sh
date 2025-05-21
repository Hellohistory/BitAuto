#!/usr/bin/env bash
# --------------------------------------------
# 脚本名称：install_rustdesk.sh
# 功能    ：自动化安装 RustDesk hbbs + hbbr 服务
# 适用    ：CentOS7/8、Ubuntu18/20 及同类发行版
# --------------------------------------------
set -euo pipefail

echo "==> 安装依赖：curl、jq、unzip、firewalld"
# 安装 curl/jq
if ! command -v curl >/dev/null; then
  (apt-get update && apt-get install -y curl) || yum install -y curl
fi
if ! command -v jq >/dev/null; then
  (apt-get update && apt-get install -y jq) || yum install -y jq
fi
# 安装 unzip :contentReference[oaicite:6]{index=6}
if ! command -v unzip >/dev/null; then
  apt-get install -y unzip || yum install -y unzip
fi
# 安装并启动 firewalld
if ! command -v firewall-cmd >/dev/null; then
  (apt-get update && apt-get install -y firewalld) || yum install -y firewalld
  systemctl enable --now firewalld
fi

echo "==> 获取最新版本号"
latest_version=$(curl -sSL \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest \
  | jq -r '.tag_name')
echo "最新版本：$latest_version" # GitHub API 返回 release tag :contentReference[oaicite:7]{index=7}

echo "==> 下载并解压 RustDesk Server 二进制 (ZIP)"
tmp_dir=$(mktemp -d)
download_url="https://github.com/rustdesk/rustdesk-server/releases/download/${latest_version}/rustdesk-server-${latest_version}-linux-amd64.zip"
curl -sSL "$download_url" -o "$tmp_dir/rustdesk.zip"
mkdir -p /opt/rustdesk
unzip -q "$tmp_dir/rustdesk.zip" -d /opt/rustdesk

echo "==> 安装可执行文件到 /usr/local/bin"
install -m 755 /opt/rustdesk/hbbs /usr/local/bin/hbbs
install -m 755 /opt/rustdesk/hbbr /usr/local/bin/hbbr

echo "==> 创建 systemd 服务单元"
cat >/etc/systemd/system/hbbs.service <<'EOF'
[Unit]
Description=RustDesk hbbs (信令 & 心跳 服务)
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
Description=RustDesk hbbr (中继 服务)
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
# 重新加载 systemd 配置 :contentReference[oaicite:8]{index=8}
systemctl daemon-reload
# 开机自启并立即启动 :contentReference[oaicite:9]{index=9}
systemctl enable --now hbbs hbbr

echo "==> 配置防火墙端口"
# 开放核心端口：TCP 21115,21116,21117；UDP 21116 :contentReference[oaicite:10]{index=10}
firewall-cmd --permanent --add-port=21115/tcp
firewall-cmd --permanent --add-port=21116/tcp
firewall-cmd --permanent --add-port=21116/udp
firewall-cmd --permanent --add-port=21117/tcp
firewall-cmd --reload

echo "✅ RustDesk 服务安装完成：hbbs & hbbr 已启动并启用自启"
