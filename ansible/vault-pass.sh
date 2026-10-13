#!/bin/sh
# Prints the Ansible Vault password, kept in 1Password (see README).
# ansible.cfg runs this so vault-encrypted vars decrypt without a prompt.
# On WSL, the Windows op.exe talks to the 1Password app (Windows Hello); a Linux op can't.
ref="${ANSIBLE_VAULT_OP_REF:-op://Homelab/homelab-ansible-vault/password}"
if command -v op.exe >/dev/null 2>&1; then
  exec op.exe read "$ref"
fi
exec op read "$ref"
