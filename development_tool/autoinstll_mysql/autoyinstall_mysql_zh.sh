#!/bin/bash

# MySQL安装脚本（支持Ubuntu/Debian/CentOS/RHEL/Fedora/openSUSE）
# 需要 root 权限执行

# 生成随机 root 密码（可选）
generate_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# 让用户输入或随机生成 MySQL root 密码
read -rp "请输入 MySQL root 密码（留空自动生成）: " MYSQL_ROOT_PASSWORD
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-$(generate_password)}

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "错误：必须使用 root 用户运行此脚本。"
    exit 1
fi

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法检测操作系统类型！"
    exit 1
fi

# 让用户选择 MySQL 版本
read -rp "请输入要安装的 MySQL 版本（默认: 8.0）: " MYSQL_VERSION
MYSQL_VERSION=${MYSQL_VERSION:-"8.0"}

# 安装 MySQL
install_mysql() {
    case $OS in
        ubuntu|debian)
            echo "检测到 Ubuntu/Debian，开始安装 MySQL $MYSQL_VERSION..."

            # 更新包索引并安装依赖
            apt-get update
            apt-get install -y wget gnupg lsb-release

            # 添加 MySQL APT 源
            wget -qO- https://repo.mysql.com/mysql-apt-config_0.8.28-1_all.deb -O /tmp/mysql-apt-config.deb
            dpkg -i /tmp/mysql-apt-config.deb
            apt-get update

            # 安装 MySQL
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y mysql-server

            # 启动 MySQL 服务
            systemctl start mysql
            systemctl enable mysql
            ;;

        centos|rhel|fedora)
            echo "检测到 CentOS/RHEL/Fedora，开始安装 MySQL $MYSQL_VERSION..."

            # 添加 MySQL Yum 源
            rpm -Uvh https://dev.mysql.com/get/mysql80-community-release-el7-6.noarch.rpm

            # 安装 MySQL
            yum install -y mysql-community-server

            # 启动 MySQL 服务
            systemctl start mysqld
            systemctl enable mysqld
            ;;

        opensuse*)
            echo "检测到 openSUSE，开始安装 MySQL $MYSQL_VERSION..."
            zypper install -y mysql-community-server
            systemctl start mysql
            systemctl enable mysql
            ;;

        *)
            echo "不支持的 Linux 发行版：$OS"
            exit 1
            ;;
    esac
}

# 执行 MySQL 安全配置
secure_installation() {
    echo "正在执行 MySQL 安全配置..."

    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF
}

# 配置防火墙
configure_firewall() {
    echo "配置防火墙..."

    if command -v ufw >/dev/null 2>&1; then
        ufw allow 3306/tcp
        ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=3306/tcp
        firewall-cmd --reload
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport 3306 -j ACCEPT
        iptables-save > /etc/iptables.rules
    else
        echo "警告：未找到支持的防火墙工具，跳过端口配置。"
    fi
}

# 优化 MySQL 配置
optimize_mysql() {
    echo "优化 MySQL 配置..."

    cat <<EOF >> /etc/mysql/mysql.conf.d/mysqld.cnf
[mysqld]
max_connections = 200
bind-address = 0.0.0.0
EOF

    systemctl restart mysql
}

# 验证安装
verify_installation() {
    echo "验证安装..."

    if mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION();" >/dev/null 2>&1; then
        echo "MySQL 安装成功！"
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT VERSION();"
    else
        echo "错误：MySQL 安装失败！"
        exit 1
    fi
}

# 主执行流程
main() {
    install_mysql
    secure_installation
    configure_firewall
    optimize_mysql
    verify_installation

    echo "================================"
    echo "MySQL 安装完成！"
    echo "Root 密码: $MYSQL_ROOT_PASSWORD"
    echo "连接命令: mysql -u root -p"
    echo "================================"
}

# 执行主函数
main
