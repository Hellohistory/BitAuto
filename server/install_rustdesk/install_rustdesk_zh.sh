#!/usr/bin/env bash
# --------------------------------------------
# 脚本名称：install_rustdesk.sh
# 功能    ：自动化安装 RustDesk 中继和注册服务器
# 运行方式：sudo bash install_rustdesk.sh
# 适用    ：CentOS7/8、Ubuntu18/20 及同类发行版
# --------------------------------------------
set -euo pipefail

echo "==> 安装依赖：curl、jq、tar、firewall-cmd"
if ! command -v curl >/dev/null; then
  yum install -y curl || apt-get update && apt-get install -y curl
fi
if ! command -v jq >/dev/null; then
  yum install -y jq || apt-get install -y jq
fi
if ! command -v tar >/dev/null; then
  yum install -y tar || apt-get install -y tar
fi
if ! command -v firewall-cmd >/dev/null; then
  yum install -y firewalld || apt-get install -y firewalld
  systemctl enable --now firewalld
fi

echo "==> 通过 GitHub API 获取最新版本号"
latest_version=$(curl -sSL \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest \
  | jq -r '.tag_name')
echo "最新版本：$latest_version"

echo "==> 下载并解压 RustDesk Server 二进制"
tmp_dir=$(mktemp -d)
download_url="https://github.com/rustdesk/rustdesk-server/releases/download/${latest_version}/rustdesk-server-${latest_version}-linux-amd64.tar.gz"
curl -sSL "$download_url" -o "$tmp_dir/rustdesk.tar.gz"
mkdir -p /opt/rustdesk
tar -xzvf "$tmp_dir/rustdesk.tar.gz" -C /opt/rustdesk

echo "==> 安装可执行文件到 /usr/local/bin"
install -m 755 /opt/rustdesk/hbbs /usr/local/bin/hbbs
install -m 755 /opt/rustdesk/hbbr /usr/local/bin/hbbr

echo "==> 生成 systemd 服务文件"
cat >/etc/systemd/system/hbbs.service <<'EOF'
[Unit]
Description=RustDesk hbbs (ID/心跳 服务)
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
systemctl daemon-reload
systemctl enable --now hbbs hbbr

echo "==> 配置防火墙端口"
firewall-cmd --permanent --add-port=21115/tcp
firewall-cmd --permanent --add-port=21116/tcp
firewall-cmd --permanent --add-port=21116/udp
firewall-cmd --permanent --add-port=21117/tcp
firewall-cmd --reload

echo "✅ RustDesk 服务安装完成：hbbs & hbbr 已启动并已开启自启"
