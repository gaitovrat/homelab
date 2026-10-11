#!/bin/sh
# Prints the Ansible Vault password, kept in 1Password (see README).
# ansible.cfg runs this so vault-encrypted vars decrypt without a prompt.
exec op read "${ANSIBLE_VAULT_OP_REF:-op://Private/homelab-ansible-vault/password}"
