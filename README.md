# Vault Cluster Setup

This repository contains the necessary files and scripts to set up and manage a HashiCorp Vault cluster. The provided Makefile automates the process of configuring and deploying Vault nodes.

## Prerequisites

Ensure you have sshpass installed for password-based SSH operations. An environment file (ENV_FILE) containing the necessary environment variables is required.

## Environment File
The `ENV_FILE` should define the following variables:

- `REGION:` The region of the deployment.
- `DOMAIN:` The domain used in the configuration.
- `NODE_1_IP:` The IP address of the first node.
- `NODE_2_IP:` The IP address of the second node.
- `NODE_3_IP:` The IP address of the third node.

## Environment Variables (Secrets)
`ROOT_PASSWORD:` The root password for SSH access.

## Cluster Creation Steps
1. Define `ENV_FILE` and `ROOT_PASSWORD` environment variables locally:
```
*export ENV_FILE="environments/joburg.env"*
*export ROOT_PASSWORD="12345"*
```
2. Create `Ubuntu` user on the remote VMs: This will create the Ubuntu user and copy the admin SSH public key to the VMs to enable interaction using the Ubuntu user. `This step only needs to be executed once.`

```
make create-ubuntu-user
```

3. Set up `admin access` on the VMs: This will copy the admin local SSH public key to all VMs, enabling interaction with the VMs using the root user. `This step only needs to be executed once.`
```
make setup-admin-access
```

4. Generate `SSH keys` on the VMs: This will generate SSH keys for the VMs and copy them between the VMs. This is required for file transfer between the VMs, such as TLS certificates, root token, and unseal keys.
```
make generate-ssh-keys
```

5. Create the `Vault cluster`: This will create the necessary configs, install Vault, and configure the cluster on all VMs.
```
make create-cluster
```

After completing the above steps, you should be able to access Vault at: `https://vault.<region>.example.com:8200/ui/`

## Helpful Make Targets

Use the following targets to interact with the VMs for specific tasks such as creating config files, setting up the Vault cluster, or cleaning a specific node:

- Create necessary configs for only `vault-1` node:
```
make create-config-vault-1
```
- Create necessary configs for `all` VMs:
```
make create-config-vault
```
- Install Vault and configure the cluster for only `vault-1` node:
```
make setup-vault-1
```
- Install Vault and configure the cluster for `all` VMs:
```
make setup-vault
```
- Stop the Vault service and remove all configs and folders on only `vault-1` node:
```
make clean-vault-1
```
- Stop the Vault service and remove all configs and folders on `all` VMs:
```
make clean-vault
```
## Backup and Restore

We take backups every day at 00:01. A backup script is available at `/opt/vault/backup.sh` to backup the Vault data. It also checks and deletes backups older than `7 days`. Backups are stored under the `/vault-backup/` folder, and backup logs are saved in `/vault-backup/backup.log`.

- To create a manual backup, run:
```
bash /opt/vault/backup.sh
```
- To restore data from a backup file, use:
```
vault operator raft snapshot restore <path-to-backup>
```

### Script Details

The backup script performs the following tasks:
1. Checks if the current node is the leader node.
2. If the current node is the leader:
   - Creates a snapshot and saves it under `/vault-backup/`.
   - Copies the snapshot to other nodes in the cluster.
3. Independently on all nodes:
   - Checks and deletes snapshots older than 7 days.
   - Keeps up to 7 snapshots.
