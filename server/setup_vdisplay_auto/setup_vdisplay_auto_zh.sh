#!/bin/bash
set -e

echo "🔧 安装依赖..."
apt update
apt install -y xserver-xorg-video-dummy

echo "📄 创建虚拟显示器配置目录..."
mkdir -p /etc/X11/xorg.conf.d

DUMMY_CONF="/etc/X11/xorg.conf.d/10-dummy.conf"
DUMMY_CONF_CONTENT=$(cat <<EOF
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
)

if [ ! -f "$DUMMY_CONF" ]; then
    echo "$DUMMY_CONF_CONTENT" > "$DUMMY_CONF"
    echo "✅ 创建虚拟显示配置成功"
fi

echo "⚙️ 创建检测脚本..."
cat > /usr/local/bin/hotplug-monitor.sh <<'EOF'
#!/bin/bash
HDMI_INTERFACE="HDMI-A-1"
DUMMY_CONF="/etc/X11/xorg.conf.d/10-dummy.conf"
DUMMY_CONF_BAK="/etc/X11/xorg.conf.d/10-dummy.conf.bak"

if [ -f "/sys/class/drm/card0-${HDMI_INTERFACE}/status" ]; then
    HDMI_STATUS=$(cat /sys/class/drm/card0-${HDMI_INTERFACE}/status)
    if [ "$HDMI_STATUS" = "connected" ]; then
        [ -f "$DUMMY_CONF" ] && mv "$DUMMY_CONF" "$DUMMY_CONF_BAK"
        echo "✅ 检测到显示器，使用物理显示输出"
    else
        [ -f "$DUMMY_CONF_BAK" ] && mv "$DUMMY_CONF_BAK" "$DUMMY_CONF"
        echo "✅ 未检测到显示器，启用虚拟显示器"
    fi
else
    echo "⚠️ 未发现接口 /sys/class/drm/card0-${HDMI_INTERFACE}/status"
fi
EOF

chmod +x /usr/local/bin/hotplug-monitor.sh

echo "🛠️ 创建 systemd 服务..."
cat > /etc/systemd/system/hotplug-monitor.service <<EOF
[Unit]
Description=自动检测显示器热插拔并切换虚拟显示器
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hotplug-monitor.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hotplug-monitor.service

echo "🔌 创建 udev 规则..."
cat > /etc/udev/rules.d/85-hotplug-monitor.rules <<EOF
ACTION=="change", SUBSYSTEM=="drm", KERNEL=="card0", RUN+="/bin/systemctl start hotplug-monitor.service"
EOF

udevadm control --reload
udevadm trigger

echo "🚀 执行一次检测..."
bash /usr/local/bin/hotplug-monitor.sh

echo "🎉 安装完成！系统将自动检测是否连接显示器，并切换虚拟显示配置。"
