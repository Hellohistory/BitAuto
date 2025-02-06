#!/bin/bash
#
# 深度更新的自动化部署 Squid 代理服务器脚本（支持多项可选配置）
#
# 功能特性：
#   1. 代理类型（正向/反向）
#   2. 监听端口
#   3. 透明代理可选
#   4. SSL Bump（HTTPS 解密）可选
#   5. IP 限制（单 IP / 网段）
#   6. 用户名密码认证
#   7. Key 验证
#   8. 缓存设置（目录、大小、刷新规则、最大对象大小）
#   9. 时间访问控制
#   10. 域名黑/白名单过滤
#   11. 日志模式选择（默认 / 精简），并示例如何使用 logrotate
#   12. 防火墙端口开放
#   13. 一键卸载
#
# 所有可选功能通过交互式问答一一开启或关闭，实现高度定制化的配置输出。
#

#====================================================================#
#                      全局变量与默认值                               #
#====================================================================#

LOG_FILE="/var/log/squid_install.log"   # 日志文件
SQUID_CONF_PATH="/etc/squid/squid.conf" # Squid 主配置文件

# 以下变量将在交互式函数中赋值
proxy_type=""             # 代理类型（1=正向代理，2=反向代理）
port="3128"               # 监听端口
target_domain=""          # 反向代理目标域名（当选择反向代理时生效）

transparent_choice="n"    # 是否开启透明代理
ssl_bump_choice="n"       # 是否开启 SSL Bump
certificate_path="/etc/squid/certs" # SSL 自签证书存放路径
ssl_cert_file="squidCA.pem"
ssl_key_file="squidCA.key"

ip_choice=""              # IP 限制选项（1=允许所有，2=仅允许特定IP）
allowed_ip=""             # 允许访问的 IP 或子网

auth_choice="n"           # 是否启用用户名密码认证
auth_user=""              # 认证用户名

key_choice="n"            # 是否启用 Key 验证
secret_header="X-Auth-Key"
secret_key="mysecretkey"

cache_choice="n"          # 是否启用缓存
cache_dir="/var/spool/squid"
cache_size="100"          # 缓存大小（MB）
max_obj_size="1024"       # 最大缓存对象大小（MB）
refresh_choice="n"        # 是否自定义 Refresh Pattern

time_choice="n"           # 是否启用时间访问控制
time_range=""             # 访问时间段

domain_filter_choice="n"  # 是否启用域名过滤
domain_filter_type="1"    # 过滤方式（1=黑名单，2=白名单）
blocked_domains_file="/etc/squid/blocked_domains.txt"
allowed_domains_file="/etc/squid/allowed_domains.txt"

log_choice="1"            # 日志记录模式（1=默认, 2=精简日志）

UNINSTALL=false           # 是否执行卸载


#====================================================================#
# 1. 函数：检查是否以 root 用户执行                                   #
#====================================================================#
function check_root() {
    # 检查是否以 root 身份执行，否则退出
    if [ "$(id -u)" != "0" ]; then
        echo "请以 root 用户执行该脚本。"
        exit 1
    fi
}

#====================================================================#
# 2. 函数：解析命令行参数                                            #
#     - 支持命令:
#       1) ./script.sh uninstall  (执行卸载)                         #
#====================================================================#
function parse_arguments() {
    if [ "$1" == "uninstall" ]; then
        UNINSTALL=true
    fi
}

#====================================================================#
# 3. 函数：卸载 Squid                                                #
#====================================================================#
function uninstall_squid() {
    echo "开始卸载 Squid..."
    systemctl stop squid
    apt remove --purge -y squid
    rm -rf /etc/squid
    echo "Squid 已卸载。"
}

#====================================================================#
# 4. 函数：安装 Squid（适配 Debian/Ubuntu）                           #
#====================================================================#
function install_squid() {
    # 检查系统版本
    OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
        echo "此脚本仅支持 Debian 或 Ubuntu 系统。"
        exit 1
    fi

    echo "更新软件包列表..."
    apt update -y
    echo "安装 Squid 代理服务器..."
    apt install -y squid
}

