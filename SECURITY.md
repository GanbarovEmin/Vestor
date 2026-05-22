# Security Policy

Vestor is a local-first finance app. Portfolio files, backups, import presets, and optional provider cookies must stay on the user's Mac and must not be committed to this repository.

## Sensitive Data

- Do not commit local Application Support data.
- Do not commit broker statements, CSV exports, screenshots with private account values, or Keychain data.
- Do not commit Sparkle private signing keys.
- Public Sparkle EdDSA keys are safe to commit.

## Reporting

Open a private issue or contact the repository owner if a security-sensitive problem is found. Include the affected version, reproduction steps, and whether local user data or update integrity is affected.
