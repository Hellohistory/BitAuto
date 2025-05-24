#!/bin/bash
set -e

echo "🔧 安装虚拟显示器驱动..."
apt update
apt install -y xserver-xorg-video-dummy

echo "🔍 自动识别 HDMI 接口..."
HDMI_INTERFACE=$(find /sys/class/drm/ -name "card0-*-*/status" -exec basename {} \; 2>/dev/null | grep -i hdmi | head -n1 | cut -d'-' -f2-)
if [ -z "$HDMI_INTERFACE" ]; then
    echo "❌ 没有发现 HDMI 接口，尝试使用默认 HDMI-A-1"
    HDMI_INTERFACE="HDMI-A-1"
else
    echo "✅ 已识别接口：$HDMI_INTERFACE"
fi

echo "📄 创建虚拟显示器配置..."
mkdir -p /etc/X11/xorg.conf.d
DUMMY_CONF="/etc/X11/xorg.conf.d/10-dummy.conf"

cat > "$DUMMY_CONF" <<EOF
Section "Monitor"
    Identifier  "VirtualMonitor"
    HorizSync   30.0-62.0
    VertRefresh 50.0-70.0
    Modeline "1920x1080" 172.80 1920 2040 2248 2576 1080 1081 1084 1118
EndSection

Section "Device"
    Identifier  "VirtualCard"
    Driver      "dummy"
    VideoRam    256000
EndSection

Section "Screen"
    Identifier  "VirtualScreen"
    Device      "VirtualCard"
    Monitor     "VirtualMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth   24
        Modes   "1920x1080"
    EndSubSection
EndSection
EOF

echo "✅ 虚拟显示配置写入完毕"

echo "⚙️ 创建检测脚本..."
cat > /usr/local/bin/hotplug-monitor.sh <<EOF
#!/bin/bash

LOG="/var/log/hotplug-monitor.log"
HDMI_INTERFACE="$HDMI_INTERFACE"
DUMMY_CONF="/etc/X11/xorg.conf.d/10-dummy.conf"
DUMMY_CONF_BAK="/etc/X11/xorg.conf.d/10-dummy.conf.bak"
STATUS_FILE="/sys/class/drm/card0-\${HDMI_INTERFACE}/status"

echo "[\$(date)] 正在检测接口状态：\$HDMI_INTERFACE" >> \$LOG

if [ -f "\$STATUS_FILE" ]; then
    HDMI_STATUS=\$(cat "\$STATUS_FILE")
    if [ "\$HDMI_STATUS" = "connected" ]; then
        if [ -f "\$DUMMY_CONF" ]; then
            mv "\$DUMMY_CONF" "\$DUMMY_CONF_BAK"
            echo "[\$(date)] 检测到物理显示器，禁用虚拟显示" >> \$LOG
        fi
    else
        if [ -f "\$DUMMY_CONF_BAK" ]; then
            mv "\$DUMMY_CONF_BAK" "\$DUMMY_CONF"
            echo "[\$(date)] 未检测到物理显示器，启用虚拟显示" >> \$LOG
        fi
    fi
else
    echo "[\$(date)] 警告：接口 \$STATUS_FILE 不存在，无法判断显示器状态" >> \$LOG
fi
EOF

chmod +x /usr/local/bin/hotplug-monitor.sh

echo "🔧 注册 systemd 服务..."
cat > /etc/systemd/system/hotplug-monitor.service <<EOF
[Unit]
Description=自动检测 HDMI 热插拔并切换虚拟显示器
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hotplug-monitor.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hotplug-monitor.service

echo "📡 注册 udev 规则监听热插拔..."
cat > /etc/udev/rules.d/85-hotplug-monitor.rules <<EOF
ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card0", RUN+="/bin/systemctl start hotplug-monitor.service"
EOF

udevadm control --reload
udevadm trigger

echo "🚀 执行首次检测..."
bash /usr/local/bin/hotplug-monitor.sh

echo "🎉 [完成] 全自动虚拟显示配置已部署！现在支持开机自动检测、显示器热插拔自动切换，无需手动操作！"
