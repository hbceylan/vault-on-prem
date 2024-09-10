#!/bin/bash
# shellcheck disable=SC2005,SC2030,SC2031,SC2174

set -e

config_dir="/opt/vault"
script_name="$(basename "$0")"
os_name="$(uname -s | awk '{print tolower($0)}')"

ssh_user="ubuntu"

if [ "$os_name" != "darwin" ] && [ "$os_name" != "linux" ]; then
  >&2 echo "Sorry, this script supports only Linux or macOS operating systems."
  exit 1
fi

create_vault_folders() {
  create_vault_user

  if [ ! -d "$config_dir"/raft ] || [ ! -d "$config_dir"/tls ]; then
    sudo mkdir -p "$config_dir"/raft
    echo "Vault folders created: $config_dir/raft"
    sudo mkdir -p "$config_dir"/tls
    echo "Vault folders created: $config_dir/tls"
    sudo chmod -R 777 "$config_dir"
  else
    echo "Vault folders already exist: $config_dir/raft and $config_dir/tls"
  fi
}

fix_folders_permission() {
  sudo chown -R vault:vault "$config_dir"
  sudo chmod -R 755 "$config_dir"
  echo "Vault $config_dir permission is fixed."
}

create_vault_user() {
  if ! id -u vault >/dev/null 2>&1; then
    sudo useradd --system --home /etc/vault.d --shell /bin/false vault
    echo "Vault user created."
  fi
}

generate_and_copy_ssh_keys_between_nodes() {
  local source_ip="$1"
  shift
  local target_ips=("$@")

  if ssh -o StrictHostKeyChecking=no "$ssh_user@$source_ip" '[ ! -f ~/.ssh/id_rsa ] && [ ! -f ~/.ssh/id_rsa.pub ]'; then
    ssh -o StrictHostKeyChecking=no "$ssh_user@$source_ip" 'ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa'
    echo "SSH keys generated on $source_ip"
  else
    echo "SSH keys already exist on $source_ip"
  fi

  local public_key=$(ssh -o StrictHostKeyChecking=no "$ssh_user@$source_ip" 'cat ~/.ssh/id_rsa.pub')

  for target_ip in "${target_ips[@]}"; do
    if [ "$target_ip" != "$source_ip" ]; then
      if ! ssh -o StrictHostKeyChecking=no "$ssh_user@$target_ip" "grep -q '$public_key' ~/.ssh/authorized_keys"; then
        ssh -o StrictHostKeyChecking=no "$ssh_user@$target_ip" "echo '$public_key' >> ~/.ssh/authorized_keys"
        echo "Public key copied from $source_ip to $target_ip"
      else
        echo "Public key already exists on $target_ip"
      fi
    fi
  done
}

generate_node_ssh_keys() {
  local vault_1_ip=$1
  local vault_2_ip=$2
  local vault_3_ip=$3

  generate_and_copy_ssh_keys_between_nodes "$vault_1_ip" "$vault_2_ip" "$vault_3_ip"
  generate_and_copy_ssh_keys_between_nodes "$vault_2_ip" "$vault_1_ip" "$vault_3_ip"
  generate_and_copy_ssh_keys_between_nodes "$vault_3_ip" "$vault_1_ip" "$vault_2_ip"
}

create_ubuntu_user() {
  local node_ip=$2

  if ! command -v sshpass &> /dev/null; then
    echo "sshpass is not installed. Installing..."
    apt update
    apt install -y sshpass
  else
    echo "sshpass is already installed."
  fi

  ssh_connection="sshpass -p $1 ssh -o StrictHostKeyChecking=no root@$node_ip"
  sshpass -p "$1" ssh-copy-id -o StrictHostKeyChecking=no root@"$node_ip"

  if ! $ssh_connection id -u "ubuntu" >/dev/null 2>&1; then
    $ssh_connection "sudo adduser --disabled-password --gecos \"\" ubuntu"
    $ssh_connection "sudo usermod -aG sudo ubuntu"
  else
    $ssh_connection "echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"
    echo "ubuntu user is already created."
  fi
}

stop_vault() {
  if pgrep vault >/dev/null; then
    sudo systemctl stop vault
    printf "\n%s" "[$1] Existing Vault process killed."
  fi
}

stop() {
  case "$1" in
    vault_1)
      stop_vault "vault_1"
      ;;
    vault_2)
      stop_vault "vault_2"
      ;;
    vault_3)
      stop_vault "vault_3"
      ;;
    all)
      for vault_node_name in vault_1 vault_2 vault_3 ; do
        stop_vault $vault_node_name
      done
      ;;
    *)
      printf "\n%s" \
        "Usage: $script_name stop [all|vault_1|vault_2|vault_3]" \
        ""
      ;;
    esac
}

clean() {
  echo "First stopping the Vault process"
  stop_vault "$1"

  echo "Deleting the $config_dir"
  sudo rm -rf $config_dir

  echo "Deleting the service"
  sudo rm -rf "/etc/systemd/system/vault.service"

  echo "Uninstalling the Vault"
  sudo apt remove vault -y

  echo "Removing crontab tasks"
  sudo crontab -r

  echo "Unsetting the VAULT_TOKEN variable"
  unset VAULT_TOKEN

  printf "\n%s" "Clean complete" ""
}

status() {
  service_count=$(pgrep -f "$(pwd)"/config | wc -l | tr -d '[:space:]')

  printf "\n%s" \
    "Found $service_count Vault services" \
    ""

  if [[ "$service_count" != 4 ]] ; then
    printf "\n%s" \
    "Unable to find all Vault services" \
    ""
  fi

  printf "\n%s" \
    "[vault_1] status" \
    ""
  vault status || true

  printf "\n%s" \
    "[vault_2] status" \
    ""
  vault status || true

  printf "\n%s" \
    "[vault_3] status" \
    ""
  vault status || true

  sleep 2
}

case "$1" in
  generate-ssh-keys)
    shift ;
    generate_node_ssh_keys "$@"
    ;;
  create-ubuntu-user)
    shift ;
    create_ubuntu_user "$@"
    ;;
  create-vault-folders)
    create_vault_folders
    ;;
  create)
    shift ;
    ./scripts/create-config.sh "$@"
    ;;
  setup)
    shift ;
    ./scripts/setup-vault.sh "$@"
    ;;
  vault_1)
    shift ;
    ./scripts/setup-vault.sh vault_1 "$@"
    ;;
  vault_2)
    shift ;
    ./scripts/setup-vault.sh vault_2 "$@"
    ;;
  vault_3)
    shift ;
    ./scripts/setup-vault.sh vault_3 "$@"
    ;;
  status)
    status
    ;;
  start)
    shift ;
    start "$@"
    ;;
  stop)
    shift ;
    stop "$@"
    ;;
  clean)
    shift ;
    stop all
    clean "$@"
    ;;
  *)
    printf "\n%s" \
      "This script helps manage a Vault HA cluster with raft storage." \
      "View the README.md for the complete guide at https://learn.hashicorp.com/vault/beta/raft-storage" \
      "" \
      "Usage: $script_name [generate-ssh-keys|create|setup|status|stop|clean|vault_1|vault_2|vault_3]" \
      ""
    ;;
esac
