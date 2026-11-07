# Global constraints (verbatim from plan)


- **Location:** every content file lives in `examples/system-design/`. File names are `NN-<slug>.md`, where NN is the spec's library number zero-padded (`00-primer.md` … `19-llm-serving-rag.md`).
- **Template:** every walkthrough has the 13 template sections, in order, as `##` headings with exactly these titles:
  - `The question`
  - `The two-minute answer`
  - `Clarify the requirements`
  - `Back-of-envelope estimates`
  - `API and data model`
  - `High-level design`
  - `Deep dives`
  - `Trade-offs to defend`
  - `Failure modes and scaling limits`
  - `AWS and GCP mapping`
  - `Build it here`
  - `Runbook`
  - `Study aids`
- **Length:** 3,000–6,000 words per walkthrough. The primer is exempt.
- **Diagrams:** Mermaid only, no images, and at most 15 nodes per diagram.
- **Cloud coverage:** AWS and GCP appear side by side in the same file.
- **Citations:** every drifting fact (service limit, quota, provider argument, latency or throughput figure, pricing model) carries an inline link to official docs with a `(checked 2026-11)` marker. Facts the docs don't state are marked **verify before relying on**.
- **Snippet pins:** snippets use google `~> 8.0` and aws `>= 6.46.0, < 7.0.0` argument names. Fence HCL as `hcl` and config as `yaml`.
- **"Build it here" length:** at most about 150 lines of snippets.
- **Raw resources** follow the primer's conventions section: naming, CMEK, VPC tier, the four tags/labels, and a per-component identity.
- **Placeholders:** no real account IDs, project IDs or secrets. Use placeholders in the repo's existing style.
- **Gates:** `make links`, `make examples-refs` (Task 1), markdownlint via pre-commit, `make count-check` and `make consistency` stay green.
- **Commits:** one per task. Conventional message `docs(examples): <walkthrough title>`. Use `git commit --no-verify` (user-authorised for this repo's legacy hook) with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.


# Execution rules (controller)
- Worktree: /Users/edwinkassier/Desktop/Ashes/Ashes-Devops-Tools/.claude/worktrees/enterprise-boilerplate-audit-3e9f85, branch claude/system-design-examples. Never push.
- Stage only your own files by explicit path; never `git add -A`/`-f`; nothing under .superpowers or docs/superpowers. Retry on index.lock (other writers may be committing concurrently).
- `git commit --no-verify` is user-authorised.
- Web research (WebSearch/WebFetch) is allowed and expected; cite official docs only.
- Spec (binding): docs/superpowers/specs/2026-11-07-system-design-examples-design.md
- Do not dispatch subagents.
