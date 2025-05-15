#!/bin/bash

# 加载配置文件
source config.ini

# 配置 Neutron 数据库
neutron_db_setup() {
    echo "${YELLOW}配置 Neutron 数据库...${RESET}"
    mysql -u root << EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';
FLUSH PRIVILEGES;
EOF
    echo "${GREEN}Neutron 数据库配置完成.${RESET}"
}

# 创建 Neutron 用户和服务凭据
neutron_user_and_service_setup() {
    echo "${YELLOW}创建 Neutron 用户和服务凭据...${RESET}"
    source /root/admin-openrc
    openstack user create --domain default --password $NEUTRON_PASS neutron
    openstack role add --project service --user neutron admin
    openstack service create --name neutron --description "OpenStack Networking" network
    echo "${GREEN}Neutron 用户和服务凭据创建完成.${RESET}"
}

# 创建 Neutron API 端点
neutron_endpoint_setup() {
    echo "${YELLOW}创建 Neutron API 端点...${RESET}"
    openstack endpoint create --region RegionOne network public http://controller:9696
    openstack endpoint create --region RegionOne network internal http://controller:9696
    openstack endpoint create --region RegionOne network admin http://controller:9696
    echo "${GREEN}Neutron API 端点创建完成.${RESET}"
}

# 安装并配置 Neutron
neutron_install_and_configure() {
    echo "${YELLOW}安装并配置 Neutron...${RESET}"
    sudo apt install -y neutron-server neutron-plugin-ml2 \
        neutron-openvswitch-agent neutron-l3-agent \
        neutron-dhcp-agent neutron-metadata-agent

    local neutron_conf="/etc/neutron/neutron.conf"
    local neutron_conf_bak="/etc/neutron/neutron.conf.bak"
    cp $neutron_conf $neutron_conf_bak
    egrep -v "^#|^$" $neutron_conf_bak > $neutron_conf

    # 数据库配置
    crudini --set "$neutron_conf" "database" "connection" "mysql+pymysql://neutron:$NEUTRON_DBPASS@controller/neutron"

    # DEFAULT 配置
    crudini --set "$neutron_conf" "DEFAULT" "core_plugin" "ml2"
    crudini --set "$neutron_conf" "DEFAULT" "service_plugins" "router"
    crudini --set "$neutron_conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller"
    crudini --set "$neutron_conf" "DEFAULT" "auth_strategy" "keystone"
    crudini --set "$neutron_conf" "DEFAULT" "notify_nova_on_port_status_changes" "true"
    crudini --set "$neutron_conf" "DEFAULT" "notify_nova_on_port_data_changes" "true"

    # Keystone 认证配置
    crudini --set "$neutron_conf" "keystone_authtoken" "www_authenticate_uri" "http://controller:5000"
    crudini --set "$neutron_conf" "keystone_authtoken" "auth_url" "http://controller:5000"
    crudini --set "$neutron_conf" "keystone_authtoken" "memcached_servers" "controller:11211"
    crudini --set "$neutron_conf" "keystone_authtoken" "auth_type" "password"
    crudini --set "$neutron_conf" "keystone_authtoken" "project_domain_name" "Default"
    crudini --set "$neutron_conf" "keystone_authtoken" "user_domain_name" "Default"
    crudini --set "$neutron_conf" "keystone_authtoken" "project_name" "service"
    crudini --set "$neutron_conf" "keystone_authtoken" "username" "neutron"
    crudini --set "$neutron_conf" "keystone_authtoken" "password" "$NEUTRON_PASS"

    # Nova 配置
    crudini --set "$neutron_conf" "nova" "auth_url" "http://controller:5000"
    crudini --set "$neutron_conf" "nova" "auth_type" "password"
    crudini --set "$neutron_conf" "nova" "project_domain_name" "Default"
    crudini --set "$neutron_conf" "nova" "user_domain_name" "Default"
    crudini --set "$neutron_conf" "nova" "region_name" "RegionOne"
    crudini --set "$neutron_conf" "nova" "project_name" "service"
    crudini --set "$neutron_conf" "nova" "username" "nova"
    crudini --set "$neutron_conf" "nova" "password" "$NOVA_PASS"

    # oslo_concurrency 配置
    crudini --set "$neutron_conf" "oslo_concurrency" "lock_path" "/var/lib/neutron/tmp"

    echo "${GREEN}Neutron 配置已更新.${RESET}"
}

