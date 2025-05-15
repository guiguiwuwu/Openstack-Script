#!/bin/bash

# 加载配置文件
source config.ini

# 配置 systemd-resolved 的 DNS
setup_dns_with_systemd_resolved() {
    echo "${YELLOW}配置 systemd-resolved 使用 DNS 223.5.5.5...${RESET}"
    local resolved_conf="/etc/systemd/resolved.conf"

    # 备份原始配置
    sudo cp $resolved_conf "${resolved_conf}.bak"

    # 修改 DNS 配置
    sudo sed -i '/^#DNS=/c\DNS=223.5.5.5' $resolved_conf

    # 重启 systemd-resolved 服务
    sudo systemctl restart systemd-resolved

    # 验证 DNS 配置
    echo "${YELLOW}验证 DNS 配置...${RESET}"
    resolvectl status | grep "DNS Servers"

    echo "${GREEN}systemd-resolved 配置完成。${RESET}"
}

# 安装 Neutron Open vSwitch agent
install_neutron_ovs_agent() {
    echo "${YELLOW}安装 Neutron Open vSwitch agent...${RESET}"
    sudo apt install -y neutron-openvswitch-agent
    echo "${GREEN}Neutron Open vSwitch agent 安装完成。${RESET}"
}

# 配置 neutron.conf
setup_neutron_conf() {
    local neutron_conf="/etc/neutron/neutron.conf"
    local neutron_conf_bak="/etc/neutron/neutron.conf.bak"
    
    echo "${YELLOW}配置 $neutron_conf...${RESET}"
    cp $neutron_conf $neutron_conf_bak
    egrep -v "^#|^$" $neutron_conf_bak > $neutron_conf

    # 注释 [database] 段的 connection 选项
    sudo sed -i "/^\[database\]/,/^\[/ s/^connection/#connection/" $neutron_conf

    # 配置 RabbitMQ 消息队列
    crudini --set "$neutron_conf" "DEFAULT" "transport_url" "rabbit://openstack:$RABBIT_PASS@controller"

    # 配置 oslo_concurrency 锁路径
    crudini --set "$neutron_conf" "oslo_concurrency" "lock_path" "/var/lib/neutron/tmp"

    echo "${GREEN}$neutron_conf 配置完成。${RESET}"
}

# 持久化 Open vSwitch 手动配置
persist_ovs_manual_config() {
    echo "${YELLOW}持久化 Open vSwitch 手动配置...${RESET}"

    cat << EOF | sudo tee /usr/local/bin/setup-bridge.sh > /dev/null
#!/bin/bash
# 清除原有 IP
ip addr flush dev $OS_PROVIDER_INTERFACE_NAME
# 启动网桥
ip link set $OS_PROVIDER_BRIDGE_NAME up
# 给网桥添加 IP
ip addr add $COM_PROVIDER/$NETMASK dev $OS_PROVIDER_BRIDGE_NAME
# 添加默认路由
ip route add default via $GW_PROVIDER
EOF

    sudo chmod +x /usr/local/bin/setup-bridge.sh

    cat << EOF | sudo tee /etc/systemd/system/setup-bridge.service > /dev/null
[Unit]
Description=设置 Open vSwitch 网桥
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
    echo "${GREEN}Open vSwitch 手动配置已持久化。${RESET}"
}

# 配置 Open vSwitch agent
setup_ovs_agent_conf() {
    local ovs_agent_conf="/etc/neutron/plugins/ml2/openvswitch_agent.ini"
    local ovs_agent_conf_bak="/etc/neutron/plugins/ml2/openvswitch_agent.ini.bak"
    
    echo "${YELLOW}配置 $ovs_agent_conf...${RESET}"
    cp $ovs_agent_conf $ovs_agent_conf_bak
    egrep -v "^#|^$" $ovs_agent_conf_bak > $ovs_agent_conf

    # 启用网桥过滤支持
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo modprobe br_netfilter
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-arptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1

    # 创建 provider 网桥并添加接口
    echo "${YELLOW}创建 provider 网桥并添加接口...${RESET}"
    sudo ovs-vsctl add-br $OS_PROVIDER_BRIDGE_NAME
    sudo ovs-vsctl add-port $OS_PROVIDER_BRIDGE_NAME $OS_PROVIDER_INTERFACE_NAME

    # 配置 [ovs] 段
    crudini --set "$ovs_agent_conf" "ovs" "bridge_mappings" "provider:$OS_PROVIDER_BRIDGE_NAME"
    crudini --set "$ovs_agent_conf" "ovs" "local_ip" "$COM_MANAGEMENT"

    # 配置 [agent] 段
    crudini --set "$ovs_agent_conf" "agent" "tunnel_types" "vxlan"
    crudini --set "$ovs_agent_conf" "agent" "l2_population" "true"

    # 配置 [securitygroup] 段
    crudini --set "$ovs_agent_conf" "securitygroup" "enable_security_group" "true"
    crudini --set "$ovs_agent_conf" "securitygroup" "firewall_driver" "openvswitch"

    persist_ovs_manual_config
    systemctl restart openvswitch-switch

    echo "${GREEN}Open vSwitch agent 配置完成。${RESET}"
}

# 配置 nova.conf 以使用 Neutron
setup_nova_conf_for_neutron() {
    local nova_conf="/etc/nova/nova.conf"
    
    echo "${YELLOW}配置 $nova_conf 以使用 Neutron...${RESET}"

    crudini --set "$nova_conf" "neutron" "auth_url" "http://controller:5000"
    crudini --set "$nova_conf" "neutron" "auth_type" "password"
    crudini --set "$nova_conf" "neutron" "project_domain_name" "Default"
    crudini --set "$nova_conf" "neutron" "user_domain_name" "Default"
    crudini --set "$nova_conf" "neutron" "region_name" "RegionOne"
    crudini --set "$nova_conf" "neutron" "project_name" "service"
    crudini --set "$nova_conf" "neutron" "username" "neutron"
    crudini --set "$nova_conf" "neutron" "password" "$NEUTRON_PASS"

    echo "${GREEN}Nova 已成功配置为使用 Neutron。${RESET}"
}

# 重启相关服务
restart_openstack_services() {
    echo "${YELLOW}重启 Nova Compute 和 Neutron Open vSwitch agent 服务...${RESET}"
    sudo service nova-compute restart
    sudo service neutron-openvswitch-agent restart
    echo "${GREEN}服务重启完成。${RESET}"
}

# 主流程
setup_dns_with_systemd_resolved
install_neutron_ovs_agent
setup_neutron_conf
setup_ovs_agent_conf
setup_nova_conf_for_neutron
restart_openstack_services

echo "${GREEN}计算节点 OpenStack 网络（Neutron）配置完成。${RESET}"
