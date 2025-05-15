#!/bin/bash

# 加载配置文件
source config.ini

# 创建 admin-openrc 文件
create_admin_openrc() {
    echo "${YELLOW}正在创建 /root/admin-openrc 文件...${RESET}"
    sudo tee /root/admin-openrc > /dev/null << EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
    echo "${GREEN}/root/admin-openrc 文件创建完成.${RESET}"
}

# 配置 Keystone 数据库
setup_keystone_db() {
    echo "${YELLOW}正在配置 Keystone 数据库...${RESET}"
    mysql << EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF
    echo "${GREEN}Keystone 数据库配置完成.${RESET}"
}

# 安装并配置 Keystone
install_and_configure_keystone() {
    echo "${YELLOW}正在安装 Keystone...${RESET}"
    sudo apt update
    sudo apt install -y keystone

    local conf="/etc/keystone/keystone.conf"
    local bak="/etc/keystone/keystone.conf.bak"
    cp $conf $bak
    egrep -v "^#|^$" $bak > $conf

    echo "${YELLOW}正在配置 $conf ...${RESET}"
    crudini --set "$conf" "database" "connection" "mysql+pymysql://keystone:$KEYSTONE_DBPASS@controller/keystone"
    crudini --set "$conf" "token" "provider" "fernet"
    echo "${GREEN}Keystone 配置已更新.${RESET}"
}

# 初始化 Keystone 数据库
sync_keystone_db() {
    echo "${YELLOW}正在同步 Keystone 数据库...${RESET}"
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    echo "${GREEN}Keystone 数据库同步完成.${RESET}"
}

# 初始化 Fernet 密钥
init_fernet_keys() {
    echo "${YELLOW}正在初始化 Fernet 密钥仓库...${RESET}"
    sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    echo "${GREEN}Fernet 密钥仓库初始化完成.${RESET}"
}

# Keystone 服务引导
bootstrap_keystone() {
    echo "${YELLOW}正在引导 Keystone 服务...${RESET}"
    sudo keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
        --bootstrap-admin-url http://controller:5000/v3/ \
        --bootstrap-internal-url http://controller:5000/v3/ \
        --bootstrap-public-url http://controller:5000/v3/ \
        --bootstrap-region-id RegionOne
    echo "${GREEN}Keystone 服务引导完成.${RESET}"
}

# 配置 Apache 服务
config_apache_for_keystone() {
    echo "${YELLOW}正在配置 Apache HTTP 服务...${RESET}"
    if ! grep -q "ServerName controller" /etc/apache2/apache2.conf; then
        echo "ServerName controller" | sudo tee -a /etc/apache2/apache2.conf
    fi
    sudo service apache2 restart
    echo "${GREEN}Apache 配置并重启完成.${RESET}"
}

# 加载管理员环境变量
load_admin_env() {
    echo "${YELLOW}正在加载管理员环境变量...${RESET}"
    source /root/admin-openrc
    echo "${GREEN}管理员环境变量加载完成.${RESET}"
}

# 创建域、项目、用户和角色
create_keystone_entities() {
    echo "${YELLOW}正在创建域、项目、用户和角色...${RESET}"
    source /root/admin-openrc
    openstack project create --domain default --description "Service Project" service
    echo "${GREEN}项目 'service' 创建完成.${RESET}"
}

# 主流程
main() {
    create_admin_openrc
    setup_keystone_db
    install_and_configure_keystone
    sync_keystone_db
    init_fernet_keys
    bootstrap_keystone
    config_apache_for_keystone
    load_admin_env
    create_keystone_entities
    echo "${GREEN}OpenStack Identity (Keystone) 部署完成.${RESET}"
}

main
