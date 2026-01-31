#!/bin/bash
set -e

MAX_ITERATIONS=${1:-10}
AGENT=${AGENT:-claude}
SCRIPT_DIR="$(cd "$(dirname \
  "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting Ralph (using $AGENT)"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══ Iteration $i ═══"

  # Inject the actual RALPH_DIR path into the prompt so agents can read files reliably
  RAW_PROMPT=$(cat "$SCRIPT_DIR/prompt.md")
  PROMPT=$(printf "%s" "$RAW_PROMPT" | sed -e "s|{{RALPH_DIR}}|$SCRIPT_DIR|g")

  case "$AGENT" in
    claude)
      OUTPUT=$(claude -p "$PROMPT" --dangerously-skip-permissions --model sonnet 2>&1 \
        | tee /dev/stderr) || true
      ;;
    codex)
      OUTPUT=$(echo "$PROMPT" | codex exec --yolo --skip-git-repo-check - 2>&1 \
        | tee /dev/stderr) || true
      ;;
    gemini)
      OUTPUT=$(gemini -p "$PROMPT" --yolo 2>&1 \
        | tee /dev/stderr) || true
      ;;
    amp)
      OUTPUT=$(echo "$PROMPT" | amp --dangerously-allow-all 2>&1 \
        | tee /dev/stderr) || true
      ;;
    *)
      echo "❌ Unknown agent: $AGENT"
      echo "Supported agents: claude, codex, gemini, amp"
      exit 1
      ;;
  esac

  # Check for completion marker
  # Different agents have different echo behaviors:
  # - Claude: doesn't echo prompt, count >= 1 means done
  # - Codex/Gemini: echo prompt, count >= 2 means done
  # Accept either legacy or documented completion markers
  # Use '|| true' to avoid duplicating a fallback '0' in output
  COUNT_A=$(echo "$OUTPUT" | grep -c "<complete>ALL_DONE</complete>" 2>/dev/null || true)
  COUNT_B=$(echo "$OUTPUT" | grep -c "<promise>COMPLETE</promise>" 2>/dev/null || true)
  MARKER_COUNT=$(( COUNT_A + COUNT_B ))
  MARKER_COUNT=$(echo "$MARKER_COUNT" | tr -d '\n')
  case "$AGENT" in
    claude|amp)
      THRESHOLD=1
      ;;
    *)
      THRESHOLD=2
      ;;
  esac
  if [ "$MARKER_COUNT" -ge "$THRESHOLD" ]; then
    echo "✅ All stories complete!"
    exit 0
  fi

  sleep 2
done

echo "⚠️ Max iterations reached"
exit 1
