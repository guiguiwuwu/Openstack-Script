#!/bin/bash

# 加载配置文件
source config.ini

# 创建Provider网络及其子网的函数
create_provider_network_and_subnet_custom() {
  # 加载OpenStack管理员凭据
  source /root/admin-openrc

  echo "${YELLOW}正在创建Provider网络...${RESET}"
  openstack network create --share --external \
    --provider-physical-network provider \
    --provider-network-type flat provider
  echo "${GREEN}Provider网络创建成功。${RESET}"

  echo "${YELLOW}正在为Provider网络创建子网...${RESET}"
  openstack subnet create --network provider \
    --allocation-pool start=$OS_PROVIDER_IP_START,end=$OS_PROVIDER_IP_END \
    --dns-nameserver $OS_PROVIDER_DNS \
    --gateway $OS_PROVIDER_GATEWAY \
    --subnet-range $OS_PROVIDER_SUBNET provider

  echo "${GREEN}Provider子网创建成功。${RESET}"
}

