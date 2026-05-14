# opencode-pr-reviewer

A GitHub Action that runs an [opencode](https://opencode.ai)-powered code review on a pull request and posts the verdict as a single comment that's edited as the run progresses.

- Reviews on PR open, reopen, or `ready_for_review`.
- Re-review on demand by commenting `/oc review` or `/opencode review` on the PR.
- Opt out of auto-review per-PR with `/no-bot-review` in the description.
- Works with any LLM provider opencode supports — DeepSeek, Anthropic, OpenAI, Google, etc.

## Quick start

1. Copy [`examples/opencode-review.yml`](examples/opencode-review.yml) into your repo at `.github/workflows/opencode-review.yml`.
2. Pick a model and add the matching API key to your repo secrets (see [Provider setup](#provider-setup)).

Open a PR. The bot comments "Starting review…" within a few seconds and edits that comment with its verdict when opencode finishes.

## Provider setup

The action calls `opencode run --model <model>`. opencode picks up provider credentials from the process environment, so the calling workflow sets the right `*_API_KEY` env var for the model you chose:

| Model prefix         | Env var to set       |
|----------------------|----------------------|
| `deepseek/…`         | `DEEPSEEK_API_KEY`   |
| `anthropic/…`        | `ANTHROPIC_API_KEY`  |
| `openai/…`           | `OPENAI_API_KEY`     |
| `google/…`           | `GOOGLE_API_KEY`     |
| `groq/…`             | `GROQ_API_KEY`       |
| `mistral/…`          | `MISTRAL_API_KEY`    |

For other providers, see the [opencode provider docs](https://opencode.ai/docs/providers/). Set whichever env var opencode expects in the `env:` block of the calling job, exactly as the example workflow does for `DEEPSEEK_API_KEY`.

## Action inputs

| Input              | Required | Default                          | Notes |
|--------------------|----------|----------------------------------|-------|
| `model`            | yes      | —                                | e.g. `deepseek/deepseek-v4-pro`. |
| `pr-number`        | yes      | —                                | Use `${{ github.event.pull_request.number || github.event.issue.number }}`. |
| `opencode-version` | no       | `''` (latest)                    | Passed to the installer as `OPENCODE_VERSION`. Pin for reproducibility. |
| `user-comment`     | no       | `''`                             | Pass `${{ github.event.comment.body }}` so reviewer guidance after `/oc review` is forwarded to the model. |
| `review-file`      | no       | `./opencode-review.md`           | Where opencode writes the review. Path is also added to the permission config's edit allow-list. |
| `workflow-run-url` | no       | current run                      | Override only if you're wrapping this in something custom. |

The action expects these env vars to be set by the calling job:

- `GH_TOKEN` — `secrets.GITHUB_TOKEN`. Needed for `gh` to fetch PR data and post/edit the comment.
- A provider API key env var (see [Provider setup](#provider-setup)).

## Security model

This action runs an autonomous LLM coding agent on PR content with `GH_TOKEN` and an LLM API key in its process environment. That's the classic "pwn request" shape: trusted workflow definition, untrusted PR content, sensitive tokens in env. Without care, prompt-injection content planted in source files, docstrings, or commit messages could cause the agent to shell out, exfiltrate secrets, post fraudulent reviews, or modify the working tree.

The action mitigates this with **defense in depth**:

1. **opencode is run with a locked-down permission config** written to `/tmp/opencode-config.json` at the start of the job. `bash`, `edit` (except for the review file), `webfetch`, `websearch`, `task`, `external_directory`, and `doom_loop` are all denied. The agent can only `read`, `grep`, and `glob`, plus write the single review file.
2. **The calling workflow grants `issues: write` only** — no `pull-requests: write`, so the agent token can't approve, dismiss, or edit reviews even if the agent goes rogue.
3. **`pull_request` (not `pull_request_target`) trigger.** Fork PRs run without secrets, so even if the `author_association` gate were somehow bypassed, the API key wouldn't be in the environment and opencode would fail at startup.
4. **`author_association` gate** restricts both auto and manual triggers to `OWNER`, `MEMBER`, and `COLLABORATOR`.
5. **The action's scripts are loaded from the pinned ref of this repo**, so a PR can't substitute the review scripts at runtime. Pin to a release tag (e.g. `@v1`) or a SHA — both work; SHA pinning additionally protects against tag-mutation attacks if you don't trust the action's maintainer.
6. **The prompt explicitly frames PR content as data, not instructions**, with `<pr-description>` / `<pr-comments>` delimiters. This is best-effort hardening, not a security boundary — the permission config above is the real boundary.

### Residual risks worth knowing about

- **The review verdict is attacker-controlled output.** A malicious PR can convince opencode to write `### Overall (Approve)` followed by a benign-looking summary. The bot's verdict is advisory — treat code from untrusted sources with the same scrutiny you would without it.
- **Prompt content reaches the LLM provider.** opencode sends the PR title, description, comments, and any code the agent reads to your chosen provider. If your code or PR discussions are sensitive, factor that in when picking a model.

## Customization

The workflow file is deliberately distributed as a copy-paste example rather than a reusable workflow so you can adjust the parts most teams want to tweak. Three knobs worth knowing about:

### `pull_request` vs `pull_request_target`

The example uses `pull_request`. **Don't switch to `pull_request_target` unless you fully understand the consequences.**

- `pull_request` runs in the fork's context for fork PRs — secrets are not available, so a fork PR slipping past the `author_association` gate would cause the action to fail at startup instead of running with secrets against untrusted code. This is the safer default.
- `pull_request_target` runs in the base repo's context with secrets always present, even for fork PRs. If you switch to this, **the `author_association` gate becomes the only barrier** between a malicious fork PR and your secrets. A single misconfiguration there exfiltrates your API keys. Only use this if you specifically need to review fork PRs and you're confident in the gate.

### Tightening or loosening `author_association`

The example allows `OWNER`, `MEMBER`, and `COLLABORATOR`. `CONTRIBUTOR` and `FIRST_TIME_CONTRIBUTOR` are deliberately excluded — those values are returned for users who have had a PR merged into the repo but have no other affiliation, which is not a strong enough signal to extend trust.

Adjust as you see fit:

- **Tighter:** drop `COLLABORATOR` if you only want direct org members.
- **Looser:** add `CONTRIBUTOR` if you trust anyone with a merged PR. **Do not** add `NONE` or `FIRST_TIME_CONTRIBUTOR` — that exposes the workflow to anyone who opens a PR.

The same gate appears twice in the workflow file (once for the `pull_request` branch, once for the `issue_comment` branch). Update both.

### Trigger phrases and the skip marker

- The comment-trigger phrases `/oc review` and `/opencode review` are matched in both the workflow `if:` and the prompt-extraction regex in `scripts/opencode-review-prompt.sh`. To rename them, change both places.
- The `/no-bot-review` skip marker is matched by `contains(github.event.pull_request.body, '/no-bot-review')`. Rename or remove freely.

## Reference

- `action.yml` — the composite action.
- `scripts/opencode-review-prompt.sh` — builds the prompt from PR title, description, comments, and reviews.
- `scripts/opencode-review-start-comment.sh` — posts the initial "starting review" comment and saves its ID.
- `scripts/opencode-review-post.sh` — edits that comment with the final review and rewrites bracketed locations into GitHub links.
- `examples/opencode-review.yml` — the workflow to copy into your repo.
