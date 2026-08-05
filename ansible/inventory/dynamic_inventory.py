#!/usr/bin/env python3
"""
Dynamic Ansible inventory — reads Terraform outputs from Azure remote state.

Usage:
  ansible-inventory -i inventory/dynamic_inventory.py --list
  ansible-playbook -i inventory/dynamic_inventory.py playbooks/site.yml

How it works:
  Runs `terraform output -json` in the ../terraform directory,
  parses app_vm_public_ip and db_vm_private_ip, and returns a
  valid Ansible JSON inventory.

Requirements:
  - Terraform CLI must be installed and initialized
  - Azure credentials must be configured (az login or env vars)
"""

import json
import subprocess
import sys
import os

TERRAFORM_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "terraform")


def get_terraform_outputs() -> dict:
    """Run terraform output -json and return parsed dict."""
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=os.path.abspath(TERRAFORM_DIR),
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def build_inventory(tf_outputs: dict) -> dict:
    """Build Ansible inventory JSON from Terraform outputs."""
    app_ip = tf_outputs["app_vm_public_ip"]["value"]
    db_ip  = tf_outputs["db_vm_private_ip"]["value"]

    return {
        "all": {
            "children": ["app_servers", "db_servers"]
        },
        "app_servers": {
            "hosts": [app_ip],
        },
        "db_servers": {
            "hosts": [db_ip],
        },
        "_meta": {
            "hostvars": {
                app_ip: {
                    "ansible_host": app_ip,
                    "ansible_user": "gillani",
                    "ansible_ssh_private_key_file": "~/.ssh/az-vm-ssh",
                    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no",
                    "role": "app",
                },
                db_ip: {
                    "ansible_host": db_ip,
                    "ansible_user": "gillani",
                    # DB VM is private — reached via app VM as a jump host
                    "ansible_ssh_common_args": (
                        f"-o StrictHostKeyChecking=no "
                        f"-o ProxyJump=gillani@{app_ip} "
                        f"-i ~/.ssh/az-vm-ssh"
                    ),
                    "ansible_ssh_private_key_file": "~/.ssh/az-vm-ssh",
                    "role": "db",
                    "db_host": db_ip,
                },
            }
        },
    }


def main():
    # Ansible calls inventory scripts with --list or --host <hostname>
    if len(sys.argv) > 1 and sys.argv[1] == "--host":
        # Return empty hostvars — _meta covers all hosts already
        print(json.dumps({}))
        return

    try:
        tf_outputs = get_terraform_outputs()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: terraform output failed:\n{e.stderr}", file=sys.stderr)
        sys.exit(1)
    except KeyError as e:
        print(f"ERROR: missing expected Terraform output: {e}", file=sys.stderr)
        sys.exit(1)

    inventory = build_inventory(tf_outputs)
    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
