#!/bin/bash

# 从配置文件加载变量
source config.ini

# 设置阿里云APT源
set_aliyun_apt_source() {
    echo "${YELLOW}正在设置阿里云APT源...${RESET}"
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    sudo tee /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs) main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-backports main restricted universe multiverse
EOF
    sudo apt-get update -y
    echo "${GREEN}阿里云APT源设置完成。${RESET}"
}


# 禁用swap
disable_swap() {
    echo "${YELLOW}正在禁用swap...${RESET}"
    sudo swapoff -a
    sudo sudo sed -i '/swap/s/^/#/' /etc/fstab
    echo "${GREEN}swap已禁用。${RESET}"
}

# 禁用防火墙
disable_firewall() {
    echo "${YELLOW}正在禁用防火墙...${RESET}"
    sudo systemctl stop ufw || sudo systemctl stop firewalld
    sudo systemctl disable ufw || sudo systemctl disable firewalld
    echo "${GREEN}防火墙已禁用。${RESET}"
}

# 更新和升级控制节点
update_and_upgrade_controller() {
    echo "${YELLOW}正在更新和升级控制节点...${RESET}"
    sudo apt-get update -y && sudo apt-get upgrade -y
    echo "${GREEN}控制节点更新和升级完成。${RESET}"
}

# 添加 OpenStack Caracal 仓库
add_openstack_repository() {
    echo "${YELLOW}正在添加 OpenStack Caracal 仓库...${RESET}"
    sudo add-apt-repository cloud-archive:caracal -y
    echo "${GREEN}仓库添加成功。${RESET}"
}

# 安装 crudini 工具
install_crudini_tool() {
    echo "${YELLOW}正在安装 crudini...${RESET}"
    sudo apt install -y crudini
    echo "${GREEN}crudini 安装成功。${RESET}"
}

# 安装 OpenStack 客户端
install_openstack_client() {
    echo "${YELLOW}正在安装 OpenStack 客户端...${RESET}"
    sudo apt-get install -y python3-openstackclient
    echo "${GREEN}OpenStack 客户端安装成功。${RESET}"
}

# 安装并配置 MariaDB 数据库
configure_mariadb() {
    echo "${YELLOW}正在安装和配置 MariaDB...${RESET}"
    sudo apt install -y mariadb-server python3-pymysql

    local mariadb_conf="/etc/mysql/mariadb.conf.d/99-openstack.cnf"
    # 配置 MariaDB 参数
    crudini --set "$mariadb_conf" "mysqld" "bind-address" "$CTL_MANAGEMENT"
    crudini --set "$mariadb_conf" "mysqld" "default-storage-engine" "innodb"
    crudini --set "$mariadb_conf" "mysqld" "innodb_file_per_table" "on"
    crudini --set "$mariadb_conf" "mysqld" "max_connections" "4096"
    crudini --set "$mariadb_conf" "mysqld" "collation-server" "utf8_general_ci"
    crudini --set "$mariadb_conf" "mysqld" "character-set-server" "utf8"

    # 重启并安全配置 MariaDB
    echo "${YELLOW}正在重启 MariaDB...${RESET}"
    sudo service mysql restart
    echo "${YELLOW}正在执行 MariaDB 安全配置...${RESET}"
    sudo mysql_secure_installation
    echo "${GREEN}MariaDB 配置完成。${RESET}"
}

# 安装并配置 RabbitMQ 消息队列
configure_rabbitmq() {
    echo "${YELLOW}正在安装和配置 RabbitMQ...${RESET}"
    sudo apt install -y rabbitmq-server

    # 配置 RabbitMQ 用户和权限
    sudo rabbitmqctl add_user openstack $RABBIT_PASS
    sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
    echo "${GREEN}RabbitMQ 配置完成。${RESET}"
}

# 安装并配置 Memcached 缓存服务
configure_memcached() {
    echo "${YELLOW}正在安装和配置 Memcached...${RESET}"
    sudo apt install -y memcached python3-memcache

    # 修改监听地址
    sudo sed -i "s/^-l 127.0.0.1/-l $CTL_MANAGEMENT/" /etc/memcached.conf

    # 重启 Memcached 服务
    sudo service memcached restart
    echo "${GREEN}Memcached 配置完成。${RESET}"
}

# 安装并配置 Chrony NTP 服务
configure_chrony_ntp() {
    echo "${YELLOW}正在安装和配置 Chrony...${RESET}"
    sudo apt install -y chrony

    # 删除默认的 NTP 服务器配置
    local chrony_conf="/etc/chrony/chrony.conf"
    sudo sed -i '/^pool /d;/^server /d' $chrony_conf

    # 添加阿里云NTP服务器
    echo "server ntp.aliyun.com iburst" | sudo tee -a $chrony_conf

    # 允许管理网段同步时间
    echo "allow $MANAGEMENT_NW/24" | sudo tee -a $chrony_conf

    # 重启 Chrony 服务
    sudo service chrony restart
    echo "${GREEN}Chrony 配置完成。${RESET}"
}

# 按顺序执行所有配置函数
set_aliyun_apt_source
disable_swap
disable_firewall
update_and_upgrade_controller
add_openstack_repository
install_crudini_tool
install_openstack_client
configure_chrony_ntp
configure_mariadb
configure_rabbitmq
configure_memcached

echo "${GREEN}所有组件安装和配置完成。${RESET}"
