# Enterprise Secrets Management with SOPS: A Production-Ready Implementation

*How to build a scalable, secure, and auditable secrets management system using SOPS, age encryption, and GitHub Actions*

> 📦 **Full implementation available**: All code, scripts, and examples from this post are available at [github.com/cgoolsby/sops-for-companies](https://github.com/cgoolsby/sops-for-companies)

---

## Introduction

Managing secrets in a corporate environment is one of those challenges that keeps security engineers up at night. You need to balance security with usability, ensure proper access control, maintain audit trails, and make it all work seamlessly with your CI/CD pipelines. After implementing secrets management systems at several organizations, I've found that SOPS (Secrets OPerationS) combined with age encryption provides an elegant solution that checks all these boxes.

In this post, I'll walk you through building a production-ready secrets management system that handles employee onboarding/offboarding, role-based access control, automated secret rotation, and GitHub Actions integration. We'll use YAML anchors for efficient configuration management and implement comprehensive audit logging throughout.

## Why SOPS?

Before diving into the implementation, let's address why SOPS stands out among the numerous secrets management solutions available:

### The Problem Space

Traditional approaches to secrets management often fall into these traps:
- **Plain text in environment variables**: Zero security, high risk
- **Encrypted files with shared passwords**: Poor access control, no audit trail
- **Cloud provider secret stores**: Vendor lock-in, complex local development
- **HashiCorp Vault**: Excellent but requires infrastructure and operational overhead

### Enter SOPS

SOPS hits the sweet spot by:
- **Encrypting values, not keys**: You can still see the structure of your configuration
- **Git-friendly**: Encrypted files are text-based and diff-able
- **Multi-cloud support**: Works with AWS KMS, GCP KMS, Azure Key Vault, age, and GPG
- **Minimal infrastructure**: No servers to maintain
- **Developer-friendly**: Integrates with existing workflows

### Why age Over GPG?

While SOPS supports multiple encryption backends, we chose [age](https://github.com/FiloSottile/age) for several reasons:

```bash
# age key generation is simple
$ age-keygen -o key.txt
Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

# Compare to GPG's complexity
$ gpg --full-generate-key  # Multiple prompts, expiry dates, subkeys...
```

Age advantages:
- **Simplicity**: No key expiry, web of trust, or subkeys to manage
- **Modern cryptography**: Uses modern algorithms by default
- **Small key format**: Keys are just text strings
- **No agent required**: No gpg-agent or keyring complexities

## Architecture Design

### Role-Based Access Model

Our implementation defines three distinct roles with different access levels:

```yaml
# Simplified view of our access matrix
developers:
  - development: ✅
  - staging: ❌
  - production: ❌
  - examples: ✅ (testing)

administrators:
  - development: ✅
  - staging: ✅
  - production: ✅
  - examples: ✅

ci_cd:
  - development: ✅ (deploy)
  - staging: ✅ (deploy)
  - production: ✅ (deploy with approval)
```

This model follows the principle of least privilege while maintaining operational efficiency.

### The Power of YAML Anchors

One of the clever features of our implementation is using YAML anchors in `.sops.yaml` to create reusable key groups. Here's how it works:

```yaml
# Define reusable key groups using YAML anchors
keys:
  developers: &developers
    - &alice_key age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
    - &bob_key age1cy0su9fwf8gzkdqh3r4r6xgc92fp8jqrjp4fvd4ak6vd3mc0jjpqnhymkw
  
  administrators: &administrators
    - &admin1_key age1yx3z8r0hnzjy9wh6fq5gldq3p7hxg6nfkz5vgqcdqhsj8tqxj8xq8w6qur
    - &admin2_key age1gwehlaawmwzqnn43gp0q6mmxxw8vj64sxz3jc85c2g0lyq5cy3kqpkjz9g

# Reference anchors in creation rules
creation_rules:
  - path_regex: secrets/dev/.*\.enc\.yaml$
    key_groups:
      - age:
          - *alice_key    # Developer keys referenced individually
          - *bob_key
          - *admin1_key   # Plus admin keys
          - *admin2_key
```

This approach provides several benefits:
1. **DRY principle**: Define each key once
2. **Clear organization**: Group keys by role
3. **Easy updates**: Change a key in one place
4. **Reduced errors**: No copy-paste mistakes

### Directory Structure

Our repository structure reflects the security boundaries:

```
sops-for-companies/
├── .sops.yaml                 # Central configuration
├── keys/
│   ├── developers/            # Public keys only
│   ├── administrators/
│   └── ci/
├── secrets/
│   ├── dev/                   # Environment isolation
│   ├── staging/
│   └── production/
├── scripts/                    # Automation tooling
└── .github/workflows/         # CI/CD integration
```

## Implementation Deep Dive

### Employee Onboarding Automation

The onboarding script (`scripts/onboard.sh`) automates the entire process of adding a new employee:

```bash
#!/usr/bin/env bash
# Simplified excerpt from onboard.sh

# Script supports both interactive and non-interactive modes
# Interactive mode:
read -p "Enter employee name: " employee_name
read -p "Select role (1=Developer, 2=Administrator): " role_choice

# 2. Handle key provisioning
echo "1) Enter existing age public key"
echo "2) Generate new age keypair"
read -p "Choice: " key_choice

if [ "$key_choice" == "2" ]; then
    # Generate new keypair
    keypair_output=$(age-keygen 2>&1)
    public_key=$(echo "$keypair_output" | grep "Public key:" | cut -d' ' -f3)
    private_key=$(echo "$keypair_output" | grep "AGE-SECRET-KEY")
    
    echo "IMPORTANT: Save this private key securely:"
    echo "$private_key"
fi

# 3. Add key to .sops.yaml using awk for reliable pattern matching
# This function handles YAML anchors correctly unlike sed
add_key_to_config "$employee_name" "$public_key" "$role"

# 4. Re-encrypt all secrets with new key
find secrets -name "*.enc.yaml" | while read -r secret; do
    sops updatekeys -y "$secret"
done

# 5. Commit with audit trail
git add .sops.yaml keys/
git commit -m "chore: onboard $employee_name as $role"

# Non-interactive mode example:
# ./onboard.sh --name alice --role developer --key age1... --non-interactive
```

Key features:
- **Interactive and CLI modes**: Supports both manual and automated workflows
- **Key generation**: Optional automatic keypair creation
- **Automatic re-encryption**: All secrets updated with new access
- **Git integration**: Changes tracked with meaningful commits
- **Cross-platform compatibility**: Works on macOS, Linux, and WSL

### Employee Offboarding with Security

Offboarding (`scripts/offboard.sh`) is even more critical from a security perspective:

```bash
# Key offboarding steps

# 1. Identify affected secrets
accessible_secrets=$(find_employee_accessible_secrets "$employee_name")

# 2. Remove key from configuration
remove_key_from_config "$employee_name"

# 3. Re-encrypt without removed key
for secret in $all_secrets; do
    sops updatekeys -y "$secret"
done

# 4. Optional secret rotation for critical environments
if [[ "$rotate_choice" == "yes" ]]; then
    for secret in $production_secrets; do
        rotate_secret "$secret"
    done
fi

# 5. Audit logging
echo "$(date -Iseconds) - Offboarded: $employee_name" >> offboarding_audit.log
```

Security considerations:
- **Immediate revocation**: Access removed instantly
- **Secret rotation**: Option to rotate compromised secrets
- **Audit trail**: Complete record of who was removed when
- **No cleanup required**: Employee can't decrypt even old Git history

### Secret Rotation Strategy

Our rotation script (`scripts/rotate-secrets.sh`) provides both automated and manual rotation:

```bash
# Automated rotation example
rotate_database_secret() {
    local secret_file="$1"
    local temp_file="/tmp/sops_rotate_$$.yaml"
    
    # Decrypt current secret
    sops -d "$secret_file" > "$temp_file"
    
    # Generate new credentials
    new_password=$(generate_password 32)
    yq eval ".data.password = \"$new_password\"" -i "$temp_file"
    
    # Add rotation metadata
    echo "# Rotated: $(date -Iseconds)" >> "$temp_file"
    
    # Re-encrypt
    sops -e "$temp_file" > "$secret_file"
    
    # Log rotation
    echo "$(date) | Rotated $secret_file" >> rotation.log
}
```

Rotation triggers:
- **Scheduled**: Quarterly rotation for compliance
- **Event-based**: After employee offboarding
- **On-demand**: Security incidents or suspected compromise

## CI/CD Integration

### GitHub Actions Setup

Our GitHub Actions integration provides three critical workflows:

#### 1. Pull Request Validation

```yaml
# .github/workflows/validate-secrets.yml
name: Validate Secrets

on:
  pull_request:
    paths:
      - 'secrets/**/*.enc.yaml'
      - '.sops.yaml'

jobs:
  validate:
    steps:
      - name: Check all secrets are encrypted
        run: |
          for file in $(find secrets -name "*.enc.yaml"); do
            if ! grep -q "sops:" "$file"; then
              echo "ERROR: $file is not encrypted!"
              exit 1
            fi
          done
      
      - name: Validate key references
        run: |
          # Ensure all referenced keys exist
          # Check for orphaned keys
          # Validate access patterns
```

#### 2. Secret Deployment

```yaml
# .github/workflows/deploy-secrets.yml
name: Deploy Secrets

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [development, staging, production]
      target:
        type: choice
        options: [kubernetes, aws-secrets-manager, azure-keyvault]

jobs:
  deploy:
    environment: ${{ inputs.environment }}  # Requires approval
    steps:
      - name: Setup decryption
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          # Decrypt and deploy to target platform
```

Key features:
- **Environment protection**: Production requires approval
- **Multi-platform support**: Deploy anywhere
- **Audit trail**: All deployments logged

#### 3. Weekly Audit

```yaml
# .github/workflows/audit-keys.yml
name: Audit Keys

on:
  schedule:
    - cron: '0 9 * * 1'  # Weekly on Mondays

jobs:
  audit:
    steps:
      - name: Analyze key usage
        run: |
          # Find unused keys
          # Check access patterns
          # Validate security posture
      
      - name: Create issue if problems found
        if: contains(findings, 'problem')
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              title: '⚠️ Security Audit Findings',
              body: auditReport
            })
```

### Setting Up the CI/CD Key

The GitHub Actions setup requires a dedicated service account:

```bash
# 1. Generate CI/CD keypair
$ age-keygen -o ci-key.txt
Public key: age1wqer098upgs5y5xgm8qgve0dg86j8gzmupqh9lw5w5hhkqwqcpkq2djzk5

# 2. Add public key to .sops.yaml under 'ci' group
# 3. Add private key to GitHub Secrets as SOPS_AGE_KEY
# 4. Configure environment protection rules
```

Important: The CI/CD key should only decrypt, never encrypt new secrets. This prevents automated systems from adding unauthorized secrets.

## Operational Excellence

### Testing and Validation

The repository includes comprehensive testing capabilities:
- **full-tests.sh**: Automated test suite for all scripts with visual feedback
- **verify-access.sh**: Validates user access permissions
- **Scripts CLI mode**: All scripts support `--non-interactive` for automation

### Monitoring and Alerting

Key metrics to track:
- **Key age**: Alert when keys exceed 90 days
- **Access attempts**: Failed decryption attempts
- **Rotation compliance**: Secrets not rotated on schedule
- **Orphaned keys**: Keys in config but not used

### Disaster Recovery

Prepare for these scenarios:

#### Lost Private Key
```bash
# Prevention: Backup keys in secure password manager
# Recovery: Administrator re-encrypts for new key
sops updatekeys -y secrets/dev/*.enc.yaml
```

#### Compromised Key
```bash
# Immediate response (now with CLI support)
./scripts/offboard.sh --name compromised_employee --non-interactive
./scripts/offboard.sh --name compromised_employee --rotate-secrets --non-interactive

# Follow-up
- Audit access logs
- Review git history for exposed secrets
- Update security policies
```

#### Corrupted Secret File
```bash
# Recovery from Git history
git log --follow secrets/production/database.enc.yaml
git checkout <last-known-good> -- secrets/production/database.enc.yaml
```

### Performance Considerations

SOPS performance tips for large deployments:

1. **Batch operations**: Re-encrypt multiple files in parallel
```bash
find secrets -name "*.enc.yaml" | \
  parallel -j 4 'sops updatekeys -y {}'
```

2. **Selective encryption**: Only encrypt sensitive values
```yaml
# .sops.yaml
# This regex tells SOPS to only encrypt specific fields
encrypted_regex: '^(data|stringData|password|apiKey|token|secret|key|credential)$'
```

3. **Use environment variables**: Set `SOPS_AGE_KEY_FILE` or `SOPS_AGE_KEY` to avoid repeated file reads

4. **Optimize script execution**: All scripts support non-interactive mode for faster batch operations

## Security Best Practices

### Defense in Depth

Layer your security controls:

1. **Repository level**: Branch protection, required reviews
2. **SOPS level**: Encryption, access control
3. **CI/CD level**: Environment protection, audit logs
4. **Runtime level**: Least privilege, secret rotation
5. **Monitoring level**: Alerting, anomaly detection

### Common Pitfalls to Avoid

#### 1. Committing Plaintext Secrets
```bash
# Bad: Forgetting to encrypt
$ echo "password: secret" > secrets/dev/config.yaml
$ git add . && git commit  # EXPOSED!

# Good: Always encrypt before committing
$ sops -e config.yaml > config.enc.yaml
$ rm config.yaml  # Remove plaintext
$ git add config.enc.yaml
```

#### 2. Weak Access Control
```yaml
# Bad: Everyone has production access
creation_rules:
  - path_regex: .*
    key_groups:
      - age: [*developers, *administrators]

# Good: Environment-based restrictions
creation_rules:
  - path_regex: secrets/production/.*
    key_groups:
      - age: [*administrators]  # Only admins
```

#### 3. No Key Rotation
```bash
# Bad: Using the same keys for years
# Keys never expire with age, but rotation is still important

# Good: Quarterly rotation schedule (crontab entry)
0 0 1 */3 * /path/to/scripts/rotate-secrets.sh --all --notify
```

### Compliance Considerations

For regulated industries, ensure:

- **Audit logging**: All access and changes logged
- **Separation of duties**: Developers can't access production
- **Key rotation**: Regular rotation schedule
- **Access reviews**: Quarterly access audits
- **Data residency**: Keys and secrets in approved regions

## Production Insights

After implementing this system across multiple organizations, here are key insights from real-world deployments:

### What Works Well

1. **YAML anchors** significantly reduce configuration errors and maintenance overhead
2. **Automated scripts** ensure consistent processes and reduce human error
3. **Git-based workflow** provides natural audit trail with zero additional infrastructure
4. **Role separation** prevents unauthorized access while maintaining usability
5. **CI/CD integration** enables secure deployments without manual intervention
6. **Non-interactive mode** allows full automation and integration with other tools
7. **Cross-platform compatibility** works seamlessly on macOS, Linux, and WSL

### What To Watch For

1. **Key sprawl**: Regular audits prevent accumulation of unused keys - use `scripts/list-keys.sh`
2. **Onboarding delays**: Have backup administrators across time zones for 24/7 coverage
3. **Rotation coordination**: Communicate rotation schedules to teams before executing
4. **Backup strategies**: Ensure multiple admins have recovery keys stored securely
5. **Training needs**: Developers need education on the new workflow - provide runbooks
6. **Git conflicts**: Multiple simultaneous onboardings can cause merge conflicts in `.sops.yaml`
7. **Performance impact**: Re-encrypting many files can be slow - use parallel processing

### Team Adoption Strategies

Successfully rolling out this system requires:

1. **Start small**: Begin with development environment
2. **Document everything**: Clear runbooks and troubleshooting guides
3. **Provide tooling**: Scripts support both interactive and CLI modes for automation
4. **Training sessions**: Hands-on workshops for teams
5. **Champion program**: Identify power users in each team
6. **Gradual migration**: Don't force immediate adoption

The included scripts all support non-interactive mode for CI/CD integration:
```bash
# Examples of non-interactive usage
./scripts/onboard.sh --name alice --role developer --key age1... --non-interactive
./scripts/offboard.sh --name bob --rotate-secrets --non-interactive
./scripts/verify-access.sh --non-interactive --json
```

## Advanced Topics

### Script Automation Examples

All scripts support non-interactive mode for CI/CD and automation:

```bash
# Batch onboarding from CSV
while IFS=, read -r name role pubkey; do
  ./scripts/onboard.sh --name "$name" --role "$role" --key "$pubkey" --non-interactive
done < employees.csv

# Automated offboarding with Slack notification
./scripts/offboard.sh --name "$employee" --rotate-secrets --non-interactive
curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"Offboarded $employee and rotated secrets\"}" \
  "$SLACK_WEBHOOK_URL"

# JSON output for monitoring dashboards
./scripts/verify-access.sh --non-interactive --json | jq '.accessible_environments'
```

### Multi-Region Deployments

For global deployments, consider:

```yaml
# Regional key management
creation_rules:
  - path_regex: secrets/us-east-1/.*
    kms: arn:aws:kms:us-east-1:xxx:key/xxx
    
  - path_regex: secrets/eu-west-1/.*
    kms: arn:aws:kms:eu-west-1:xxx:key/xxx
```

### Integration with Kubernetes

Deploy secrets directly to Kubernetes:

```bash
# Decrypt and create Kubernetes secret
sops -d secrets/production/database.enc.yaml | \
  kubectl create secret generic db-credentials \
  --from-file=config=/dev/stdin \
  --namespace=production
```

Or use tools like [Sealed Secrets](https://sealed-secrets.netlify.app/) or [External Secrets Operator](https://external-secrets.io/) for GitOps workflows.

### Terraform Integration

Use SOPS with Terraform for infrastructure secrets:

```hcl
# terraform/main.tf
data "sops_file" "secrets" {
  source_file = "secrets/terraform/aws.enc.yaml"
}

resource "aws_db_instance" "database" {
  master_password = data.sops_file.secrets.data["database_password"]
}
```

## Conclusion

Building a robust secrets management system doesn't require complex infrastructure or expensive solutions. With SOPS, age encryption, and well-designed processes, you can create a system that is:

- **Secure**: End-to-end encryption with role-based access control
- **Auditable**: Complete Git-based audit trail of all changes
- **Scalable**: From startups to enterprises (tested with 100+ secrets)
- **Developer-friendly**: Works with existing Git workflows
- **Cost-effective**: Zero infrastructure cost, no servers to maintain
- **Cross-platform**: Runs on macOS, Linux, and Windows (WSL)
- **Automation-ready**: Full CLI support for CI/CD integration

The implementation we've walked through provides a production-ready foundation that you can adapt to your organization's specific needs. All scripts have been tested in production environments and support both interactive use for humans and non-interactive mode for automation.

Start with the basics, add automation gradually, and continuously improve based on your team's feedback. The included test suite (`full-tests.sh`) makes it safe to experiment and learn the complete workflow.

Remember: the best secrets management system is one that your team will actually use. Make it simple, make it secure, and make it part of the natural workflow.

**Pro tip**: Start by running `./full-tests.sh` to see the complete system in action and validate your setup. The test script is non-destructive and will help you understand the workflow before deploying to production. It demonstrates all key features including onboarding, access control, and offboarding.

## Resources and Next Steps

### Get Started

1. Clone the repository: [github.com/cgoolsby/sops-for-companies](https://github.com/cgoolsby/sops-for-companies)
2. Install prerequisites:
   ```bash
   # macOS
   brew install sops age
   
   # Linux
   # Download SOPS from https://github.com/getsops/sops/releases
   # Install age: go install filippo.io/age/cmd/...@latest
   ```
3. Generate your first keypair:
   ```bash
   age-keygen -o key.txt
   # Save the output securely!
   ```
4. Encrypt your first secret:
   ```bash
   echo "password: supersecret" > secret.yaml
   sops -e secret.yaml > secret.enc.yaml
   rm secret.yaml  # Never leave plaintext!
   ```
5. Run the test suite to see everything in action:
   ```bash
   ./full-tests.sh
   # This demonstrates the complete lifecycle:
   # - Onboarding developers and administrators
   # - Verifying role-based access control
   # - Offboarding with secret rotation
   ```

### Additional Resources

- [SOPS Documentation](https://github.com/getsops/sops)
- [age Encryption](https://github.com/FiloSottile/age)
- [SOPS Terraform Provider](https://registry.terraform.io/providers/carlpett/sops)
- [External Secrets Operator](https://external-secrets.io/)

### Security Checklist

- **Never commit private keys** - Use .gitignore patterns
- **Rotate keys quarterly** - Schedule with `scripts/rotate-secrets.sh`
- **Audit access regularly** - Weekly GitHub Actions workflow included
- **Test disaster recovery** - Practice key recovery procedures
- **Monitor for anomalies** - Track failed decryption attempts
- **Use strong passphrases** - Protect private keys with password managers
- **Implement MFA** - Require for production deployments
- **Regular backups** - Keep encrypted backups of critical keys

### Need Help?

This implementation has been battle-tested in production environments. If you encounter issues:

1. **Check the scripts** - All scripts support `--help` for usage information
2. **Run the test suite** - `./full-tests.sh` validates your setup
3. **Review audit logs** - Check `offboarding_audit.log` for history
4. **Open an issue** - Report bugs or suggest improvements in the repository

Common troubleshooting:
- **"mapfile: command not found"** - Scripts are compatible with bash 3.2+ (macOS)
- **"cannot decrypt"** - Verify your key is in `.sops.yaml` and secrets were re-encrypted
- **"permission denied"** - Ensure scripts are executable: `chmod +x scripts/*.sh`

---

*This implementation has been tested with teams ranging from 5 to 500+ developers. If you found this helpful, please share it with your team. Secure secrets management is everyone's responsibility, and the more organizations that implement proper controls, the safer we all become.*

*All code in this post is from a working implementation available in the accompanying repository. The scripts have been tested on macOS (10.15+), Ubuntu (20.04+), and Windows WSL2.*

**Tags**: #DevSecOps #SecretsManagement #SOPS #Security #GitOps #InfrastructureAsCode