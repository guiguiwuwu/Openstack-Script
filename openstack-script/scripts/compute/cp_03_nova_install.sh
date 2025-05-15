#!/bin/bash

# 加载配置文件
source config.ini

# 安装 Nova 计算服务
nova_compute_install() {
    echo -e "${YELLOW}正在安装 Nova Compute...${RESET}"
    sudo apt install -y nova-compute
    echo -e "${GREEN}Nova Compute 安装完成。${RESET}"
}

# 配置 nova.conf 文件
nova_conf_configure() {
    local conf="/etc/nova/nova.conf"
    local conf_bak="/etc/nova/nova.conf.bak"

    # 备份并清理配置文件
    echo -e "${YELLOW}正在配置 $conf...${RESET}"
    cp "$conf" "$conf_bak"
    egrep -v "^#|^$" "$conf_bak" > "$conf"

    # [DEFAULT] 配置
    crudini --set "$conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller"
    crudini --set "$conf" "DEFAULT" "my_ip" "$COM_MANAGEMENT"

    # [api] 配置
    crudini --set "$conf" "api" "auth_strategy" "keystone"

    # 注释 [keystone_authtoken] 其他配置
    sed -i "/^\[keystone_authtoken\]/,/^\[/ s/^/#/" "$conf"
    crudini --set "$conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000/"
    crudini --set "$conf" "keystone_authtoken" "auth_url" "http://controller:5000/"
    crudini --set "$conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$conf" "keystone_authtoken" "username" "nova"
    crudini --set "$conf" "keystone_authtoken" "password" "$NOVA_PASS"

    # [service_user] 配置
    crudini --set "$conf" "service_user" "send_service_user_token" "true"
    crudini --set "$conf" "service_user" "auth_url" "http://controller:5000/"
    crudini --set "$conf" "service_user" "auth_strategy" "keystone"
    crudini --set "$conf" "service_user" "auth_type" "password"
    crudini --set "$conf" "service_user" "project_domain_name" "Default"
    crudini --set "$conf" "service_user" "project_name" "service"
    crudini --set "$conf" "service_user" "user_domain_name" "Default"
    crudini --set "$conf" "service_user" "username" "nova"
    crudini --set "$conf" "service_user" "password" "$NOVA_PASS"

    # [vnc] 配置
    crudini --set "$conf" "vnc" "enabled" "true"
    crudini --set "$conf" "vnc" "server_listen" "0.0.0.0"
    crudini --set "$conf" "vnc" "server_proxyclient_address" "\$my_ip"
    crudini --set "$conf" "vnc" "novncproxy_base_url" "http://controller:6080/vnc_auto.html"

    # [glance] 配置
    crudini --set "$conf" "glance" "api_servers" "http://controller:9292"

    # [oslo_concurrency] 配置
    crudini --set "$conf" "oslo_concurrency" "lock_path" "/var/lib/nova/tmp"

    # 注释 [placement] 其他配置
    sed -i "/^\[placement\]/,/^\[/ s/^/#/" "$conf"
    crudini --set "$conf" "placement" "region_name" "RegionOne"
    crudini --set "$conf" "placement" "project_domain_name" "Default"
    crudini --set "$conf" "placement" "project_name" "service"
    crudini --set "$conf" "placement" "auth_type" "password"
    crudini --set "$conf" "placement" "user_domain_name" "Default"
    crudini --set "$conf" "placement" "auth_url" "http://controller:5000/v3"
    crudini --set "$conf" "placement" "username" "placement"
    crudini --set "$conf" "placement" "password" "$PLACEMENT_PASS"

    echo -e "${GREEN}$conf 配置完成。${RESET}"
}

# 配置 nova-compute.conf 文件
nova_compute_conf_configure() {
    local conf="/etc/nova/nova-compute.conf"
    local conf_bak="/etc/nova/nova-compute.conf.bak"

    # 备份并清理配置文件
    echo -e "${YELLOW}正在配置 $conf...${RESET}"
    cp "$conf" "$conf_bak"
    egrep -v "^#|^$" "$conf_bak" > "$conf"

    # 检查硬件加速支持并配置 virt_type
    if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]]; then
        echo -e "${YELLOW}未检测到硬件加速，配置 libvirt 使用 QEMU...${RESET}"
        crudini --set "$conf" "libvirt" "virt_type" "qemu"
    else
        echo -e "${GREEN}检测到硬件加速，无需配置 virt_type。${RESET}"
    fi
}

# 重启 Nova Compute 服务
nova_compute_restart() {
    echo -e "${YELLOW}正在重启 Nova Compute 服务...${RESET}"
    sudo service nova-compute restart
    echo -e "${GREEN}Nova Compute 服务重启完成。${RESET}"
}

# 主流程
nova_compute_install
nova_conf_configure
nova_compute_conf_configure
nova_compute_restart

echo -e "${GREEN}OpenStack Compute (Nova) 节点配置完成。${RESET}"
