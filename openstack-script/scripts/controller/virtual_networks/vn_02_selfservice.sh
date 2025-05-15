#!/bin/bash

# 加载配置文件
source config.ini

# 创建自服务网络、子网和路由器，并连接到提供者网络
create_selfservice_network_with_router() {

    # 加载 OpenStack 管理员凭据
    source /root/admin-openrc

    echo "${YELLOW}正在创建自服务网络...${RESET}"
    openstack network create selfservice
    echo "${GREEN}自服务网络创建成功。${RESET}"

    echo "${YELLOW}正在为自服务网络创建子网...${RESET}"
    openstack subnet create --network selfservice \
        --dns-nameserver $OS_MANAGEMENT_DNS \
        --gateway $OS_MANAGEMENT_GATEWAY \
        --subnet-range $OS_MANAGEMENT_SUBNET selfservice
    echo "${GREEN}自服务子网创建成功。${RESET}"

    echo "${YELLOW}正在创建路由器...${RESET}"
    openstack router create router
    echo "${GREEN}路由器创建成功。${RESET}"

    echo "${YELLOW}正在将自服务子网添加到路由器接口...${RESET}"
    openstack router add subnet router selfservice
    echo "${GREEN}自服务子网已成功添加到路由器。${RESET}"

    echo "${YELLOW}正在设置提供者网络为路由器网关...${RESET}"
    openstack router set router --external-gateway provider
    echo "${GREEN}提供者网络已设置为路由器网关。${RESET}"

    # 显示网络命名空间和路由器端口信息
    ip netns
    openstack port list --router router

    echo "${GREEN}自服务网络及路由器配置完成。${RESET}"
}