#====================================================================#
# 5. 函数：备份现有配置文件                                          #
#====================================================================#
function backup_squid_config() {
    # 如果已有配置文件，则做备份
    if [ -f "${SQUID_CONF_PATH}" ]; then
        echo "备份原有的 ${SQUID_CONF_PATH}..."
        cp "${SQUID_CONF_PATH}" "${SQUID_CONF_PATH}.bak"
    fi
}

#====================================================================#
# 6. 函数：生成自签证书（SSL Bump 场景）                              #
#====================================================================#
function generate_self_signed_cert() {
    # 创建存放证书的目录
    mkdir -p "${certificate_path}"

    # 如果证书已存在则跳过生成
    if [ -f "${certificate_path}/${ssl_cert_file}" ] && [ -f "${certificate_path}/${ssl_key_file}" ]; then
        echo "检测到已存在自签证书，将直接复用。"
        return
    fi

    echo "开始生成自签证书，用于 SSL Bump..."
    openssl req -new -x509 -days 3650 -nodes -out "${certificate_path}/${ssl_cert_file}" \
        -keyout "${certificate_path}/${ssl_key_file}" \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=MyOrg/OU=IT/CN=SquidSSL"

    # 更改权限（供 Squid 读取）
    chmod 600 "${certificate_path}/${ssl_key_file}"
    chown proxy:proxy "${certificate_path}/${ssl_key_file}"
    chmod 644 "${certificate_path}/${ssl_cert_file}"
    chown proxy:proxy "${certificate_path}/${ssl_cert_file}"

    echo "自签证书生成完毕，证书路径: ${certificate_path}/${ssl_cert_file}"
    echo "密钥路径: ${certificate_path}/${ssl_key_file}"
}

