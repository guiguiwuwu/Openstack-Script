#!/bin/bash

# 加载配置文件
source config.ini

# 配置Cinder数据库
cinder_db_setup() {
    echo "${YELLOW}正在配置Cinder数据库...${RESET}"
    mysql << EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';
FLUSH PRIVILEGES;
EOF
    echo "${GREEN}Cinder数据库配置完成.${RESET}"
}

# 创建Cinder服务凭据
cinder_service_credentials_create() {
    echo "${YELLOW}正在创建Cinder服务凭据...${RESET}"
    source /root/admin-openrc

    openstack user create --domain default --password "$CINDER_PASS" cinder
    openstack role add --project service --user cinder admin
    openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
    openstack role add --project service --user cinder service
    openstack role add --project service --user nova service
    
    echo "${GREEN}Cinder服务凭据创建完成.${RESET}"
}

# 创建Cinder API端点
cinder_api_endpoints_create() {
    echo "${YELLOW}正在创建Cinder API端点...${RESET}"
    openstack endpoint create --region RegionOne volumev3 public http://controller:8776/v3/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev3 internal http://controller:8776/v3/%\(project_id\)s
    openstack endpoint create --region RegionOne volumev3 admin http://controller:8776/v3/%\(project_id\)s
    echo "${GREEN}Cinder API端点创建完成.${RESET}"
}

# 安装并配置Cinder
cinder_install_and_configure() {
    echo "${YELLOW}正在安装并配置Cinder...${RESET}"
    sudo apt install -y cinder-api cinder-scheduler

    local cinder_conf="/etc/cinder/cinder.conf"
    local cinder_conf_bak="/etc/cinder/cinder.conf.bak"
    cp "$cinder_conf" "$cinder_conf_bak"
    egrep -v "^#|^$" "$cinder_conf_bak" > "$cinder_conf"

    # 配置数据库连接
    crudini --set "$cinder_conf" "database" "connection" "mysql+pymysql://cinder:$CINDER_DBPASS@controller/cinder"

    # 配置RabbitMQ消息队列
    crudini --set "$cinder_conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller"

    # 配置身份认证服务
    crudini --set "$cinder_conf" "DEFAULT" "auth_strategy" "keystone"
    crudini --set "$cinder_conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000"
    crudini --set "$cinder_conf" "keystone_authtoken" "auth_url" "http://controller:5000"
    crudini --set "$cinder_conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$cinder_conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$cinder_conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$cinder_conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$cinder_conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$cinder_conf" "keystone_authtoken" "username" "cinder"
    crudini --set "$cinder_conf" "keystone_authtoken" "password" "$CINDER_PASS"

    # 配置管理IP
    crudini --set "$cinder_conf" "DEFAULT" "my_ip" "$CTL_MANAGEMENT"

    # 配置Oslo Concurrency锁路径
    crudini --set "$cinder_conf" "oslo_concurrency" "lock_path" "/var/lib/cinder/tmp"

    echo "${GREEN}Cinder配置更新完成.${RESET}"
}

# 初始化Cinder数据库
cinder_db_sync() {
    echo "${YELLOW}正在初始化Cinder数据库...${RESET}"
    su -s /bin/sh -c "cinder-manage db sync" cinder
    echo "${GREEN}Cinder数据库初始化完成.${RESET}"
}

# 配置Nova使用Cinder
nova_configure_for_cinder() {
    echo "${YELLOW}正在配置Nova使用Cinder...${RESET}"
    local nova_conf="/etc/nova/nova.conf"
    crudini --set "$nova_conf" "cinder" "os_region_name" "RegionOne"
    echo "${GREEN}Nova已成功配置使用Cinder.${RESET}"
}

# 重启相关服务，完成Cinder安装
cinder_services_restart() {
    echo "${YELLOW}正在重启相关服务...${RESET}"
    sudo service nova-api restart
    sudo service cinder-scheduler restart
    sudo service apache2 restart
    echo "${GREEN}Cinder相关服务重启完成.${RESET}"
}

# 主流程
cinder_db_setup
cinder_service_credentials_create
cinder_api_endpoints_create
cinder_install_and_configure
cinder_db_sync
nova_configure_for_cinder
cinder_services_restart

echo "${GREEN}OpenStack块存储（Cinder）安装配置完成.${RESET}"
