# Somnia Blockscout Fork

This repository is a fork of [blockscout/blockscout](https://github.com/blockscout/blockscout) maintained by Protofire for Somnia Network.

## Rollout Command

The `/rollout` command is used to merge upstream Blockscout releases into the fork branches.

### Usage

```
/rollout <base-branch> <upstream-tag>
```

**Examples:**
```
/rollout testnet v9.4.0
/rollout mainnet v9.3.3
```

**Arguments:**
- `<base-branch>` — the fork branch to upgrade (e.g., `testnet`, `mainnet`)
- `<upstream-tag>` — the upstream blockscout release tag (e.g., `v9.4.0`)

### What It Does

The rollout command automates the complex process of merging upstream Blockscout releases:

1. **Setup & Validation** — Validates branches and tags, fetches upstream
2. **Branch Creation** — Creates a dedicated rollout branch (e.g., `testnet-rollout-9.4.0`)
3. **Pre-Merge Analysis** — Shows what will be merged (upstream commits, custom Protofire changes)
4. **Release Change Analysis** — Extracts new/deprecated env vars, breaking changes, build updates from CHANGELOG
5. **Merge** — Attempts to merge upstream tag
6. **Conflict Resolution** — Auto-resolves when safe, escalates when needed
7. **Verification** — Confirms Protofire customizations are preserved
8. **Migration Risk Analysis** — Analyzes new database migrations for lock risks
9. **Docker Build Test** — Runs local build verification and smoke tests
10. **Summary** — Provides complete report with next steps

### Output

The command generates analysis reports in `.specs/features/<rollout-branch>/`:
- `release-changes.md` — Environment variables, build changes, action items
- `migration-risks.md` — Database migration risk assessment

### Safety

- Never pushes to base branches directly (always creates a rollout branch)
- Preserves Protofire custom commits during merge
- Validates changes before committing
- Runs Docker build tests to catch issues early

### Team Members

Commits authored by the following are considered Protofire customizations:
- `*@protofire.io`
- `leoni.mella@gmail.com`
- `zhiltsov.nick@gmail.com`

## Configuration

### Permissions

The `.claude/settings.local.json` file grants access to Blockscout documentation for context during rollouts.
