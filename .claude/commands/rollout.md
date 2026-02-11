# /rollout — Merge Upstream Blockscout Release

Merge an upstream blockscout tag into a fork branch via a dedicated rollout branch.

## Usage

```
/rollout <base-branch> <upstream-tag>
```

**Examples:**
```
/rollout testnet v9.4.0
/rollout mainnet v9.3.3
```

**Arguments:**
- `$ARGUMENTS` — expects `<base-branch> <upstream-tag>` (e.g., `testnet v9.4.0`)
- `<base-branch>` — the fork branch to upgrade (e.g., `testnet`, `mainnet`)
- `<upstream-tag>` — the upstream blockscout release tag (e.g., `v9.4.0`)

## Workflow

### Phase 1: Setup

1. Parse arguments from `$ARGUMENTS` — extract `<base-branch>` and `<upstream-tag>`
2. Validate that `<base-branch>` exists at origin: `git branch -r | grep origin/<base-branch>`
3. Ensure upstream remote exists, add if missing:
   ```
   git remote add upstream git@github.com:blockscout/blockscout.git 2>/dev/null
   ```
4. Fetch upstream tags: `git fetch upstream --tags`
5. Validate that `<upstream-tag>` exists: `git tag -l <upstream-tag>`
6. If tag not found, abort with error

### Phase 2: Branch Creation

7. Derive rollout branch name: `<base-branch>-rollout-<tag-without-v>` (e.g., `testnet-rollout-9.4.0`)
8. Create rollout branch from origin base: `git checkout -b <rollout-branch> origin/<base-branch>`
9. **CRITICAL**: Immediately fix tracking to avoid pushing to base branch:
   ```
   git branch --unset-upstream
   ```
10. Verify branch starts at correct commit

### Phase 3: Pre-Merge Analysis

11. Find the merge base (current upstream version the fork is based on):
    ```
    git merge-base <rollout-branch> <upstream-tag>
    ```
    Then determine the old upstream tag at the merge base:
    ```
    git describe --tags --abbrev=0 <merge-base>
    ```
    Store the result as `<old-tag>` — this is the version the fork is currently based on.
12. Count upstream commits to merge: `git log --oneline <merge-base>..<upstream-tag> | wc -l`
13. Count custom Protofire commits: `git log --oneline <merge-base>..<rollout-branch> --author="protofire\|leoni.mella\|zhiltsov.nick" | wc -l`
14. List all custom commits for reference
15. Check for post-tag hotfixes: `git tag -l '<tag-major>.<tag-minor>.*' --sort=-v:refname`
16. **Present analysis to user** — show scope and ask to proceed

> STOP: Wait for user confirmation before merging.

### Phase 4: Release Change Analysis

Analyze what changed between `<old-tag>` and `<upstream-tag>` at the application level — new env vars, deprecated config, breaking changes, build dependency updates. This ensures the team knows what infrastructure/config changes to prepare before deployment.

**Step 1: CHANGELOG extraction**

17. Read `CHANGELOG.md` and extract all sections between `<old-tag>` version and `<upstream-tag>` version.
    - CHANGELOG uses headings like `## 9.3.3` (no `v` prefix) — strip the `v` from tags when matching.
    - Extract all `### New ENV variables` tables (variable name, required, description, default)
    - Extract all `### Deprecated ENV variables` tables (variable name, replacement, version)
    - Extract all `### 🚀 Features` entries (for new service/feature awareness)
    - Note any breaking behavior changes from `### 🐛 Bug Fixes` and `### ⚙️ Miscellaneous Tasks`

**Step 2: Config file diff**

18. Run config diff to detect env var changes not captured in CHANGELOG:
    ```
    git diff <old-tag>..<upstream-tag> -- config/runtime.exs config/runtime/prod.exs
    ```
19. Scan diff for new `System.get_env` calls and changed defaults in `ConfigHelper.parse_*_env_var`
20. Cross-reference with CHANGELOG findings — flag any env vars found in config diff but missing from CHANGELOG

**Step 3: Docker/build dependency diff**

21. Run build file diff:
    ```
    git diff <old-tag>..<upstream-tag> -- docker/Dockerfile docker-compose/docker-compose.yml mix.exs
    ```
22. Detect: new base image versions (Elixir/Erlang), new build ARGs, new services in docker-compose, new mix dependencies requiring external services

**Step 4: Generate report**

23. Save report to `.specs/features/<rollout-branch>/release-changes.md` with these sections:
    - **New ENV Variables** — table with: variable name, default value, description, required/optional
    - **Deprecated ENV Variables** — table with: variable name, replacement, version deprecated
    - **Breaking Changes** — list of behavior changes that could affect the fork
    - **Build Changes** — Elixir/Erlang version changes, new Dockerfile ARGs, dependency changes
    - **New Services** — any new docker-compose services or external service dependencies
    - **Action Items** — checklist of things to do before deployment (e.g., set env vars, update Docker image, add services)

