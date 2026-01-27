---
description: Quickly decide which agent(s)/command(s) to use for a task, and what context to gather before starting.
---

# Triage Command

Use `/triage` when you’re not sure which **agent** (or command) to use.

This command acts like a “dispatcher”: it classifies your request and recommends:
- the best agent(s) (and order),
- what inputs you should paste (logs, files, requirements),
- what to run next (e.g. `/plan`, `/tdd`, `/code-review`, `/build-fix`, `/verify`).

## What This Command Does

1. **Restates your goal** in one sentence
2. **Classifies the task** (Feature / Bug / Build / Security / DB / Docs / E2E / Go / DevOps)
3. **Selects agent(s)** and suggests an execution order
4. **Requests missing context** (only what’s needed)
5. **Outputs a next-step checklist** (commands to run + acceptance criteria)

## Agent Selection Rules (Quick)

- **planner**: new feature / ambiguous request / multi-step work
- **architect**: system design, boundaries, interfaces, migrations, performance tradeoffs
- **build-error-resolver**: CI/build/tooling errors (Node/TS/etc.)
- **go-build-resolver**: Go build/test/module errors
- **code-reviewer**: quality, maintainability, correctness review
- **security-reviewer**: authn/authz, secrets, injection, supply-chain risk, public exposure
- **database-reviewer**: schema, migrations, queries, indexes, transactions
- **e2e-runner**: Playwright E2E tests for critical user flows
- **refactor-cleaner**: technical debt cleanup, structure improvements
- **doc-updater**: keep docs in sync (README, API docs, runbooks)
- **tdd-guide**: TDD workflow for core logic and regression prevention

## How to Use

### Minimal
```
/triage I want to add a dark mode toggle to the app.
```

### With context
```
/triage
Goal: Fix CI failing on main
Repo: <link>
Error:
<paste logs>
Constraints: must keep Node 20, no breaking changes
```

## Example Outputs (What you should expect)

### Example 1 — Feature
**Recommendation**:
- Use `planner` → then `architect` (if cross-module) → implement → `code-reviewer` → `verify`

**Ask you for**:
- current architecture summary
- key files/modules involved

**Next steps**:
- run `/plan` and wait for confirmation

### Example 2 — Build Failure
**Recommendation**:
- Use `build-error-resolver` (or `go-build-resolver` for Go)

**Ask you for**:
- full error log
- environment versions

**Next steps**:
- run `/build-fix` (or paste logs directly)

### Example 3 — Security-sensitive change
**Recommendation**:
- Use `architect` → `security-reviewer`

**Ask you for**:
- threat model context (who can access what)
- auth boundaries

**Next steps**:
- propose 2 solution options + mitigations

## Notes

- If the task is risky (auth, payments, public endpoints, data access), always include `security-reviewer`.
- If the task changes schema/queries/migrations, always include `database-reviewer`.
- If the task is large, always start with `planner` and WAIT for confirmation before editing code.
