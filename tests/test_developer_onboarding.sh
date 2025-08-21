#!/usr/bin/env bash

# SOPS for Companies - Developer Onboarding Test Suite
# Tests the complete developer onboarding workflow

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test configuration
TEST_DIR="/tmp/sops-test-$$"
TEST_DEV="testdev"
TEST_ADMIN="testadmin"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Cleanup on exit
trap cleanup EXIT

cleanup() {
    echo -e "\n${YELLOW}Cleaning up test environment...${NC}"
    [ -f "$TEST_DIR/.sops.yaml.backup" ] && cp "$TEST_DIR/.sops.yaml.backup" .sops.yaml
    rm -rf "$TEST_DIR"
}

# Test output functions
print_test_header() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
}

print_test() {
    echo -e "\n${BLUE}TEST:${NC} $1"
    ((TESTS_TOTAL++))
}

pass_test() {
    echo -e "  ${GREEN}✅ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo -e "  ${RED}❌ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [ "$expected" = "$actual" ]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="$2"
    
    if [ -f "$file" ]; then
        pass_test "$message"
        return 0
    else
        fail_test "$message (file not found: $file)"
        return 1
    fi
}

assert_command_succeeds() {
    local command="$1"
    local message="$2"
    
    if eval "$command" >/dev/null 2>&1; then
        pass_test "$message"
        return 0
    else
        fail_test "$message (command failed: $command)"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local message="$2"
    
    if eval "$command" >/dev/null 2>&1; then
        fail_test "$message (command should have failed: $command)"
        return 1
    else
        pass_test "$message"
        return 0
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        pass_test "$message"
        return 0
    else
        fail_test "$message (pattern not found in $file: $pattern)"
        return 1
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    local message="$3"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        fail_test "$message (pattern should not exist in $file: $pattern)"
        return 1
    else
        pass_test "$message"
        return 0
    fi
}

# Test Suite Start
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Developer Onboarding Test Suite                      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

# Setup test environment
print_test_header "Test Setup"
mkdir -p "$TEST_DIR"

print_test "Backing up current configuration"
if [ -f ".sops.yaml" ]; then
    cp .sops.yaml "$TEST_DIR/.sops.yaml.backup"
    pass_test "Configuration backed up"
else
    fail_test "No .sops.yaml found to backup"
    exit 1
fi

print_test "Verifying prerequisites"
assert_command_succeeds "which sops" "SOPS is installed"
assert_command_succeeds "which age" "age is installed"
assert_command_succeeds "which age-keygen" "age-keygen is installed"

# Use admin1's key for privileged operations
ADMIN_KEY="AGE-SECRET-KEY-1MG38AFNCSJMQCKKD6NM0RG9RG40GSUWSNTUJRKVXL9SDCLG6Z6SSMCL9CX"
echo "$ADMIN_KEY" > "$TEST_DIR/admin.key"

# Test 1: Key Generation
print_test_header "Test 1: Developer Key Generation"

print_test "Generating age keypair for developer"
age-keygen > "$TEST_DIR/dev_keys.txt" 2>&1
assert_file_exists "$TEST_DIR/dev_keys.txt" "Keypair file created"

DEV_PUBLIC=$(grep "Public key:" "$TEST_DIR/dev_keys.txt" | cut -d' ' -f3)
DEV_PRIVATE=$(grep "AGE-SECRET-KEY" "$TEST_DIR/dev_keys.txt")

assert_equals "age1" "${DEV_PUBLIC:0:4}" "Public key has correct prefix"
assert_equals "AGE-SECRET-KEY-1" "${DEV_PRIVATE:0:16}" "Private key has correct prefix"

# Test 2: Configuration Modification
print_test_header "Test 2: SOPS Configuration Modification"

print_test "Adding developer to .sops.yaml"

# Add to keys section
awk -v key="    - &${TEST_DEV}_key $DEV_PUBLIC" '
/developers: &developers/ { print; print key; next }
{ print }
' .sops.yaml > "$TEST_DIR/temp1.yaml"

assert_contains "$TEST_DIR/temp1.yaml" "${TEST_DEV}_key" "Developer key added to keys section"

# Add to dev creation rule
awk -v ref="          - *${TEST_DEV}_key" '
/secrets\/dev\/.*\.enc\.yaml/ { in_dev=1 }
in_dev && /age:/ { print; print ref; in_dev=0; next }
{ print }
' "$TEST_DIR/temp1.yaml" > "$TEST_DIR/temp2.yaml"

assert_contains "$TEST_DIR/temp2.yaml" "*${TEST_DEV}_key" "Developer key reference added to dev rule"

# Apply configuration
cp "$TEST_DIR/temp2.yaml" .sops.yaml

print_test "Validating YAML syntax"
assert_command_succeeds "python3 -c 'import yaml; yaml.safe_load(open(\".sops.yaml\"))'" "YAML syntax is valid"

# Test 3: Secret Re-encryption
print_test_header "Test 3: Secret Re-encryption"

print_test "Re-encrypting development secrets"
if [ -f "secrets/dev/database.enc.yaml" ]; then
    assert_command_succeeds "SOPS_AGE_KEY_FILE=\"$TEST_DIR/admin.key\" sops updatekeys -y secrets/dev/database.enc.yaml" \
        "Development database secrets re-encrypted"
else
    fail_test "Development database secrets file not found"
fi

if [ -f "examples/sample-secret.enc.yaml" ]; then
    assert_command_succeeds "SOPS_AGE_KEY_FILE=\"$TEST_DIR/admin.key\" sops updatekeys -y examples/sample-secret.enc.yaml" \
        "Example secrets re-encrypted"
else
    fail_test "Example secrets file not found"
fi

# Test 4: Access Verification
print_test_header "Test 4: Developer Access Verification"

