#!/bin/bash

set -e

region="$2"
domain="$3"

install_vault() {
  if ! command -v vault &> /dev/null; then
    echo "Adding HashiCorp GPG key..."
    tmp_key="$(mktemp)"
    if ! wget -qO "$tmp_key" https://apt.releases.hashicorp.com/gpg; then
      echo "Failed to download HashiCorp GPG key."
      exit 1
    fi

    if ! sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg < "$tmp_key"; then
      echo "Failed to add HashiCorp GPG key."
      rm "$tmp_key"
      exit 1
    fi
    
    rm "$tmp_key"
    
    echo "Adding HashiCorp repository to sources list..."
    if ! echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list; then
      echo "Failed to add HashiCorp repository to sources list."
      exit 1
    fi
  
    echo "Updating apt package index..."
    sudo apt -qq update
    sudo apt -qq install vault jq -y
    sudo chmod 777 -R /opt/vault
  else
    echo "Vault is already installed."
  fi
}

create_vault_service() {
  local node_name=$1
  local config_file="/opt/vault/vault.hcl"
  local log_file="/opt/vault/vault.log"
  local service_template="/opt/vault/vault.service"
  local service_file="/etc/systemd/system/vault.service"

  echo "Creating systemd service for $node_name..."

  sed -e "s|{{ node_name }}|$node_name|g" \
      -e "s|{{ config_file }}|$config_file|g" \
      -e "s|{{ log_file }}|$log_file|g" \
      $service_template | sudo tee $service_file > /dev/null

  sudo rm $service_template
  echo "Systemd service for $node_name created."

  sudo systemctl daemon-reload
  sudo systemctl enable vault
  sudo systemctl start vault

  while ! nc -w 1 localhost 8200 </dev/null; do sleep 1; done
  echo "Systemd service for $node_name started."
}

setup_vault() {
  local node_name="vault$1"
  local node_fqdn="${node_name}.${region}.${domain}"

  export VAULT_ADDR=https://$node_fqdn:8200
  export VAULT_API_ADDR=https://$node_fqdn:8200
  export VAULT_CACERT="/opt/vault/tls/wildcard.${region}.${domain}.ca"
  export CA_CERT="/opt/vault/tls/wildcard.${region}.${domain}.ca"

  install_vault

  if pgrep vault >/dev/null; then
    echo "Vault process is already running on $node_name."
  else
    printf "\n%s" "[$node_name] Starting Vault server @ $node_name"
    
    create_vault_service "$node_name"
    
    sleep 2
  fi

  if [ "$node_name" == "vault1" ]; then
    if vault operator init -status | grep "Vault is initialized" >/dev/null; then
      printf "\n%s" "[vault1] Vault is already initialized. Skipping initialization step."
    else
      printf "\n%s" "[vault1] Initializing Vault"

      initResult=$(vault operator init -format=json -key-shares=1 -key-threshold=1)

      unsealKey=$(echo -n "$initResult" | jq -r '.unseal_keys_b64[0]')
      rootToken=$(echo -n "$initResult" | jq -r '.root_token')
      echo -n "$unsealKey" > "/opt/vault/unsealKey"
      echo -n "$rootToken" > "/opt/vault/rootToken"

      vault operator unseal "$(cat "/opt/vault/unsealKey")"

      sleep 10

      vault login "$(cat "/opt/vault/rootToken")"

      printf "\n%s" "[vault1] Waiting for post-unseal setup (15 seconds)"

      sleep 5

      printf "\n%s" "[vault1] Logging in and enabling the KV secrets engine"
      sleep 2

      vault secrets enable -path=kv kv-v2
      sleep 2

      printf "\n%s" "[vault1] Storing secret 'kv/apikey' for testing"

      vault kv put kv/apikey webapp=ABB39KKPTWOR832JGNLS02
      vault kv get kv/apikey

      for node_ip in vault2.${region}.${domain} vault3.${region}.${domain}; do
        scp -o StrictHostKeyChecking=no "/opt/vault/unsealKey" "/opt/vault/rootToken" ubuntu@"$node_ip":"/opt/vault/"
        echo "Unseal key and root token copied to $node_ip"
      done
    fi

    printf "\n%s" "[vault1] Enabling userpass authentication"
    vault auth enable userpass

    printf "\n%s" "[vault1] Creating policy for developer user"
    vault policy write dev-policy /opt/vault/dev-policy.hcl

    printf "\n%s" "[vault1] Creating developer user"
    vault write auth/userpass/users/developer password="developer" policies="dev-policy"
  fi

  printf "\n%s" "[$node_name] Unseal $node_name"
  if vault status -format json | jq -e '.sealed' | grep "false" >/dev/null; then
    echo "Vault $node_name is already unsealed."
  else
    vault operator unseal "$(cat "/opt/vault/unsealKey")"
  fi

  sleep 1

  printf "\n%s" "[$node_name] Join the raft cluster"
  if ! vault operator raft join; then
    echo "Vault $node_name is already joined to the raft cluster."
  fi

  sleep 5

  vault login "$(cat "/opt/vault/rootToken")"

  printf "\n%s" "[$node_name] List the raft cluster members"
  vault operator raft list-peers

  printf "\n%s" "[$node_name] Vault status"
  vault status
}

setup_vault "$1" "$2" "$3"
