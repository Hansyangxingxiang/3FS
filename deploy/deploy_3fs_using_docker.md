# Deploy 3FS using Docker Guide

This section provides a manual deployment 3FS in Docker environments Guide

## Installation prerequisites

### Hardware specifications

| Node     | OS            | IP           | Memory | SSD        | RDMA  |
|----------|---------------|--------------|--------|------------|-------|
| meta       | Ubuntu 20.04  | 192.168.1.1  | 128GB  | -        | RoCE  |
| storage1   | Ubuntu 20.04  | 192.168.1.2  | 128GB  | 7TB × 2  | RoCE  |
| storage2   | Ubuntu 20.04  | 192.168.1.3  | 128GB  | 7TB × 2  | RoCE  |

> **RDMA Configuration**
> 1. Assign IP addresses to RDMA NICs. Multiple RDMA NICs (InfiniBand or RoCE) are supported on each node.
> 2. Check RDMA connectivity between nodes using `ib_write_bw`.

---
## Step 0: Build 3FS Docker images

   ### Follow the [instructions](../README.md#Check out source code) to check out source code

   ### Docker build with Ubuntu 20.04
   ```bash
   ./build.sh docker-ubuntu2004
   ```

   ### Build 3FS Docker images
   ```bash
   docker build -t hf3fs-monitor -f dockerfile/monitor.ubuntu2004.Dockerfile .
   docker build -t hf3fs-mgmtd -f dockerfile/mgmtd.ubuntu2004.Dockerfile .
   docker build -t hf3fs-meta -f dockerfile/meta.ubuntu2004.Dockerfile .
   docker build -t hf3fs-storage -f dockerfile/storage.ubuntu2004.Dockerfile .
   ```

### Node-Service Deployment Matrix

| Node       | Services |
|------------|---------------|
| Meta       |  clickHouse<br>foundationDB<br>monitor<br>mgmtd<br>meta<br>fuse|
| Storage1   |  storage<br>admin_cli |
| Storage2   |  storage<br>admin_cli |


---
## Step 1:  Deploy ClickHouse Service on Meta Node

   拉取镜像
   ```bash
   docker pull clickhouse/clickhouse-server:25.3.1.2703
   ```
   启动容器
   ```bash
   docker run -d  -p9000:9000 -e CLICKHOUSE_PASSWORD=3fs --name clickhouse-server --ulimit nofile=262144:262144 clickhouse/clickhouse-server:25.3.1.2703
   ```
---

## Step 2:  Deploy FoundationDB Service on Meta Node

   拉取镜像
   ```bash
   docker pull foundationdb/foundationdb:7.3.63
   ```
   启动容器
   ```bash
   docker run -d --privileged --network host -e FDB_NETWORKING_MODE=host --name foundationdb-server foundationdb/foundationdb:7.3.63
   ```

   登录容器
   ```bash
   docker exec -it foundationdb-server /bin/sh
   ```

   修改/var/fdb/.fdbenv 为实际的host IP，并把/var/fdb/scripts/fdb.bash中create_server_environment函数注释，如下：
   ```bash
   cat /var/fdb/.fdbenv
   export PUBLIC_IP=10.10.1.114

   cat /var/fdb/scripts/fdb.bash |grep create_server_environment
   #create_server_environment
   ```

   重启容器
   ```bash
   docker restart  foundationdb-server
   ```

   初始化单机数据库
   ```bash
   docker exec foundationdb-server /usr/bin/fdbcli -C /var/fdb/fdb.cluster --exec 'configure new single ssd'
   ```
   检查数据状态
   ```bash
   docker exec foundationdb-server /usr/bin/fdbcli -C /var/fdb/fdb.cluster --exec 'status'
   ```
---
## Step 3: Deploy Monitor Service on Meta Node
   ```bash
   docker run --name 3fs_monitor \
                  --privileged \
                  --network host \
                  -d --restart always \
                  --env CLUSTER_ID=${CLUSTER_ID} \
                  --env CLICKHOUSE_DB=${CLICKHOUSE_DB} \
                  --env CLICKHOUSE_HOST=${CLICKHOUSE_HOST} \
                  --env CLICKHOUSE_PASSWD=${CLICKHOUSE_PASSWD} \
                  --env CLICKHOUSE_PORT=${CLICKHOUSE_PORT} \
                  --env CLICKHOUSE_USER=${CLICKHOUSE_USER} \
                  --env FDB_CLUSTER=${FDB_CLUSTER} \
                  --env DEVICE_FILTER=${DEVICE_FILTER} \
                  ${IMAGE} \
   ```

---
## Step 4: Deploy Mgmtd Service on Meta Node
   ```bash
   docker run --name 3fs_mgmtd \
            --privileged \
            --network host \
            -d --restart always \
            --env CLUSTER_ID=${CLUSTER_ID} \
            --env FDB_CLUSTER=${FDB_CLUSTER} \
            --env MGMTD_NODE_ID=${MGMTD_NODE_ID} \
            --env DEVICE_FILTER=${DEVICE_FILTER} \
            --env REMOTE_IP=${REMOTE_IP} \
            ${IMAGE} 
   ```

