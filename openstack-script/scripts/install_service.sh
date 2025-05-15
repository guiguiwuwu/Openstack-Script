#!/bin/bash

# 从 config.ini 加载配置
source config.ini

# 存储已安装服务的文件
STATUS_FILE="services_status.log"

# 如果状态文件不存在则初始化
if [[ ! -f $STATUS_FILE ]]; then
    touch $STATUS_FILE
fi

# 检查服务是否已安装
is_installed() {
    grep -q "$1" "$STATUS_FILE"
}

# 标记服务为已安装
mark_installed() {
    echo "$1" >> "$STATUS_FILE"
}

# 显示服务状态
service_status() {
    if is_installed "$1"; then
        echo "${GREEN}(已安装)${RESET}"
    else
        echo "${YELLOW}(未安装)${RESET}"
    fi
}

# 控制节点服务安装函数
install_controller() {
    echo "请选择要在控制节点安装的服务（如：1 2 或 1-4）："
    echo "1) 环境设置 $(service_status "Controller-1")"
    echo "2) Keystone $(service_status "Controller-2")"
    echo "3) Glance $(service_status "Controller-3")"
    echo "4) Placement $(service_status "Controller-4")"
    echo "5) Nova $(service_status "Controller-5")"
    echo "6) Neutron $(service_status "Controller-6")"
    echo "7) Horizon $(service_status "Controller-7")"
    echo "8) Cinder $(service_status "Controller-8")"
    echo "9) 实例预启动 $(service_status "Controller-9")"
    echo "A) 全部"
    read -p "请输入你的选择: " service_choice

    install_service() {
        if is_installed "Controller-$1"; then
            echo "服务 $1 已安装。"
        else
            case $1 in
                1) ./controller/ctl_02_env_setup.sh ;;
                2) ./controller/ctl_03_keystone_install.sh ;;
                3) ./controller/ctl_04_glance_install.sh ;;
                4) ./controller/ctl_05_placement_install.sh ;;
                5) ./controller/ctl_06_nova_install.sh ;;
                6) ./controller/ctl_07_neutron_install.sh ;;
                7) ./controller/ctl_08_horizon_install.sh ;;
                8) ./controller/ctl_09_cinder_install.sh ;;
                9) ./controller/ctl_10_pre_launch_instance.sh ;;
                *) echo "无效的服务编号: $1" ;;
            esac
            mark_installed "Controller-$1"
        fi
    }

    if [[ "$service_choice" =~ ^[Aa]$ ]]; then
        for i in {1..9}; do
            install_service "$i"
        done
    else
        IFS=' ' read -r -a choices <<< "$service_choice"
        for choice in "${choices[@]}"; do
            if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r start end <<< "$choice"
                for ((i=start; i<=end; i++)); do
                    install_service "$i"
                done
            else
                install_service "$choice"
            fi
        done
    fi

    echo "控制节点服务安装完成。"
}

# 计算节点服务安装函数
install_compute() {
    echo "请选择要在计算节点安装的服务（如：1 2 或 1-2）："
    echo "1) 环境设置 $(service_status "Compute-1")"
    echo "2) Nova $(service_status "Compute-2")"
    echo "3) Neutron $(service_status "Compute-3")"
    echo "A) 全部"
    read -p "请输入你的选择: " service_choice

    install_service() {
        if is_installed "Compute-$1"; then
            echo "服务 $1 已安装。"
        else
            case $1 in
                1) ./compute/cp_02_env_setup.sh ;;
                2) ./compute/cp_03_nova_install.sh ;;
                3) ./compute/cp_04_neutron_install.sh ;;
                *) echo "无效的服务编号: $1" ;;
            esac
            mark_installed "Compute-$1"
        fi
    }

    if [[ "$service_choice" =~ ^[Aa]$ ]]; then
        for i in {1..3}; do
            install_service "$i"
        done
    else
        IFS=' ' read -r -a choices <<< "$service_choice"
        for choice in "${choices[@]}"; do
            if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r start end <<< "$choice"
                for ((i=start; i<=end; i++)); do
                    install_service "$i"
                done
            else
                install_service "$choice"
            fi
        done
    fi

    echo "计算节点服务安装完成。"
}

# 存储节点服务安装函数
install_storage() {
    echo "请选择要在存储节点安装的服务（如：1 或 A 全部）："
    echo "1) 环境设置 $(service_status "Storage-1")"
    echo "2) Cinder $(service_status "Storage-2")"
    echo "A) 全部"
    read -p "请输入你的选择: " service_choice

    install_service() {
        if is_installed "Storage-$1"; then
            echo "服务 $1 已安装。"
        else
            case $1 in
                1) ./block/blk_01_env_setup.sh ;;
                2) ./block/blk_02_cinder.sh ;;
                *) echo "无效的服务编号: $1" ;;
            esac
            mark_installed "Storage-$1"
        fi
    }

    if [[ "$service_choice" =~ ^[Aa]$ ]]; then
        for i in {1..2}; do
            install_service "$i"
        done
    else
        IFS=' ' read -r -a choices <<< "$service_choice"
        for choice in "${choices[@]}"; do
            if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r start end <<< "$choice"
                for ((i=start; i<=end; i++)); do
                    install_service "$i"
                done
            else
                install_service "$choice"
            fi
        done
    fi

    echo "存储节点服务安装完成。"
}

# 监控节点服务安装函数
install_monitor() {
    echo "请选择要在监控节点安装的服务（如：1 或 A 全部）："
    echo "1) 环境设置 $(service_status "Monitor-1")"
    echo "2) Openstack exporter $(service_status "Monitor-2")"
    echo "3) Prometheus $(service_status "Monitor-3")"
    echo "4) Grafana $(service_status "Monitor-4")"
    echo "5) Alertmanager $(service_status "Monitor-5")"
    echo "A) 全部"
    read -p "请输入你的选择: " service_choice

    install_service() {
        if is_installed "Monitor-$1"; then
            echo "服务 $1 已安装。"
        else
            case $1 in
                1) ./monitor/mon_01_env.sh ;;
                2) ./monitor/mon_02_openstack_exporter.sh ;;
                3) ./monitor/mon_03_prometheus.sh ;;
                4) ./monitor/mon_04_grafana.sh ;;
                5) ./monitor/mon_05_alertmanager.sh ;;
                *) echo "无效的服务编号: $1" ;;
            esac
            mark_installed "Monitor-$1"
        fi
    }

    if [[ "$service_choice" =~ ^[Aa]$ ]]; then
        for i in {1..5}; do
            install_service "$i"
        done
    else
        IFS=' ' read -r -a choices <<< "$service_choice"
        for choice in "${choices[@]}"; do
            if [[ "$choice" =~ ^[0-9]+-[0-9]+$ ]]; then
                IFS='-' read -r start end <<< "$choice"
                for ((i=start; i<=end; i++)); do
                    install_service "$i"
                done
            else
                install_service "$choice"
            fi
        done
    fi

    echo "监控节点服务安装完成。"
}

# 主流程
echo "请选择要安装的节点："
echo "1) 控制节点"
echo "2) 计算节点"
echo "3) 存储节点"
echo "4) 监控节点"
read -p "请输入节点编号: " node_choice

case $node_choice in
    1) install_controller ;;
    2) install_compute ;;
    3) install_storage ;;
    4) install_monitor ;;
    *) echo "无效选择，退出。" ;;
esac

echo "安装流程结束。"
