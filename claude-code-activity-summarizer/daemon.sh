#!/bin/bash
set -u

INTERVAL_HOURS="${INTERVAL_HOURS:-6}"

case "${1:-}" in
  test)
    # Dry run: summarize the last INTERVAL_HOURS, print payloads, post nothing
    DRY_RUN=1 exec /app/summarize.sh
    ;;
  once)
    # Single real run, then exit
    exec /app/summarize.sh
    ;;
  "")
    echo "claude-code-activity-summarizer: running every ${INTERVAL_HOURS}h"
    while true; do
      /app/summarize.sh || echo "summarize failed; retrying next interval" >&2
      sleep $(( INTERVAL_HOURS * 3600 ))
    done
    ;;
  *)
    echo "usage: daemon.sh [test|once]" >&2
    exit 1
    ;;
esac
