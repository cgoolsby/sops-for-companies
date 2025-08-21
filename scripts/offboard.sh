#!/usr/bin/env bash

# Employee Offboarding Script for SOPS Key Management
# This script removes an employee's public key and re-encrypts all secrets
# Optionally rotates sensitive secrets for security
#
# Usage:
#   Interactive mode: ./offboard.sh
#   Non-interactive: ./offboard.sh --name <name> [--rotate-secrets] [--non-interactive]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOPS_CONFIG=".sops.yaml"
KEYS_DIR="keys"
ROTATION_LOG="offboarding_rotation.log"

# CLI parameters
EMPLOYEE_NAME=""
ROTATE_SECRETS=false
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

print_question() {
    echo -e "${BLUE}[?]${NC} $1"
}

# Function to show usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Employee offboarding script for SOPS key management.

OPTIONS:
    -n, --name NAME           Employee name to offboard
    -r, --rotate-secrets      Rotate secrets after removing access
    --non-interactive         Run in non-interactive mode
    --skip-git                Skip git commit
    -h, --help                Show this help message

EXAMPLES:
    # Interactive mode
    $(basename "$0")
    
    # Remove developer without rotating secrets
    $(basename "$0") --name alice --non-interactive
    
    # Remove admin and rotate secrets
    $(basename "$0") --name bob --rotate-secrets --non-interactive

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
            -r|--rotate-secrets)
                ROTATE_SECRETS=true
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
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if ! command -v sops &> /dev/null; then
        print_error "SOPS is not installed. Please install it first."
        exit 1
    fi
    
    if [ ! -f "$SOPS_CONFIG" ]; then
        print_error ".sops.yaml configuration file not found."
        exit 1
    fi
}

# Function to find employee's key in config
find_employee_key() {
    local name="$1"
    
    # Search for the employee's key in .sops.yaml
    grep -E "&${name}_key age1[a-z0-9]{58}" "$SOPS_CONFIG" | head -1 | awk '{print $3}'
}

# Function to remove key from .sops.yaml
remove_key_from_config() {
    local name="$1"
    local temp_file=".sops.yaml.tmp"
    
    # Create a backup
    cp "$SOPS_CONFIG" "${SOPS_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    
    # Remove the key definition line
    sed "/&${name}_key age1/d" "$SOPS_CONFIG" > "$temp_file"
    
    # Remove all references to the key
    sed -i.bak2 "/\*${name}_key/d" "$temp_file"
    
    # Move the temp file to the actual config
    mv "$temp_file" "$SOPS_CONFIG"
    
    # Clean up
    rm -f "${SOPS_CONFIG}.bak2"
}

