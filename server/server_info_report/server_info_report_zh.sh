#!/bin/bash

# —— 颜色定义（用 $'…' 保证实际 ANSI 控制码） ——
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'  # 无色

# 获取当前日期和主机名
current_date=$(date "+%Y年%m月%d日 %A %H:%M:%S")
hostname=$(hostname)

#######################################
# 输出标题信息
#######################################
print_header() {
    echo -e "==================== 服务器硬件信息报告 ===================="
    echo -e "日期: ${current_date}"
    echo -e "主机名: ${hostname}"
    echo -e "============================================================"
    echo ""
}

#######################################
# 执行 dmidecode 并过滤指定类型
# Globals:
#   None
# Arguments:
#   $1 - dmidecode 类型 (如 1, processor, memory)
#   $2 - grep 过滤模式
#######################################
dmidecode_filter() {
    local type="$1"
    local pattern="$2"
    sudo dmidecode -t "${type}" | grep -E "${pattern}"
}

#######################################
# 获取并打印主板信息
#######################################
get_pm_info() {
    echo -e "${RED}主板信息:${NC}"
    dmidecode_filter 1 "Manufacturer|Product Name|Serial Number"
    echo ""
}

#######################################
# 获取并打印 CPU 信息
#######################################
get_cpu_info() {
    echo -e "${RED}CPU 信息:${NC}"
    dmidecode_filter processor "Socket|Core Count|Version"
    echo ""
}

#######################################
# 获取并打印内存信息
#######################################
get_mem_info() {
    echo -e "${RED}内存信息:${NC}"
    local total_slots
    total_slots=$(dmidecode_filter memory "Number Of Devices" | awk '{print $NF}')
    echo "  内存槽位总数: ${total_slots}"

    echo "  已安装的内存模块:"
    local installed_count=0
    while read -r locator; do
        read -r size_line
        local slot size
        slot=$(echo "${locator}" | awk -F': ' '{print $2}')
        size=$(echo "${size_line}" | awk '{print $2}')
        if [[ "${size}" != "No" && "${size}" != "Unknown" ]]; then
            ((installed_count++))
            echo "    ${slot}: ${size} GB"
        fi
    done < <(sudo dmidecode -t memory | grep -E "Locator:|Size:")

    echo "  已安装内存模块数量: ${installed_count}"
    local total_mem
    total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    echo "  内存总容量: ${total_mem}"
    echo ""
}

#######################################
# 获取并打印磁盘信息
#######################################
get_disk_info() {
    echo -e "${RED}磁盘信息:${NC}"
    lsblk -d -o NAME,TYPE,SIZE | grep -v loop
    echo ""
}

#######################################
# 获取并打印 GPU 信息（含 CUDA 版本）
#######################################
get_gpu_info() {
    echo -e "${RED}GPU 信息:${NC}"
    if command -v nvidia-smi &> /dev/null; then
        # 列出所有 GPU
        nvidia-smi -L
        # 提取 CUDA 版本
        cuda_ver=$(nvidia-smi | grep -oP 'CUDA Version: \K[0-9.]+')
        echo "  CUDA Version (nvidia-smi): ${cuda_ver:-未知}"
    else
        echo "  未检测到 NVIDIA GPU 或 nvidia-smi 不可用"
    fi
    # 如果安装了 nvcc，也显示编译工具版本
    if command -v nvcc &> /dev/null; then
        nvcc_ver=$(nvcc --version | grep "release" | awk '{print $6}' | sed 's/,//')
        echo "  NVCC Compiler Version: ${nvcc_ver}"
    fi
    # 使用 lspci 作为补充
    echo "  其他 GPU 设备（lspci）:"
    lspci | grep -i --color 'vga\|3d\|2d'
    echo ""
}

#######################################
# 打印网络详情表格
#######################################
print_network_table() {
    local ifaces ip4 ip6 mac speed
    ifaces=$(ls /sys/class/net)

    printf "\n${RED}网络接口详细信息:${NC}\n"
    printf "%-10s %-15s %-20s %-18s %-8s\n" "接口" "IPv4 地址" "IPv6 地址" "MAC 地址" "速率"
    printf "%-10s %-15s %-20s %-18s %-8s\n" "----------" "---------------" "--------------------" "------------------" "--------"

    for iface in ${ifaces}; do
        ip4=$(ip -4 addr show dev "${iface}" | awk '/inet /{print $2}' | cut -d/ -f1)
        [[ -z "${ip4}" ]] && ip4="—"
        ip6=$(ip -6 addr show dev "${iface}" scope global \
              | awk '/inet6 /{print $2}' | cut -d/ -f1 | head -n1)
        [[ -z "${ip6}" ]] && ip6="—"
        mac=$(< /sys/class/net/"${iface}"/address)
        speed=$(ethtool "${iface}" 2>/dev/null | awk -F': ' '/Speed:/{print $2}')
        [[ -z "${speed}" ]] && speed="—"

        printf "%-10s %-15s %-20s %-18s %-8s\n" \
            "${GREEN}${iface}${NC}" "${ip4}" "${ip6}" "${mac}" "${speed}"
    done
    echo ""
}

#######################################
# 脚本入口
#######################################
main() {
    print_header
    get_pm_info
    get_cpu_info
    get_mem_info
    get_disk_info
    get_gpu_info
    print_network_table
}

# 执行主流程，并将输出保存到 /tmp 下的带时间戳文件中
main | tee "/tmp/server_info_$(date +%F_%H-%M-%S).txt"
