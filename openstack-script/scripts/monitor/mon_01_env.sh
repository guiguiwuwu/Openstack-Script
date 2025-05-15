#!/bin/bash

# 从配置文件 config.ini 加载配置
source config.ini

# 设置阿里云APT源
set_aliyun_apt_source() {
    echo "${YELLOW}正在设置阿里云APT源...${RESET}"
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo tee /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs) main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-backports main restricted universe multiverse
EOF
    sudo apt-get update -y
    echo "${GREEN}阿里云APT源设置完成。${RESET}"
}

# 更新和升级系统
update_and_upgrade_system() {
    echo "${YELLOW}正在更新和升级系统...${RESET}"
    apt-get update -y && apt-get upgrade -y
    echo "${GREEN}系统更新和升级完成。${RESET}"
}

# 添加 OpenStack 仓库
add_openstack_repository() {
    echo "${YELLOW}正在添加 OpenStack Caracal 仓库...${RESET}"
    sudo add-apt-repository cloud-archive:caracal -y
    echo "${GREEN}OpenStack 仓库添加成功。${RESET}"
}

# 安装 crudini 工具
install_crudini_tool() {
    echo "${YELLOW}正在安装 crudini 工具...${RESET}"
    sudo apt install -y crudini
    echo "${GREEN}crudini 工具安装成功。${RESET}"
}

# 安装 OpenStack 客户端
install_openstack_client() {
    echo "${YELLOW}正在安装 OpenStack 客户端...${RESET}"
    sudo apt-get install python3-openstackclient -y
    echo "${GREEN}OpenStack 客户端安装成功。${RESET}"
}

# 安装并配置 Chrony NTP 服务
install_and_configure_chrony() {
    echo -e "${YELLOW}正在安装并配置 Chrony NTP 服务...${RESET}"
    sudo apt install -y chrony
    local chrony_conf="/etc/chrony/chrony.conf"

    # 删除所有原有的 NTP 服务器配置（server、pool、peer 等）
    sudo sed -i '/^\s*\(server\|pool\|peer\)\s\+/d' $chrony_conf

    # 添加控制节点的 NTP 服务器
    echo "server $CTL_MANAGEMENT iburst" | sudo tee -a $chrony_conf
    sudo systemctl restart chrony
    echo -e "${GREEN}Chrony NTP 服务配置完成。${RESET}"
}

# 安装 jq 工具
install_jq_tool() {
    echo -e "${YELLOW}正在安装 jq 工具...${RESET}"
    sudo apt install -y jq
    echo -e "${GREEN}jq 工具安装成功。${RESET}"
}

# 按顺序运行所有函数
set_aliyun_apt_source
update_and_upgrade_system
add_openstack_repository
install_jq_tool
install_crudini_tool
install_openstack_client
install_and_configure_chrony

echo "${GREEN}所有组件已安装并配置完成。${RESET}"
