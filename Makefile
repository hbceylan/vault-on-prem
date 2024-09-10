# Function to check environment variables
define check_env_var
  $(if $(strip $($(1))),,$(error $(1) is not set. Please provide the $(1) using 'make <target> $(1)=<value>'))
endef

# Check if ENV_FILE and ROOT_PASSWORD are set
$(eval $(call check_env_var,ENV_FILE))
$(eval $(call check_env_var,ROOT_PASSWORD))

# Include the environment file
include $(ENV_FILE)

# Base variables
SSH_USERNAME = ubuntu
SSH_HOST_1 = $(SSH_USERNAME)@$(NODE_1_IP)
SSH_HOST_2 = $(SSH_USERNAME)@$(NODE_2_IP)
SSH_HOST_3 = $(SSH_USERNAME)@$(NODE_3_IP)

VAULT_CONFIG_PATH = "/opt/vault"
SCRIPT_PATH = ./scripts/main.sh
CERTS_PATH := ./certs/joburg.example.com
VAULT_TEMPLATE_FILE := ./templates/vault.hcl
VAULT_SERVICE_TEMPLATE_FILE := ./templates/vault.service
VAULT_DEV_POLICY_TEMPLATE_FILE := ./templates/dev-policy.hcl
BACKUP_SCRIPT = ./scripts/backup.sh

.PHONY: create-ubuntu-user
create-ubuntu-user:
	@echo "Setting up Ubuntu user and copying SSH public key"
	@ssh root@$(NODE_1_IP) 'bash -s' < $(SCRIPT_PATH) create-ubuntu-user "$(ROOT_PASSWORD)" "$(NODE_1_IP)"
	@ssh root@$(NODE_2_IP) 'bash -s' < $(SCRIPT_PATH) create-ubuntu-user "$(ROOT_PASSWORD)" "$(NODE_2_IP)"
	@ssh root@$(NODE_3_IP) 'bash -s' < $(SCRIPT_PATH) create-ubuntu-user "$(ROOT_PASSWORD)" "$(NODE_3_IP)"

.PHONY: setup-admin-access
setup-admin-access:
	@echo "Copying Admin local SSH public key to nodes..."
	$(foreach node_ip, $(NODE_1_IP) $(NODE_2_IP) $(NODE_3_IP), \
		@sshpass -p "$(ROOT_PASSWORD)" ssh-copy-id -o StrictHostKeyChecking=no root@$(node_ip) && \
		echo "SSH public key copied successfully to $(node_ip) root user." && \
		sshpass -p "$(ROOT_PASSWORD)" ssh root@$(node_ip) "cat >> /home/ubuntu/.ssh/authorized_keys" < ~/.ssh/id_rsa.pub && \
		echo "SSH public key copied successfully to $(node_ip) ubuntu user." \
	)
	@echo "SSH public key copied successfully to all nodes."

.PHONY: generate-ssh-keys
generate-ssh-keys:
	@$(SCRIPT_PATH) generate-ssh-keys $(NODE_1_IP) $(NODE_2_IP) $(NODE_3_IP)

