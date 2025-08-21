#!/usr/bin/env bash

# Employee Onboarding Script for SOPS Key Management
# This script adds a new employee's public key to the appropriate group
# and re-encrypts all secrets to include their access
#
# Usage:
#   Interactive mode: ./onboard.sh
#   Non-interactive: ./onboard.sh --name <name> --role <developer|administrator> [--key <public-key>|--generate-key] [--non-interactive]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SOPS_CONFIG=".sops.yaml"
KEYS_DIR="keys"

# CLI parameters
EMPLOYEE_NAME=""
EMPLOYEE_ROLE=""
PUBLIC_KEY=""
GENERATE_KEY=false
NON_INTERACTIVE=false
SKIP_GIT=false

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to show usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Employee onboarding script for SOPS key management.

OPTIONS:
    -n, --name NAME           Employee name (lowercase, no spaces)
    -r, --role ROLE           Employee role (developer|administrator)
    -k, --key KEY             Age public key (conflicts with --generate-key)
    -g, --generate-key        Generate a new age keypair (conflicts with --key)
    --non-interactive         Run in non-interactive mode
    --skip-git                Skip git commit
    -h, --help                Show this help message

EXAMPLES:
    # Interactive mode
    $(basename "$0")
    
    # Add developer with existing key
    $(basename "$0") --name alice --role developer --key age1abc... --non-interactive
    
    # Add admin with generated key
    $(basename "$0") --name bob --role administrator --generate-key --non-interactive

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                EMPLOYEE_NAME="$2"
                shift 2
                ;;
            -r|--role)
                EMPLOYEE_ROLE="$2"
                shift 2
                ;;
            -k|--key)
                PUBLIC_KEY="$2"
                shift 2
                ;;
            -g|--generate-key)
                GENERATE_KEY=true
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --skip-git)
                SKIP_GIT=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Validate arguments in non-interactive mode
    if [ "$NON_INTERACTIVE" = true ]; then
        if [ -z "$EMPLOYEE_NAME" ]; then
            print_error "Employee name is required in non-interactive mode"
            exit 1
        fi
        if [ -z "$EMPLOYEE_ROLE" ]; then
            print_error "Employee role is required in non-interactive mode"
            exit 1
        fi
        if [ -z "$PUBLIC_KEY" ] && [ "$GENERATE_KEY" = false ]; then
            print_error "Either --key or --generate-key is required in non-interactive mode"
            exit 1
        fi
        if [ -n "$PUBLIC_KEY" ] && [ "$GENERATE_KEY" = true ]; then
            print_error "Cannot use both --key and --generate-key"
            exit 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if ! command -v sops &> /dev/null; then
        print_error "SOPS is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v age &> /dev/null && ! command -v gpg &> /dev/null; then
        print_error "Neither age nor gpg is installed. Please install one of them."
        exit 1
    fi
    
    if [ ! -f "$SOPS_CONFIG" ]; then
        print_error ".sops.yaml configuration file not found."
        exit 1
    fi
}

# Function to validate age public key format
validate_age_key() {
    local key="$1"
    if [[ ! "$key" =~ ^age1[a-z0-9]{58}$ ]]; then
        return 1
    fi
    return 0
}

# Function to add key to .sops.yaml
add_key_to_config() {
    local name="$1"
    local key="$2"
    local group="$3"
    local temp_file=".sops.yaml.tmp"
    
    # Create a backup
    cp "$SOPS_CONFIG" "${SOPS_CONFIG}.bak"
    
    # Add the key to the appropriate group in the YAML
    # Using awk for better pattern matching
    if [ "$group" == "developers" ]; then
        # Add to developers section
        awk -v key="    - &${name}_key $key" '
        /developers: &developers/ { print; print key; next }
        { print }
        ' "$SOPS_CONFIG" > "$temp_file"
        
        # Update dev creation rule
        awk -v ref="          - *${name}_key" '
        /path_regex: secrets\/dev\// { in_dev=1 }
        in_dev && /age:/ { print; print ref; in_dev=0; next }
        { print }
        ' "$temp_file" > "${temp_file}.2"
        
        # Update examples creation rule
        awk -v ref="          - *${name}_key" '
        /path_regex: examples\// { in_ex=1 }
        in_ex && /age:/ { print; print ref; in_ex=0; next }
        { print }
        ' "${temp_file}.2" > "$temp_file"
        
        rm -f "${temp_file}.2"
        
    elif [ "$group" == "administrators" ]; then
        # Add to administrators section
        awk -v key="    - &${name}_key $key" '
        /administrators: &administrators/ { print; print key; next }
        { print }
        ' "$SOPS_CONFIG" > "$temp_file"
        
        # Update all environment rules
        cp "$temp_file" "${temp_file}.2"
        for env in dev staging production; do
            awk -v ref="          - *${name}_key" -v pattern="path_regex: secrets/${env}/" '
            $0 ~ pattern { in_env=1 }
            in_env && /age:/ { print; print ref; in_env=0; next }
            { print }
            ' "${temp_file}.2" > "${temp_file}.3"
            cp "${temp_file}.3" "${temp_file}.2"
        done
        
        # Also update examples for admins
        awk -v ref="          - *${name}_key" '
        /path_regex: examples\// { in_ex=1 }
        in_ex && /age:/ { print; print ref; in_ex=0; next }
        { print }
        ' "${temp_file}.2" > "$temp_file"
        
        rm -f "${temp_file}.2" "${temp_file}.3"
    fi
    
    # Move the temp file to the actual config
    mv "$temp_file" "$SOPS_CONFIG"
    
    # Clean up backup files
    rm -f "${SOPS_CONFIG}.bak2" "${SOPS_CONFIG}.bak3"
}

