# SOPS for Companies - Enterprise Secrets Management

A production-ready implementation of SOPS (Secrets OPerationS) for managing encrypted secrets in a corporate environment with employee key management, role-based access control, and CI/CD integration.

## 🔐 Overview

This repository demonstrates best practices for using [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption to manage secrets across multiple environments while maintaining security, auditability, and ease of use.

### Key Features

- **Role-Based Access Control**: Separate access levels for developers, administrators, and CI/CD
- **YAML Anchors**: Efficient key group management using YAML anchors in `.sops.yaml`
- **Employee Lifecycle Management**: Scripts for onboarding and offboarding employees
- **Secret Rotation**: Automated and manual secret rotation capabilities
- **GitHub Actions Integration**: CI/CD workflows for validation and deployment
- **Multi-Environment Support**: Separate secrets for dev, staging, and production
- **Audit Trail**: Comprehensive logging of all key and secret operations

## 📁 Repository Structure

```
sops-for-companies/
├── .sops.yaml                 # SOPS configuration with key groups
├── keys/                       # Public keys directory
│   ├── developers/            # Developer public keys
│   ├── administrators/        # Admin public keys
│   └── ci/                    # CI/CD public keys
├── secrets/                    # Encrypted secrets
│   ├── dev/                   # Development environment
│   ├── staging/               # Staging environment
│   └── production/            # Production environment
├── scripts/                    # Management scripts
│   ├── onboard.sh            # Add new employee keys
│   ├── offboard.sh           # Remove employee keys
│   ├── rotate-secrets.sh     # Rotate secrets
│   ├── list-keys.sh          # List current keys
│   └── verify-access.sh      # Test decryption access
├── .github/workflows/         # GitHub Actions
│   ├── validate-secrets.yml  # PR validation
│   ├── deploy-secrets.yml    # Secret deployment
│   └── audit-keys.yml        # Weekly audit
└── examples/                  # Example files
```

## 🚀 Quick Start

### Prerequisites

1. Install SOPS:
```bash
# macOS
brew install sops

# Linux
curl -LO https://github.com/getsops/sops/releases/latest/download/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

2. Install age:
```bash
# macOS
brew install age

# Linux
apt-get install age  # Debian/Ubuntu
# or download from https://github.com/FiloSottile/age/releases
```

### Initial Setup

1. Clone the repository:
```bash
git clone https://github.com/yourcompany/sops-for-companies.git
cd sops-for-companies
```

2. Generate your age keypair:
```bash
age-keygen -o ~/.config/sops/age/keys.txt
```

3. Share your public key with an administrator to get onboarded

4. Verify your access:
```bash
./scripts/verify-access.sh
```

## 👥 Employee Management

### Onboarding a New Employee

Run the onboarding script as an administrator:

```bash
./scripts/onboard.sh
```

The script will:
1. Prompt for employee name and role (developer/administrator)
2. Accept an existing public key or generate a new keypair
3. Add the key to `.sops.yaml` with proper group assignment
4. Re-encrypt all secrets to include the new key
5. Commit changes with an audit trail

### Offboarding an Employee

```bash
./scripts/offboard.sh
```

The script will:
1. Remove the employee's key from `.sops.yaml`
2. Re-encrypt all secrets without the removed key
3. Optionally rotate sensitive secrets
4. Create an audit log entry
5. Commit all changes

## 🔑 Key Management

### Key Groups

The `.sops.yaml` file uses YAML anchors to define reusable key groups:

- **`&developers`**: Access to development secrets only
- **`&administrators`**: Access to all environments
- **`&ci`**: CI/CD service account with deployment access

### Access Matrix

| Role | Development | Staging | Production | Examples |
|------|-------------|---------|------------|----------|
| Developers | ✅ | ❌ | ❌ | ✅ |
| Administrators | ✅ | ✅ | ✅ | ✅ |
| CI/CD | ✅ | ✅ | ✅ | ❌ |

### Viewing Current Keys

```bash
./scripts/list-keys.sh
```

This displays:
- All configured keys grouped by role
- Access levels for each key
- Total statistics
- Last configuration update

## 🔄 Secret Management

### Creating a New Secret

1. Create a plaintext YAML file:
```yaml
# secrets/dev/new-service.yaml
apiVersion: v1
kind: Secret
data:
  api_key: "your-api-key"
  password: "your-password"
```

2. Encrypt it with SOPS:
```bash
sops -e secrets/dev/new-service.yaml > secrets/dev/new-service.enc.yaml
rm secrets/dev/new-service.yaml  # Remove plaintext
```

### Editing an Existing Secret

```bash
sops secrets/production/credentials.enc.yaml
```

This opens your default editor with the decrypted content. Changes are automatically re-encrypted on save.

### Rotating Secrets

Use the rotation script for automated rotation:

```bash
./scripts/rotate-secrets.sh
```

Options:
1. Rotate specific secret file
2. Rotate all secrets in an environment
3. Rotate all production secrets
4. View rotation history

### Viewing Decrypted Secrets

```bash
# View entire file
sops -d secrets/dev/database.enc.yaml

# Extract specific value
sops -d secrets/dev/database.enc.yaml | yq '.data.password'
```

## 🤖 CI/CD Integration

### GitHub Actions Setup

1. Generate a CI/CD age keypair:
```bash
age-keygen -o ci-keys.txt
```

2. Add the private key to GitHub Secrets:
   - Go to Settings → Secrets → Actions
   - Create `SOPS_AGE_KEY` with the private key value

3. Add the public key to `.sops.yaml` under the `ci` group

### Available Workflows

#### validate-secrets.yml
- Runs on every PR affecting secrets
- Validates encryption status
- Checks key references
- Security audit

#### deploy-secrets.yml
- Manual workflow for deploying secrets
- Supports multiple targets:
  - Kubernetes
  - AWS Secrets Manager
  - Azure Key Vault
  - HashiCorp Vault
- Requires environment approval

#### audit-keys.yml
- Weekly automated audit
- Checks for unused keys
- Validates access patterns
- Creates issues for problems

## 📊 Utilities

### Verify Access

Test your decryption capabilities:

```bash
# Check all access
./scripts/verify-access.sh

# Test specific file
./scripts/verify-access.sh secrets/dev/database.enc.yaml
```

### List Keys

View current key configuration:

```bash
./scripts/list-keys.sh
```

## 🔒 Security Best Practices

### Key Storage

1. **Never commit private keys** to the repository
2. Store private keys in:
   - `~/.config/sops/age/keys.txt` (Linux/macOS)
   - Password manager for backup
   - Hardware security module (HSM) for production

### Secret Rotation

- Rotate secrets quarterly at minimum
- Immediate rotation after employee offboarding
- Automated rotation for dynamic secrets
- Document rotation in audit logs

### Access Control

- Follow principle of least privilege
- Separate production access from development
- Require multiple administrators (bus factor)
- Regular access audits

### Audit Trail

- All key changes are logged
- Git commits provide change history
- Offboarding audit log tracks removed access
- Rotation log documents secret changes

## 🐛 Troubleshooting

### Common Issues

#### "Cannot decrypt file"
- Verify your key is in `.sops.yaml`
- Check `SOPS_AGE_KEY` environment variable
- Ensure key file exists at expected location
- Run `./scripts/verify-access.sh` to diagnose

#### "Key not found in config"
- Your key needs to be added by an administrator
- Run `./scripts/onboard.sh` as admin

#### "Failed to re-encrypt"
- Check that all referenced keys are valid
- Verify no syntax errors in `.sops.yaml`
- Ensure all key groups are properly defined

### Getting Help

1. Check the scripts' built-in help
2. Review workflow logs in GitHub Actions
3. Examine audit logs for historical context
4. Contact your security team

## 📝 Blog Post Outline

This repository serves as a practical example for the blog post "Enterprise Secrets Management with SOPS". Key topics covered:

1. **Introduction to SOPS**
   - Why SOPS over other solutions
   - age vs GPG encryption
   - Integration with existing tools

2. **Architecture Design**
   - Role-based access patterns
   - Environment segregation
   - Key group management with YAML anchors

3. **Implementation Details**
   - Employee lifecycle scripts
   - Secret rotation strategies
   - CI/CD integration patterns

4. **Security Considerations**
   - Threat model
   - Compliance requirements
   - Audit and monitoring

5. **Operational Excellence**
   - Automation strategies
   - Monitoring and alerting
   - Disaster recovery

6. **Lessons Learned**
   - Common pitfalls
   - Performance considerations
   - Team adoption strategies

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run validation: `./scripts/verify-access.sh`
5. Submit a pull request

## 📄 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- [SOPS](https://github.com/getsops/sops) by Mozilla
- [age](https://github.com/FiloSottile/age) by Filippo Valsorda
- The DevSecOps community for best practices

---

**Security Notice**: This repository contains example keys for demonstration purposes only. Never use these keys in production. Always generate your own unique keys for real deployments.