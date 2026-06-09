---
id: github-activity-digest
purpose: Publish one low-noise daily digest of meaningful GitHub pull request and CI activity.
routines:
  - Collect meaningful GitHub pull request and CI activity since the previous scheduled run.
  - Select only high-signal items that changed what the team needs to know or do.
  - Post one concise digest to the configured Slack channel when the signal threshold is met.
deny:
  - Do not modify GitHub state.
  - Do not create more than one digest message for the same UTC date.
  - Do not post raw event dumps, long watch lists, speculative metrics, or inferred performance scores.
  - Do not name people in problem-oriented bullets unless the team policy explicitly allows it.
  - Do not post on low-signal days unless the team explicitly wants quiet-day confirmations.
schedule: "0 15 * * 1-5"
---

# GitHub Activity Digest

## Repository configuration

Use these repository-specific values:

- Slack channel: `#steady-playground`
- Daily digest key format: `github-activity-digest:steadyspacecorp/steady-playground:{YYYY-MM-DD}`

## Scope

Collect activity from the repository that contains this daemon.

Default window:

- previous scheduled run to current scheduled run
- Monday includes weekend activity since the prior Friday run

## Signal threshold

Include activity only when it changes what the team needs to know or do.

Examples:

- pull request merged
- pull request opened and ready for review
- pull request unblocked
- recurring CI failure affecting active work

Exclude:

- label-only churn
- assignment-only changes
- bot housekeeping
- comment-only chatter without action
- duplicate references to the same underlying change

## Low-noise behavior

If fewer than two meaningful items exist, do not post unless the single item is a critical blocker or unblocker.

If no item meets the signal threshold, no-op silently.

No-op silently when there has been no repository activity since the previous scheduled run.

## Duplicate-post detection strategy

Before posting, query recent Slack message history in `#steady-playground` from `00:00` to `23:59` UTC for the current digest date.

Treat today's digest as already posted when any message in that window contains an exact line matching:

`Digest key: github-activity-digest:steadyspacecorp/steady-playground:{YYYY-MM-DD}`

If that exact digest key line already exists for today's date, no-op silently and do not post a second digest.

## Output format

Use `references/digest-template.md`.

Format the Slack message with Slack `mrkdwn`, not standard Markdown. Use Slack link syntax (`<url|label>`), bold section labels with `*text*`, and plain hyphen bullets. Do not use Markdown headings, Markdown links (`[label](url)`), tables, nested lists, or code fences in the final Slack message.

Limits:

- 1 link maximum per bullet
- no tables
- no nested bullet lists
- no unverified counts
- include the digest key line exactly once as the final line of the message body

## Communication policy

No-op silently when no item meets the signal threshold, duplicate-post detection finds today's digest key in the destination channel, or required configuration is missing.

Do not post a digest asking for configuration or policy decisions. Surface blockers only when a configured safe Slack channel exists and human action is required.