# 配置 ML2 插件
ml2_plugin_configure() {
    echo "${YELLOW}配置 ML2 插件...${RESET}"
    local ml2_conf="/etc/neutron/plugins/ml2/ml2_conf.ini"
    local ml2_conf_bak="/etc/neutron/plugins/ml2/ml2_conf.ini.bak"
    cp $ml2_conf $ml2_conf_bak
    egrep -v "^#|^$" $ml2_conf_bak > $ml2_conf

    crudini --set "$ml2_conf" "ml2" "type_drivers" "flat,vlan,vxlan"
    crudini --set "$ml2_conf" "ml2" "tenant_network_types" "vxlan"
    crudini --set "$ml2_conf" "ml2" "mechanism_drivers" "openvswitch,l2population"
    crudini --set "$ml2_conf" "ml2" "extension_drivers" "port_security"
    crudini --set "$ml2_conf" "ml2_type_flat" "flat_networks" "provider"
    crudini --set "$ml2_conf" "ml2_type_vxlan" "vni_ranges" "1:1000"

    echo "${GREEN}ML2 插件配置已更新.${RESET}"
}

# 持久化 Open vSwitch 手动配置
ovs_manual_config_persist() {
    echo "${YELLOW}持久化 Open vSwitch 手动配置...${RESET}"
    cat << EOF | sudo tee /usr/local/bin/setup-bridge.sh > /dev/null
#!/bin/bash
ip addr flush dev $OS_PROVIDER_INTERFACE_NAME
ip link set $OS_PROVIDER_BRIDGE_NAME up
ip addr add $CTL_PROVIDER/$NETMASK dev $OS_PROVIDER_BRIDGE_NAME
ip route add default via $GW_PROVIDER
EOF
    sudo chmod +x /usr/local/bin/setup-bridge.sh

    cat << EOF | sudo tee /etc/systemd/system/setup-bridge.service > /dev/null
[Unit]
Description=Set up Open vSwitch bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-bridge.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable setup-bridge.service
    sudo systemctl start setup-bridge.service
    echo "${GREEN}Open vSwitch 手动配置持久化完成.${RESET}"
}

# 配置 Open vSwitch (OVS) agent
ovs_agent_configure() {
    echo "${YELLOW}配置 Open vSwitch (OVS) agent...${RESET}"
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo modprobe br_netfilter
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-arptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1

    sudo ovs-vsctl add-br $OS_PROVIDER_BRIDGE_NAME
    sudo ovs-vsctl add-port $OS_PROVIDER_BRIDGE_NAME $OS_PROVIDER_INTERFACE_NAME

    local ovs_agent_conf="/etc/neutron/plugins/ml2/openvswitch_agent.ini"
    local ovs_agent_conf_bak="/etc/neutron/plugins/ml2/openvswitch_agent.ini.bak"
    cp $ovs_agent_conf $ovs_agent_conf_bak
    egrep -v "^#|^$" $ovs_agent_conf_bak > $ovs_agent_conf

    crudini --set "$ovs_agent_conf" "ovs" "bridge_mappings" "provider:$OS_PROVIDER_BRIDGE_NAME"
    crudini --set "$ovs_agent_conf" "ovs" "local_ip" "$CTL_MANAGEMENT"
    crudini --set "$ovs_agent_conf" "agent" "tunnel_types" "vxlan"
    crudini --set "$ovs_agent_conf" "agent" "l2_population" "true"
    crudini --set "$ovs_agent_conf" "securitygroup" "enable_security_group" "true"
    crudini --set "$ovs_agent_conf" "securitygroup" "firewall_driver" "openvswitch"

    ovs_manual_config_persist
    systemctl restart openvswitch-switch

    echo "${GREEN}Open vSwitch agent 配置完成.${RESET}"
}

# 配置 L3 agent
l3_agent_configure() {
    echo "${YELLOW}配置 L3 agent...${RESET}"
    local l3_agent_conf="/etc/neutron/l3_agent.ini"
    local l3_agent_conf_bak="/etc/neutron/l3_agent.ini.bak"
    cp $l3_agent_conf $l3_agent_conf_bak
    egrep -v "^#|^$" $l3_agent_conf_bak > $l3_agent_conf

    crudini --set "$l3_agent_conf" "DEFAULT" "interface_driver" "openvswitch"
    echo "${GREEN}L3 agent 配置完成.${RESET}"
}

