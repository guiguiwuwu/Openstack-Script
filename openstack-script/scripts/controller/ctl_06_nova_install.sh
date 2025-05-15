#!/bin/bash

# 加载配置文件
source config.ini

# 配置Nova数据库
nova_db_setup() {
    echo "${YELLOW}正在配置Nova数据库...${RESET}"
    mysql -u root << EOF
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
FLUSH PRIVILEGES;
EOF
    echo "${GREEN}Nova数据库配置完成.${RESET}"
}

# 创建Nova用户和服务凭据
nova_user_service_create() {
    echo "${YELLOW}正在创建Nova用户和服务凭据...${RESET}"
    source /root/admin-openrc
    openstack user create --domain default --password $NOVA_PASS nova
    openstack role add --project service --user nova admin
    openstack service create --name nova --description "OpenStack Compute" compute
    echo "${GREEN}Nova用户和服务凭据创建完成.${RESET}"
}

# 创建Nova API端点
nova_endpoint_create() {
    echo "${YELLOW}正在创建Nova API端点...${RESET}"
    openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
    openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
    openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
    echo "${GREEN}Nova API端点创建完成.${RESET}"
}

# 安装并配置Nova服务
nova_install_configure() {
    echo "${YELLOW}正在安装并配置Nova服务...${RESET}"
    sudo apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler

    local conf="/etc/nova/nova.conf"
    local bak="/etc/nova/nova.conf.bak"
    cp $conf $bak
    egrep -v "^#|^$" $bak > $conf

    # 数据库相关配置
    crudini --set "$conf" "api_database" "connection" "mysql+pymysql://nova:$NOVA_DBPASS@controller/nova_api"
    crudini --set "$conf" "database" "connection" "mysql+pymysql://nova:$NOVA_DBPASS@controller/nova"

    # RabbitMQ配置
    crudini --set "$conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller:5672/"
    crudini --set "$conf" "DEFAULT" "my_ip" "$CTL_MANAGEMENT"

    # Keystone认证配置
    crudini --set "$conf" "api" "auth_strategy" "keystone"
    crudini --set "$conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000/"
    crudini --set "$conf" "keystone_authtoken" "auth_url" "http://controller:5000/"
    crudini --set "$conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$conf" "keystone_authtoken" "username" "nova"
    crudini --set "$conf" "keystone_authtoken" "password" "$NOVA_PASS"

    # 服务用户配置
    crudini --set "$conf" "service_user" "send_service_user_token" "true"
    crudini --set "$conf" "service_user" "auth_url" "http://controller:5000/v3"
    crudini --set "$conf" "service_user" "auth_strategy" "keystone"
    crudini --set "$conf" "service_user" "auth_type" "password"
    crudini --set "$conf" "service_user" "project_domain_name" "Default"
    crudini --set "$conf" "service_user" "project_name" "service"
    crudini --set "$conf" "service_user" "user_domain_name" "Default"
    crudini --set "$conf" "service_user" "username" "nova"
    crudini --set "$conf" "service_user" "password" "$NOVA_PASS"

    # VNC配置
    crudini --set "$conf" "vnc" "enabled" "true"
    crudini --set "$conf" "vnc" "server_listen" "\$my_ip"
    crudini --set "$conf" "vnc" "server_proxyclient_address" "\$my_ip"

    # Glance服务配置
    crudini --set "$conf" "glance" "api_servers" "http://controller:9292"

    # Oslo并发配置
    crudini --set "$conf" "oslo_concurrency" "lock_path" "/var/lib/nova/tmp"

    # Placement服务配置
    crudini --set "$conf" "placement" "region_name" "RegionOne"
    crudini --set "$conf" "placement" "project_domain_name" "Default"
    crudini --set "$conf" "placement" "project_name" "service"
    crudini --set "$conf" "placement" "auth_type" "password"
    crudini --set "$conf" "placement" "user_domain_name" "Default"
    crudini --set "$conf" "placement" "auth_url" "http://controller:5000/v3"
    crudini --set "$conf" "placement" "username" "placement"
    crudini --set "$conf" "placement" "password" "$PLACEMENT_PASS"

    # 调度器配置
    crudini --set "$conf" "scheduler" "discover_hosts_in_cells_interval" "300"

    echo "${GREEN}Nova配置已更新.${RESET}"
}

# 初始化Nova API数据库
nova_api_db_sync() {
    echo "${YELLOW}正在初始化Nova API数据库...${RESET}"
    su -s /bin/sh -c "nova-manage api_db sync" nova
    echo "${GREEN}Nova API数据库初始化完成.${RESET}"
}

# 注册cell0并创建cell1
nova_cell_register() {
    echo "${YELLOW}正在注册cell0并创建cell1...${RESET}"
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    echo "${GREEN}cell0注册及cell1创建完成.${RESET}"
}

# 初始化Nova数据库
nova_db_sync() {
    echo "${YELLOW}正在初始化Nova数据库...${RESET}"
    su -s /bin/sh -c "nova-manage db sync" nova
    echo "${GREEN}Nova数据库初始化完成.${RESET}"
}

# 验证cell注册情况
nova_cell_verify() {
    echo "${YELLOW}正在验证cell0和cell1注册情况...${RESET}"
    su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
}

# 重启Nova服务
nova_service_restart() {
    echo "${YELLOW}正在重启Nova服务...${RESET}"
    sudo service nova-api restart
    sudo service nova-scheduler restart
    sudo service nova-conductor restart
    sudo service nova-novncproxy restart
    echo "${GREEN}Nova服务重启完成.${RESET}"
}

# 主流程
nova_db_setup
nova_user_service_create
nova_endpoint_create
nova_install_configure
nova_api_db_sync
nova_cell_register
nova_db_sync
nova_cell_verify
nova_service_restart

echo "${GREEN}OpenStack Nova服务部署完成.${RESET}"
