#!/bin/bash

# 加载配置文件
source config.ini

# 加载虚拟网络脚本
source controller/virtual_networks/vn_01_provider.sh
source controller/virtual_networks/vn_02_selfservice.sh

# 创建云主机规格（flavor）
create_instance_flavors() {
    source /root/admin-openrc

    echo "${YELLOW}正在创建云主机规格...${RESET}"
    openstack flavor create --id 2 --vcpus 1 --ram 192 --disk 1 m1.nano
    openstack flavor create --id 4 --vcpus 1 --ram 256 --disk 1 m1.micro
    openstack flavor create --id 6 --vcpus 1 --ram 512 --disk 1 m1.tiny
    openstack flavor create --id 8 --vcpus 1 --ram 512 --disk 5 ds512m
    openstack flavor create --id 10 --vcpus 1 --ram 1024 --disk 10 ds1G
    openstack flavor create --id 12 --vcpus 1 --ram 2048 --disk 10 ds2G
    openstack flavor create --id 14 --vcpus 1 --ram 2048 --disk 20 m1.small
    openstack flavor create --id 16 --vcpus 2 --ram 4096 --disk 20 ds4G
    openstack flavor create --id 18 --vcpus 2 --ram 4096 --disk 40 m1.medium
    openstack flavor create --id 20 --vcpus 2 --ram 8192 --disk 80 m1.large
    openstack flavor create --id 22 --vcpus 2 --ram 16384 --disk 160 m1.xlarge
    echo "${GREEN}云主机规格创建完成。${RESET}"
}

# 生成并导入SSH密钥对
generate_and_import_ssh_key() {
    source /root/admin-openrc

    echo "${YELLOW}正在生成SSH密钥对...${RESET}"
    
    # 检查本地是否已有密钥，没有则生成
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        ssh-keygen -q -N ""
    fi

    # 导入公钥到OpenStack
    openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey

    openstack keypair list
    echo "${GREEN}SSH密钥对已生成并导入OpenStack。${RESET}"
}

# 添加安全组规则
add_default_security_rules() {
    source /root/admin-openrc

    echo "${YELLOW}正在添加安全组规则...${RESET}"

    # 允许ICMP（ping）
    openstack security group rule create --proto icmp default
    echo "${GREEN}已添加ICMP规则到默认安全组。${RESET}"

    # 允许SSH访问
    openstack security group rule create --proto tcp --dst-port 22 default
    echo "${GREEN}已添加SSH规则到默认安全组。${RESET}"
}

# 执行所有操作

create_provider_network_and_subnet_custom    # 创建 Provider 网络和子网
create_selfservice_network_with_router       # 创建自服务网络
create_instance_flavors                      # 创建云主机规格
generate_and_import_ssh_key                  # 生成并导入 SSH 密钥对
add_default_security_rules                   # 添加安全组规则

echo "${GREEN}环境初始化完成。${RESET}"