# Function to re-encrypt all secrets
reencrypt_secrets() {
    print_info "Re-encrypting all secrets with updated keys..."
    
    # Find all encrypted yaml files
    find secrets -name "*.enc.yaml" -type f | while read -r secret_file; do
        print_info "Re-encrypting: $secret_file"
        
        # Check if file exists and is encrypted
        if [ -f "$secret_file" ]; then
            # Use updatekeys to re-encrypt with new key configuration
            sops updatekeys -y "$secret_file" 2>/dev/null || {
                print_warning "Could not re-encrypt $secret_file (might be empty or not yet encrypted)"
            }
        fi
    done
    
    # Also re-encrypt examples
    find examples -name "*.enc.yaml" -type f | while read -r example_file; do
        print_info "Re-encrypting example: $example_file"
        if [ -f "$example_file" ]; then
            sops updatekeys -y "$example_file" 2>/dev/null || {
                print_warning "Could not re-encrypt $example_file"
            }
        fi
    done
}

# Function to save public key to file
save_public_key() {
    local name="$1"
    local key="$2"
    local group="$3"
    
    local key_file="${KEYS_DIR}/${group}/${name}.age"
    echo "$key" > "$key_file"
    print_info "Public key saved to: $key_file"
}

# Main script
main() {
    # Parse arguments first
    parse_args "$@"
    
    if [ "$NON_INTERACTIVE" = false ]; then
        echo "======================================"
        echo "   SOPS Employee Onboarding Script   "
        echo "======================================"
        echo
    fi
    
    check_prerequisites
    
    # Get employee name
    if [ -z "$EMPLOYEE_NAME" ]; then
        read -p "Enter employee name (lowercase, no spaces): " EMPLOYEE_NAME
    fi
    
    if [[ ! "$EMPLOYEE_NAME" =~ ^[a-z0-9_]+$ ]]; then
        print_error "Invalid name format. Use only lowercase letters, numbers, and underscores."
        exit 1
    fi
    
    # Get employee role
    if [ -z "$EMPLOYEE_ROLE" ]; then
        echo "Select employee role:"
        echo "1) Developer"
        echo "2) Administrator"
        read -p "Enter choice (1 or 2): " role_choice
        
        case $role_choice in
            1)
                EMPLOYEE_ROLE="developer"
                ;;
            2)
                EMPLOYEE_ROLE="administrator"
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Map role to group name
    case $EMPLOYEE_ROLE in
        developer)
            employee_group="developers"
            ;;
        administrator)
            employee_group="administrators"
            ;;
        *)
            print_error "Invalid role: $EMPLOYEE_ROLE (must be 'developer' or 'administrator')"
            exit 1
            ;;
    esac
    
    # Get or generate public key
    if [ -z "$PUBLIC_KEY" ] && [ "$GENERATE_KEY" = false ]; then
        echo
        echo "How would you like to provide the public key?"
        echo "1) Enter existing age public key"
        echo "2) Generate new age keypair"
        read -p "Enter choice (1 or 2): " key_choice
        
        case $key_choice in
            1)
                read -p "Enter age public key: " PUBLIC_KEY
                ;;
            2)
                GENERATE_KEY=true
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Handle key generation if needed
    if [ "$GENERATE_KEY" = true ]; then
        print_info "Generating new age keypair..."
        keypair_output=$(age-keygen 2>&1)
        PUBLIC_KEY=$(echo "$keypair_output" | grep "Public key:" | cut -d' ' -f3)
        private_key=$(echo "$keypair_output" | grep "AGE-SECRET-KEY" | head -1)
        
        if [ "$NON_INTERACTIVE" = true ]; then
            echo "GENERATED_PRIVATE_KEY: $private_key"
        else
            echo
            print_warning "IMPORTANT: Save this private key securely and share it with the employee:"
            echo "$private_key"
            echo
            read -p "Press Enter when you have saved the private key..."
        fi
    fi
    
    # Validate public key
    if ! validate_age_key "$PUBLIC_KEY"; then
        print_error "Invalid age public key format: $PUBLIC_KEY"
        exit 1
    fi
    
    # Add key to configuration
    print_info "Adding key to SOPS configuration..."
    add_key_to_config "$EMPLOYEE_NAME" "$PUBLIC_KEY" "$employee_group"
    
    # Save public key to file
    save_public_key "$EMPLOYEE_NAME" "$PUBLIC_KEY" "$employee_group"
    
    # Re-encrypt secrets
    reencrypt_secrets
    
    # Commit changes
    if [ "$SKIP_GIT" = false ]; then
        print_info "Creating git commit..."
        git add "$SOPS_CONFIG" "${KEYS_DIR}/${employee_group}/${EMPLOYEE_NAME}.age"
        git add -u secrets/ examples/ 2>/dev/null || true
        git commit -m "chore: onboard employee ${EMPLOYEE_NAME} as ${employee_group}" \
                   -m "Added public key for ${EMPLOYEE_NAME}" \
                   -m "Re-encrypted all secrets with updated key configuration" || {
            print_warning "Could not create git commit. Please commit changes manually."
        }
    fi
    
    echo
    print_info "✅ Successfully onboarded ${EMPLOYEE_NAME} as ${employee_group}"
    if [ "$NON_INTERACTIVE" = false ]; then
        print_info "Next steps:"
        echo "  1. Push changes to repository"
        echo "  2. Share private key with employee (if generated)"
        echo "  3. Have employee verify access with: ./scripts/verify-access.sh"
    fi
}

# Run main function
main "$@"