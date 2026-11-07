# Handoff: system-design examples library

Work in progress on branch `claude/system-design-examples`. Everything another agent needs to resume is in this folder.

| File | What it is |
|---|---|
| [design.md](design.md) | The approved design (binding spec). |
| [plan.md](plan.md) | The 22-task implementation plan. |
| [progress.md](progress.md) | The execution ledger: rulings, task status, review outcomes, deferred minors. **Trust it and `git log` over memory.** |
| [global-constraints.md](global-constraints.md) | Constraints every task must meet, plus the execution rules. |

## How to resume

1. Read `design.md`, then `plan.md`'s Global Constraints, then `progress.md`.
2. A task with a `Task <N>: complete` line is done; do not redo it. Resume at the first task without one. A task whose last line is a fix round is mid-review: re-review the latest commit, then continue the loop.
3. Execute with the superpowers `subagent-driven-development` skill. Use one implementer per task, an independent reviewer per task, and a final whole-library review. Walkthrough tasks 3–21 may run up to 3 at a time, because each writes one new file (see the rulings in `progress.md`).
4. Gates for every task: `make links examples-refs`, markdownlint on the touched files, `make count-check`. For walkthroughs, also a word count of 3,000–6,000 and exactly 13 `## ` headings.
5. Keep this folder in sync: copy the ledger here after each task and push.

## Notes

- Commits use `git commit --no-verify` (the user authorised it for this repo's legacy pre-commit hook).
- The originals live in gitignored paths (`docs/superpowers/`, `.superpowers/sdd/`). This folder is the tracked copy. Delete it when the library is finished.
- This branch is stacked on PR #592 (`claude/enterprise-boilerplate-audit-3e9f85`). Rebase onto `main` once #592 merges.