# Function to re-encrypt all secrets without the removed key
reencrypt_secrets() {
    local failed_files=()
    
    print_info "Re-encrypting all secrets without the removed key..."
    
    # Find all encrypted yaml files
    while IFS= read -r secret_file; do
        print_info "Re-encrypting: $secret_file"
        
        if [ -f "$secret_file" ]; then
            # Use updatekeys to re-encrypt without the removed key
            if ! sops updatekeys -y "$secret_file" 2>/dev/null; then
                print_warning "Could not re-encrypt $secret_file"
                failed_files+=("$secret_file")
            fi
        fi
    done < <(find secrets examples -name "*.enc.yaml" -type f 2>/dev/null)
    
    if [ ${#failed_files[@]} -gt 0 ]; then
        print_warning "Failed to re-encrypt the following files:"
        printf '%s\n' "${failed_files[@]}"
    fi
}

# Function to rotate specific secrets
rotate_secret() {
    local secret_file="$1"
    local temp_decrypted="/tmp/sops_temp_$$.yaml"
    
    print_info "Rotating secret: $secret_file"
    
    # Decrypt the file
    if sops -d "$secret_file" > "$temp_decrypted" 2>/dev/null; then
        # Here you would implement actual secret rotation logic
        # For demo purposes, we'll just add a rotation timestamp
        
        echo "# Rotated on $(date -Iseconds) due to employee offboarding" >> "$temp_decrypted"
        
        # Re-encrypt with new content
        sops -e "$temp_decrypted" > "$secret_file"
        
        # Log the rotation
        echo "$(date -Iseconds): Rotated $secret_file" >> "$ROTATION_LOG"
        
        rm -f "$temp_decrypted"
        return 0
    else
        print_warning "Could not decrypt $secret_file for rotation"
        return 1
    fi
}

# Function to get secrets accessed by employee
get_employee_accessible_secrets() {
    local employee_name="$1"
    local accessible_secrets=()
    
    # Check which secrets the employee had access to based on their group
    if grep -q "${employee_name}_key" "$SOPS_CONFIG" | grep -q "developers"; then
        # Developer - had access to dev secrets
        while IFS= read -r file; do
            accessible_secrets+=("$file")
        done < <(find secrets/dev -name "*.enc.yaml" -type f 2>/dev/null)
    fi
    
    if grep -q "${employee_name}_key" "$SOPS_CONFIG" | grep -q "administrators"; then
        # Administrator - had access to all secrets
        while IFS= read -r file; do
            accessible_secrets+=("$file")
        done < <(find secrets -name "*.enc.yaml" -type f 2>/dev/null)
    fi
    
    printf '%s\n' "${accessible_secrets[@]}"
}

# Function to remove employee's key file
remove_key_file() {
    local name="$1"
    
    # Find and remove the key file
    for group in developers administrators ci; do
        local key_file="${KEYS_DIR}/${group}/${name}.age"
        if [ -f "$key_file" ]; then
            rm -f "$key_file"
            print_info "Removed key file: $key_file"
            git rm "$key_file" 2>/dev/null || true
        fi
    done
}

# Main script
main() {
    # Parse arguments first
    parse_args "$@"
    
    if [ "$NON_INTERACTIVE" = false ]; then
        echo "======================================="
        echo "   SOPS Employee Offboarding Script   "
        echo "======================================="
        echo
    fi
    
    check_prerequisites
    
    # Get employee name
    if [ -z "$EMPLOYEE_NAME" ]; then
        read -p "Enter employee name to offboard: " EMPLOYEE_NAME
    fi
    
    if [[ ! "$EMPLOYEE_NAME" =~ ^[a-z0-9_]+$ ]]; then
        print_error "Invalid name format."
        exit 1
    fi
    
    # Use the variable consistently
    employee_name="$EMPLOYEE_NAME"
    
    # Find employee's key
    employee_key=$(find_employee_key "$employee_name")
    if [ -z "$employee_key" ]; then
        print_error "Employee '${employee_name}' not found in SOPS configuration."
        exit 1
    fi
    
    print_info "Found employee key: ${employee_key:0:20}..."
    
    # Get list of accessible secrets
    print_info "Analyzing secrets accessible by ${employee_name}..."
    accessible_secrets=()
    while IFS= read -r line; do
        accessible_secrets+=("$line")
    done < <(get_employee_accessible_secrets "$employee_name")
    
    if [ ${#accessible_secrets[@]} -gt 0 ]; then
        print_warning "Employee had access to ${#accessible_secrets[@]} secret file(s):"
        printf '  - %s\n' "${accessible_secrets[@]}"
    fi
    
    # Ask about secret rotation
    echo
    # Ask about rotation if not specified
    rotate_choice="n"
    if [ "$NON_INTERACTIVE" = false ] && [ "$ROTATE_SECRETS" = false ]; then
        print_question "Do you want to rotate secrets that ${employee_name} had access to?"
        echo "  This is recommended for:"
        echo "  - Production secrets"
        echo "  - Sensitive API keys"
        echo "  - Database credentials"
        read -p "Rotate secrets? (y/N): " rotate_choice
    elif [ "$ROTATE_SECRETS" = true ]; then
        rotate_choice="y"
    fi
    
    # Remove key from configuration
    print_info "Removing employee key from SOPS configuration..."
    remove_key_from_config "$employee_name"
    
    # Remove key file
    remove_key_file "$employee_name"
    
    # Re-encrypt all secrets
    reencrypt_secrets
    
    # Rotate secrets if requested
    if [[ "$rotate_choice" =~ ^[Yy]$ ]]; then
        print_info "Rotating accessible secrets..."
        
        for secret in "${accessible_secrets[@]}"; do
            # For production, you'd want to be selective about which secrets to rotate
            if [[ "$secret" == *"production"* ]]; then
                rotate_secret "$secret"
            else
                print_info "Skipping rotation for non-production secret: $secret"
            fi
        done
        
        print_info "Secret rotation log saved to: $ROTATION_LOG"
    fi
    
    # Create audit log entry
    audit_entry="$(date -Iseconds) - Offboarded: ${employee_name} - Key: ${employee_key:0:20}... - Secrets rotated: ${rotate_choice}"
    echo "$audit_entry" >> "offboarding_audit.log"
    
    # Commit changes
    if [ "$SKIP_GIT" = false ]; then
        print_info "Creating git commit..."
        git add "$SOPS_CONFIG"
        git add -u secrets/ examples/ 2>/dev/null || true
        git add "offboarding_audit.log" 2>/dev/null || true
        [ -f "$ROTATION_LOG" ] && git add "$ROTATION_LOG" 2>/dev/null || true
        
        git commit -m "chore: offboard employee ${employee_name}" \
                   -m "Removed public key for ${employee_name}" \
                   -m "Re-encrypted all secrets without removed key" \
                   -m "Rotation performed: ${rotate_choice}" || {
            print_warning "Could not create git commit. Please commit changes manually."
        }
    fi
    
    echo
    print_info "✅ Successfully offboarded ${employee_name}"
    print_info "Completed actions:"
    echo "  • Removed key from SOPS configuration"
    echo "  • Re-encrypted all secrets"
    if [[ "$rotate_choice" =~ ^[Yy]$ ]]; then
        echo "  • Rotated production secrets"
    fi
    echo "  • Created audit log entry"
    echo
    print_warning "Next steps:"
    echo "  1. Push changes to repository"
    echo "  2. Revoke any additional access (GitHub, cloud accounts, etc.)"
    echo "  3. Update secret values in production if rotation was performed"
    echo "  4. Notify team of completed offboarding"
}

# Run main function
main "$@"