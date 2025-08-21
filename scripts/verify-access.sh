#!/usr/bin/env bash

# Verify Access Script for SOPS
# This script helps employees verify their access to encrypted secrets
# Useful for testing after onboarding or configuration changes
#
# Usage:
#   Interactive mode: ./verify-access.sh
#   Non-interactive: ./verify-access.sh [--non-interactive] [--json]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons
CHECK="✓"
CROSS="✗"
LOCK="🔒"
KEY="🔑"

# CLI parameters
NON_INTERACTIVE=false
JSON_OUTPUT=false

# Function to print colored output
print_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

print_error() {
    echo -e "${RED}${CROSS}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to show usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Verify SOPS access for the current user.

OPTIONS:
    --non-interactive    Run in non-interactive mode (no prompts)
    --json               Output results in JSON format
    -h, --help           Show this help message

EXAMPLES:
    # Interactive verification
    $(basename "$0")
    
    # Non-interactive verification
    $(basename "$0") --non-interactive
    
    # JSON output for scripting
    $(basename "$0") --json --non-interactive

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
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
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v sops &> /dev/null; then
        missing_tools+=("sops")
    fi
    
    if ! command -v age &> /dev/null; then
        if ! command -v gpg &> /dev/null; then
            missing_tools+=("age or gpg")
        fi
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to detect key type and location
detect_key_config() {
    local key_type=""
    local key_location=""
    
    # Check for age key
    if [ -n "${SOPS_AGE_KEY:-}" ]; then
        key_type="age"
        key_location="SOPS_AGE_KEY environment variable"
    elif [ -n "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "${SOPS_AGE_KEY_FILE}" ]; then
        key_type="age"
        key_location="SOPS_AGE_KEY_FILE: ${SOPS_AGE_KEY_FILE}"
    elif [ -f "${HOME}/.config/sops/age/keys.txt" ]; then
        key_type="age"
        key_location="${HOME}/.config/sops/age/keys.txt"
    elif [ -f "${HOME}/Library/Application Support/sops/age/keys.txt" ]; then
        key_type="age"
        key_location="${HOME}/Library/Application Support/sops/age/keys.txt"
    elif command -v gpg &> /dev/null && gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
        key_type="gpg"
        key_location="GPG keyring"
    else
        key_type="none"
        key_location="No keys found"
    fi
    
    echo "${key_type}:${key_location}"
}

# Function to get current user's public key
get_user_public_key() {
    local key_type="$1"
    
    case "$key_type" in
        age)
            if [ -n "${SOPS_AGE_KEY:-}" ]; then
                # Extract public key from private key
                echo "$SOPS_AGE_KEY" | age-keygen -y 2>/dev/null || echo "unknown"
            elif [ -n "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "${SOPS_AGE_KEY_FILE}" ]; then
                # Extract public key from key file
                grep -v "^#" "${SOPS_AGE_KEY_FILE}" | head -1 | age-keygen -y 2>/dev/null || echo "unknown"
            elif [ -f "${HOME}/.config/sops/age/keys.txt" ]; then
                grep -v "^#" "${HOME}/.config/sops/age/keys.txt" | head -1 | age-keygen -y 2>/dev/null || echo "unknown"
            elif [ -f "${HOME}/Library/Application Support/sops/age/keys.txt" ]; then
                grep -v "^#" "${HOME}/Library/Application Support/sops/age/keys.txt" | head -1 | age-keygen -y 2>/dev/null || echo "unknown"
            else
                echo "unknown"
            fi
            ;;
        gpg)
            gpg --list-secret-keys --with-colons 2>/dev/null | grep "^fpr" | head -1 | cut -d: -f10 || echo "unknown"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Function to test decryption of a secret
test_decrypt() {
    local secret_file="$1"
    local temp_file="/tmp/sops_verify_$$.yaml"
    
    if sops -d "$secret_file" > "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        return 0
    else
        return 1
    fi
}

# Function to check access to a directory of secrets
check_directory_access() {
    local dir="$1"
    local accessible=0
    local total=0
    
    if [ -d "$dir" ]; then
        while IFS= read -r secret_file; do
            ((total++))
            if test_decrypt "$secret_file"; then
                ((accessible++))
            fi
        done < <(find "$dir" -name "*.enc.yaml" -type f 2>/dev/null)
    fi
    
    echo "${accessible}/${total}"
}

# Main function
main() {
    # Parse arguments first
    parse_args "$@"
    
    if [ "$JSON_OUTPUT" = true ]; then
        # JSON output mode - no headers
        :
    elif [ "$NON_INTERACTIVE" = false ]; then
        echo
        print_header "========================================="
        print_header "     SOPS Access Verification Tool      "
        print_header "========================================="
        echo
    fi
    
    check_prerequisites
    
    # Detect key configuration
    IFS=':' read -r key_type key_location <<< "$(detect_key_config)"
    
    if [ "$JSON_OUTPUT" = false ] && [ "$NON_INTERACTIVE" = false ]; then
        print_header "${KEY} Key Configuration:"
    fi
    
    if [ "$key_type" == "none" ]; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo '{"error": "No encryption keys found", "key_type": "none"}'
        else
            print_error "No encryption keys found!"
            if [ "$NON_INTERACTIVE" = false ]; then
                echo
                print_info "To set up age keys:"
                echo "  1. Generate a key: age-keygen -o ~/.config/sops/age/keys.txt"
                echo "  2. Or set SOPS_AGE_KEY_FILE environment variable"
                echo
                print_info "To set up GPG keys:"
                echo "  1. Generate a key: gpg --full-generate-key"
                echo "  2. Configure SOPS to use your GPG key"
            fi
        fi
        exit 1
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        print_success "Key type: $key_type"
        print_success "Location: $key_location"
    fi
    
    # Get public key
    public_key=$(get_user_public_key "$key_type")
    if [ "$JSON_OUTPUT" = false ]; then
        if [ "$public_key" != "unknown" ] && [ "$public_key" != "none" ]; then
            print_info "Public key: ${public_key:0:20}..."
        fi
        echo
    fi
    
    # Check if key is in .sops.yaml
    if [ "$JSON_OUTPUT" = false ] && [ "$NON_INTERACTIVE" = false ]; then
        print_header "${LOCK} Checking Configuration:"
    fi
    if [ -f ".sops.yaml" ]; then
        if [ "$key_type" == "age" ] && [ "$public_key" != "unknown" ]; then
            if grep -q "$public_key" .sops.yaml 2>/dev/null; then
                print_success "Your key is configured in .sops.yaml"
                
                # Determine role
                if grep -B5 "$public_key" .sops.yaml | grep -q "developers:"; then
                    print_info "Role: Developer"
                elif grep -B5 "$public_key" .sops.yaml | grep -q "administrators:"; then
                    print_info "Role: Administrator"
                elif grep -B5 "$public_key" .sops.yaml | grep -q "ci:"; then
                    print_info "Role: CI/CD Service"
                fi
            else
                print_warning "Your key is NOT in .sops.yaml"
                print_info "You may need to be onboarded: ./scripts/onboard.sh"
            fi
        else
            print_info "Manual verification required for $key_type keys"
        fi
    else
        print_error ".sops.yaml not found"
    fi
    if [ "$JSON_OUTPUT" = false ]; then
        echo
    fi
    
    # Test access to secrets
    if [ "$JSON_OUTPUT" = false ] && [ "$NON_INTERACTIVE" = false ]; then
        print_header "🔐 Testing Secret Access:"
    fi
    
    # Test development secrets
    echo -n "  Development secrets: "
    dev_access=$(check_directory_access "secrets/dev")
    IFS='/' read -r accessible total <<< "$dev_access"
    if [ "$total" -eq 0 ]; then
        echo "(no secrets found)"
    elif [ "$accessible" -eq "$total" ]; then
        print_success "Full access ($dev_access)"
    elif [ "$accessible" -gt 0 ]; then
        print_warning "Partial access ($dev_access)"
    else
        print_error "No access ($dev_access)"
    fi
    
    # Test staging secrets
    echo -n "  Staging secrets:     "
    staging_access=$(check_directory_access "secrets/staging")
    IFS='/' read -r accessible total <<< "$staging_access"
    if [ "$total" -eq 0 ]; then
        echo "(no secrets found)"
    elif [ "$accessible" -eq "$total" ]; then
        print_success "Full access ($staging_access)"
    elif [ "$accessible" -gt 0 ]; then
        print_warning "Partial access ($staging_access)"
    else
        print_error "No access ($staging_access)"
    fi
    
    # Test production secrets
    echo -n "  Production secrets:  "
    prod_access=$(check_directory_access "secrets/production")
    IFS='/' read -r accessible total <<< "$prod_access"
    if [ "$total" -eq 0 ]; then
        echo "(no secrets found)"
    elif [ "$accessible" -eq "$total" ]; then
        print_success "Full access ($prod_access)"
    elif [ "$accessible" -gt 0 ]; then
        print_warning "Partial access ($prod_access)"
    else
        print_error "No access ($prod_access)"
    fi
    
    # Test example secrets
    echo -n "  Example secrets:     "
    example_access=$(check_directory_access "examples")
    IFS='/' read -r accessible total <<< "$example_access"
    if [ "$total" -eq 0 ]; then
        echo "(no secrets found)"
    elif [ "$accessible" -eq "$total" ]; then
        print_success "Full access ($example_access)"
    elif [ "$accessible" -gt 0 ]; then
        print_warning "Partial access ($example_access)"
    else
        print_error "No access ($example_access)"
    fi
    echo
    
    # Detailed test of a specific file if requested
    if [ $# -gt 0 ]; then
        secret_file="$1"
        print_header "📄 Testing specific file: $secret_file"
        
        if [ -f "$secret_file" ]; then
            if test_decrypt "$secret_file"; then
                print_success "Can decrypt $secret_file"
                
                # Show first few lines of decrypted content (safely)
                print_info "Preview (first 5 lines):"
                sops -d "$secret_file" 2>/dev/null | head -5 | sed 's/^/    /'
            else
                print_error "Cannot decrypt $secret_file"
                print_info "This could mean:"
                echo "    • Your key is not authorized for this file"
                echo "    • The file uses a different encryption method"
                echo "    • The file is corrupted"
            fi
        else
            print_error "File not found: $secret_file"
        fi
        echo
    fi
    
    # Summary and recommendations
    print_header "📊 Summary:"
    
    # Count total accessible secrets
    total_accessible=0
    total_secrets=0
    for dir in "secrets/dev" "secrets/staging" "secrets/production" "examples"; do
        if [ -d "$dir" ]; then
            access=$(check_directory_access "$dir")
            IFS='/' read -r acc tot <<< "$access"
            ((total_accessible += acc))
            ((total_secrets += tot))
        fi
    done
    
    if [ "$total_secrets" -eq 0 ]; then
        print_warning "No encrypted secrets found in repository"
        print_info "Create secrets with: sops -e plaintext.yaml > secret.enc.yaml"
    elif [ "$total_accessible" -eq "$total_secrets" ]; then
        print_success "You have access to all $total_secrets secrets! 🎉"
    elif [ "$total_accessible" -gt 0 ]; then
        print_warning "You have access to $total_accessible out of $total_secrets secrets"
        print_info "This may be expected based on your role"
    else
        print_error "You don't have access to any secrets"
        print_info "Please contact an administrator for access"
    fi
    echo
}

# Run main function
main "$@"