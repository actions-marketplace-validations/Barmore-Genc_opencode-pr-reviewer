#!/usr/bin/env bash
# Post the final review content from $REVIEW_FILE to the PR.
#
# If opencode-review-start-comment.sh ran, edit that comment so progress and
# results live in one place. Otherwise (start comment disabled via the
# `post-start-comment` action input), post a fresh comment.
#
# GitHub Actions tokens can't approve PRs, so this posts a plain issue comment
# rather than a PR review.
#
# Requires: GITHUB_REPOSITORY, PR_NUMBER, GH_TOKEN. Optional: REVIEW_FILE
# (defaults to ./opencode-review.md), WORKFLOW_RUN_URL (used in the failure
# message), /tmp/opencode-comment-id (written by the start step).
set -euo pipefail

REVIEW_FILE="${REVIEW_FILE:-./opencode-review.md}"
COMMENT_ID_FILE="/tmp/opencode-comment-id"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"

COMMENT_ID=""
if [ -s "$COMMENT_ID_FILE" ]; then
  COMMENT_ID=$(cat "$COMMENT_ID_FILE")
fi

if [ ! -s "$REVIEW_FILE" ]; then
  BODY="Review failed — opencode did not produce a review. See [the workflow run](${WORKFLOW_RUN_URL:-#}) for details."
else
  # Resolve the PR head commit so location links are stable even if the
  # branch is force-pushed later. Falls back to leaving the bracketed
  # location as plain text if the lookup fails.
  HEAD_SHA=$(gh pr view "$PR_NUMBER" \
    --repo "$GITHUB_REPOSITORY" \
    --json headRefOid -q .headRefOid)
  BASE_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/blob/${HEAD_SHA}"

  # Rewrite [`path:line`] and [`path:start-end`] into clickable GitHub links.
  # The range form must run first so its end number isn't consumed by the
  # single-line pattern.
  BODY=$(sed -E '
    s|\[`([^`:]+):([0-9]+)-([0-9]+)`\]|[`\1:\2-\3`]('"${BASE_URL}"'/\1#L\2-L\3)|g
    s|\[`([^`:]+):([0-9]+)`\]|[`\1:\2`]('"${BASE_URL}"'/\1#L\2)|g
  ' "$REVIEW_FILE")
fi

if [ -n "$COMMENT_ID" ]; then
  gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${COMMENT_ID}" \
    --method PATCH \
    -f body="$BODY"
else
  gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
    --method POST \
    -f body="$BODY"
fi
