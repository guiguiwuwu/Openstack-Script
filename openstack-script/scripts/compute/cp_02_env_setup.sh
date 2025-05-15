#!/bin/bash

# 加载配置文件
source config.ini

# 更新并升级系统，替换为阿里源
system_update_upgrade() {
    echo -e "${YELLOW}正在备份并替换为阿里源...${RESET}"
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo bash -c 'cat > /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs) main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-backports main restricted universe multiverse
EOF'
    echo -e "${YELLOW}正在更新和升级系统...${RESET}"
    sudo apt-get update -y && sudo apt-get upgrade -y
    echo -e "${GREEN}系统更新和升级完成。${RESET}"
}
# 禁用swap
disable_swap() {
    echo -e "${YELLOW}正在禁用swap...${RESET}"
    sudo swapoff -a
    sudo sed -i '/swap/s/^/#/' /etc/fstab
    echo -e "${GREEN}swap已禁用。${RESET}"
}

# 添加 OpenStack 仓库
add_openstack_repo() {
    echo -e "${YELLOW}正在添加 OpenStack Caracal 仓库...${RESET}"
    sudo add-apt-repository cloud-archive:caracal -y
    echo -e "${GREEN}仓库添加成功。${RESET}"
}

# 安装 crudini 工具
install_crudini_tool() {
    echo -e "${YELLOW}正在安装 crudini...${RESET}"
    sudo apt install -y crudini
    echo -e "${GREEN}crudini 安装成功。${RESET}"
}

# 安装 OpenStack 客户端
install_openstack_client() {
    echo -e "${YELLOW}正在安装 OpenStack 客户端...${RESET}"
    sudo apt-get install -y python3-openstackclient
    echo -e "${GREEN}OpenStack 客户端安装成功。${RESET}"
}

# 安装并配置Chrony NTP服务
setup_chrony_ntp() {
    echo -e "${YELLOW}正在安装并配置Chrony...${RESET}"
    sudo apt install -y chrony
    local chrony_conf="/etc/chrony/chrony.conf"

    # 删除所有原有的NTP服务器配置（server、pool、peer等）
    sudo sed -i '/^\s*\(server\|pool\|peer\)\s\+/d' $chrony_conf

    # 添加控制节点NTP服务器
    echo "server $CTL_MANAGEMENT iburst" | sudo tee -a $chrony_conf
    sudo systemctl restart chrony
    echo -e "${GREEN}Chrony配置完成。${RESET}"
}


# 按顺序执行各函数
system_update_upgrade
disable_swap
add_openstack_repo
install_crudini_tool
install_openstack_client
setup_chrony_ntp

echo -e "${GREEN}所有组件已安装并配置完成。${RESET}"
