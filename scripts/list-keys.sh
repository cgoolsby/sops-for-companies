#!/usr/bin/env bash

# List Keys Script - Display current key assignments and access levels
# This script parses .sops.yaml to show who has access to what

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SOPS_CONFIG=".sops.yaml"
KEYS_DIR="keys"

# Function to print colored output
print_header() {
    echo -e "${CYAN}$1${NC}"
}

print_group() {
    echo -e "${BLUE}$1${NC}"
}

print_key() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_access() {
    echo -e "    ${YELLOW}→${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    if [ ! -f "$SOPS_CONFIG" ]; then
        echo -e "${RED}[ERROR]${NC} .sops.yaml configuration file not found." >&2
        exit 1
    fi
}

# Function to extract keys from a group
extract_group_keys() {
    local group="$1"
    local in_group=0
    local keys=()
    
    while IFS= read -r line; do
        # Check if we're entering the target group
        if [[ "$line" == *"${group}: &${group}"* ]]; then
            in_group=1
            continue
        fi
        
        # Check if we've exited the group (next group or creation_rules)
        if [ $in_group -eq 1 ]; then
            if [[ "$line" =~ ^[[:space:]]*[a-z]+: ]] || [[ "$line" == "creation_rules:" ]]; then
                break
            fi
            
            # Extract key if line contains one
            if [[ "$line" =~ -[[:space:]]*\&([a-z0-9_]+)_key[[:space:]]+(age1[a-z0-9]{58}) ]]; then
                local name="${BASH_REMATCH[1]}"
                local key="${BASH_REMATCH[2]}"
                keys+=("${name}:${key}")
            fi
        fi
    done < "$SOPS_CONFIG"
    
    printf '%s\n' "${keys[@]}"
}

# Function to determine access levels for each key
get_access_for_key() {
    local key_ref="$1"
    local access=()
    
    # Check each path rule for this key reference
    if grep -q "\*${key_ref}" "$SOPS_CONFIG"; then
        # Check development access
        if sed -n '/secrets\/dev\//,/^[[:space:]]*-[[:space:]]*path_regex:/p' "$SOPS_CONFIG" | grep -q "\*${key_ref}"; then
            access+=("Development secrets")
        fi
        
        # Check staging access
        if sed -n '/secrets\/staging\//,/^[[:space:]]*-[[:space:]]*path_regex:/p' "$SOPS_CONFIG" | grep -q "\*${key_ref}"; then
            access+=("Staging secrets")
        fi
        
        # Check production access
        if sed -n '/secrets\/production\//,/^[[:space:]]*-[[:space:]]*path_regex:/p' "$SOPS_CONFIG" | grep -q "\*${key_ref}"; then
            access+=("Production secrets")
        fi
        
        # Check examples access
        if sed -n '/examples\//,/^[[:space:]]*-[[:space:]]*path_regex:/p' "$SOPS_CONFIG" | grep -q "\*${key_ref}"; then
            access+=("Example secrets")
        fi
    fi
    
    printf '%s\n' "${access[@]}"
}

# Function to count total secrets
count_secrets() {
    local env="$1"
    local count=0
    
    if [ -d "secrets/${env}" ]; then
        count=$(find "secrets/${env}" -name "*.enc.yaml" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi
    
    echo "$count"
}

# Main function
main() {
    echo
    print_header "========================================="
    print_header "      SOPS Key Management Overview      "
    print_header "========================================="
    echo
    
    check_prerequisites
    
    # Display statistics
    print_header "📊 Repository Statistics:"
    echo -e "  Development secrets:  $(count_secrets 'dev')"
    echo -e "  Staging secrets:     $(count_secrets 'staging')"
    echo -e "  Production secrets:  $(count_secrets 'production')"
    echo
    
    # List Developers
    print_header "👥 Key Groups and Access Levels:"
    echo
    print_group "Developers:"
    dev_keys=()
    while IFS= read -r line; do
        dev_keys+=("$line")
    done < <(extract_group_keys "developers")
    
    if [ ${#dev_keys[@]} -eq 0 ]; then
        echo "  (No developers configured)"
    else
        for key_data in "${dev_keys[@]}"; do
            IFS=':' read -r name key <<< "$key_data"
            print_key "${name} (${key:0:20}...)"
            access=()
            while IFS= read -r line; do
                access+=("$line")
            done < <(get_access_for_key "${name}_key")
            for level in "${access[@]}"; do
                print_access "$level"
            done
        done
    fi
    echo
    
    # List Administrators
    print_group "Administrators:"
    admin_keys=()
    while IFS= read -r line; do
        admin_keys+=("$line")
    done < <(extract_group_keys "administrators")
    
    if [ ${#admin_keys[@]} -eq 0 ]; then
        echo "  (No administrators configured)"
    else
        for key_data in "${admin_keys[@]}"; do
            IFS=':' read -r name key <<< "$key_data"
            print_key "${name} (${key:0:20}...)"
            access=()
            while IFS= read -r line; do
                access+=("$line")
            done < <(get_access_for_key "${name}_key")
            for level in "${access[@]}"; do
                print_access "$level"
            done
        done
    fi
    echo
    
    # List CI/CD Keys
    print_group "CI/CD Service Accounts:"
    ci_keys=()
    while IFS= read -r line; do
        ci_keys+=("$line")
    done < <(extract_group_keys "ci")
    
    if [ ${#ci_keys[@]} -eq 0 ]; then
        echo "  (No CI/CD keys configured)"
    else
        for key_data in "${ci_keys[@]}"; do
            IFS=':' read -r name key <<< "$key_data"
            print_key "${name} (${key:0:20}...)"
            access=()
            while IFS= read -r line; do
                access+=("$line")
            done < <(get_access_for_key "${name}_key")
            for level in "${access[@]}"; do
                print_access "$level"
            done
        done
    fi
    echo
    
    # Summary
    total_keys=$((${#dev_keys[@]} + ${#admin_keys[@]} + ${#ci_keys[@]}))
    print_header "📋 Summary:"
    echo -e "  Total keys configured: ${total_keys}"
    echo -e "  Developers: ${#dev_keys[@]}"
    echo -e "  Administrators: ${#admin_keys[@]}"
    echo -e "  CI/CD accounts: ${#ci_keys[@]}"
    echo
    
    # Show key files on disk
    if [ -d "$KEYS_DIR" ]; then
        print_header "💾 Stored Public Keys:"
        for group in developers administrators ci; do
            if [ -d "${KEYS_DIR}/${group}" ]; then
                local count=$(find "${KEYS_DIR}/${group}" -name "*.age" -type f 2>/dev/null | wc -l | tr -d ' ')
                if [ "$count" -gt 0 ]; then
                    echo -e "  ${group}: ${count} key file(s)"
                fi
            fi
        done
    fi
    echo
    
    # Last modification time
    if [ -f "$SOPS_CONFIG" ]; then
        local last_modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$SOPS_CONFIG" 2>/dev/null || \
                             stat -c "%y" "$SOPS_CONFIG" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        print_header "🕒 Last configuration update: $last_modified"
    fi
    echo
}

# Run main function
main "$@"