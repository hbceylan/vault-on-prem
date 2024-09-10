#!/bin/bash

set -e

config_dir="$2"
region="$3"
domain="$4"
fqdn="$region.$domain"
cluster_name="$region-vault"

vault_1_ip="$5"
vault_2_ip="$6"
vault_3_ip="$7"

vault_1_fqdn="vault1.$fqdn"
vault_2_fqdn="vault2.$fqdn"
vault_3_fqdn="vault3.$fqdn"

vault_port="8200"
vault_cluster_port="8201"

tls_ca="wildcard.$fqdn.ca"
tls_crt="wildcard.$fqdn.chain.crt"
tls_key="wildcard.$fqdn.pem"

vault_cacert="$config_dir/tls/$tls_ca"
ca_cert="$config_dir/tls/$tls_ca"

# Define the hostname/IP mappings
hosts_entries=(
  "$vault_1_ip $vault_1_fqdn"
  "$vault_2_ip $vault_2_fqdn"
  "$vault_3_ip $vault_3_fqdn"
)

add_variables() {
  if grep -q "^export $1=" ~/.profile; then
      sed -i "s|^export $1=.*$|export $1=$2|" ~/.profile
  else
      echo "export $1=$2" >> ~/.profile
  fi
}

update_or_add_entry() {
  local hosts_entries=("$@")
  local hosts_file="/etc/hosts"

  for entry in "${hosts_entries[@]}"; do
      local ip=$(echo "$entry" | awk '{print $1}')
      local hostname=$(echo "$entry" | awk '{print $2}')

      if grep -qE "^\s*$ip\s+$hostname(\s|$)" "$hosts_file"; then
          sudo sed -i "s/^\s*$ip\s.*/$ip $hostname/g" "$hosts_file"
          echo "Updated entry: $ip $hostname in $hosts_file"
      else
          echo "$ip $hostname" | sudo tee -a "$hosts_file" >/dev/null
          echo "Added entry: $ip $hostname to $hosts_file"
      fi
  done
}

create_backup() {
  local node_name=$1

  echo "Updating permissions and adding to cronjob on $node_name"
  sudo chmod +x /opt/vault/backup.sh

  if ! crontab -l | grep -q '/opt/vault/backup.sh'; then
      (crontab -l 2>/dev/null; echo "0 0 * * * /opt/vault/backup.sh") | crontab -
  else
      echo "Cronjob already exists."
  fi
}

create_config() {
  local node_name=$1
  local node_id
  local node_fqdn
  local leader1_fqdn
  local leader2_fqdn

  case "$node_name" in
    vault_1)
      node_id="vault1"
      node_fqdn="$vault_1_fqdn"
      leader1_fqdn="$vault_2_fqdn"
      leader2_fqdn="$vault_3_fqdn"
      ;;
    vault_2)
      node_id="vault2"
      node_fqdn="$vault_2_fqdn"
      leader1_fqdn="$vault_1_fqdn"
      leader2_fqdn="$vault_3_fqdn"
      ;;
    vault_3)
      node_id="vault3"
      node_fqdn="$vault_3_fqdn"
      leader1_fqdn="$vault_1_fqdn"
      leader2_fqdn="$vault_2_fqdn"
      ;;
    *)
      echo "Invalid node name. Usage: create_config [vault_1|vault_2|vault_3]"
      return 1
      ;;
  esac

  echo "Update or add variables"
  add_variables "VAULT_ADDR" "https://$node_fqdn:$vault_port"
  add_variables "VAULT_CACERT" "$vault_cacert"
  add_variables "CA_CERT" "$ca_cert"
  add_variables "VAULT_DOMAIN" "$domain"
  add_variables "VAULT_REGION" "$region"

  echo "Update or add entries in /etc/hosts"
  update_or_add_entry "${hosts_entries[@]}"

  echo "Create Raft backup job"
  create_backup "$node_name"

  echo "Creating Vault configuration for $node_name"

  sed -e "s|{{ node_id }}|$node_id|g" \
      -e "s|{{ node_fqdn }}|$node_fqdn|g" \
      -e "s|{{ leader1_fqdn }}|$leader1_fqdn|g" \
      -e "s|{{ leader2_fqdn }}|$leader2_fqdn|g" \
      -e "s|{{ vault_port }}|$vault_port|g" \
      -e "s|{{ vault_cluster_port }}|$vault_cluster_port|g" \
      -e "s|{{ tls_ca }}|$tls_ca|g" \
      -e "s|{{ tls_crt }}|$tls_crt|g" \
      -e "s|{{ tls_key }}|$tls_key|g" \
      -e "s|{{ cluster_name }}|$cluster_name|g" \
      -e "s|{{ config_dir }}|$config_dir|g" \
      "$config_dir/vault.hcl" | sudo tee "$config_dir/vault.hcl" > /dev/null

  printf "\n"
}

create_config "$1" "$2" "$3" "$4" "$5" "$6" "$7"
