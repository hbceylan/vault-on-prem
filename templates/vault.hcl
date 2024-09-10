storage "raft" {
    path = "{{ config_dir }}/raft/"
    node_id = "{{ node_id }}"
    retry_join {
        leader_api_addr = "https://{{ leader1_fqdn }}:{{ vault_port }}"
        leader_ca_cert_file = "/opt/vault/tls/{{ tls_ca }}"
        leader_client_cert_file = "/opt/vault/tls/{{ tls_crt }}"
        leader_client_key_file = "/opt/vault/tls/{{ tls_key }}"
    }
    retry_join {
        leader_api_addr = "https://{{ leader2_fqdn }}:{{ vault_port }}"
        leader_ca_cert_file = "/opt/vault/tls/{{ tls_ca }}"
        leader_client_cert_file = "/opt/vault/tls/{{ tls_crt }}"
        leader_client_key_file = "/opt/vault/tls/{{ tls_key }}"
    }
}

listener "tcp" {
    address = "0.0.0.0:{{ vault_port }}"
    tls_disable = false
    tls_cert_file = "/opt/vault/tls/{{ tls_crt }}"
    tls_key_file = "/opt/vault/tls/{{ tls_key }}"
    tls_client_ca_file = "/opt/vault/tls/{{ tls_ca }}"
    tls_disable_client_certs = true
}

api_addr = "https://{{ node_fqdn }}:{{ vault_port }}"
cluster_addr = "https://{{ node_fqdn }}:{{ vault_cluster_port }}"
disable_mlock = true
ui = true
log_level = "info"
disable_cache = true
cluster_name = "{{ cluster_name }}"
