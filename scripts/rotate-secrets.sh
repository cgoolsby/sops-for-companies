#!/usr/bin/env bash

# Secret Rotation Script for SOPS
# This script helps rotate specific secrets or all secrets in an environment
# Useful for security compliance and after employee offboarding

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ROTATION_LOG="secret_rotation.log"
BACKUP_DIR=".sops_backups"

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

# Function to check prerequisites
check_prerequisites() {
    if ! command -v sops &> /dev/null; then
        print_error "SOPS is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Some features will be limited."
    fi
}

# Function to create backup
backup_secret() {
    local secret_file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/$(basename "$secret_file").${timestamp}"
    
    mkdir -p "$BACKUP_DIR"
    cp "$secret_file" "$backup_file"
    print_info "Backed up to: $backup_file"
}

# Function to generate random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n' | cut -c1-"$length"
}

# Function to generate random API key
generate_api_key() {
    local prefix="${1:-sk}"
    local key=$(openssl rand -hex 32)
    echo "${prefix}_${key}"
}

# Function to rotate database credentials
rotate_database_secret() {
    local secret_file="$1"
    local temp_file="/tmp/sops_rotate_$$.yaml"
    
    print_info "Rotating database credentials in: $secret_file"
    
    # Decrypt the file
    if ! sops -d "$secret_file" > "$temp_file" 2>/dev/null; then
        print_error "Failed to decrypt $secret_file"
        return 1
    fi
    
    # Update passwords (this is a simplified example)
    if command -v yq &> /dev/null; then
        # If yq is available, use it for proper YAML manipulation
        yq eval '.data.password = "'$(generate_password)'"' -i "$temp_file"
        yq eval '.data.root_password = "'$(generate_password 40)'"' -i "$temp_file"
    else
        # Fallback to sed (less reliable but works for simple cases)
        sed -i.bak "s/password:.*/password: $(generate_password)/" "$temp_file"
        rm -f "${temp_file}.bak"
    fi
    
    # Add rotation metadata
    echo "# Last rotated: $(date -Iseconds)" >> "$temp_file"
    echo "# Rotation reason: Scheduled rotation" >> "$temp_file"
    
    # Re-encrypt the file
    sops -e "$temp_file" > "$secret_file"
    rm -f "$temp_file"
    
    # Log the rotation
    echo "$(date -Iseconds) | DATABASE | $secret_file | Success" >> "$ROTATION_LOG"
    
    return 0
}

# Function to rotate API keys
rotate_api_keys() {
    local secret_file="$1"
    local temp_file="/tmp/sops_rotate_$$.yaml"
    
    print_info "Rotating API keys in: $secret_file"
    
    # Decrypt the file
    if ! sops -d "$secret_file" > "$temp_file" 2>/dev/null; then
        print_error "Failed to decrypt $secret_file"
        return 1
    fi
    
    # Update API keys
    if command -v yq &> /dev/null; then
        # Generate new API keys for common services
        yq eval '.data.stripe_key = "'$(generate_api_key "sk_live")'"' -i "$temp_file"
        yq eval '.data.sendgrid_key = "'$(generate_api_key "SG")'"' -i "$temp_file"
        yq eval '.data.github_token = "'$(generate_api_key "ghp")'"' -i "$temp_file"
    else
        # Fallback approach
        sed -i.bak "s/api_key:.*/api_key: $(generate_api_key)/" "$temp_file"
        rm -f "${temp_file}.bak"
    fi
    
    # Add rotation metadata
    echo "# Last rotated: $(date -Iseconds)" >> "$temp_file"
    
    # Re-encrypt the file
    sops -e "$temp_file" > "$secret_file"
    rm -f "$temp_file"
    
    # Log the rotation
    echo "$(date -Iseconds) | API_KEYS | $secret_file | Success" >> "$ROTATION_LOG"
    
    return 0
}

# Function to rotate generic secret
rotate_generic_secret() {
    local secret_file="$1"
    local temp_file="/tmp/sops_rotate_$$.yaml"
    
    print_info "Rotating generic secrets in: $secret_file"
    
    # Decrypt the file
    if ! sops -d "$secret_file" > "$temp_file" 2>/dev/null; then
        print_error "Failed to decrypt $secret_file"
        return 1
    fi
    
    # Add rotation timestamp
    echo "" >> "$temp_file"
    echo "# Rotated: $(date -Iseconds)" >> "$temp_file"
    echo "# Note: Manual update required for actual secret values" >> "$temp_file"
    
    # Re-encrypt the file
    sops -e "$temp_file" > "$secret_file"
    rm -f "$temp_file"
    
    # Log the rotation
    echo "$(date -Iseconds) | GENERIC | $secret_file | Manual update required" >> "$ROTATION_LOG"
    
    print_warning "Generic rotation completed. Manual update of secret values required."
    return 0
}