echo "$DEV_PRIVATE" > "$TEST_DIR/dev.key"

print_test "Testing developer access to development environment"
if [ -f "secrets/dev/database.enc.yaml" ]; then
    assert_command_succeeds "SOPS_AGE_KEY_FILE=\"$TEST_DIR/dev.key\" sops -d secrets/dev/database.enc.yaml" \
        "Developer can decrypt development secrets"
    
    # Verify we can actually read a value
    PASSWORD=$(SOPS_AGE_KEY_FILE="$TEST_DIR/dev.key" sops -d secrets/dev/database.enc.yaml 2>/dev/null | grep "password:" | head -1 | cut -d' ' -f2)
    if [ -n "$PASSWORD" ]; then
        pass_test "Developer can read actual secret values"
    else
        fail_test "Developer cannot read secret values"
    fi
fi

print_test "Testing developer access to production environment"
if [ -f "secrets/production/credentials.enc.yaml" ]; then
    assert_command_fails "SOPS_AGE_KEY_FILE=\"$TEST_DIR/dev.key\" sops -d secrets/production/credentials.enc.yaml" \
        "Developer cannot decrypt production secrets (correct)"
else
    fail_test "Production credentials file not found"
fi

# Test 5: Developer Offboarding
print_test_header "Test 5: Developer Offboarding"

print_test "Removing developer from configuration"
grep -v "${TEST_DEV}_key" .sops.yaml > "$TEST_DIR/temp3.yaml"
cp "$TEST_DIR/temp3.yaml" .sops.yaml

assert_not_contains ".sops.yaml" "${TEST_DEV}_key" "Developer key removed from configuration"

print_test "Re-encrypting secrets after offboarding"
if [ -f "secrets/dev/database.enc.yaml" ]; then
    assert_command_succeeds "SOPS_AGE_KEY_FILE=\"$TEST_DIR/admin.key\" sops updatekeys -y secrets/dev/database.enc.yaml" \
        "Secrets re-encrypted without developer key"
fi

print_test "Verifying access revocation"
if [ -f "secrets/dev/database.enc.yaml" ]; then
    assert_command_fails "SOPS_AGE_KEY_FILE=\"$TEST_DIR/dev.key\" sops -d secrets/dev/database.enc.yaml" \
        "Offboarded developer cannot decrypt secrets"
fi

# Test 6: Multiple Developer Management
print_test_header "Test 6: Multiple Developer Management"

print_test "Adding multiple developers simultaneously"

# Generate keys for two developers
age-keygen > "$TEST_DIR/dev2_keys.txt" 2>&1
DEV2_PUBLIC=$(grep "Public key:" "$TEST_DIR/dev2_keys.txt" | cut -d' ' -f3)

age-keygen > "$TEST_DIR/dev3_keys.txt" 2>&1
DEV3_PUBLIC=$(grep "Public key:" "$TEST_DIR/dev3_keys.txt" | cut -d' ' -f3)

# Add both to configuration
cp "$TEST_DIR/.sops.yaml.backup" .sops.yaml
awk -v key1="    - &testdev2_key $DEV2_PUBLIC" -v key2="    - &testdev3_key $DEV3_PUBLIC" '
/developers: &developers/ { print; print key1; print key2; next }
{ print }
' .sops.yaml > "$TEST_DIR/multi.yaml"

cp "$TEST_DIR/multi.yaml" .sops.yaml

assert_contains ".sops.yaml" "testdev2_key" "First developer added"
assert_contains ".sops.yaml" "testdev3_key" "Second developer added"

# Test 7: Configuration Validation
print_test_header "Test 7: Configuration File Validation"

print_test "Testing YAML structure integrity"
assert_command_succeeds "python3 -c 'import yaml; d=yaml.safe_load(open(\".sops.yaml\")); assert \"creation_rules\" in d'" \
    "creation_rules section exists"

assert_command_succeeds "python3 -c 'import yaml; d=yaml.safe_load(open(\".sops.yaml\")); assert \"keys\" in d'" \
    "keys section exists"

print_test "Testing path patterns"
python3 -c "
import yaml
config = yaml.safe_load(open('.sops.yaml'))
rules = config.get('creation_rules', [])
has_dev = any('secrets/dev' in r.get('path_regex', '') for r in rules)
has_prod = any('secrets/production' in r.get('path_regex', '') for r in rules)
assert has_dev and has_prod
" 2>/dev/null

if [ $? -eq 0 ]; then
    pass_test "Path patterns are correctly configured"
else
    fail_test "Path patterns are missing or incorrect"
fi

# Test 8: Error Handling
print_test_header "Test 8: Error Handling"

print_test "Testing invalid key format handling"
INVALID_KEY="not-a-valid-age-key"

# Try to add invalid key
awk -v key="    - &invalid_key $INVALID_KEY" '
/developers: &developers/ { print; print key; next }
{ print }
' "$TEST_DIR/.sops.yaml.backup" > "$TEST_DIR/invalid.yaml"

cp "$TEST_DIR/invalid.yaml" .sops.yaml

if [ -f "secrets/dev/database.enc.yaml" ]; then
    assert_command_fails "SOPS_AGE_KEY_FILE=\"$TEST_DIR/admin.key\" sops updatekeys -y secrets/dev/database.enc.yaml 2>/dev/null" \
        "Invalid key format is rejected"
fi

# Restore valid configuration
cp "$TEST_DIR/.sops.yaml.backup" .sops.yaml

# Test Summary
print_test_header "Test Results"

echo
echo -e "${CYAN}Test Summary:${NC}"
echo -e "  Total Tests: $TESTS_TOTAL"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            All Tests Passed Successfully! ✅               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              Some Tests Failed ❌                          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi