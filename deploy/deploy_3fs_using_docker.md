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

| Node       | IP          | Services  |
|------------|-------------|-----------|
| Meta       | 192.168.1.1 | clickHouse<br>foundationDB<br>monitor<br>mgmtd<br>meta<br>fuse|
| Storage1   | 192.168.1.2 | storage<br>admin_cli |
| Storage2   | 192.168.1.3 | storage<br>admin_cli |


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
   docker run --name hf3fs-monitor \
                  --privileged \
                  --network host \
                  -d --restart always \
                  --env CLICKHOUSE_DB=3fs \
                  --env CLICKHOUSE_HOST=10.10.1.144 \
                  --env CLICKHOUSE_PASSWD=3fs \
                  --env CLICKHOUSE_PORT=9000 \
                  --env CLICKHOUSE_USER=default \
                  --env DEVICE_FILTER=mlx5_2 \
                  hf3fs-monitor 
   ```

---
## Step 4: Deploy Mgmtd Service on Meta Node
   ```bash
   docker run --name hf3fs-mgmtd \
            --privileged \
            --network host \
            -d --restart always \
            --env CLUSTER_ID=stage \
            --env FDB_CLUSTER=docker:docker@10.10.1.144:4500 \
            --env MGMTD_NODE_ID=1 \
            --env DEVICE_FILTER=mlx5_2 \
            --env REMOTE_IP=10.10.1.114:10000 \
            hf3fs-mgmtd
   ```

---
## Step 5: Deploy Meta Service on Meta Node
   ```bash
   docker run  --name 3fs_meta \
               --privileged \
               -d --restart always \
               --network host \
               --env CLUSTER_ID=stage \
               --env FDB_CLUSTER=docker:docker@10.10.1.144:4500 \
               --env MGMTD_SERVER_ADDRESSES=RDMA://10.10.1.114:8000 \
               --env META_NODE_ID=100 \
               --env DEVICE_FILTER=mlx5_2 \
               --env REMOTE_IP=10.10.1.114:10000 \
               hf3fs-meta
   ```

---
## Step 5: Deploy Storage Service on Storage1 Node
   Format the attached 2 SSDs as XFS and mount at /storage/data{0..1}, then create data directories /storage/data{0..1}/3fs
   ```bash
      mkdir -p /storage/data{0..1}
      for i in {0..1};do mkfs.xfs -L data${i} -s size=4096 /dev/nvme${i}n1;mount -o noatime,nodiratime -L data${i} /storage/data${i};done
      mkdir -p /storage/data{0..1}/3fs
   ```

   ```bash
   docker  run --name hf3fs-storage \
            --privileged \
            -d --restart always \
            --network host \
            -v /storage:/storage \
            --env CLUSTER_ID=stage \
            --env FDB_CLUSTER=docker:docker@10.10.1.144:4500 \
            --env MGMTD_SERVER_ADDRESSES=RDMA://10.10.1.114:8000 \
            --env STORAGE_NODE_ID=10001 \
            --env TARGET_PATHS='/storage/data0/3fs,/storage/data0/3fs' \
            --env DEVICE_FILTER=mlx5_2 \
            --env REMOTE_IP=10.10.1.114:10000 \
            hf3fs-storage
   ```
---
## Step 6: Deploy Storage Service on Storage2 Node
   Format the attached 2 SSDs as XFS and mount at /storage/data{0..1}, then create data directories /storage/data{0..1}/3fs
   ```bash
      mkdir -p /storage/data{0..1}
      for i in {0..1};do mkfs.xfs -L data${i} -s size=4096 /dev/nvme${i}n1;mount -o noatime,nodiratime -L data${i} /storage/data${i};done
      mkdir -p /storage/data{0..1}/3fs
   ```
   ```bash
   docker  run --name hf3fs-storage \
            --privileged \
            -d --restart always \
            --network host \
            -v /storage:/storage \
            --env CLUSTER_ID=stage \
            --env FDB_CLUSTER=docker:docker@10.10.1.144:4500 \
            --env MGMTD_SERVER_ADDRESSES=RDMA://10.10.1.114:8000 \
            --env STORAGE_NODE_ID=10002 \
            --env TARGET_PATHS='/storage/data0/3fs,/storage/data0/3fs' \
            --env DEVICE_FILTER=mlx5_2 \
            --env REMOTE_IP=10.10.1.114:10000 \
            hf3fs-storage
   ```

## Step 7: Create admin user, storage targets and chain table

1. Generate `admin_cli` commands to create storage targets on 2 storage nodes (2 SSD per node, 6 targets per SSD).
   - Follow instructions at [here](data_placement/README.md) to install Python packages.
   ```bash
   pip install -r ~/3fs/deploy/data_placement/requirements.txt
   python ~/3fs/deploy/data_placement/src/model/data_placement.py \
      -ql -relax -type CR --num_nodes 2 --replication_factor 2 --min_targets_per_disk 6
   python ~/3fs/deploy/data_placement/src/setup/gen_chain_table.py \
      --chain_table_type CR --node_id_begin 10001 --node_id_end 10002 \
      --num_disks_per_node 2 --num_targets_per_disk 6 \
      --target_id_prefix 1 --chain_id_prefix 9 \
      --incidence_matrix_path output/DataPlacementModel-v_2-b_6-r_6-k_3-λ_2-lb_1-ub_1/incidence_matrix.pickle
   ```
   The following 3 files will be generated in `output` directory: `create_target_cmd.txt`, `generated_chains.csv`, and `generated_chain_table.csv`. Then copy these 3 files into the mgmtd Docker container

   ```bash
  docker cp output/create_target_cmd.txt hf3fs-mgmtd:/opt/3fs/etc/
  docker cp output/generated_chains.csv hf3fs-mgmtd:/opt/3fs/etc/
  docker cp output/generated_chain_table.csv hf3fs-mgmtd:/opt/3fs/etc/
   ```

2. Create an admin user:

   ```bash
   docker exec -it hf3fs-mgmtd /bin/sh
   ```
   Login mgmtd docker container

   ```bash
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' "user-add --root --admin 0 root"
   ```

   ```bash
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' "user-add --root --admin 0 root"
   ```
   The admin token is printed to the console, save it to `/opt/3fs/etc/token.txt`.

3. Create storage targets:
   ```bash
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") < output/create_target_cmd.txt
   ```
4. Upload chains to mgmtd service:
   ```bash
   /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chains output/generated_chains.csv"
   ```
5. Upload chain table to mgmtd service:
    ```bash
    /opt/3fs/bin/admin_cli --cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' --config.user_info.token $(<"/opt/3fs/etc/token.txt") "upload-chain-table --desc stage 1 output/generated_chain_table.csv"
    ```
6. List chains and chain tables to check if they have been correctly uploaded:
   ```bash
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' "list-chains"
   /opt/3fs/bin/admin_cli -cfg /opt/3fs/etc/admin_cli.toml --config.mgmtd_client.mgmtd_server_addresses '["RDMA://10.10.1.144:8000"]' "list-chain-tables"
   ```
---
## Step 8: Deploy fuse client on Meta Node
   ```bash
   docker run --name hf3fs-fuse \
            --privileged \
            -d --restart always \
            --network host \
            --mount type=bind,source=/mnt/3fs,target=/mnt/3fs,bind-propagation=shared \
            --env CLUSTER_ID=stage} \
            --env FDB_CLUSTER=docker:docker@10.10.1.144:4500 \
            --env MGMTD_SERVER_ADDRESSES=RDMA://10.10.1.114:8000 \
            --env REMOTE_IP=10.10.1.114:10000 \
            --env DEVICE_FILTER=mlx5_2 \
            --env TOKEN=${TOKEN} \
           hf3fs-fuse
   ```

   Check if 3FS has been mounted at /3fs/stage
   ```bash
   mount | grep '/3fs/stage'
   ```