---
## Step 5: Deploy Meta Service on Meta Node
   ```bash
   docker run  --name 3fs_meta \
               --privileged \
               -d --restart always \
               --network host \
               --env CLUSTER_ID=${CLUSTER_ID} \
               --env FDB_CLUSTER=${FDB_CLUSTER} \
               --env MGMTD_SERVER_ADDRESSES=${MGMTD_SERVER_ADDRESSES} \
               --env META_NODE_ID=${META_NODE_ID} \
               --env DEVICE_FILTER=${DEVICE_FILTER} \
               --env REMOTE_IP=${REMOTE_IP} \
               ${IMAGE} \
   ```

---
## Step 5: Deploy Storage Service on Storage1 Node
   ```bash
   docker  run --name 3fs_storage \
            --privileged \
            -d --restart always \
            --network host \
            -v /data/3fs:/3fs/data \
            --env CLUSTER_ID=${CLUSTER_ID} \
            --env FDB_CLUSTER=${FDB_CLUSTER} \
            --env MGMTD_SERVER_ADDRESSES=${MGMTD_SERVER_ADDRESSES} \
            --env STORAGE_NODE_ID=${STORAGE_NODE_ID} \
            --env TARGET_PATHS=${TARGET_PATHS} \
            --env DEVICE_FILTER=${DEVICE_FILTER} \
            --env REMOTE_IP=${REMOTE_IP} \
            ${IMAGE} \
   ```
---
## Step 6: Deploy Storage Service on Storage2 Node
   ```bash
   docker  run --name 3fs_storage \
            --privileged \
            -d --restart always \
            --network host \
            -v /data/3fs:/3fs/data \
            --env CLUSTER_ID=${CLUSTER_ID} \
            --env FDB_CLUSTER=${FDB_CLUSTER} \
            --env MGMTD_SERVER_ADDRESSES=${MGMTD_SERVER_ADDRESSES} \
            --env STORAGE_NODE_ID=${STORAGE_NODE_ID} \
            --env TARGET_PATHS=${TARGET_PATHS} \
            --env DEVICE_FILTER=${DEVICE_FILTER} \
            --env REMOTE_IP=${REMOTE_IP} \
            ${IMAGE} \
   ```

## Step 7: Create admin user, storage targets and chain table
1. Create an admin user:
   ```bash
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' "user-add --root --admin 0 root"
   ```
   The admin token is printed to the console, save it to `/opt/3fs/etc/token.txt`.
2. Generate `admin_cli` commands to create storage targets on 5 storage nodes (16 SSD per node, 6 targets per SSD).
   - Follow instructions at [here](data_placement/README.md) to install Python packages.
   ```bash
   pip install -r ~/3fs/deploy/data_placement/requirements.txt
   python ~/3fs/deploy/data_placement/src/model/data_placement.py \
      -ql -relax -type CR --num_nodes 5 --replication_factor 3 --min_targets_per_disk 6
   python ~/3fs/deploy/data_placement/src/setup/gen_chain_table.py \
      --chain_table_type CR --node_id_begin 10001 --node_id_end 10005 \
      --num_disks_per_node 16 --num_targets_per_disk 6 \
      --target_id_prefix 1 --chain_id_prefix 9 \
      --incidence_matrix_path output/DataPlacementModel-v_5-b_10-r_6-k_3-λ_2-lb_1-ub_1/incidence_matrix.pickle
   ```
   The following 3 files will be generated in `output` directory: `create_target_cmd.txt`, `generated_chains.csv`, and `generated_chain_table.csv`.
3. Create storage targets:
   ```bash
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") < output/create_target_cmd.txt
   ```
4. Upload chains to mgmtd service:
   ```bash
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chains output/generated_chains.csv"
   ```
5. Upload chain table to mgmtd service:
    ```bash
    /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chain-table --desc stage 1 output/generated_chain_table.csv"
    ```
6. List chains and chain tables to check if they have been correctly uploaded:
   ```bash
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' "list-chains"
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://192.168.1.1:8000"]' "list-chain-tables"
   ```
---
## Step 8: Deploy fuse client on Meta Node
   ```bash
   docker run --name 3fs_fuse_container \
            --privileged \
            -d --restart always \
            --network host \
            --mount type=bind,source=/mnt/3fs,target=/mnt/3fs,bind-propagation=shared \
            --env CLUSTER_ID=${CLUSTER_ID} \
            --env FDB_CLUSTER=${FDB_CLUSTER} \
            --env MGMTD_SERVER_ADDRESSES=${MGMTD_SERVER_ADDRESSES} \
            --env REMOTE_IP=${REMOTE_IP} \
            --env DEVICE_FILTER=${DEVICE_FILTER} \
            --env TOKEN=${TOKEN} \
            ${IMAGE} \
   ```

