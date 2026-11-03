#!/bin/zsh
# Runs FORGE's real coach code against Apple's on-device model on this Mac, which needs Apple
# Intelligence turned on. The iOS Simulator can't do this: its safety filter fails on every request.
#
#   tools/coach-eval/run.sh                 # chat: every line of messages.txt
#   tools/coach-eval/run.sh my-messages.txt # chat: your own messages, one per line
#   PLAN=1 tools/coach-eval/run.sh          # planner: five sample setups
#   SETS=1 tools/coach-eval/run.sh          # between sets: rewording the rules' notes, and a recap
#   PAR=1 tools/coach-eval/run.sh           # one request at a time (default 3)
#
# Read the output by eye: the model's wording varies run to run. The decisions underneath it
# (notes, goals, time, rest days) are unit-tested in FORGETests/ChatDecisionTests.swift.
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=$(mktemp -d)/coach-eval
xcrun swiftc -O -parse-as-library \
  -plugin-path "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
  -o "$out" tools/coach-eval/*.swift \
  Shared/Domain.swift Shared/ExerciseCatalog.swift Shared/Progression.swift Shared/Strength.swift \
  Shared/SkillGoals.swift Shared/WorkoutProgress.swift Shared/WarmUpSteps.swift \
  FORGE/Coach/CoachEngine.swift FORGE/Coach/ChatDecision.swift FORGE/Coach/AppleIntelligenceCoach.swift FORGE/Coach/WarmUps.swift FORGE/Coach/SetCoach.swift
PAR=${PAR:-3} "$out" "${1:-tools/coach-eval/messages.txt}"