#====================================================================#
# 7. 函数：交互式配置输入（read -rp）                                 #
#====================================================================#
function configure_squid() {
    # 1) 代理类型
    echo "请选择代理类型："
    echo "1. 正向代理（普通代理）"
    echo "2. 反向代理（Web 加速）"
    read -rp "请输入选项编号（1 或 2，默认 1）： " proxy_type
    if [ -z "${proxy_type}" ]; then
        proxy_type="1"
    fi

    # 2) 端口
    read -rp "请输入 Squid 监听端口（默认 3128）： " tmp_port
    if [ -n "$tmp_port" ]; then
        port="$tmp_port"
    fi

    # 如果是反向代理，只需要询问目标域名，后续配置更简单
    if [ "$proxy_type" == "2" ]; then
        read -rp "请输入需要代理的目标网站域名（例如 example.com）： " target_domain
        return
    fi

    # ========== 以下配置仅在正向代理时才会继续问 ==========

    # 3) 是否开启透明代理
    read -rp "是否配置为透明代理 (iptables 转发流量)？(y/n) " transparent_choice

    # 4) 是否开启 SSL Bump
    read -rp "是否启用 SSL Bump（需要自签证书）？(y/n) " ssl_bump_choice
    if [ "$ssl_bump_choice" == "y" ]; then
        # 调用生成证书的函数
        generate_self_signed_cert
    fi

    # 5) IP 限制
    echo "请选择是否限制允许访问的 IP："
    echo "1. 允许所有 IP 访问（开放代理）"
    echo "2. 仅允许特定 IP 或子网"
    read -rp "请输入选项编号（1 或 2，默认 1）： " ip_choice
    if [ -z "$ip_choice" ]; then
        ip_choice="1"
    fi
    if [ "$ip_choice" == "2" ]; then
        read -rp "请输入允许访问的 IP 或子网（例如 192.168.1.0/24）： " allowed_ip
    fi

    # 6) 用户名密码认证
    read -rp "是否启用代理认证（用户名密码）？(y/n) " auth_choice
    if [ "$auth_choice" == "y" ]; then
        apt install -y apache2-utils
        read -rp "请输入认证的用户名： " auth_user
        htpasswd -c /etc/squid/passwd "$auth_user"
    fi

    # 7) Key 验证
    read -rp "是否启用 Key 验证（自定义请求头）？(y/n) " key_choice
    if [ "$key_choice" == "y" ]; then
        read -rp "请输入请求头名称（默认 X-Auth-Key）： " tmp_header
        if [ -n "$tmp_header" ]; then
            secret_header="$tmp_header"
        fi
        read -rp "请输入秘钥值（默认 mysecretkey）： " tmp_key
        if [ -n "$tmp_key" ]; then
            secret_key="$tmp_key"
        fi
    fi

    # 8) 缓存
    read -rp "是否启用缓存功能？(y/n) " cache_choice
    if [ "$cache_choice" == "y" ]; then
        read -rp "请输入缓存目录（默认 /var/spool/squid）： " tmp_cache_dir
        if [ -n "$tmp_cache_dir" ]; then
            cache_dir="$tmp_cache_dir"
        fi
        read -rp "请输入最大缓存大小 (MB，默认 100)： " tmp_cache_size
        if [ -n "$tmp_cache_size" ]; then
            cache_size="$tmp_cache_size"
        fi
        read -rp "请输入最大缓存对象大小 (MB，默认 1024)： " tmp_obj_size
        if [ -n "$tmp_obj_size" ]; then
            max_obj_size="$tmp_obj_size"
        fi

        read -rp "是否需要自定义 Refresh Pattern（高级缓存刷新规则）？(y/n) " refresh_choice
    fi

    # 9) 时间访问控制
    read -rp "是否启用基于时间的访问限制？(y/n) " time_choice
    if [ "$time_choice" == "y" ]; then
        echo "请输入允许访问的时间段（例如 08:00-18:00）："
        read -rp "时间段（格式 HH:MM-HH:MM）： " time_range
    fi

    # 10) 域名黑/白名单过滤
    read -rp "是否启用域名过滤功能？(y/n) " domain_filter_choice
    if [ "$domain_filter_choice" == "y" ]; then
        echo "请选择过滤类型："
        echo "1. 黑名单（阻止列出的域名）"
        echo "2. 白名单（只允许列出的域名）"
        read -rp "请输入选项编号（1 或 2，默认 1）： " domain_filter_type
        if [ -z "$domain_filter_type" ]; then
            domain_filter_type="1"
        fi
        if [ "$domain_filter_type" == "1" ]; then
            echo "请在 $blocked_domains_file 中维护被阻止域名列表，一行一个。"
            # 示例写入：touch /etc/squid/blocked_domains.txt
            [ ! -f "$blocked_domains_file" ] && touch "$blocked_domains_file"
        else
            echo "请在 $allowed_domains_file 中维护允许域名列表，一行一个。"
            [ ! -f "$allowed_domains_file" ] && touch "$allowed_domains_file"
        fi
    fi

    # 11) 日志模式
    echo "请选择日志记录模式："
    echo "1. 默认记录（记录所有请求）"
    echo "2. 精简日志（仅记录错误和警告）"
    read -rp "请输入选项编号（1 或 2，默认 1）： " tmp_log_choice
    if [ -n "$tmp_log_choice" ]; then
        log_choice="$tmp_log_choice"
    fi
}

#====================================================================#
# 8. 函数：配置透明代理（仅当用户选择时）                             #
#====================================================================#
function configure_transparent_proxy() {
    # 若需要透明代理，需要进行 iptables 转发或通过 ufw 配置
    # 示例：将 80 端口的流量转发到 Squid 端口
    # 同时在 squid.conf 中添加 http_port xxx intercept
    # 这里仅给出一个简易示例，实际需要根据网络环境定制。

    # 假设只针对 IPv4，端口 80 -> $port
    echo "配置透明代理 iptables 规则..."
    # 开启路由转发
    sysctl -w net.ipv4.ip_forward=1

    # 备份 iptables 规则
    iptables-save > /root/iptables.backup

    # DNAT 将 80 端口流量重定向到 Squid
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port "$port"

    echo "透明代理 iptables 配置已执行。"
}

