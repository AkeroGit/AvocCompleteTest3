# Maintenance

## Metadata consistency check

Run this check before opening a PR to catch stale branding/install-channel references.

```sh
./scripts/check_metadata_consistency.sh
```

What it validates:
- disallowed legacy references are absent (for example `github.com/develOseven` and `AUR`),
- canonical repository URL is present in `README.md` and `pyproject.toml`:
  - `https://github.com/AkeroGit/AvocCompleteTest`.