# Function to detect secret type
detect_secret_type() {
    local secret_file="$1"
    local content=$(sops -d "$secret_file" 2>/dev/null || echo "")
    
    if [[ "$content" == *"database"* ]] || [[ "$content" == *"password"* ]] || [[ "$content" == *"mysql"* ]] || [[ "$content" == *"postgres"* ]]; then
        echo "database"
    elif [[ "$content" == *"api_key"* ]] || [[ "$content" == *"token"* ]] || [[ "$content" == *"stripe"* ]] || [[ "$content" == *"sendgrid"* ]]; then
        echo "api"
    else
        echo "generic"
    fi
}

# Function to rotate a single secret file
rotate_single_secret() {
    local secret_file="$1"
    
    if [ ! -f "$secret_file" ]; then
        print_error "File not found: $secret_file"
        return 1
    fi
    
    # Create backup
    backup_secret "$secret_file"
    
    # Detect type and rotate accordingly
    local secret_type=$(detect_secret_type "$secret_file")
    
    case "$secret_type" in
        database)
            rotate_database_secret "$secret_file"
            ;;
        api)
            rotate_api_keys "$secret_file"
            ;;
        *)
            rotate_generic_secret "$secret_file"
            ;;
    esac
}

# Function to rotate all secrets in an environment
rotate_environment_secrets() {
    local environment="$1"
    local secret_dir="secrets/${environment}"
    
    if [ ! -d "$secret_dir" ]; then
        print_error "Environment directory not found: $secret_dir"
        return 1
    fi
    
    print_info "Rotating all secrets in ${environment} environment..."
    
    find "$secret_dir" -name "*.enc.yaml" -type f | while read -r secret_file; do
        rotate_single_secret "$secret_file"
    done
}

# Main script
main() {
    echo
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${CYAN}      SOPS Secret Rotation Tool      ${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo
    
    check_prerequisites
    
    # Show menu
    echo "Select rotation option:"
    echo "1) Rotate specific secret file"
    echo "2) Rotate all secrets in an environment"
    echo "3) Rotate all production secrets"
    echo "4) Show rotation history"
    read -p "Enter choice (1-4): " choice
    
    case $choice in
        1)
            # Rotate specific file
            echo
            echo "Available secret files:"
            find secrets -name "*.enc.yaml" -type f | nl
            read -p "Enter file number or path: " file_input
            
            if [[ "$file_input" =~ ^[0-9]+$ ]]; then
                # User entered a number
                secret_file=$(find secrets -name "*.enc.yaml" -type f | sed -n "${file_input}p")
            else
                # User entered a path
                secret_file="$file_input"
            fi
            
            if [ -n "$secret_file" ]; then
                rotate_single_secret "$secret_file"
            else
                print_error "Invalid selection"
                exit 1
            fi
            ;;
            
        2)
            # Rotate environment
            echo
            echo "Select environment:"
            echo "1) Development"
            echo "2) Staging"
            echo "3) Production"
            read -p "Enter choice (1-3): " env_choice
            
            case $env_choice in
                1) rotate_environment_secrets "dev" ;;
                2) rotate_environment_secrets "staging" ;;
                3) rotate_environment_secrets "production" ;;
                *) print_error "Invalid choice"; exit 1 ;;
            esac
            ;;
            
        3)
            # Rotate all production
            print_warning "This will rotate ALL production secrets!"
            read -p "Are you sure? Type 'yes' to confirm: " confirm
            
            if [ "$confirm" == "yes" ]; then
                rotate_environment_secrets "production"
            else
                print_info "Rotation cancelled"
                exit 0
            fi
            ;;
            
        4)
            # Show history
            if [ -f "$ROTATION_LOG" ]; then
                echo
                echo -e "${CYAN}Recent rotation history:${NC}"
                tail -20 "$ROTATION_LOG" | column -t -s '|'
            else
                print_info "No rotation history found"
            fi
            ;;
            
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo
    print_info "✅ Rotation complete!"
    
    if [ -f "$ROTATION_LOG" ]; then
        echo
        print_warning "Important next steps:"
        echo "  1. Update the actual services with new credentials"
        echo "  2. Test that services can authenticate with new credentials"
        echo "  3. Commit and push the rotated secrets"
        echo "  4. Monitor services for any authentication issues"
    fi
}

# Run main function
main "$@"