#====================================================================#
# 9. 函数：根据用户交互写入 squid.conf                                #
#====================================================================#
function write_squid_conf() {
    # 如果选择反向代理，则直接写入反向代理配置
    if [ "$proxy_type" == "2" ]; then
        cat > "${SQUID_CONF_PATH}" << EOF
# ---------------------------
# 反向代理配置（Web 加速）
# ---------------------------
http_port ${port} accel vhost allow-direct
cache_peer ${target_domain} parent 80 0 no-query originserver name=myAccel
cache_peer_access myAccel allow all

# 可选：关闭日志（或按需开启）
access_log none
cache_log /dev/null
cache_store_log none
EOF
        echo "反向代理配置已生成，目标域名：${target_domain}，监听端口：${port}"
        return
    fi

    # ========== 以下是正向代理的配置生成 ==========

    local conf="# -------------------------------------\n"
    conf+="# 自动生成的 Squid 配置文件\n"
    conf+="# -------------------------------------\n\n"

    # 1) 端口设置
    # 如果开启 SSL Bump，我们通常需要占用 http_port + https_port 分别
    # 例如 http_port 3128 intercept、https_port 3130 ssl-bump 等
    if [ "$transparent_choice" == "y" ]; then
        # 透明代理端口：intercept
        conf+="http_port ${port} intercept\n"
    else
        conf+="http_port ${port}\n"
    fi

    # SSL Bump 配置
    if [ "$ssl_bump_choice" == "y" ]; then
        # 这里演示新增一个 https_port 3130，如果想复用同一个端口则更复杂
        conf+="https_port 3130 ssl-bump cert=${certificate_path}/${ssl_cert_file} key=${certificate_path}/${ssl_key_file} generate-host-certificates=on dynamic_cert_mem_cache_size=4MB\n"
        conf+="sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid_ssldb -M 4MB\n"
        conf+="\n# SSL Bump 阶段定义\n"
        conf+="acl step1 at_step SslBump1\n"
        conf+="ssl_bump peek step1\n"
        conf+="ssl_bump bump all\n"
    fi

    conf+="\n# 提高匿名性设置\n"
    conf+="via off\n"
    conf+="forwarded_for delete\n"
    conf+="request_header_access X-Forwarded-For deny all\n"
    conf+="request_header_access From deny all\n"
    conf+="request_header_access Referer deny all\n"
    conf+="request_header_access User-Agent allow all\n"
    conf+="request_header_access Cache-Control deny all\n\n"

    # 2) ACL 规则的字符串累加
    local allow_acls=""

    # （a）IP 限制
    if [ "$ip_choice" == "2" ]; then
        conf+="acl allowed_ips src ${allowed_ip}\n"
        allow_acls+=" allowed_ips"
    fi

    # （b）用户名密码认证
    if [ "$auth_choice" == "y" ]; then
        conf+="# 代理认证配置\n"
        conf+="auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd\n"
        conf+="auth_param basic realm Squid Proxy\n"
        conf+="acl authenticated proxy_auth REQUIRED\n"
        allow_acls+=" authenticated"
        conf+="\n"
    fi

    # （c）Key 验证
    if [ "$key_choice" == "y" ]; then
        conf+="# Key 验证\n"
        conf+="acl valid_key req_header ${secret_header} ^${secret_key}\$\n"
        allow_acls+=" valid_key"
        conf+="\n"
    fi

    # （d）基于时间的访问限制
    if [ "$time_choice" == "y" ]; then
        conf+="# 时间段访问限制\n"
        conf+="acl allowed_time time MTWHF ${time_range}\n"
        allow_acls+=" allowed_time"
        conf+="\n"
    fi

    # （e）域名过滤
    if [ "$domain_filter_choice" == "y" ]; then
        if [ "$domain_filter_type" == "1" ]; then
            # 黑名单
            conf+="acl bad_domains dstdomain \"${blocked_domains_file}\"\n"
            # 允许先前所有 ACL，但拒绝 bad_domains
        else
            # 白名单
            conf+="acl good_domains dstdomain \"${allowed_domains_file}\"\n"
        fi
        conf+="\n"
    fi

    # 3) http_access 规则
    conf+="# -----------------------\n"
    conf+="# http_access 规则汇总：\n"
    conf+="# -----------------------\n"
    if [ -z "$allow_acls" ]; then
        # 没有任何 ACL，完全开放
        conf+="acl all src 0.0.0.0/0\n"
        # 如果开启了域名过滤
        if [ "$domain_filter_choice" == "y" ]; then
            if [ "$domain_filter_type" == "1" ]; then
                # 黑名单：允许所有域名访问，但拒绝 bad_domains
                conf+="http_access deny bad_domains\n"
                conf+="http_access allow all\n"
            else
                # 白名单：只允许 good_domains
                conf+="http_access allow good_domains\n"
                conf+="http_access deny all\n"
            fi
        else
            conf+="http_access allow all\n"
        fi
    else
        # 存在一些 ACL
        # 允许满足所有 ACL 的请求
        conf+="http_access allow${allow_acls}\n"
        if [ "$domain_filter_choice" == "y" ]; then
            if [ "$domain_filter_type" == "1" ]; then
                # 黑名单优先拒绝
                conf+="http_access deny bad_domains\n"
                conf+="http_access allow${allow_acls}\n"
                conf+="http_access deny all\n"
            else
                # 白名单
                conf+="http_access allow good_domains\n"
                conf+="http_access deny all\n"
            fi
        else
            # 没有域名过滤时，其余全部拒绝
            conf+="http_access deny all\n"
        fi
    fi

    # 4) 缓存设置
    if [ "$cache_choice" == "y" ]; then
        conf+="\n# 缓存配置\n"
        conf+="cache_dir ufs ${cache_dir} ${cache_size} 16 256\n"
        conf+="cache_mem 256 MB\n"
        conf+="maximum_object_size ${max_obj_size} MB\n"
        if [ "$refresh_choice" == "y" ]; then
            conf+="# 自定义刷新规则示例\n"
            conf+="refresh_pattern ^ftp:           1440    20%     10080\n"
            conf+="refresh_pattern ^gopher:        1440    0%      1440\n"
            conf+="refresh_pattern -i (/cgi-bin/|\\?) 0     0%      0\n"
            conf+="refresh_pattern .               30      20%     4320\n"
        else
            conf+="# 默认刷新规则\n"
            conf+="refresh_pattern . 0 20% 4320\n"
        fi
        conf+="\n"
    fi

    # 5) 日志模式
    if [ "$log_choice" == "2" ]; then
        conf+="# 精简日志\n"
        conf+="access_log none\n"
        conf+="cache_log /dev/null\n"
        conf+="cache_store_log none\n"
    else
        # 默认日志：保留 access.log、cache.log
        conf+="\n# 默认日志模式\n"
        conf+="access_log /var/log/squid/access.log\n"
        conf+="cache_log /var/log/squid/cache.log\n"
    fi

    # 6) 最终写入
    echo -e "$conf" > "${SQUID_CONF_PATH}"

    echo "生成的 Squid 配置文件："
    echo "-----------------------------------------------------"
    echo -e "$conf"
    echo "-----------------------------------------------------"
}

