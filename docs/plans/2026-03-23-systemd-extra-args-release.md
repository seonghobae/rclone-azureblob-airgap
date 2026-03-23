# Systemd EXTRA_ARGS Release Fix Implementation Plan

> For Claude: REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Fix the packaged systemd mount regression caused by invalid
`ExecStart=` argument expansion, verify it with regression coverage, and ship
the replacement release.

**Architecture:** The package ships two systemd unit templates that source
`REMOTE`, `MOUNTPOINT`, and `EXTRA_ARGS` from `/etc/rclone/mounts/%i.conf`.
`REMOTE` and `MOUNTPOINT` must remain single arguments, while `EXTRA_ARGS`
must be whitespace-split by systemd using `$EXTRA_ARGS`, not shell default
expansion syntax. The change is complete only when source, tests, workflows,
tag release, and published artifacts all align.

**Tech Stack:** Bash, systemd unit templates, Debian packaging, GitHub
Actions, Python unittest

---

## Task 1: Lock the regression in tests

**Files:**

- Modify: `tests/test_release_hardening.py`
- Test: `tests/test_release_hardening.py`

### Step 1: Write the failing test

Assert that both systemd unit templates reject `${EXTRA_ARGS:-}` and keep
`${REMOTE} ${MOUNTPOINT}` intact.

### Step 2: Run test to verify it fails

Run:

```bash
python3 -m unittest tests/test_release_hardening.py -v
```

Expected: FAIL because `${EXTRA_ARGS:-}` is still present.

### Step 3: Write minimal implementation

No production code in this task.

### Step 4: Run test to verify it passes

Run the same command after Task 2.

Expected: PASS.

### Step 5: Commit

Commit with the production fix in Task 2.

## Task 2: Fix packaged systemd units

**Files:**

- Modify: `systemd/rclone-azureblob@.service`
- Modify: `systemd/rclone-mount@.service`

### Step 1: Implement the minimal fix

Replace `${EXTRA_ARGS:-}` with `$EXTRA_ARGS` in both unit templates and add
comments explaining why shell default expansion is invalid in `ExecStart=`.

### Step 2: Verify unit-focused regression tests

Run the same unittest command from Task 1.

Expected: PASS.

### Step 3: Commit

Commit together with Task 1 and docs updates.

## Task 3: Canonical docs and release metadata alignment

**Files:**

- Modify: `ARCHITECTURE.md`
- Modify: `debian/changelog`

### Step 1: Document the systemd argument rule

Explain that `EXTRA_ARGS` must use `$EXTRA_ARGS` while `REMOTE` and
`MOUNTPOINT` remain `${REMOTE} ${MOUNTPOINT}`.

### Step 2: Add a new changelog entry

Add the next package revision with a concise fix summary for the systemd
runtime regression.

### Step 3: Verify docs and markdown lint

Run:

```bash
python3 -m unittest tests/test_release_hardening.py -v
```

Run the markdown and python checks with lint-by-filetype.

Expected: repository-local markdown and python checks pass, and any unrelated
baseline tool failure is captured explicitly.

## Task 4: Source verification and release path verification

**Files:**

- Modify if needed: workflow or docs files only if verification reveals a
  mismatch

### Step 1: Run local verification

Run:

```bash
python3 -m unittest tests/test_release_hardening.py -v
```

Expected: PASS.

### Step 2: Push and confirm mainline CI

Run `git push`, then verify with:

```bash
gh run list --repo seonghobae/rclone-azureblob-airgap --limit 10
```

Expected: `Build deb package` and `Integration test (Docker / Azure Private
Link mock)` succeed for the pushed commit.

### Step 3: Tag and release

Run:

```bash
git tag v1.73.2-15
git push origin v1.73.2-15
```

Then verify with:

```bash
gh run list --repo seonghobae/rclone-azureblob-airgap --limit 10
gh release view v1.73.2-15 --repo seonghobae/rclone-azureblob-airgap
```

Expected: the Release workflow succeeds and publishes amd64 and arm64 `.deb`
plus `.sha256` assets.

## Task 5: Post-release closure evidence

**Files:**

- No source changes unless verification fails

### Step 1: Re-check continuity

Run:

```bash
python3 "$HOME/.config/opencode/scripts/pr_continuity.py" --json --limit 50
```

Expected: no canonical PR is needed on direct-push `main`.

### Step 2: Confirm release and runbook alignment

Verify that the latest release and latest successful workflows reference the
new revision.

### Step 3: Record closure evidence

Use commit, tag, workflow, and release evidence as the closure source of
truth.
