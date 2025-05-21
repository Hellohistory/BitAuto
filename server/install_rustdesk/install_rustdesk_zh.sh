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
# 安装 unzip :contentReference[oaicite:5]{index=5}
if ! command -v unzip >/dev/null; then
  (apt-get update && apt-get install -y unzip) || yum install -y unzip
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
echo "最新版本：$latest_version"   # GitHub API 返回 release tag :contentReference[oaicite:6]{index=6}

echo "==> 确定下载包格式并下载"
base_url="https://github.com/rustdesk/rustdesk-server/releases/download/${latest_version}"
tgz_file="rustdesk-server-${latest_version}-linux-amd64.tar.gz"
zip_file="rustdesk-server-${latest_version}-linux-amd64.zip"

# 检查 .tar.gz 是否存在
if curl -sI "${base_url}/${tgz_file}" | grep -q "200 OK"; then
  file="${tgz_file}"
  dl_cmd="curl -sSL \"${base_url}/${file}\" -o \"\$tmp_dir/rustdesk.tar.gz\""
  extract_cmd="tar -xzvf \"\$tmp_dir/rustdesk.tar.gz\" -C /opt/rustdesk"
else
  file="${zip_file}"
  dl_cmd="curl -sSL \"${base_url}/${file}\" -o \"\$tmp_dir/rustdesk.zip\""
  extract_cmd="unzip -q \"\$tmp_dir/rustdesk.zip\" -d /opt/rustdesk"
fi

tmp_dir=$(mktemp -d)
echo "下载文件：$file"
eval "$dl_cmd"

echo "==> 解压二进制"
mkdir -p /opt/rustdesk
eval "$extract_cmd"

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
EOF   # systemd 服务配置参考 :contentReference[oaicite:7]{index=7}

echo "==> 启用并启动服务"
systemctl daemon-reload    # 重新加载 systemd 配置 :contentReference[oaicite:8]{index=8}
systemctl enable --now hbbs hbbr   # 启用并启动 :contentReference[oaicite:9]{index=9}

echo "==> 配置防火墙端口"
firewall-cmd --permanent --add-port=21115/tcp   # 打开 TCP 21115 :contentReference[oaicite:10]{index=10}
firewall-cmd --permanent --add-port=21116/tcp   # 打开 TCP 21116 :contentReference[oaicite:11]{index=11}
firewall-cmd --permanent --add-port=21116/udp   # 打开 UDP 21116 :contentReference[oaicite:12]{index=12}
firewall-cmd --permanent --add-port=21117/tcp   # 打开 TCP 21117 :contentReference[oaicite:13]{index=13}
firewall-cmd --reload

echo "✅ RustDesk 服务安装完成：hbbs & hbbr 已启动并启用自启"
