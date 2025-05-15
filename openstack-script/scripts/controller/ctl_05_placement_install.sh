#!/bin/bash

# 加载配置文件
source config.ini

# 配置 Placement 数据库
placement_db_setup() {
    echo "${YELLOW}配置 Placement 数据库...${RESET}"

    mysql -u root << EOF
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';
FLUSH PRIVILEGES;
EOF

    echo "${GREEN}Placement 数据库配置完成.${RESET}"
}

# 创建 Placement 用户和服务凭据
placement_user_and_service_setup() {
    echo "${YELLOW}创建 Placement 用户和服务凭据...${RESET}"

    # 加载管理员凭据
    source /root/admin-openrc

    # 创建 Placement 用户
    openstack user create --domain default --password "$PLACEMENT_PASS" placement

    # 将 Placement 用户添加到 service 项目并赋予 admin 角色
    openstack role add --project service --user placement admin

    # 创建 Placement 服务实体
    openstack service create --name placement --description "Placement API" placement

    echo "${GREEN}Placement 用户和服务凭据创建完成.${RESET}"
}

# 创建 Placement API 端点
placement_endpoint_setup() {
    echo "${YELLOW}创建 Placement API 端点...${RESET}"

    openstack endpoint create --region RegionOne placement public   http://controller:8778
    openstack endpoint create --region RegionOne placement internal http://controller:8778
    openstack endpoint create --region RegionOne placement admin    http://controller:8778

    echo "${GREEN}Placement API 端点创建完成.${RESET}"
}

# 安装并配置 Placement 服务
placement_install_and_configure() {
    echo "${YELLOW}安装并配置 Placement 服务...${RESET}"

    # 安装 Placement 软件包
    sudo apt install -y placement-api

    # 配置 Placement
    local conf="/etc/placement/placement.conf"
    local bak="/etc/placement/placement.conf.bak"
    cp "$conf" "$bak"
    egrep -v "^#|^$" "$bak" > "$conf"

    # 数据库连接配置
    crudini --set "$conf" "placement_database" "connection" "mysql+pymysql://placement:$PLACEMENT_DBPASS@controller/placement"

    # API 认证策略
    crudini --set "$conf" "api" "auth_strategy" "keystone"

    # Keystone 认证相关配置
    crudini --set "$conf" "keystone_authtoken" "auth_url" "http://controller:5000/v3"
    crudini --set "$conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$conf" "keystone_authtoken" "username" "placement"
    crudini --set "$conf" "keystone_authtoken" "password" "$PLACEMENT_PASS"

    # 注释掉 [keystone_authtoken] 其他无关配置项
    local allowed_keys=("auth_url" "memcached_servers" "auth_type" "project_domain_name" "user_domain_name" "project_name" "username" "password")
    sed -i "/^\[keystone_authtoken\]/,/^\[/{ 
        /^\[keystone_authtoken\]/!{/^\[/!s/^\([^#].*\)/#\1/}
    }" "$conf"

    # 取消注释需要保留的配置项
    for key in "${allowed_keys[@]}"; do
        sed -i "/^\[keystone_authtoken\]/,/^\[/s/^#\($key[ ]*=.*\)/\1/" "$conf"
    done

    echo "${GREEN}Placement 配置已更新.${RESET}"
}

# 初始化 Placement 数据库
placement_db_sync() {
    echo "${YELLOW}初始化 Placement 数据库...${RESET}"
    su -s /bin/sh -c "placement-manage db sync" placement
    echo "${GREEN}Placement 数据库初始化完成.${RESET}"
}

# 完成 Placement 安装
placement_finalize() {
    echo "${YELLOW}完成 Placement 安装...${RESET}"

    # 重启 Apache 服务
    sudo service apache2 restart

    echo "${GREEN}Placement 服务安装完成.${RESET}"
}

# 按顺序执行各步骤
placement_db_setup
placement_user_and_service_setup
placement_endpoint_setup
placement_install_and_configure
placement_db_sync
placement_finalize

echo "${GREEN}OpenStack Placement 服务部署完成.${RESET}"
