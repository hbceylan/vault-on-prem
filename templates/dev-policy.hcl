path "kv/metadata/development/*" {
  capabilities = ["read", "list"]
}

path "kv/data/development/*" {
  capabilities = ["create", "read", "delete", "update"]
}
