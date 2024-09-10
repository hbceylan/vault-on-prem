#!/bin/bash

# Load environment variables
. /home/ubuntu/.profile

set -e

# Ensure region and domain are provided
if [ -z "$VAULT_REGION" ] || [ -z "$VAULT_DOMAIN" ]; then
    echo "VAULT_REGION and VAULT_DOMAIN environment variables must be set"
    exit 1
fi

backup_dir="/vault-backup"
log_file="/vault-backup/backup.log"
snapshot_file="vault-$(date +%Y-%m-%d_%H-%M-%S).snapshot"

# Function to log messages with a timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$log_file"
}

# Add a separator to the log file
log_message "======================================="
log_message "Starting new backup schedule"

# Create backup directory if it doesn't exist
sudo mkdir -p "$backup_dir"
sudo chmod 777 -R "$backup_dir"

# Determine the leader node
leader_node=$(vault operator raft list-peers -format json | jq -r '.data.config.servers[] | select(.leader == true) | .address' | cut -d: -f1)

# Get the current hostname and extract the last part
current_hostname=$(hostname)
host_suffix=$(echo "$current_hostname" | grep -o 'vault[0-9]\{2\}')

# Construct FQDNs based on provided region and domain
declare -A hostname_map=(
    ["vault01"]="vault1.$VAULT_REGION.$VAULT_DOMAIN"
    ["vault02"]="vault2.$VAULT_REGION.$VAULT_DOMAIN"
    ["vault03"]="vault3.$VAULT_REGION.$VAULT_DOMAIN"
)
current_fqdn=${hostname_map[$host_suffix]}

# Verify that the current host suffix is recognized
if [ -z "$current_fqdn" ]; then
    log_message "Unknown host suffix: $host_suffix"
    exit 1
fi

# Check if the current node is the leader node
if [ "$leader_node" == "$current_fqdn" ]; then
    log_message "This node is the leader: $current_fqdn"
    log_message "Creating snapshot file: $snapshot_file on leader node $leader_node"
    vault operator raft snapshot save "$backup_dir/$snapshot_file" >> "$log_file" 2>&1
    log_message "Snapshot creation completed."

    # Copy the snapshot to other nodes
    for suffix in "${!hostname_map[@]}"; do
        target_fqdn=${hostname_map[$suffix]}
        if [ "$current_fqdn" != "$target_fqdn" ]; then
            log_message "Copying snapshot to $target_fqdn"
            scp "$backup_dir/$snapshot_file" ubuntu@"$target_fqdn":"$backup_dir/" >> "$log_file" 2>&1
        fi
    done
else
    log_message "This node is not the leader. Backup will not be performed on this node. The leader is $leader_node."
fi

# Check and delete snapshots older than 7 days
log_message "Checking and deleting old snapshots on $current_fqdn"
find "$backup_dir" -type f -name "vault-*.snapshot" -mtime +7 -exec rm {} \; -exec log_message "Deleted old snapshot: {}" \;

# Keep up to 7 snapshots
while [ "$(find "$backup_dir" -maxdepth 1 -type f -name "vault-*.snapshot" | wc -l)" -gt 7 ]; do
    old_snapshot=$(find "$backup_dir" -maxdepth 1 -type f -name "vault-*.snapshot" -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d ' ' -f 2-)
    rm "$old_snapshot"
    log_message "Deleted old snapshot: $old_snapshot"
done

log_message "Backup and maintenance process completed."
log_message "======================================="
