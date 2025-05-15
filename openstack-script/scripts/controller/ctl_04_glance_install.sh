#!/bin/bash

# 加载配置文件
source config.ini

# 配色变量（假设已在 config.cfg 定义）
# YELLOW, GREEN, RED, RESET

# 配置 Glance 数据库
glance_configure_database() {
    echo "${YELLOW}正在配置 Glance 数据库...${RESET}"

    mysql -u root << EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';
FLUSH PRIVILEGES;
EOF

    echo "${GREEN}Glance 数据库配置完成。${RESET}"
}

# 创建 Glance 用户和服务凭据
glance_create_user_and_service() {
    echo "${YELLOW}正在创建 Glance 用户和服务凭据...${RESET}"

    # 加载管理员凭据
    source /root/admin-openrc

    # 创建 glance 用户
    openstack user create --domain default --password "$GLANCE_PASS" glance

    # 为 glance 用户添加 admin 角色
    openstack role add --project service --user glance admin

    # 创建 glance 服务实体
    openstack service create --name glance --description "OpenStack Image" image

    # 为 glance 用户分配 system-scope reader 角色
    openstack role add --user glance --user-domain Default --system all reader

    echo "${GREEN}Glance 用户和服务凭据创建完成。${RESET}"
}

# 创建 Glance API 端点并获取 endpoint_id
glance_create_endpoints() {
    echo "${YELLOW}正在创建 Glance API 端点...${RESET}"

    public_endpoint=$(openstack endpoint create --region RegionOne image public http://controller:9292 -f value -c id)
    internal_endpoint=$(openstack endpoint create --region RegionOne image internal http://controller:9292 -f value -c id)
    admin_endpoint=$(openstack endpoint create --region RegionOne image admin http://controller:9292 -f value -c id)

    echo "${GREEN}Glance API 端点创建完成，端点 ID 如下：${RESET}"
    echo "${GREEN}Public Endpoint ID: $public_endpoint${RESET}"
    echo "${GREEN}Internal Endpoint ID: $internal_endpoint${RESET}"
    echo "${GREEN}Admin Endpoint ID: $admin_endpoint${RESET}"

    # 导出 public 端点 ID 供后续使用
    export GLANCE_ENDPOINT_ID=$public_endpoint
}

# 安装并配置 Glance
glance_install_and_configure() {
    echo "${YELLOW}正在安装并配置 Glance...${RESET}"

    # 安装 glance 包
    sudo apt install -y glance

    # 配置 glance-api.conf
    local glance_conf="/etc/glance/glance-api.conf"
    local glance_conf_bak="/etc/glance/glance-api.conf.bak"
    cp "$glance_conf" "$glance_conf_bak"
    egrep -v "^#|^$" "$glance_conf_bak" > "$glance_conf"

    # 数据库配置
    crudini --set "$glance_conf" "database" "connection" "mysql+pymysql://glance:$GLANCE_DBPASS@controller/glance"

    # Keystone 认证配置
    crudini --set "$glance_conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000"
    crudini --set "$glance_conf" "keystone_authtoken" "auth_url" "http://controller:5000"
    crudini --set "$glance_conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$glance_conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$glance_conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$glance_conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$glance_conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$glance_conf" "keystone_authtoken" "username" "glance"
    crudini --set "$glance_conf" "keystone_authtoken" "password" "$GLANCE_PASS"

    # paste_deploy 配置
    crudini --set "$glance_conf" "paste_deploy" "flavor" "keystone"

    # 存储后端配置
    crudini --set "$glance_conf" "DEFAULT" "enabled_backends" "fs:file"
    crudini --set "$glance_conf" "glance_store" "default_backend" "fs"
    crudini --set "$glance_conf" "fs" "filesystem_store_datadir" "/var/lib/glance/images/"

    # oslo_limit 配置
    crudini --set "$glance_conf" "oslo_limit" "auth_url" "http://controller:5000"
    crudini --set "$glance_conf" "oslo_limit" "auth_type" "password"
    crudini --set "$glance_conf" "oslo_limit" "user_domain_id" "default"
    crudini --set "$glance_conf" "oslo_limit" "username" "glance"
    crudini --set "$glance_conf" "oslo_limit" "system_scope" "all"
    crudini --set "$glance_conf" "oslo_limit" "password" "$GLANCE_PASS"
    crudini --set "$glance_conf" "oslo_limit" "endpoint_id" "$GLANCE_ENDPOINT_ID"
    crudini --set "$glance_conf" "oslo_limit" "region_name" "RegionOne"

    echo "${GREEN}Glance 配置已更新。${RESET}"
}

# 初始化 Glance 数据库
glance_db_sync() {
    echo "${YELLOW}正在初始化 Glance 数据库...${RESET}"
    su -s /bin/sh -c "glance-manage db_sync" glance
    echo "${GREEN}Glance 数据库初始化完成。${RESET}"
}

# 重启 Glance 服务，完成安装
glance_finalize_install() {
    echo "${YELLOW}正在重启 Glance 服务，完成安装...${RESET}"
    sudo service glance-api restart
    echo "${GREEN}Glance 安装与配置已完成。${RESET}"
}

# 验证 Glance 是否可用
glance_verify() {
    echo "${YELLOW}正在验证 Glance 服务...${RESET}"

    source /root/admin-openrc

    apt-get install wget -y
    wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img

    glance image-create --name "cirros" \
        --file cirros-0.4.0-x86_64-disk.img \
        --disk-format qcow2 --container-format bare \
        --visibility=public

    # 检查镜像是否为 active 状态
    if openstack image list | grep -q 'cirros.*active'; then
        echo "${GREEN}Glance 服务可用。${RESET}"
    else
        echo "${RED}Glance 镜像验证失败，退出。${RESET}"
        exit 1
    fi
}

# 主流程，按顺序调用各函数
glance_configure_database
glance_create_user_and_service
glance_create_endpoints
glance_install_and_configure
glance_db_sync
glance_finalize_install
glance_verify

echo "${GREEN}OpenStack 镜像服务（Glance）部署完成。${RESET}"