#====================================================================#
# 10. 函数：重启并设置开机自启                                       #
#====================================================================#
function restart_squid() {
    echo "重启 Squid 服务..."
    systemctl restart squid
    if systemctl is-active --quiet squid; then
        echo "Squid 服务启动成功。"
    else
        echo "Squid 服务启动失败，请检查日志信息！"
        exit 1
    fi

    echo "设置 Squid 开机自启..."
    systemctl enable squid
}

#====================================================================#
# 11. 函数：配置防火墙规则                                           #
#====================================================================#
function config_firewall() {
    echo "配置防火墙，允许 ${port} 端口..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${port}/tcp"
        ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --reload
    else
        echo "未检测到常见防火墙工具，请手动开放 ${port} 端口。"
    fi

    # 若启用了 SSL Bump，默认开放 3130
    if [ "$ssl_bump_choice" == "y" ]; then
        if command -v ufw >/dev/null 2>&1; then
            ufw allow 3130/tcp
            ufw reload
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=3130/tcp
            firewall-cmd --reload
        else
            echo "请手动开放 3130 端口（用于 SSL Bump）。"
        fi
    fi
}

#====================================================================#
# 12. 函数：设置日志自动轮转示例（logrotate）                          #
#====================================================================#
function setup_logrotate() {
    # 仅示例如何写入一个 logrotate 配置来定期处理 /var/log/squid/*.log
    # 实际需要可根据自己需求修改周期、压缩、保留时长等
    cat > /etc/logrotate.d/squid << EOF
/var/log/squid/*.log {
    daily
    rotate 7
    compress
    missingok
    delaycompress
    notifempty
    create 640 proxy proxy
    sharedscripts
    postrotate
        systemctl reload squid > /dev/null 2>&1 || true
    endscript
}
EOF
    echo "logrotate 日志轮转已配置，可在 /etc/logrotate.d/squid 中查看或修改。"
}

#====================================================================#
# 入口函数：main                                                     #
#====================================================================#
function main() {
    # 所有输出同时写入日志文件
    exec > >(tee -a "$LOG_FILE") 2>&1

    check_root
    parse_arguments "$@"

    # 如果是卸载操作
    if [ "$UNINSTALL" == "true" ]; then
        uninstall_squid
        exit 0
    fi

    echo "开始部署 Squid 代理服务器..."
    install_squid
    backup_squid_config
    configure_squid
    if [ "$transparent_choice" == "y" ] && [ "$proxy_type" == "1" ]; then
        # 正向代理且选择透明代理
        configure_transparent_proxy
    fi
    write_squid_conf
    restart_squid
    config_firewall
    setup_logrotate

    # 自动检测公网 IP 和内网 IP
    public_ip=$(curl -s ifconfig.me)
    internal_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo "==============================================="
    echo "      Squid 代理服务器部署完成！"
    echo "==============================================="
    echo "服务器公网 IP: ${public_ip}"
    echo "服务器内网 IP: ${internal_ip}"
    echo "监听端口: ${port}"
    if [ "$ssl_bump_choice" == "y" ]; then
        echo "SSL Bump 端口: 3130"
        echo "你需要将生成的根证书安装到客户端受信任列表才能正常解密 HTTPS 流量。"
        echo "证书路径: ${certificate_path}/${ssl_cert_file}"
    fi
    echo "可测试访问命令示例："
    echo "  curl -x http://${public_ip}:${port} http://www.google.com -v"
    echo "或者使用内网 IP："
    echo "  curl -x http://${internal_ip}:${port} http://www.google.com -v"

    # 提示透明代理如何测试
    if [ "$transparent_choice" == "y" ]; then
        echo "已配置透明代理，请在网关或路由层使用 iptables/路由转发来拦截 80/443 流量。"
        echo "本脚本仅示例了将 80 端口流量重定向到 Squid（${port}），请自行根据环境二次调整。"
    fi

    # 提示反向代理如何测试
    if [ "$proxy_type" == "2" ]; then
        echo "已配置反向代理，目标域名: ${target_domain}"
        echo "请将 DNS 或上游流量指向当前服务器，对外提供加速/缓存服务。"
    fi

    echo "==============================================="
    echo "如需卸载请执行:  $0 uninstall"
}

#====================================================================#
# 调用入口函数
#====================================================================#
main "$@"
