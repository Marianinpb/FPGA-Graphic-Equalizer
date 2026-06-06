# Instructions for Antigravity (Project Initialization)

> **This file activates the SDD Harness.** The agent MUST follow these
> instructions as its FIRST action before processing any other request.

---

## 1. Harness Initialization (MANDATORY FIRST ACTION)

Before processing any other instruction, you MUST execute the following steps
in order:

### 1.1. Locate the Harness

The SDD Harness is located at `.antigravity/harness/` relative to this file.
If the directory does not exist, clone it:

```bash
git clone https://github.com/Marianinpb/antigravity-sdd-harness.git .antigravity/harness
```

### 1.2. Load Configuration

Read and LOAD into your context the following files from `.antigravity/harness/`:

1. **`harness-config.yaml`** — Project configuration (tech stack, security profile)
2. **`constitution.md`** — Non-negotiable principles (supreme authority)
3. **`workflows/sdd-lifecycle.md`** — The main development lifecycle
4. **`rules/coding-standards.md`** — Coding conventions to enforce
5. **`rules/security-rules.md`** — Security rules for the active profile
6. **`rules/quality-gates.json`** — Quality gates to validate against

### 1.3. Load Project Context

Read the following files if they contain content:
1. **`memory/project-context.md`** — Current project state
2. **`memory/decision-log.md`** — Historical decisions

---

## 2. Acknowledgment (MANDATORY)

Once the files are loaded, you MUST confirm to the user:

```
✅ SDD Harness activated.
- Project: [name from harness-config.yaml]
- Type: [type from harness-config.yaml]
- Security Profile: [profile from harness-config.yaml]
- Quality Gates: [enabled/disabled]

Ready to receive SDD commands:
  /specify    — Start Phase 1: Discovery and Specification
  /plan       — Start Phase 2: Design and Planning
  /implement  — Start Phase 3: Implementation (TDD)
  /review     — Trigger quality gates and code review
  /exposition — Generate academic presentation (summary, slides, script)
  /report     — Generate academic/technical report with Mermaid diagrams
```

---

## 3. Operational Mode

From this point forward, your **sole objective** is to follow the rules and
workflows defined in `.antigravity/harness/`.

- You MUST follow the SDD lifecycle phases in order.
- You MUST NOT skip phases or proceed without human approval.
- You MUST enforce all rules marked as `enforce: true` in `harness-config.yaml`.
- Any deviation from the harness rules is considered a **system error**.

---

## 4. Quick Reference

| Command | Phase | Description |
|---------|-------|-------------|
| `/specify` | 1 | Analyze requirements, ask questions, generate specification |
| `/plan` | 2 | Read approved spec, design architecture, create implementation plan |
| `/implement` | 3 | Execute tasks with TDD (RED → GREEN → REFACTOR) |
| `/review` | - | Run quality gates, self-review, validate compliance |
| `/exposition` | - | Generate academic presentation (summary, slides, script) |
| `/report` | - | Generate academic/technical report with Mermaid diagrams |
