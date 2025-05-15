#!/bin/bash

# 加载配置文件
source config.ini

# 函数：安装 LVM 和相关工具
install_lvm_dependencies() {
    echo "${YELLOW}正在安装 LVM 和相关工具...${RESET}"
    sudo apt install -y lvm2 thin-provisioning-tools
    echo "${GREEN}LVM 和相关工具安装成功。${RESET}"
}

# 函数：配置 LVM 物理卷和卷组
setup_lvm() {
    echo "${YELLOW}正在配置 LVM 用于块存储...${RESET}"
    
    # 创建物理卷
    sudo pvcreate /dev/sdb
    
    # 创建卷组
    sudo vgcreate cinder-volumes /dev/sdb

    # 更新 LVM 配置，仅扫描特定设备
    local lvm_conf="/etc/lvm/lvm.conf"
    sudo sed -i '/^ *filter =/d' $lvm_conf
    sudo sed -i '/^devices {/a\    filter = [ "a/sda/", "a/sdb/", "r/.*/"]' $lvm_conf

    echo "${GREEN}LVM 配置完成，已创建物理卷和卷组。${RESET}"
}

# 函数：安装并配置 Cinder 组件
install_and_configure_cinder() {
    echo "${YELLOW}正在安装并配置 Cinder 组件...${RESET}"
    
    # 安装所需软件包
    sudo apt install -y cinder-volume tgt

    # 配置 /etc/cinder/cinder.conf
    local cinder_conf="/etc/cinder/cinder.conf"
    local cinder_conf_bak="/etc/cinder/cinder.conf.bak"
    cp $cinder_conf $cinder_conf_bak
    egrep -v "^#|^$" $cinder_conf_bak > $cinder_conf

    # 配置数据库连接
    crudini --set "$cinder_conf" "database" "connection" "mysql+pymysql://cinder:$CINDER_DBPASS@controller/cinder"

    # 配置默认选项
    crudini --set "$cinder_conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller"
    crudini --set "$cinder_conf" "DEFAULT" "auth_strategy" "keystone"
    crudini --set "$cinder_conf" "DEFAULT" "my_ip" "$BLK_MANAGEMENT"
    crudini --set "$cinder_conf" "DEFAULT" "enabled_backends" "lvm"
    crudini --set "$cinder_conf" "DEFAULT" "glance_api_servers" "http://controller:9292"

    # 配置 Keystone 身份验证
    crudini --set "$cinder_conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000"
    crudini --set "$cinder_conf" "keystone_authtoken" "auth_url" "http://controller:5000"
    crudini --set "$cinder_conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$cinder_conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$cinder_conf" "keystone_authtoken" "project_domain_name" "default"
    crudini --set "$cinder_conf" "keystone_authtoken" "user_domain_name" "default"
    crudini --set "$cinder_conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$cinder_conf" "keystone_authtoken" "username" "cinder"
    crudini --set "$cinder_conf" "keystone_authtoken" "password" "$CINDER_PASS"

    # 配置 LVM 后端
    crudini --set "$cinder_conf" "lvm" "volume_driver" "cinder.volume.drivers.lvm.LVMVolumeDriver"
    crudini --set "$cinder_conf" "lvm" "volume_group" "cinder-volumes"
    crudini --set "$cinder_conf" "lvm" "target_protocol" "iscsi"
    crudini --set "$cinder_conf" "lvm" "target_helper" "tgtadm"

    # 配置并发锁路径
    crudini --set "$cinder_conf" "oslo_concurrency" "lock_path" "/var/lib/cinder/tmp"

    echo "${GREEN}Cinder 配置已更新。${RESET}"
}

# 函数：配置 tgt 服务以支持 Cinder 卷
configure_tgt_service() {
    echo "${YELLOW}正在配置 tgt 服务以支持 Cinder 卷...${RESET}"
    
    # 创建 tgt 配置文件
    echo 'include /var/lib/cinder/volumes/*' | sudo tee /etc/tgt/conf.d/cinder.conf > /dev/null

    echo "${GREEN}tgt 服务配置成功。${RESET}"
}

# 函数：重启服务以完成安装
restart_services() {
    echo "${YELLOW}正在重启服务以完成块存储安装...${RESET}"

    # 重启 tgt 和 Cinder 卷服务
    sudo service tgt restart
    sudo service cinder-volume restart

    echo "${GREEN}块存储服务重启成功。${RESET}"
}

# 按顺序执行各个函数
install_lvm_dependencies
setup_lvm
install_and_configure_cinder
configure_tgt_service
restart_services

echo "${GREEN}OpenStack 块存储（Cinder）在存储节点上的安装和配置已完成。${RESET}"