.PHONY: create-config-vault
create-config-vault:
	@echo "Creating Vault folders for Vault $(VAULT)"
	@ssh $(SSH_USERNAME)@$(NODE_$(VAULT)_IP) 'bash -s' < $(SCRIPT_PATH) create-vault-folders

	@echo "Copying certs to Vault $(VAULT)"
	scp -o StrictHostKeyChecking=no -r $(CERTS_PATH)/* $(SSH_USERNAME)@$(NODE_$(VAULT)_IP):$(VAULT_CONFIG_PATH)/tls

	@echo "Copying Vault config template to Vault $(VAULT)"
	scp -o StrictHostKeyChecking=no $(VAULT_TEMPLATE_FILE) $(SSH_USERNAME)@$(NODE_$(VAULT)_IP):$(VAULT_CONFIG_PATH)

	@echo "Copying Vault service template to Vault $(VAULT)"
	scp -o StrictHostKeyChecking=no $(VAULT_SERVICE_TEMPLATE_FILE) $(SSH_USERNAME)@$(NODE_$(VAULT)_IP):$(VAULT_CONFIG_PATH)

	@echo "Copying Vault dev-policy template to Vault $(VAULT)"
	scp -o StrictHostKeyChecking=no $(VAULT_DEV_POLICY_TEMPLATE_FILE) $(SSH_USERNAME)@$(NODE_$(VAULT)_IP):$(VAULT_CONFIG_PATH)

	@echo "Copying backup script to Vault $(VAULT)"
	scp -o StrictHostKeyChecking=no $(BACKUP_SCRIPT) $(SSH_USERNAME)@$(NODE_$(VAULT)_IP):$(VAULT_CONFIG_PATH)

	@echo "Creating config for Vault $(VAULT)"
	@ssh $(SSH_USERNAME)@$(NODE_$(VAULT)_IP) 'bash -s' < ./scripts/create-config.sh vault_$(VAULT) $(VAULT_CONFIG_PATH) $(REGION) $(DOMAIN) $(NODE_1_IP) $(NODE_2_IP) $(NODE_3_IP)

.PHONY: create-config-vault-1
create-config-vault-1:
	@$(MAKE) create-config-vault VAULT=1

.PHONY: create-config-vault-2
create-config-vault-2:
	@$(MAKE) create-config-vault VAULT=2

.PHONY: create-config-vault-3
create-config-vault-3:
	@$(MAKE) create-config-vault VAULT=3

.PHONY: create-config-vault-all
create-config-vault-all: create-config-vault-1 create-config-vault-2 create-config-vault-3

.PHONY: setup-vault
setup-vault:
	@echo "Setting up Vault $(VAULT)"
	@ssh $(SSH_USERNAME)@$(NODE_$(VAULT)_IP) 'bash -s' < ./scripts/setup-vault.sh $(VAULT) $(REGION) $(DOMAIN) 

.PHONY: setup-vault-1
setup-vault-1:
	@$(MAKE) setup-vault VAULT=1

.PHONY: setup-vault-2
setup-vault-2:
	@$(MAKE) setup-vault VAULT=2

.PHONY: setup-vault-3
setup-vault-3:
	@$(MAKE) setup-vault VAULT=3

.PHONY: setup-vault-all
setup-vault-all: setup-vault-1 setup-vault-2 setup-vault-3

.PHONY: stop-vault-1
stop-vault-1:
	@echo "Stopping Vault 1"
	@ssh $(SSH_HOST_1) 'bash -s' < $(SCRIPT_PATH) stop vault_1

.PHONY: stop-vault-2
stop-vault-2:
	@echo "Stopping Vault 2"
	@ssh $(SSH_HOST_2) 'bash -s' < $(SCRIPT_PATH) stop vault_2

.PHONY: stop-vault-3
stop-vault-3:
	@echo "Stopping Vault 3"
	@ssh $(SSH_HOST_3) 'bash -s' < $(SCRIPT_PATH) stop vault_3

.PHONY: stop-vault-all
stop-vault-all: stop-vault-1 stop-vault-2 stop-vault-3

.PHONY: clean-vault-1
clean-vault-1:
	@echo "Cleaning Vault 1"
	@ssh $(SSH_HOST_1) 'bash -s' < $(SCRIPT_PATH) clean

.PHONY: clean-vault-2
clean-vault-2:
	@echo "Cleaning Vault 2"
	@ssh $(SSH_HOST_2) 'bash -s' < $(SCRIPT_PATH) clean

.PHONY: clean-vault-3
clean-vault-3:
	@echo "Cleaning Vault 3"
	@ssh $(SSH_HOST_3) 'bash -s' < $(SCRIPT_PATH) clean

.PHONY: clean-vault-all
clean-vault-all: clean-vault-1 clean-vault-2 clean-vault-3

.PHONY: status
status:
	@$(SCRIPT_PATH) status

.PHONY: create-cluster
create-cluster: generate-ssh-keys create-config-vault-all setup-vault-all

.PHONY: default
default:
	@echo "Usage: make <target> [VARIABLE=value ...]"
	@echo ""
	@echo "Targets:"
	@echo "  create-ubuntu-user         Set up Ubuntu user and copy SSH public key"
	@echo "  setup-admin-access         Copy Admin local SSH public key to nodes"
	@echo "  generate-ssh-keys          Generate SSH keys"
	@echo "-------------------------------------------------------------------------"
	@echo "  create-cluster             Creates the cluster with everything"
	@echo "-------------------------------------------------------------------------"
	@echo "  create-config-vault-1      Create Vault configuration for Vault 1"
	@echo "  create-config-vault-2      Create Vault configuration for Vault 2"
	@echo "  create-config-vault-3      Create Vault configuration for Vault 3"
	@echo "  create-config-vault-all    Create Vault configuration for all Vaults"
	@echo "-------------------------------------------------------------------------"
	@echo "  setup-vault-1              Setup Vault 1"
	@echo "  setup-vault-2              Setup Vault 2"
	@echo "  setup-vault-3              Setup Vault 3"
	@echo "  setup-vault-all            Setup all Vaults"
	@echo "-------------------------------------------------------------------------"
	@echo "  stop-vault-1               Stop Vault 1"
	@echo "  stop-vault-2               Stop Vault 2"
	@echo "  stop-vault-3               Stop Vault 3"
	@echo "  stop-vault-all             Stop all Vaults"
	@echo "-------------------------------------------------------------------------"
	@echo "  clean-vault-1              Clean Vault 1"
	@echo "  clean-vault-2              Clean Vault 2"
	@echo "  clean-vault-3              Clean Vault 3"
	@echo "  clean-vault-all            Clean all Vaults"
	@echo "-------------------------------------------------------------------------"
	@echo "  status                     Check status"
