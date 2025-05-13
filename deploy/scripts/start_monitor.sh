#!/bin/bash
source "$(dirname "$0")/_3fs_common.sh"

function run_monitor() { 
    if [[ ! -f "$CONFIG_DONE_FLAG" ]]; then
        config_cluster_id
        # env: CLICKHOUSE_DB, CLICKHOUSE_HOST, CLICKHOUSE_PASSWD, CLICKHOUSE_PORT, CLICKHOUSE_USER, DEVICE_FILTER, CLUSTER_ID
        # monitor_collector_main.toml
        sed -i "/^\[server.monitor_collector.reporter.clickhouse\]/,/^\s*$/{
        s/db = '.*/db = '${CLICKHOUSE_DB}'/;
        s/host = '.*/host = '${CLICKHOUSE_HOST}'/;
        s/passwd = '.*/passwd = '${CLICKHOUSE_PASSWD}'/;
        s/port = '.*/port = '${CLICKHOUSE_PORT}'/;
        s/user = '.*/user = '${CLICKHOUSE_USER}'/;
        }" /opt/3fs/etc/monitor_collector_main.toml
        # device_filter if set
        if [[ -n "${DEVICE_FILTER}" ]]; then
            sed -i "s|device_filter = \[\]|device_filter = [\"${DEVICE_FILTER//,/\",\"}\"]|g" /opt/3fs/etc/monitor_collector_main.toml
        fi

        touch "$CONFIG_DONE_FLAG"
    fi
    # run monitor
    /opt/3fs/bin/monitor_collector_main --cfg /opt/3fs/etc/monitor_collector_main.toml
}


run_monitor
