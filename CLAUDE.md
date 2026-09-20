# Working rules for this repo

This project uses a fixed `idea-generator -> coder -> supervisor` loop (`.claude/agents/`), run one at a time, never concurrently within this repo.

- **Every coder branch goes to the supervisor before it gets merged. No exceptions, no "I'll just check it myself this once."** This rule exists because it was skipped once (2026-09-19, the IAP/Tailscale branch got committed and nearly moved toward apply before review) and the user had to catch it. If you're mid-multitasking across several background agents, track this explicitly rather than trusting memory.
- Merging to `main`/`master` is fine once the supervisor approves. `git push` and `terraform apply`/`plan`/`destroy`/`gcloud` are not something you run yourself: those stay with the human, by design (see `.claude/settings.json` deny list and `NEXT_STEPS.md` for why).
- Running two coders (or two supervisors) concurrently *within this same repo* is what caused the original worktree/branch mess this project recovered from, so don't do it. Two agents running concurrently across two genuinely separate repos (e.g. this repo + the portfolio site) is fine.
- When a coder's report says something "should" work but couldn't be verified live (no terraform binary, no live GCP, etc.), don't let that caveat get lost. Either verify it once the tooling is available, or make sure the supervisor's review explicitly closes it out.