24. **Present the release change report to user** and wait for acknowledgment before proceeding to merge.

> STOP: Wait for user acknowledgment of release changes before merging.

### Phase 5: Merge

25. Start merge without auto-commit: `git merge <upstream-tag> --no-commit`
26. If no conflicts, proceed to Phase 7
27. If conflicts, proceed to Phase 6

### Phase 6: Conflict Resolution

28. List all conflicting files: `git diff --name-only --diff-filter=U`
29. Categorize each conflict:

**Auto-resolve (keep fork version) when:**
- File was modified by a Protofire team member on the fork branch
- Upstream change is a non-breaking refactor, style change, or dependency bump
- CI/CD workflow files (`.github/workflows/`) — accept upstream reorganization, keep fork's custom workflows

**Escalate to user when:**
- Database migration files conflict
- Both sides have significant logic changes in the same code
- Upstream change is a security fix
- Structural changes (new module system, renamed modules, changed function signatures)
- Breaking API changes

**Protofire team identification — check commit author email:**
- `*@protofire.io`
- `leoni.mella@gmail.com`
- `zhiltsov.nick@gmail.com`

30. For each conflict, show the user what was decided and why
31. After all conflicts resolved, verify no conflict markers remain:
    ```
    grep -rl "<<<<<<" apps/ config/ 2>/dev/null
    ```

### Phase 7: Verification

32. Verify all Protofire custom changes are preserved in key files:
    - Use an Explore agent to check each file modified by Protofire commits
    - Report which customizations are present/missing
33. **Present verification report to user**

### Phase 8: Migration Risk Analysis

34. Find all new migration files: `git diff --name-only --diff-filter=A <merge-base>..<upstream-tag> -- '*/migrations/*.exs'`
35. Read each migration in `apps/explorer/priv/repo/migrations/` (skip chain-specific ones unless relevant)
36. Analyze each migration for table lock risks:
    - **High risk**: ALTER TABLE on hot tables, CREATE INDEX without CONCURRENTLY, DROP/ADD FK constraints, UPDATE on large tables
    - **Medium risk**: ALTER ADD nullable column, MODIFY column type
    - **Safe**: CREATE TABLE, DROP small tables, concurrent operations
37. Save risk analysis to `.specs/features/<rollout-branch>/migration-risks.md`
38. **Present migration risks to user**

### Phase 9: Commit & Push

39. Create merge commit:
    ```
    git commit -m "feat: merge upstream blockscout <upstream-tag> into <base-branch> fork"
    ```
40. Push rollout branch (NOT the base branch):
    ```
    git push -u origin <rollout-branch>
    ```
41. **NEVER push to `<base-branch>` directly**

### Phase 10: Docker Build Verification

42. Run the local Docker build and smoke-test script:
    ```
    ./scripts/test-build.sh
    ```
43. This script performs:
    - **API image build** — `DISABLE_INDEXER=true` (matches CI `build-push.yml`)
    - **Indexer image build** — `DISABLE_API=true` (matches CI `build-push.yml`)
    - **Database migrations** — runs `Elixir.Explorer.ReleaseTasks.create_and_migrate()` against fresh PostgreSQL 17
    - **Indexer startup** — verifies container starts without crash errors
    - **API health checks** — verifies `GET /api/v2/stats` and `GET /api/v2/blocks` return 200
44. If the build test **fails**:
    - Show the failure output to the user
    - Ask whether to proceed anyway or investigate
    - The rollout branch is already pushed, so the user can fix and re-push
45. If the build test **passes**, report success and proceed to summary

> NOTE: Requires Docker. If Docker is unavailable, skip this phase and warn the user.

### Phase 11: Summary

46. Print final report:
    - Rollout branch name and remote URL
    - Upstream commits merged (count)
    - Conflicts resolved (count and summary)
    - Custom changes verified (list)
    - Release changes summary (new env vars count, deprecated vars count, breaking changes count)
    - Link to release-changes.md
    - Migration risks (high/medium/safe counts)
    - Link to migration-risks.md
    - Docker build test result (PASS/FAIL/SKIPPED)
    - Next steps: PR to base branch

## Safety Rules

- **NEVER** push to the base branch (`testnet`, `mainnet`, `master`)
- **NEVER** use `--force` push
- **ALWAYS** create a separate rollout branch
- **ALWAYS** unset upstream tracking immediately after branch creation
- **ALWAYS** verify Protofire custom changes are preserved before committing
- **ALWAYS** analyze migration risks before completing
- **ALWAYS** review release changes (env vars, build deps) before merging

## Output

```
.specs/features/<rollout-branch>/
├── release-changes.md    # Release change analysis (env vars, build deps, breaking changes)
└── migration-risks.md    # Database migration risk analysis
```

## Dependencies

- `scripts/test-build.sh` — Docker build & smoke-test script (Phase 10)
- `scripts/docker-compose.test.yml` — PostgreSQL 17 + Redis for test infrastructure
- Docker must be installed and running for Phase 10
