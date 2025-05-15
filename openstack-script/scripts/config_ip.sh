#!/bin/bash

# 加载配置文件
source config.ini

# 设置主机名
set_hostname() {
    local var_name="$1"
    local new_hostname="${!var_name}"
    if [ -n "$new_hostname" ]; then
        echo -e "${YELLOW}正在将主机名更改为 ${GREEN}$new_hostname${RESET}..."

        # 更新 /etc/hostname
        echo "$new_hostname" | sudo tee /etc/hostname > /dev/null

        # 更新 /etc/hosts，替换旧主机名为新主机名，并注释掉 127.0.1.1 行
        local current_hostname
        current_hostname=$(hostname)
        sudo sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
        sudo sed -i "s/^127.0.1.1/#127.0.1.1/" /etc/hosts

        # 应用新主机名
        sudo hostnamectl set-hostname "$new_hostname"
        echo -e "${GREEN}主机名已更改为 $new_hostname。${RESET}"
    else
        echo -e "${RED}config.cfg 中未设置主机名变量，跳过主机名更改。${RESET}"
    fi
}

# 更新 /etc/hosts 文件，添加自定义主机条目
append_hosts_entries() {
    echo -e "${YELLOW}正在更新 /etc/hosts ...${RESET}"

    if [ -n "$CTL_MANAGEMENT" ] && [ -n "$CTL_HOSTNAME" ] && \
       [ -n "$COM_MANAGEMENT" ] && [ -n "$COM_HOSTNAME" ] && \
       [ -n "$BLK_MANAGEMENT" ] && [ -n "$BLK_HOSTNAME" ] && \
       [ -n "$MON_MANAGEMENT" ] && [ -n "$MON_HOSTNAME" ]; then

        sudo tee -a /etc/hosts > /dev/null << EOF

# 自定义主机条目
$CTL_MANAGEMENT $CTL_HOSTNAME
$COM_MANAGEMENT $COM_HOSTNAME
$BLK_MANAGEMENT $BLK_HOSTNAME
$MON_MANAGEMENT $MON_HOSTNAME
EOF
        echo -e "${GREEN}/etc/hosts 已成功更新。${RESET}"
    else
        echo -e "${RED}config.cfg 中缺少必要变量，跳过 hosts 文件更新。${RESET}"
    fi
}

# 修改 netplan 配置文件中的 IP 地址
update_netplan_ip() {
    local mgmt_ip_var="$1"
    local prov_ip_var="$2"
    local mgmt_ip="${!mgmt_ip_var}"
    local prov_ip="${!prov_ip_var}"

    # 查找 netplan 配置文件
    local netplan_file
    netplan_file=$(find /etc/netplan/ -type f -name "*.yaml" | head -n 1)

    if [ -z "$netplan_file" ]; then
        echo -e "${RED}错误：未找到 netplan 配置文件。${RESET}"
        exit 1
    fi

    if [ -n "$mgmt_ip" ] && [ -n "$prov_ip" ]; then
        echo -e "${YELLOW}正在更新 IP 配置...${RESET}"

        cat << EOF | sudo tee "$netplan_file" > /dev/null
network:
  ethernets:
    $INTERFACE_MANAGEMENT:
      dhcp4: no
      addresses:
        - ${mgmt_ip}/${NETMASK}

    $INTERFACE_PROVIDER:
      dhcp4: no
      addresses:
        - ${prov_ip}/${NETMASK}
      routes:
        - to: 0.0.0.0/0
          via: ${GW_PROVIDER}
      nameservers:
        addresses:
          - 223.5.5.5

  version: 2
EOF

        sudo netplan apply
        echo -e "${GREEN}IP 配置已成功更新。${RESET}"
    else
        echo -e "${RED}config.cfg 中缺少 IP 地址或网关，跳过 IP 配置。${RESET}"
    fi
}

# 主流程：节点选择与配置
echo "请选择要配置的节点："
echo "1) 控制节点 (Controller)"
echo "2) 计算节点 (Compute)"
echo "3) 块存储节点 (Block Storage)"
echo "4) 监控节点 (Monitor)"
read -p "请输入对应节点的数字: " node_choice

case $node_choice in
    1)
        set_hostname CTL_HOSTNAME
        update_netplan_ip CTL_MANAGEMENT CTL_PROVIDER
        ;;
    2)
        set_hostname COM_HOSTNAME
        update_netplan_ip COM_MANAGEMENT COM_PROVIDER
        ;;
    3)
        set_hostname BLK_HOSTNAME
        update_netplan_ip BLK_MANAGEMENT BLK_PROVIDER
        ;;
    4)
        set_hostname MON_HOSTNAME
        update_netplan_ip MON_MANAGEMENT MON_PROVIDER
        ;;
    *)
        echo -e "${RED}无效选择，脚本退出。${RESET}"
        exit 1
        ;;
esac

append_hosts_entries

sudo reboot

echo -e "${GREEN}所有任务已完成。${RESET}"
