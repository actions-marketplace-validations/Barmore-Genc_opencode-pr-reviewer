#!/usr/bin/env bash
# Post an initial "starting review" comment with a link to the workflow run,
# and save the comment ID so the final post step can edit it instead of
# posting a new comment.
#
# Requires: PR_NUMBER, GITHUB_REPOSITORY, WORKFLOW_RUN_URL, GH_TOKEN.
set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${WORKFLOW_RUN_URL:?WORKFLOW_RUN_URL must be set}"

BODY="Starting review. I will edit this comment when done. You can check progress at ${WORKFLOW_RUN_URL}."

RESPONSE=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
  --method POST \
  -f body="$BODY")

COMMENT_ID=$(jq -r '.id' <<<"$RESPONSE")
if [ -z "$COMMENT_ID" ] || [ "$COMMENT_ID" = "null" ]; then
  echo "ERROR: failed to extract comment id from response: $RESPONSE" >&2
  exit 1
fi

printf '%s\n' "$COMMENT_ID" > /tmp/opencode-comment-id
echo "Posted starting comment ${COMMENT_ID}."
