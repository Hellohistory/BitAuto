#!/usr/bin/env bash
# --------------------------------------------
# 脚本名称：install_rustdesk.sh
# 功能    ：自动化安装 RustDesk hbbs + hbbr 服务
# 适用    ：CentOS/Ubuntu/Debian/Rocky Linux 等
# 作者    ：Hellohistory
# --------------------------------------------
set -euo pipefail

# 👉 系统检测
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "❌ 无法识别系统，退出" && exit 1
fi
echo "📦 系统: $PRETTY_NAME"

# 安装依赖
echo "🔧 安装依赖 curl/jq/unzip/firewalld"
case "$ID" in
  ubuntu|debian) apt update && apt install -y curl jq unzip firewalld ;;
  centos|rhel|rocky|almalinux) yum install -y curl jq unzip firewalld ;;
  *) echo "❌ 系统 $ID 不支持" && exit 1 ;;
esac

# 启用防火墙
systemctl enable --now firewalld

# 获取最新版本下载链接
echo "🌐 获取最新发布版本"
resp=$(curl -sSL https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest)
asset_url=$(jq -r '.assets[]
  | select(.name|test("linux-amd64\\.(zip|tar.gz)$"))
  | .browser_download_url' <<< "$resp")
asset_name=$(basename "$asset_url")
echo "最新版本: $asset_name"

# 下载并解压
tmp=$(mktemp -d)
curl -sSL "$asset_url" -o "$tmp/$asset_name"

mkdir -p /opt/rustdesk
pushd "$tmp" >/dev/null
case "$asset_name" in
  *.zip) unzip -q "$asset_name" ;;
  *.tar.gz) tar xzf "$asset_name" ;;
esac

# 查找 hbbs 和 hbbr
exec_dir=$(find . -type f -name hbbs -exec dirname {} \; | head -1)
[[ -z "$exec_dir" ]] && { echo "❌ 未找到 hbbs 可执行文件"; exit 1; }
echo "发现二进制目录：$exec_dir"

# 安装可执行文件
install -m755 "$exec_dir"/hbbs /usr/local/bin/hbbs
install -m755 "$exec_dir"/hbbr /usr/local/bin/hbbr
popd >/dev/null
rm -rf "$tmp"

# 创建 systemd 服务
cat >/etc/systemd/system/hbbs.service <<EOF
[Unit]
Description=RustDesk hbbs (信令 & 心跳)
After=network.target
[Service]
ExecStart=/usr/local/bin/hbbs
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/hbbr.service <<EOF
[Unit]
Description=RustDesk hbbr (中继)
After=network.target
[Service]
ExecStart=/usr/local/bin/hbbr
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable --now hbbs hbbr

# 防火墙开放端口
firewall-cmd --permanent --add-port=21115/tcp
firewall-cmd --permanent --add-port=21116/tcp
firewall-cmd --permanent --add-port=21116/udp
firewall-cmd --permanent --add-port=21117/tcp
firewall-cmd --reload

# 打印公钥
echo "✅ 安装完成！请复制以下公钥设置到客户端："
pubfile="/opt/rustdesk/id_ed25519.pub"
if [ -f "$pubfile" ]; then
  cat "$pubfile"
else
  echo "⚠️ 未找到公钥，请检查 /opt/rustdesk 目录"
fi

# 测试服务是否启动成功
sleep 2
if systemctl is-active --quiet hbbs && systemctl is-active --quiet hbbr; then
  echo -e "\n🎉 RustDesk 服务启动成功！hbbs & hbbr 正在运行。"
else
  echo -e "\n❌ 服务未启动，请查看日志: journalctl -u hbbs -u hbbr"
fi
