# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it privately.

**Do not open a public GitHub issue.** Instead, email the maintainer directly or open a draft security advisory at:

https://github.com/aziz0220/dotfiles/security/advisories/new

You should receive a response within 48 hours. If not, follow up to ensure receipt.

## Scope

This project handles sensitive personal data (SSH keys, GPG keys, cloud credentials, kube config). The following are in scope:

- Plaintext secret exposure in the repository or git history
- Weaknesses in the vault encryption scheme
- Credential leakage through CI/CD pipelines
- Unauthorized access to the secrets vault

## Out of scope

- The strength of the vault password itself (user-chosen)
- Vulnerabilities in upstream dependencies (Ansible, OpenSSL, etc.)
- Social engineering attacks

## Security Architecture

### Secrets storage

- All sensitive data is stored in `vault/home-secrets.tar.gz.aes256`
- Encryption: **AES-256-CBC** with **PBKDF2** key derivation
- The vault is the **only** committed file containing secrets
- The decrypted bootstrap home (`.bootstrap/home/`) is **gitignored** and never committed

### Encryption details

| Parameter | Value |
|-----------|-------|
| Algorithm | AES-256-CBC |
| Key derivation | PBKDF2 |
| Salt | Random, per-encryption |
| Iterations | OpenSSL default (varies by version) |

### Best practices

- Set `SETUP_SECRETS_PASSWORD` as a GitHub secret, never in code
- Use a strong, unique passphrase for the vault
- Re-capture and re-encrypt the vault when secrets change
- Run `make check` before committing to catch accidental secret exposure
