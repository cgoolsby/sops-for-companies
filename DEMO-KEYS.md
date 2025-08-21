# DEMO KEYS - FOR DEMONSTRATION ONLY

**⚠️ WARNING: NEVER SHARE PRIVATE KEYS IN PRODUCTION ⚠️**

This file contains the private keys for demonstration purposes only. In a real production environment, these keys would be:
- Stored securely in password managers
- Never committed to version control
- Distributed only through secure channels
- Rotated regularly

## Developer Keys

### Alice (Developer)
```
Public:  age1da3u58jlwx8pjzrcynpzgff79y8w0qem5scqrd5yy8m5sj2tvscs4sfnnn
Private: AGE-SECRET-KEY-1LUA60QNN0X6L099M9A6SJYA824N9FZZ29NNF5TT7JEXJUEWEKX7SLASJM0
```

### Bob (Developer)
```
Public:  age1uk2qjwhywha0ap02unmlzzft7wwqw3sy2dms3tg63t3q7h5geegsae7h47
Private: AGE-SECRET-KEY-1FAUXFRZ88HZPPHTZV0N6L93N32XLJT7R5CJ9A5NH0WRJAR5EAGXQLU4SEU
```

### Carol (Developer)
```
Public:  age1grelxvlcv2ypeh68ecrltltyu96wntzk9mcnjjt3lnw3xmr35djqdc0y0p
Private: AGE-SECRET-KEY-1E7TQPUJ42T94GHL6QA4HLCZZACQMHDW744QUA2FR7RWPF7PLL3SQWQTYNT
```

## Administrator Keys

### Admin1 (Administrator)
```
Public:  age1lj8fvkr559xgl44nzn0dsyq77sqsf33sgtu0k7k5tzhytrzzf40qdpgdjh
Private: AGE-SECRET-KEY-1MG38AFNCSJMQCKKD6NM0RG9RG40GSUWSNTUJRKVXL9SDCLG6Z6SSMCL9CX
```

### Admin2 (Administrator)
```
Public:  age1t7mpsg5zh9h225jc642rqa8jg6aszqtshj6lvxpgx9qwnwnugvjqezlljf
Private: AGE-SECRET-KEY-1443HNEF5F5RRD9EQDS04QK3W2MGKCT3HYYFZVKHL96ZV5ZYU0H6Q3XQWM7
```

## CI/CD Keys

### GitHub Actions (CI/CD)
```
Public:  age1ezq49xdmurgdpv7yc4ey6dc5tvptnrj24g8kqtcns6hnljwu6e6sv6m5pw
Private: AGE-SECRET-KEY-1Z8HHH2H9NU9AAR9LATRDH6GXX78562GJXYFRLFN5F79SUJ0YY5XQEEAVSY
```

## Testing Access

To test decryption with these keys:

```bash
# Set up a key (e.g., as Alice)
export SOPS_AGE_KEY="AGE-SECRET-KEY-1LUA60QNN0X6L099M9A6SJYA824N9FZZ29NNF5TT7JEXJUEWEKX7SLASJM0"

# Or create a key file
echo "AGE-SECRET-KEY-1LUA60QNN0X6L099M9A6SJYA824N9FZZ29NNF5TT7JEXJUEWEKX7SLASJM0" > ~/.config/sops/age/keys.txt

# Test decryption (Alice can decrypt dev secrets)
sops -d secrets/dev/database.enc.yaml

# Alice cannot decrypt production (will fail)
sops -d secrets/production/credentials.enc.yaml  # This will fail
```

## Access Matrix Verification

Based on the `.sops.yaml` configuration:

| User | Can Decrypt Dev | Can Decrypt Staging | Can Decrypt Production | Can Decrypt Examples |
|------|-----------------|---------------------|------------------------|---------------------|
| Alice (Dev) | ✅ | ❌ | ❌ | ✅ |
| Bob (Dev) | ✅ | ❌ | ❌ | ✅ |
| Carol (Dev) | ✅ | ❌ | ❌ | ✅ |
| Admin1 | ✅ | ✅ | ✅ | ✅ |
| Admin2 | ✅ | ✅ | ✅ | ✅ |
| GitHub Actions | ✅ | ✅ | ✅ | ❌ |

## GitHub Actions Setup

For GitHub Actions, add the private key as a secret:

```
Name: SOPS_AGE_KEY
Value: AGE-SECRET-KEY-1Z8HHH2H9NU9AAR9LATRDH6GXX78562GJXYFRLFN5F79SUJ0YY5XQEEAVSY
```

## Security Reminder

🔴 **CRITICAL**: This file is for demonstration only!

In production:
- NEVER commit private keys to version control
- Use secure key distribution methods
- Implement key rotation policies
- Store keys in hardware security modules (HSM) or secure vaults
- Use separate keys for each environment
- Monitor key usage and access patterns
- Implement break-glass procedures for emergency access