# 配置 DHCP agent
dhcp_agent_configure() {
    echo "${YELLOW}配置 DHCP agent...${RESET}"
    local dhcp_agent_conf="/etc/neutron/dhcp_agent.ini"
    local dhcp_agent_conf_bak="/etc/neutron/dhcp_agent.ini.bak"
    cp $dhcp_agent_conf $dhcp_agent_conf_bak
    egrep -v "^#|^$" $dhcp_agent_conf_bak > $dhcp_agent_conf

    crudini --set "$dhcp_agent_conf" "DEFAULT" "interface_driver" "openvswitch"
    crudini --set "$dhcp_agent_conf" "DEFAULT" "dhcp_driver" "neutron.agent.linux.dhcp.Dnsmasq"
    crudini --set "$dhcp_agent_conf" "DEFAULT" "enable_isolated_metadata" "true"
    echo "${GREEN}DHCP agent 配置完成.${RESET}"
}

# 配置 metadata agent
metadata_agent_configure() {
    echo "${YELLOW}配置 Neutron metadata agent...${RESET}"
    local metadata_agent_conf="/etc/neutron/metadata_agent.ini"
    local metadata_agent_conf_bak="/etc/neutron/metadata_agent.ini.bak"
    cp $metadata_agent_conf $metadata_agent_conf_bak
    egrep -v "^#|^$" $metadata_agent_conf_bak > $metadata_agent_conf

    crudini --set "$metadata_agent_conf" "DEFAULT" "nova_metadata_host" "controller"
    crudini --set "$metadata_agent_conf" "DEFAULT" "metadata_proxy_shared_secret" "$METADATA_SECRET"
    echo "${GREEN}Metadata agent 配置完成.${RESET}"
}

# 配置 Nova 使用 Neutron
nova_neutron_configure() {
    echo "${YELLOW}配置 Nova 使用 Neutron...${RESET}"
    local file="/etc/nova/nova.conf"
    crudini --set "$file" "neutron" "auth_url" "http://controller:5000"
    crudini --set "$file" "neutron" "auth_type" "password"
    crudini --set "$file" "neutron" "project_domain_name" "Default"
    crudini --set "$file" "neutron" "user_domain_name" "Default"
    crudini --set "$file" "neutron" "region_name" "RegionOne"
    crudini --set "$file" "neutron" "project_name" "service"
    crudini --set "$file" "neutron" "username" "neutron"
    crudini --set "$file" "neutron" "password" "$NEUTRON_PASS"
    crudini --set "$file" "neutron" "service_metadata_proxy" "true"
    crudini --set "$file" "neutron" "metadata_proxy_shared_secret" "$METADATA_SECRET"
    echo "${GREEN}Nova 已配置为使用 Neutron.${RESET}"
}

# 初始化 Neutron 数据库
neutron_db_sync() {
    echo "${YELLOW}初始化 Neutron 数据库...${RESET}"
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
    echo "${GREEN}Neutron 数据库初始化完成.${RESET}"
}

# 重启相关服务
neutron_services_restart() {
    echo "${YELLOW}重启 Neutron 相关服务...${RESET}"
    sudo service nova-api restart
    sudo service neutron-server restart
    sudo service neutron-openvswitch-agent restart
    sudo service neutron-dhcp-agent restart
    sudo service neutron-metadata-agent restart
    sudo service neutron-l3-agent restart
    echo "${GREEN}Neutron 服务重启完成.${RESET}"
}

# 配置 systemd-resolved DNS
systemd_resolved_dns_configure() {
    echo "${YELLOW}配置 systemd-resolved 使用 DNS 223.5.5.5...${RESET}"
    local resolved_conf="/etc/systemd/resolved.conf"
    sudo cp $resolved_conf "${resolved_conf}.bak"
    sudo sed -i '/^#DNS=/c\DNS=223.5.5.5' $resolved_conf
    sudo systemctl restart systemd-resolved
    echo "${YELLOW}验证 DNS 配置...${RESET}"
    resolvectl status | grep "DNS Servers"
    echo "${GREEN}systemd-resolved 配置完成.${RESET}"
}

# 主流程
neutron_db_setup
neutron_user_and_service_setup
neutron_endpoint_setup
neutron_install_and_configure
metadata_agent_configure
ml2_plugin_configure
ovs_agent_configure
l3_agent_configure
dhcp_agent_configure
nova_neutron_configure
systemd_resolved_dns_configure
neutron_db_sync
neutron_services_restart

echo "${GREEN}OpenStack Networking (Neutron) 部署完成.${RESET}"
