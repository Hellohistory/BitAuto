#!/bin/bash

# Titan 部署脚本
IDENTITY_CODE="87FD8C76-B4EB-479A-86DD-0B93E8BB7B7A"

# 如果之前运行过 Titan 节点，则清理数据
if [ -d "$HOME/.titan-node" ]; then
    echo "检测到之前的 Titan 节点数据，正在清理..."
    rm -rf "$HOME/.titan-node"
    echo "清理完成。"
else
    echo "没有检测到之前的 Titan 节点数据，跳过清理步骤。"
fi

# 下载 Titan CLI 节点文件
echo "正在下载 Titan CLI 节点文件..."
curl -LO https://github.com/Titannet-dao/titan-node/releases/download/v0.1.20/titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz

# 解压下载的文件
echo "正在解压文件..."
tar -zxvf titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz

# 进入解压后的目录
cd titan-edge_v0.1.20_246b9dd_linux-amd64

# 安装 Titan Edge 可执行文件
echo "正在安装 Titan Edge..."
sudo cp titan-edge /usr/local/bin

# 安装库文件
echo "正在安装库文件..."
sudo cp libgoworkerd.so /usr/local/lib

# 更新库缓存
echo "正在更新库缓存..."
sudo ldconfig

# 启动 Titan 节点
echo "正在启动 Titan 节点..."
titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0 &

# 等待节点启动完成
sleep 5

# 绑定身份码
echo "正在绑定身份码..."
titan-edge bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding

echo "Titan 节点已成功部署和启动。"
