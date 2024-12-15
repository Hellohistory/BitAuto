#!/bin/bash

# 自动化配置高匿 Squid 代理服务器

# 检查是否以 root 用户执行
if [ "$(id -u)" != "0" ]; then
   echo "请以 root 用户执行该脚本。"
   exit 1
fi

LOG_FILE="/var/log/squid_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "开始配置高匿 Squid 代理服务器..."

# 检查系统版本
OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
    echo "此脚本仅支持 Debian 或 Ubuntu 系统。"
    exit 1
fi

# 更新系统软件包
echo "更新系统软件包..."
apt update -y

# 安装 Squid
echo "安装 Squid 代理服务器..."
apt install squid -y

# 备份原始配置文件
echo "备份原始的 squid.conf 文件..."
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak

# 提供用户选项
echo "请选择是否限制允许访问的 IP 地址："
echo "1. 不限制访问（开放代理，允许所有 IP）"
echo "2. 限制访问（只允许特定的 IP 地址或子网）"
read -rp "请输入选项编号（1 或 2）： " choice

# 配置高匿 Squid
echo "配置高匿 Squid..."
if [ "$choice" == "1" ]; then
    # 开放代理配置
    cat > /etc/squid/squid.conf << EOF
# 高匿代理配置（开放代理）
http_port 3128

# 不转发客户端信息
via off
forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access From deny all
request_header_access Referer deny all
request_header_access User-Agent allow all
request_header_access Cache-Control deny all

# 允许所有 IP 访问
acl all src 0.0.0.0/0
http_access allow all

# 关闭缓存（可选）
cache deny all
EOF
    echo "已配置为开放代理，允许所有 IP 访问。请注意安全风险！"
elif [ "$choice" == "2" ]; then
    # 限制访问配置
    echo "请输入允许访问的子网（例如 192.168.1.0/24）："
    read -rp "子网地址： " subnet

    cat > /etc/squid/squid.conf << EOF
# 高匿代理配置（限制访问）
http_port 3128

# 不转发客户端信息
via off
forwarded_for delete
request_header_access X-Forwarded-For deny all
request_header_access From deny all
request_header_access Referer deny all
request_header_access User-Agent allow all
request_header_access Cache-Control deny all

# 限制访问的子网
acl allowed_ips src $subnet
http_access allow allowed_ips
http_access deny all

# 关闭缓存（可选）
cache deny all
EOF
    echo "已配置为限制访问，仅允许子网 $subnet 使用代理。"
else
    echo "无效选项，退出脚本。"
    exit 1
fi

# 日志记录级别选择
echo "请选择 Squid 日志记录级别："
echo "1. 默认日志记录（记录所有请求）"
echo "2. 精简日志（仅记录错误和警告）"
read -rp "请输入选项编号（1 或 2）： " log_choice

if [ "$log_choice" == "2" ]; then
    echo "access_log none" >> /etc/squid/squid.conf
    echo "已设置为精简日志模式。"
fi

# 监听端口选择
read -rp "请输入 Squid 服务监听的端口号（默认 3128）： " port
port=${port:-3128}
sed -i "s/^http_port .*/http_port $port/" /etc/squid/squid.conf
echo "Squid 服务将监听 $port 端口。"

# 是否启用代理认证
echo "是否启用代理认证（需要用户名和密码）？(y/n)"
read -rp "选择： " auth_choice

if [ "$auth_choice" == "y" ]; then
    apt install apache2-utils -y
    echo "创建 Squid 用户认证文件..."
    htpasswd -c /etc/squid/passwd 用户名
    echo "auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all" >> /etc/squid/squid.conf
    echo "代理认证已启用，请使用创建的用户名和密码访问代理。"
fi

# 是否启用缓存
echo "是否启用缓存功能？(y/n)"
read -rp "选择： " cache_choice

if [ "$cache_choice" == "y" ]; then
    read -rp "请输入缓存目录（默认 /var/spool/squid）： " cache_dir
    cache_dir=${cache_dir:-/var/spool/squid}
    read -rp "请输入最大缓存大小（单位 MB，默认 100）： " cache_size
    cache_size=${cache_size:-100}

    echo "cache_dir ufs $cache_dir $cache_size 16 256" >> /etc/squid/squid.conf
    echo "缓存功能已启用，缓存目录：$cache_dir，缓存大小：$cache_size MB。"
fi

# 代理类型选择
echo "请选择代理类型："
echo "1. 正向代理（普通代理）"
echo "2. 反向代理（Web 加速）"
read -rp "请输入选项编号（1 或 2）： " proxy_type

if [ "$proxy_type" == "2" ]; then
    echo "请输入需要代理的目标网站域名（例如 example.com）："
    read -rp "域名： " target_domain

    cat > /etc/squid/squid.conf << EOF
http_port $port accel vhost allow-direct
cache_peer $target_domain parent 80 0 no-query originserver name=myAccel
cache_peer_access myAccel allow all
EOF
    echo "反向代理已配置，代理目标：$target_domain"
fi

# 时间段访问限制
echo "是否启用基于时间的访问限制？(y/n)"
read -rp "选择： " time_acl

if [ "$time_acl" == "y" ]; then
    echo "请输入允许访问的时间段（例如 08:00-18:00）："
    read -rp "时间段： " time_range

    echo "acl work_hours time MTWHF $time_range
http_access allow work_hours
http_access deny all" >> /etc/squid/squid.conf
    echo "已启用基于时间的访问限制，允许访问时间：$time_range"
fi

# 重启 Squid 服务
echo "重启 Squid 服务..."
systemctl restart squid
if systemctl is-active --quiet squid; then
    echo "Squid 服务启动成功。"
else
    echo "Squid 服务启动失败，请检查日志！"
    exit 1
fi

# 设置 Squid 开机自启
echo "设置 Squid 开机自启..."
systemctl enable squid

# 配置防火墙，允许监听端口
echo "配置防火墙，允许 $port 端口..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow $port/tcp
    ufw reload
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=$port/tcp
    firewall-cmd --reload
else
    echo "未检测到防火墙工具，跳过防火墙配置。请手动开放端口 $port。"
fi

# 添加卸载功能
if [ "$1" == "uninstall" ]; then
    echo "卸载 Squid..."
    apt remove --purge squid -y
    rm -rf /etc/squid
    echo "Squid 已卸载。"
    exit 0
fi

# 输出测试说明
echo "高匿 Squid 代理服务器已成功配置并启动！"
echo "请测试代理服务器是否可用，测试命令如下："
echo "curl -x http://<服务器IP>:$port http://www.google.com -v"
