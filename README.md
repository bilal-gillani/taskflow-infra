# TaskFlow — Production CI/CD Pipeline

End-to-end CI/CD setup for the TaskFlow PHP web app on Azure VMs using:
- **Terraform** — Infrastructure provisioning (VMs, VNet, NSG, Key Vault)
- **Ansible** — Configuration management (Apache, PHP, MySQL, app deployment)
- **GitHub Actions** — CI/CD automation (plan on PR, apply+configure on merge, deploy on push)

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  GitHub                                                      │
│                                                              │
│  [App Repo: bilal-gillani/taskflow-app]                      │
│    push to main ──► deploy-app.yml ──► SSH → git pull        │
│                                                              │
│  [Infra Repo: this repo]                                     │
│    PR to main   ──► infra-cicd.yml ──► terraform plan        │
│    merge to main──► infra-cicd.yml ──► terraform apply       │
│                                        ──► ansible site.yml  │
└──────────────────────────────────────────────────────────────┘
               │ SSH                           │ SSH
               ▼                               ▼
    ┌────────────────────┐         ┌────────────────────────┐
    │   App VM           │         │   DB VM (private)      │
    │   Ubuntu 24.04     │◄───────►│   Ubuntu 24.04         │
    │   Apache + PHP     │  MySQL  │   MySQL Server         │
    │   /var/www/html/   │  3306   │   taskflow DB          │
    └────────────────────┘         └────────────────────────┘
            │ Public IP                    │ Private IP only
            │                             │ (reached via App VM as jump host)
    Azure VNet 10.2.0.0/16
    app subnet: 10.2.1.0/24    db subnet: 10.2.2.0/24
```

---

## Directory Structure

```
5 (cicd-ansible-pipeline)/
├── terraform/                   # Infra provisioning — run once (or on infra changes)
│   ├── main.tf                  # VMs, VNet, NSG (no custom_data)
│   ├── variables.tf
│   ├── outputs.tf               # Exports app_vm_public_ip, db_vm_private_ip
│   ├── providers.tf             # azurerm ~> 5.0, remote backend
│   └── terraform.tfvars         # Environment values
│
├── ansible/                     # Configuration management — idempotent, re-runnable
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── dynamic_inventory.py # Reads `terraform output -json` → Ansible JSON inventory
│   ├── group_vars/
│   │   └── all.yml              # Shared non-secret vars
│   ├── playbooks/
│   │   ├── site.yml             # Master: DB first, then App
│   │   ├── configure-db.yml
│   │   └── configure-app.yml
│   └── roles/
│       ├── common/              # Package updates, fail2ban, timezone
│       ├── db_server/           # MySQL, DB/user creation (secret from Key Vault)
│       └── app_server/          # Apache, PHP, git clone, config.php, schema import
│
└── .github/workflows/
    ├── infra-cicd.yml           # Infra pipeline (this repo)
    └── deploy-app.yml           # App pipeline (copy to bilal-gillani/taskflow-app)
```

---

## One-Time Setup

### 1. Azure OIDC Authentication for GitHub Actions

Instead of storing Azure credentials as secrets, we use **OpenID Connect (OIDC)** —
the modern, credential-free approach.

```bash
# Create an Azure AD App Registration
az ad app create --display-name "github-actions-taskflow"

# Note the appId (CLIENT_ID) and objectId
APP_ID=$(az ad app list --display-name "github-actions-taskflow" --query '[0].appId' -o tsv)
OBJECT_ID=$(az ad app list --display-name "github-actions-taskflow" --query '[0].id' -o tsv)

# Create a service principal
az ad sp create --id $APP_ID

SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

# Assign Contributor role on the subscription
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role Contributor \
  --scope /subscriptions/940a3c71-f766-4f4f-8aa4-5e1dc09b3c23

# Also assign Key Vault Secrets User role
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/940a3c71-f766-4f4f-8aa4-5e1dc09b3c23

