#!/bin/zsh
# Generates all Nova Rush voice callouts with Kokoro TTS: take 1 in voice
# af_heart, take 2 in a 70/30 blend of af_heart and af_nicole (the blend that
# sounds most clearly different — speed changes alone were inaudible, Kokoro
# speaks a line with the same intonation every time).
# Kokoro-82M: Apache-2.0 weights, trained only on permissive/non-copyrighted
# audio — chosen over OmniVoice, whose weights are CC-BY-NC.
#
# Needs the kokoro-tts pixi env in ./kokoro-tts (model files
# kokoro-v1.0.onnx + voices-v1.0.bin inside it). Raw takes go to
# generated/voices/ (git-ignored; override with KOKORO_OUT=<dir>); then screen
# and install with:
#   swift Tools/voicecheck.swift generated/voices/*.wav
#   swift Tools/voiceprep.swift <name>=<wav> ...      (this script prints the call)
#
# Usage: Tools/kokoro_voices.sh [name ...]   (default: all lines; quips = balllost,
# invitations = attract)
set -euo pipefail
cd "$(dirname "$0")/.."
VOICE=af_heart
VOICE2="af_heart:70,af_nicole:30"
OUT="${KOKORO_OUT:-generated/voices}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"     # absolute: kokoro-tts runs from inside ./kokoro-tts
TMP=$(mktemp -d)

# name | take-1 text | take-2 text | take-2 speed   (take 1 is always speed 1.0)
CALLOUTS=(
  "multiball|Multiball!|Multiball.|0.95"
  "jackpot|Jackpot!|Jackpot!|0.92"
  "warp|Warp!|Warp jump!|1.0"
  "ballsaved|Ball saved.|Ball saved!|0.95"
  "tilt|Tilt.|Tilt!|0.92"
  "asteroid|Asteroid storm!|Asteroid storm!|0.93"
  "solarflare|Solar flare!|Solar flare!|0.93"
  "gravitywell|Gravity well!|Gravity well.|0.95"
  "modelit|Mode is lit.|Mode is lit.|0.93"
  "locklit|Lock is lit.|Lock is lit.|0.93"
  "locked|Ball locked.|Ball locked!|0.95"
  "nova|Nova!|Nova!|0.92"
  "gameover|Game over.|The game is over.|1.0"
  "highscore|New high score!|A new high score!|0.95"
  "welcome|Welcome to Nova Rush. Launch when ready.|Welcome to Nova Rush. Launch when ready!|0.95"
  "extraball|Extra ball!|You earned an extra ball!|1.0"
  "shootagain|Shoot again!|Same player, shoot again!|1.0"
  "eblit|Extra ball is lit.|The extra ball is lit.|1.0"
  "skillshot|Skill shot!|Skill shot.|0.95"
  "superskill|Super skill shot!|Super skill shot!|0.93"
  "combo|Combo!|Combo shot!|1.0"
  "supercombo|Super combo!|Super combo.|0.95"
)

# Lost-ball quips (spoken in 10 % of lost balls): one callout "balllost" with
# one take per quip — file | text | voice ("heart" = $VOICE, "blend" = $VOICE2).
# Eleven quips; add more as balllost_<n>.
QUIPS=(
  "balllost|Bad luck!|heart"
  "balllost_2|Oh no!|blend"
  "balllost_3|Oh dear!|heart"
  "balllost_4|Damn!|blend"
  "balllost_5|Oh crap!|heart"
  "balllost_6|No no no!|blend"
  "balllost_7|Ouch!|heart"
  "balllost_8|So close!|blend"
  "balllost_9|Not again!|heart"
  "balllost_10|Lost in space.|blend"
  "balllost_11|Gravity wins.|heart"
)

# Attract-show invitations (spoken now and then while no game runs, only while
# the app is in front): callout "attract", one take per line, same format.
INVITES=(
  "attract|Ready for launch, pilot?|heart"
  "attract_2|Hey, pilot! Press space to play.|blend"
  "attract_3|All systems go. We just need a pilot.|heart"
  "attract_4|Come on. The stars won't wait forever.|blend"
  "attract_5|Nova Rush. No coins needed. Just courage.|heart"
  "attract_6|Feel the rush! Come and play.|blend"
)

PREP=()
for entry in "${CALLOUTS[@]}"; do
  IFS='|' read -r name text1 text2 speed2 <<< "$entry"
  if (( $# > 0 )) && [[ ! " $* " == *" $name "* ]]; then continue; fi
  printf "%s" "$text1" > "$TMP/$name.txt"
  printf "%s" "$text2" > "$TMP/${name}_2.txt"
  (cd kokoro-tts && pixi run kokoro-tts "$TMP/$name.txt" "$OUT/$name.wav" \
      --voice $VOICE --lang en-us --speed 1.0 >/dev/null 2>&1)
  (cd kokoro-tts && pixi run kokoro-tts "$TMP/${name}_2.txt" "$OUT/${name}_2.wav" \
      --voice "$VOICE2" --lang en-us --speed "$speed2" >/dev/null 2>&1)
  echo "generated $name"
  PREP+=("$name=$OUT/$name.wav" "${name}_2=$OUT/${name}_2.wav")
done
for entry in "${QUIPS[@]}" "${INVITES[@]}"; do
  IFS='|' read -r file text which <<< "$entry"
  base=${file%%_[0-9]*}                       # balllost_3 → balllost
  if (( $# > 0 )) && [[ ! " $* " == *" $base "* ]]; then continue; fi
  voice=$VOICE; [[ $which == blend ]] && voice=$VOICE2
  printf "%s" "$text" > "$TMP/$file.txt"
  (cd kokoro-tts && pixi run kokoro-tts "$TMP/$file.txt" "$OUT/$file.wav" \
      --voice "$voice" --lang en-us --speed 1.0 >/dev/null 2>&1)
  echo "generated $file"
  PREP+=("$file=$OUT/$file.wav")
done
rm -rf "$TMP"
echo
echo "Install with:"
echo "swift Tools/voiceprep.swift ${PREP[*]}"
