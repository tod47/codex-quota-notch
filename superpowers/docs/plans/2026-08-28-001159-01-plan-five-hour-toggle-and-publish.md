# Optional 5-Hour Quota Display and GitHub Publish

**Goal:** Add a user-controlled setting for the Plus 5-hour quota section while preserving the existing weekly quota behavior, then publish the verified change to the existing GitHub development branch.

**Why planning is required:** The task changes persisted application behavior and includes an externally visible Git push.

**Acceptance:** The 5-hour quota is visible by default, can be turned off and on from the settings window, stays hidden when disabled, existing weekly alerts remain unchanged, all tests and the macOS app build pass, and only the verified commit is pushed to `origin/feature/codex-quota-notch`.

### Outcome 1: Persist the display preference

- Work: Add a backward-compatible `showFiveHourQuota` setting with default `true`; decode older settings without the key as enabled; expose the setting in the existing English and Simplified Chinese appearance/display settings.
- Risks/open questions: Older user settings must continue to load without migration prompts or data loss.
- Verify: `swift test --filter 'SettingsStoreTests|LocalizationTests'`

### Outcome 2: Gate the 5-hour UI without changing quota reads

- Work: Pass the setting into the overlay/main-window view path, render the 5-hour section only when both the preference is enabled and a 300-minute limit is available, and keep panel sizing correct in top and floating modes.
- Risks/open questions: Disabling the section must not remove the 5-hour value from the internal snapshot or affect weekly alert evaluation.
- Verify: `swift test --filter 'QuotaModelsTests|LocalSessionLogDataSourceTests|AppModelTests|SettingsStoreTests'`

### Outcome 3: Rebuild and verify the deliverable

- Work: Run the full test suite, build the macOS 13+ app bundle, confirm the bundle metadata and desktop binary match, and perform a local UI smoke check with synthetic data before restoring the user's original simulation setting.
- Risks/open questions: Do not expose or upload real Codex session contents; stop before publishing if the build or UI smoke check fails.
- Verify: `swift test`, `./scripts/build-app.sh`, `git diff --check`, and a local app UI smoke check.

### Outcome 4: Publish the verified revision

- Work: Review the final diff and branch state, create one commit on the current development branch, push it to the configured `origin` remote, and verify the remote branch points at that commit.
- Risks/open questions: Do not force-push, merge, or publish a release asset unless explicitly requested; if the remote has diverged, stop and ask rather than overwriting it.
- Verify: `git status --short --branch`, `git show --stat --oneline HEAD`, and `git ls-remote origin refs/heads/feature/codex-quota-notch`.