# Add federated credential (trusts GitHub Actions for this repo)
az ad app federated-credential create \
  --id $OBJECT_ID \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_GITHUB_ORG>/<THIS_REPO>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Add these 3 secrets to GitHub repo settings:
| Secret Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | App Registration Client ID |
| `AZURE_TENANT_ID` | `1511ab2e-502b-4e2d-bd68-f679f549b5a2` |
| `AZURE_SUBSCRIPTION_ID` | `940a3c71-f766-4f4f-8aa4-5e1dc09b3c23` |

### 2. GitHub Deploy Keypair (for app repo SSH deployment)

```bash
# Generate a dedicated deploy keypair (NOT your personal key)
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/taskflow_deploy -N ""

# After first terraform apply + ansible run, add public key to the VM:
ssh-copy-id -i ~/.ssh/taskflow_deploy.pub gillani@<APP_VM_IP>
```

Add to `bilal-gillani/taskflow-app` repo secrets:
| Secret Name | Value |
|---|---|
| `DEPLOY_SSH_KEY` | Contents of `~/.ssh/taskflow_deploy` (private key) |
| `APP_VM_IP` | Public IP from `terraform output app_vm_public_ip` |
| `ADMIN_USERNAME` | `gillani` |

### 3. GitHub Environment (production approval gate)

In this repo's GitHub settings → Environments → Create `production` environment.
Add yourself as a required reviewer. This means `terraform apply` needs
manual approval even after a PR merge.

---

## Workflow: First-Time Deployment

```
1. terraform init && terraform plan     # Review what will be created
2. terraform apply                      # Provision VMs (takes ~2-3 min)
3. ansible-playbook playbooks/site.yml  # Configure DB VM, then App VM
4. Visit: http://<APP_IP>/taskflow/index.php
```

## Workflow: Routine App Deployment (after first setup)

```
1. Developer pushes code to bilal-gillani/taskflow-app main
2. GitHub Actions (deploy-app.yml) triggers automatically
3. PHP lint runs
4. SSH → git pull → chown → systemctl restart apache2
5. HTTP 200 check confirms deployment success
   Total time: ~30 seconds
```

## Workflow: Infrastructure Change

```
1. Create a branch, edit terraform/*.tf files
2. Open PR → GitHub Actions posts terraform plan as PR comment
3. Review plan, get approval, merge to main
4. GitHub Actions: terraform apply (waits for manual approval in GitHub Environments)
5. Ansible runs automatically after apply to reconfigure any changed VMs
```

## Local Ansible (for debugging/manual runs)

```bash
cd ansible/

# Run against dynamic inventory (reads terraform output)
ansible-playbook -i inventory/dynamic_inventory.py playbooks/site.yml

# Target only DB VM
ansible-playbook -i inventory/dynamic_inventory.py playbooks/configure-db.yml

# Dry run (check mode)
ansible-playbook -i inventory/dynamic_inventory.py playbooks/site.yml --check

# List inventory hosts
ansible-inventory -i inventory/dynamic_inventory.py --list
```

> **Note**: Running Ansible locally from Windows requires WSL2.
> The GitHub Actions runner (Ubuntu) handles Ansible in the automated pipeline.

---

## Secrets Summary

| Secret | Where Stored | Used By |
|---|---|---|
| DB password | Azure Key Vault (`taskflow-db-pass`) | Ansible (fetched at runtime) |
| Azure credentials | GitHub Secrets (OIDC — no key!) | GitHub Actions (infra repo) |
| SSH deploy key | GitHub Secrets (`DEPLOY_SSH_KEY`) | GitHub Actions (app repo) |
| App VM IP | GitHub Secrets (`APP_VM_IP`) | GitHub Actions (app repo) |
| Admin SSH key | Local `~/.ssh/az-vm-ssh` | Terraform, local Ansible |

**Nothing sensitive is ever committed to this repository.**
