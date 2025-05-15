#!/bin/bash

# 加载配置文件
source config.ini

OPENSTACK_HOST="controller"
ALLOWED_HOSTS="['*']"  # 实际部署时请替换为实际主机名，开发环境可用 ['*']
MEMCACHED_LOCATION="controller:11211"
TIME_ZONE="Asia/Shanghai"

# 安装 OpenStack Dashboard (Horizon)
dashboard_install() {
    echo "正在安装 OpenStack Dashboard (Horizon)..."
    sudo apt install -y openstack-dashboard
    echo "OpenStack Dashboard 安装完成。"
}

# 配置 Horizon 的 local_settings.py
dashboard_configure_settings() {
    local local_settings="/etc/openstack-dashboard/local_settings.py"

    # 备份原始配置文件
    echo "备份原始 local_settings.py 文件..."
    sudo cp "$local_settings" "${local_settings}.bak"

    # 配置 OpenStack 主机
    echo "配置 OPENSTACK_HOST..."
    sudo sed -i "s/^OPENSTACK_HOST = .*/OPENSTACK_HOST = \"$OPENSTACK_HOST\"/" "$local_settings"

    # 配置 ALLOWED_HOSTS
    echo "配置 ALLOWED_HOSTS..."
    sudo sed -i "s/^ALLOWED_HOSTS = .*/ALLOWED_HOSTS = $ALLOWED_HOSTS/" "$local_settings"

    # 注释掉 COMPRESS_OFFLINE
    echo "注释 COMPRESS_OFFLINE..."
    sudo sed -i "/^COMPRESS_OFFLINE =/s/^/#/" "$local_settings"

    # 配置 memcached 作为 session 存储
    echo "配置 memcached 作为 session 存储..."
    sudo sed -i "/^CACHES = {/,+5 d" "$local_settings"
    cat <<EOF | sudo tee -a "$local_settings" > /dev/null
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.PyMemcacheCache',
        'LOCATION': '$MEMCACHED_LOCATION',
    }
}
EOF

    # 启用 Identity API v3
    echo "启用 Identity API v3..."
    sudo sed -i "s|^OPENSTACK_KEYSTONE_URL = .*|OPENSTACK_KEYSTONE_URL = \"http://%s:5000/identity/v3\" % OPENSTACK_HOST|" "$local_settings"

    # 启用 Keystone 多域支持
    echo "启用 Keystone 多域支持..."
    echo "OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True" | sudo tee -a "$local_settings" > /dev/null

    # 配置 API 版本
    echo "配置 API 版本..."
    sudo sed -i "/^OPENSTACK_API_VERSIONS = {/,+3 d" "$local_settings"
    cat <<EOF | sudo tee -a "$local_settings" > /dev/null
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
EOF

    # 设置默认域和角色
    echo "设置默认域和角色..."
    echo "OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"" | sudo tee -a "$local_settings" > /dev/null
    echo "OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"" | sudo tee -a "$local_settings" > /dev/null

    # 禁用三层网络服务（如有需要）
    echo "禁用三层网络服务..."
    sudo sed -i "/^OPENSTACK_NEUTRON_NETWORK = {/,+6 d" "$local_settings"
    cat <<EOF | sudo tee -a "$local_settings" > /dev/null
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': True,
    'enable_quotas': True,
    'enable_ipv6': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': False,
}
EOF

    # 配置时区
    echo "配置时区..."
    sudo sed -i "s|^TIME_ZONE = .*|TIME_ZONE = \"$TIME_ZONE\"|" "$local_settings"

    echo "local_settings.py 配置完成。"
}

# 配置 Apache 服务以支持 Horizon
dashboard_configure_apache() {
    local apache_conf="/etc/apache2/conf-available/openstack-dashboard.conf"

    echo "更新 Apache 配置..."
    if ! grep -q "WSGIApplicationGroup %{GLOBAL}" "$apache_conf"; then
        echo "添加 WSGIApplicationGroup %{GLOBAL} 到 Apache 配置..."
        echo "WSGIApplicationGroup %{GLOBAL}" | sudo tee -a "$apache_conf" > /dev/null
    fi

    # 重新加载 Apache 服务
    echo "重新加载 Apache 服务..."
    sudo systemctl reload apache2.service
    echo "Apache 配置已更新并重新加载。"
}

# 执行所有 Horizon 安装与配置步骤
dashboard_setup_all() {
    dashboard_install
    dashboard_configure_settings
    dashboard_configure_apache
    echo "OpenStack Dashboard (Horizon) 安装与配置完成。"
}

# 执行主流程
dashboard_setup_all
