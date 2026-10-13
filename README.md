# MySQL 8.4 InnoDB Cluster Lab

## 1. Overview

- This project deploys a two-node Oracle MySQL InnoDB Cluster using **Vagrant, AlmaLinux 9, Ansible, and MySQL Shell**.

- The cluster uses Group Replication in Multi-Primary mode, allowing both nodes to accept read and write operations.

### Infrastructure

```bash
Component                     Configuration
Operating system              AlmaLinux 9
MySQL Server                  8.4.11
MySQL Shell                   8.4.10
Cluster name                  MySQLInnoDBCluster
Topology                      Multi-primary
Communication stack           MYSQL
MySQL port                    3306
Group communication port      33061

### Cluster nodes

| Node                    |IP address|             |Server ID|

| Master |                 |192.168.1.130|            | 1 |
| Worker |                 |192.168.1.131 |           | 2 |

### Important project files

- `Vagrantfile` — defines the virtual machines and networking.
- `inventory.ini` — defines the Ansible hosts and connection settings.
- `startupmysqlcluster.sh` — starts the VMs and runs the deployment playbook.
- `deploy_mysql_cluster.yml` — orchestrates MySQL installation and cluster creation or recovery.
- `roles/install_mysql_innodb_cluster/` — contains the Ansible role.
- `roles/install_mysql_innodb_cluster/templates/mysqld.cnf.j2` — configures MySQL.
- `roles/install_mysql_innodb_cluster/templates/configure_instance.js.j2` — configures each MySQL instance for InnoDB Cluster.
- `roles/install_mysql_innodb_cluster/templates/create_cluster.js.j2` — creates, verifies, and recovers the cluster.
- `vars/mysql_cluster_vault.yml` — stores encrypted deployment credentials.

## 2. Deploying and managing the VMs

Run commands from the project directory in WSL.

### Initial deployment

```bash
cd ~/Downloads/lab
./startupmysqlcluster.sh

vagrant.exe halt                                            | To halt the VMs / Cluster
vagrant.exe up                                              | Would bring up the cluster / VMs.
```

The master has a systemd service named `mysql-innodb-cluster-recovery.service`. It runs the persistent `/root/create_cluster.js` script during boot to recover the existing cluster when required.

## 3. Connecting to MySQL

MySQL Shell (`mysqlsh`) is used to connect to the database and administer the cluster.

### Connect to the master in SQL mode

```bash
mysqlsh --uri icadmin@192.168.1.130:3306 --sql              | Used to connect via icadmin, can only read but not write.
mysql -uroot -p                                             | Used to connect via root.
```

Enter the cluster administrator password when prompted.

## 4. Checking cluster health

Connect to the master in JavaScript mode:

Run:

```bash
ssh -i .vagrant/machines/np-mysql-lvmv9-master001/virtualbox/private_key \
  -o StrictHostKeyChecking=no \
  vagrant@192.168.1.130 \
  'sudo systemctl status mysql-innodb-cluster-recovery.service --no-pager;
   sudo journalctl -u mysql-innodb-cluster-recovery.service -b --no-pager -n 80'
```

```javascript
sudo mysqlsh --js --interactive

shell.connect({user: "icadmin", host: "localhost", port: 3306});
var cluster = dba.getCluster("labInnoDBCluster");
cluster.status({extended: 1});                                                          | Would output the status of the cluster if its online and set as primary.

/sql                                                                                    | to change to sql terminal.
```

A successful result should show:

- Both `192.168.1.130:3306` and `192.168.1.131:3306` as `ONLINE`.
- Both nodes operating in `R/W` mode.
- Multi-Primary topology enabled.

- A cluster status of `OK_NO_TOLERANCE` means the cluster is online but cannot tolerate another member failure with the current two-member topology. It is not the same as a cluster being offline.

### 5.1 Check whether MySQL is running

Run on each VM:

```bash
sudo systemctl is-enabled mysqld
sudo systemctl is-active mysqld
sudo systemctl status mysqld --no-pager
```

Expected results are `enabled` and `active`.

View MySQL service logs:

```bash
sudo journalctl -u mysqld -b --no-pager -n 100
sudo tail -n 100 /var/log/mysqld.log
```

### 7.2 Checking the automatic recovery service

Run on the master:

```bash
sudo systemctl is-enabled mysql-innodb-cluster-recovery.service
sudo systemctl is-active mysql-innodb-cluster-recovery.service
sudo systemctl status mysql-innodb-cluster-recovery.service --no-pager
```

### 7.3 Check important MySQL configuration variables

Run on each VM:

```bash
sudo mysql -uroot -p -e "
SHOW GLOBAL VARIABLES
WHERE Variable_name IN (
  'group_replication_start_on_boot',
  'group_replication_ssl_mode',
  'group_replication_communication_stack',
  'group_replication_recovery_use_ssl',
  'require_secure_transport',
  'bind_address',
  'port'
);
- Sample output
+---------------------------------------+----------+
| Variable_name                         | Value    |
+---------------------------------------+----------+
| bind_address                          | 0.0.0.0  |
| group_replication_communication_stack | MYSQL    |
| group_replication_recovery_use_ssl    | ON       |
| group_replication_ssl_mode            | REQUIRED |
| group_replication_start_on_boot       | ON       |
| port                                  | 3306     |
| require_secure_transport              | OFF      |
+---------------------------------------+----------+
"
```

## Command to SSH into VMs

```bash
ssh -i .vagrant/machines/np-mysql-lvmv9-master001/virtualbox/private_key \
  -o StrictHostKeyChecking=no \
  vagrant@192.168.1.130

ssh -i .vagrant/machines/np-mysql-lvmv9-worker001/virtualbox/private_key \
  -o StrictHostKeyChecking=no \
  vagrant@192.168.1.131

mysql_config_editor set \
  --login-path=icadmin \
  --host=localhost \
  --user=icadmin \
  --password                                                    | Used to set your log in path

mysql -uroot -p
mysql -uicadmin -p
mysql --login-path=icadmin / root                                      | Would not prompt for password

mysql_config_editor print --all                                        | Would list all configured users/credentials
sudo mysqlsh --js --interactive

shell.connect({user: "icadmin", host: "localhost", port: 3306});
var cluster = dba.getCluster("labInnoDBCluster");
cluster.status({extended: 1});     
```
