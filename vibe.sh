#!/bin/zsh
# Vibe — a tiny, mouse-aware macOS terminal editor with an AI copilot.

setopt NO_NOMATCH EXTENDED_GLOB

APP_NAME="Vibe"
ROOT_DIR="${0:A:h}"
ENV_FILE="$ROOT_DIR/.env.local"
MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
TARGET_FILE="${1:-$ROOT_DIR/untitled.txt}"
TARGET_FILE="${TARGET_FILE:A}"

typeset -a BUFFER AI_LINES FILES
BUFFER=("")
AI_LINES=("Ask AI with Ctrl-K" "" "Try:" "  explain this file" "  find bugs" "  refactor selection")
FILES=()
CURSOR_ROW=1
CURSOR_COL=0
SCROLL=0
AI_SCROLL=0
ACTIVE="editor"
EXPLORER_INDEX=1
AI_PROMPT=""
DIRTY=0
STATUS="Ready"
RUNNING=1
OLD_STTY=""

autoload -Uz colors && colors

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    local env_line model_line
    env_line="$(command grep '^GEMINI_API_KEY=' "$ENV_FILE" 2>/dev/null | command head -n 1)"
    [[ -n "$env_line" ]] && export GEMINI_API_KEY="${env_line#GEMINI_API_KEY=}"
    model_line="$(command grep '^GEMINI_MODEL=' "$ENV_FILE" 2>/dev/null | command head -n 1)"
    [[ -n "$model_line" ]] && MODEL="${model_line#GEMINI_MODEL=}"
  fi
}

load_file() {
  BUFFER=()
  if [[ -f "$TARGET_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do BUFFER+=("$line"); done < "$TARGET_FILE"
    (( ${#BUFFER} == 0 )) && BUFFER=("")
  else
    BUFFER=("")
  fi
  CURSOR_ROW=1 CURSOR_COL=0 SCROLL=0 DIRTY=0
  STATUS="Opened ${TARGET_FILE:t}"
  refresh_files
}

refresh_files() {
  FILES=()
  local item
  for item in "${TARGET_FILE:h}"/*; do
    [[ -f "$item" && "${item:t}" != .* ]] || continue
    FILES+=("${item:t}")
    (( ${#FILES} >= 40 )) && break
  done
  (( EXPLORER_INDEX < 1 )) && EXPLORER_INDEX=1
  (( EXPLORER_INDEX > ${#FILES} && ${#FILES} > 0 )) && EXPLORER_INDEX=${#FILES}
}

cleanup() {
  [[ -n "$OLD_STTY" ]] && stty "$OLD_STTY" 2>/dev/null
  printf '\e[?1000l\e[?1006l\e[?25h\e[?1049l'
}

raw_on() {
  OLD_STTY="$(stty -g)"
  stty -echo -icanon -ixon min 1 time 0
  printf '\e[?1049h\e[?25l\e[?1000h\e[?1006h'
}

save_file() {
  local parent="${TARGET_FILE:h}"
  [[ -d "$parent" ]] || { STATUS="Folder does not exist"; return; }
  {
    local i
    for (( i=1; i<=${#BUFFER}; i++ )); do
      printf '%s' "$BUFFER[$i]"
      (( i < ${#BUFFER} )) && printf '\n'
    done
  } >| "$TARGET_FILE"
  DIRTY=0 STATUS="Saved ${TARGET_FILE:t}"
  refresh_files
}

clip() {
  local text="$1" width="$2"
  text="${text//$'\t'/  }"
  (( ${#text} > width )) && text="${text[1,width-1]}…"
  printf '%-*s' "$width" "$text"
}

draw() {
  local W=$(tput cols) H=$(tput lines)
  (( W < 72 || H < 16 )) && {
    printf '\e[H\e[2J\e[38;5;213m  Make the window at least 72 × 16\e[0m'
    return
  }
  local side=20 ai=$(( W / 3 ))
  (( ai < 28 )) && ai=28
  (( ai > 46 )) && ai=46
  local edit=$(( W - side - ai - 4 ))
  local body=$(( H - 4 ))
  local line_no_width=5
  local text_width=$(( edit - line_no_width - 1 ))
  local dirty_mark=""; (( DIRTY )) && dirty_mark=" •"

  printf '\e[H\e[48;5;234m\e[38;5;255m'
  printf '  \e[1m✦ VIBE\e[0m\e[48;5;234m\e[38;5;245m  %s%s' "${TARGET_FILE:t}" "$dirty_mark"
  local used=$(( 10 + ${#TARGET_FILE:t} + ${#dirty_mark} ))
  printf '%*s' $(( W-used-20 )) ''
  printf '\e[38;5;141m⌘ terminal studio  \e[0m'

  local r idx label text ai_idx
  for (( r=1; r<=body; r++ )); do
    printf '\n\e[48;5;235m'
    # File rail
    if (( r == 1 )); then
      printf '\e[38;5;245m\e[1m  EXPLORER'
      printf '%*s' $((side-10)) ''
    else
      idx=$(( r - 2 ))
      if (( idx >= 1 && idx <= ${#FILES} )); then
        label="$FILES[$idx]"
        if [[ "$ACTIVE" == explorer && idx == EXPLORER_INDEX ]]; then
          printf '\e[48;5;61m\e[38;5;231m› '
        elif [[ "$label" == "${TARGET_FILE:t}" ]]; then
          printf '\e[48;5;60m\e[38;5;231m  '
        else
          printf '\e[38;5;250m  '
        fi
        clip "$label" $((side-2))
        printf '\e[48;5;235m'
      else
        printf '%*s' "$side" ''
      fi
    fi
    printf '\e[48;5;238m\e[38;5;238m│\e[0m'

    # Editor
    idx=$(( SCROLL + r ))
    printf '\e[48;5;233m'
    if (( idx <= ${#BUFFER} )); then
      if (( idx == CURSOR_ROW && ACTIVE == "editor" )); then
        printf '\e[48;5;236m'
      fi
      printf '\e[38;5;240m%4d ' "$idx"
      text="$BUFFER[$idx]"
      # lightweight syntax color
      if [[ "$text" == (#b)([[:space:]]#)(\#|//|/\*|\*)* ]]; then
        printf '\e[38;5;108m'
      elif [[ "$text" == (#b)([[:space:]]#)(function|def|class|if|for|while|case|echo|return)* ]]; then
        printf '\e[38;5;213m'
      else
        printf '\e[38;5;253m'
      fi
      clip "$text" "$text_width"
    else
      printf '\e[38;5;238m%4s ' '~'
      printf '%*s' "$text_width" ''
    fi
    printf '\e[48;5;238m\e[38;5;238m│\e[0m'

    # AI rail
    printf '\e[48;5;235m'
    if (( r == 1 )); then
      printf '\e[38;5;141m\e[1m  ✦ AI COPILOT'
      printf '%*s' $((ai-14)) ''
    elif (( r == body - 1 )); then
      printf '\e[38;5;245m  ASK AI'
      printf '%*s' $((ai-8)) ''
    elif (( r == body )); then
      if [[ "$ACTIVE" == ai_input ]]; then printf '\e[48;5;60m\e[38;5;255m  › '; else printf '\e[48;5;237m\e[38;5;250m  › '; fi
      clip "${AI_PROMPT:-Type a question…}" $((ai-4))
      printf '  '
    else
      ai_idx=$(( AI_SCROLL + r - 1 ))
      if (( ai_idx >= 1 && ai_idx <= ${#AI_LINES} )); then
        printf '\e[38;5;252m  '
        clip "$AI_LINES[$ai_idx]" $((ai-2))
      else
        printf '%*s' "$ai" ''
      fi
    fi
    printf '\e[0m'
  done

  printf '\n\e[48;5;237m\e[38;5;250m  ^S save  ^N new  ^B files  ^K AI  Tab panes  ^Q quit'
  local status_space=$(( W - 55 - ${#STATUS} ))
  (( status_space < 1 )) && status_space=1
  printf '%*s\e[38;5;141m%s  \e[0m' "$status_space" '' "$STATUS"
  printf '\e[48;5;234m\e[38;5;244m  Ln %d, Col %d   %s  ' "$CURSOR_ROW" $((CURSOR_COL+1)) "$MODEL"
  printf '%*s\e[0m' $(( W - 25 - ${#MODEL} )) ''

  if [[ "$ACTIVE" == editor ]]; then
    local screen_row=$(( CURSOR_ROW - SCROLL + 1 ))
    local screen_col=$(( side + line_no_width + CURSOR_COL + 2 ))
    (( screen_col > side + edit )) && screen_col=$((side+edit))
    printf '\e[%d;%dH\e[?25h' "$screen_row" "$screen_col"
  elif [[ "$ACTIVE" == ai_input ]]; then
    local input_col=$(( W - ai + 4 + ${#AI_PROMPT} ))
    (( input_col > W - 2 )) && input_col=$((W-2))
    printf '\e[%d;%dH\e[?25h' $((H-3)) "$input_col"
  else
    printf '\e[?25l'
  fi
}

prompt_line() {
  local title="$1" value="" ch
  stty echo icanon
  printf '\e[?25h\e[%d;1H\e[2K\e[48;5;60m\e[38;5;255m  %s: \e[0m' "$(tput lines)" "$title"
  IFS= read -r value
  stty -echo -icanon -ixon min 1 time 0
  REPLY="$value"
}

open_prompt() {
  prompt_line "Open file"
  [[ -z "$REPLY" ]] && return
  [[ "$REPLY" != /* ]] && REPLY="${TARGET_FILE:h}/$REPLY"
  TARGET_FILE="${REPLY:A}"
  load_file
}

create_file() {
  prompt_line "New file (relative path)"
  [[ -z "$REPLY" ]] && return
  local new_path="$REPLY"
  [[ "$new_path" != /* ]] && new_path="${TARGET_FILE:h}/$new_path"
  new_path="${new_path:A}"
  if [[ -e "$new_path" ]]; then STATUS="File already exists"; return; fi
  if [[ ! -d "$new_path:h" ]]; then STATUS="Folder does not exist"; return; fi
  TARGET_FILE="$new_path" BUFFER=("") CURSOR_ROW=1 CURSOR_COL=0 SCROLL=0 DIRTY=1 ACTIVE="editor"
  save_file
  STATUS="Created ${TARGET_FILE:t}"
}

open_explorer_file() {
  (( ${#FILES} == 0 )) && return
  TARGET_FILE="${TARGET_FILE:h}/$FILES[$EXPLORER_INDEX]"
  load_file
  ACTIVE="editor"
}

wrap_ai_text() {
  AI_LINES=()
  local input="$1" width=38 paragraph word current
  while IFS= read -r paragraph || [[ -n "$paragraph" ]]; do
    current=""
    for word in ${(z)paragraph}; do
      if (( ${#current} + ${#word} + 1 > width )); then
        AI_LINES+=("$current") current="$word"
      else
        current="${current:+$current }$word"
      fi
    done
    AI_LINES+=("$current")
  done <<< "$input"
  (( ${#AI_LINES} == 0 )) && AI_LINES=("No response")
}

ask_ai() {
  local question="$AI_PROMPT"
  [[ -z "$question" ]] && return
  AI_PROMPT=""
  if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    AI_LINES=("Gemini key not found." "Add GEMINI_API_KEY" "to .env.local") STATUS="AI unavailable"; return
  fi
  STATUS="AI is thinking…" AI_LINES=("Working…") draw
  local content="${(j:\n:)BUFFER}"
  local payload response answer
  payload="$(QUESTION="$question" CONTENT="$content" osascript -l JavaScript <<'JXA'
ObjC.import('stdlib');
JSON.stringify({system_instruction:{parts:[{text:'You are the concise coding copilot inside a terminal editor. Help with the open file. Return plain text. Do not use markdown fences unless explicitly requested.'}]},contents:[{role:'user',parts:[{text:$.getenv('QUESTION')+'\n\nOpen file:\n'+$.getenv('CONTENT')}]}],generationConfig:{maxOutputTokens:2048,temperature:0.3}})
JXA
)"
  response="$(curl -sS --max-time 90 "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/dev/null)"
  answer="$(AI_JSON="$response" osascript -l JavaScript <<'JXA' 2>/dev/null
ObjC.import('stdlib');
try {
  const x=JSON.parse($.getenv('AI_JSON'));
  if (x.error) 'Gemini: '+x.error.message;
  else (x.candidates||[]).flatMap(c=>(c.content&&c.content.parts)||[]).map(p=>p.text||'').filter(Boolean).join('\n');
} catch(e) { 'Could not reach Gemini. Check your connection.' }
JXA
)"
  [[ -z "$answer" ]] && answer="The AI returned an empty response."
  wrap_ai_text "$answer"
  ACTIVE="ai_input" AI_SCROLL=0 STATUS="AI response ready"
}

insert_char() {
  local ch="$1" line="$BUFFER[$CURSOR_ROW]"
  BUFFER[$CURSOR_ROW]="${line[1,CURSOR_COL]}${ch}${line[CURSOR_COL+1,-1]}"
  (( CURSOR_COL++ ))
  DIRTY=1
}

backspace() {
  local line="$BUFFER[$CURSOR_ROW]"
  if (( CURSOR_COL > 0 )); then
    BUFFER[$CURSOR_ROW]="${line[1,CURSOR_COL-1]}${line[CURSOR_COL+1,-1]}"
    (( CURSOR_COL-- ))
  elif (( CURSOR_ROW > 1 )); then
    local prev="$BUFFER[$((CURSOR_ROW-1))]"
    CURSOR_COL=${#prev}
    BUFFER[$((CURSOR_ROW-1))]="${prev}${line}"
    BUFFER[$CURSOR_ROW]=()
    (( CURSOR_ROW-- ))
  fi
  DIRTY=1
}

newline() {
  local line="$BUFFER[$CURSOR_ROW]" left="${line[1,CURSOR_COL]}" right="${line[CURSOR_COL+1,-1]}"
  BUFFER[$CURSOR_ROW]="$left"
  BUFFER=("${BUFFER[1,CURSOR_ROW]}" "$right" "${BUFFER[CURSOR_ROW+1,-1]}")
  (( CURSOR_ROW++ )); CURSOR_COL=0; DIRTY=1
}

handle_mouse() {
  local seq="$1"
  if [[ "$seq" =~ '^([0-9]+);([0-9]+);([0-9]+)([Mm])$' ]]; then
    local button=$match[1] x=$match[2] y=$match[3] kind=$match[4]
    [[ "$kind" == m ]] && return
    local W=$(tput cols) side=20 ai=$((W/3)); ((ai<28))&&ai=28; ((ai>46))&&ai=46
    local edit=$((W-side-ai-4))
    if (( y >= 2 && y < $(tput lines)-1 )); then
      if (( x <= side )); then
        local fi=$(( y - 2 ))
        ACTIVE="explorer"
        if (( fi >= 1 && fi <= ${#FILES} )); then EXPLORER_INDEX=$fi; open_explorer_file; fi
      elif (( x <= side + edit + 2 )); then
        ACTIVE="editor"
        local row=$(( SCROLL + y - 1 ))
        (( row < 1 )) && row=1; (( row > ${#BUFFER} )) && row=${#BUFFER}
        CURSOR_ROW=$row
        CURSOR_COL=$(( x - side - 7 ))
        (( CURSOR_COL < 0 )) && CURSOR_COL=0
        (( CURSOR_COL > ${#BUFFER[$CURSOR_ROW]} )) && CURSOR_COL=${#BUFFER[$CURSOR_ROW]}
      else
        if (( y >= $(tput lines)-3 )); then ACTIVE="ai_input"; else ACTIVE="ai"; fi
      fi
    fi
  fi
}

read_key() {
  local key rest
  IFS= read -rk1 key
  if [[ "$key" == $'\e' ]]; then
    IFS= read -rk1 -t 0.02 rest || { REPLY="ESC"; return; }
    if [[ "$rest" == '[' ]]; then
      local seq="" c
      while IFS= read -rk1 -t 0.02 c; do
        seq+="$c"
        [[ "$c" == [A-Za-z~Mm] ]] && break
      done
      if [[ "$seq" == '<'* ]]; then handle_mouse "${seq#<}"; REPLY="MOUSE"; else REPLY="ESC[$seq"; fi
    else REPLY="ESC$rest"; fi
  else REPLY="$key"; fi
}

main_loop() {
  load_env; load_file; raw_on
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  trap 'draw' WINCH
  while (( RUNNING )); do
    local H=$(tput lines) body=$((H-4))
    (( CURSOR_ROW - SCROLL > body )) && SCROLL=$((CURSOR_ROW-body))
    (( CURSOR_ROW <= SCROLL )) && SCROLL=$((CURSOR_ROW-1))
    draw; read_key
    case "$REPLY" in
      $'\x11') RUNNING=0;;
      $'\x13') save_file;;
      $'\x10') open_prompt;;
      $'\x0e') create_file;;
      $'\x02') ACTIVE="explorer";;
      $'\x0b') ACTIVE="ai_input";;
      $'\t')
        case "$ACTIVE" in editor) ACTIVE="explorer";; explorer) ACTIVE="ai_input";; *) ACTIVE="editor";; esac;;
      $'\x7f'|$'\x08')
        if [[ "$ACTIVE" == editor ]]; then backspace
        elif [[ "$ACTIVE" == ai_input && -n "$AI_PROMPT" ]]; then AI_PROMPT="${AI_PROMPT[1,-2]}"; fi;;
      $'\r'|$'\n')
        if [[ "$ACTIVE" == editor ]]; then newline
        elif [[ "$ACTIVE" == explorer ]]; then open_explorer_file
        elif [[ "$ACTIVE" == ai_input ]]; then ask_ai; fi;;
      'ESC[A')
        if [[ "$ACTIVE" == editor ]]; then ((CURSOR_ROW>1))&&((CURSOR_ROW--)); ((CURSOR_COL>${#BUFFER[$CURSOR_ROW]}))&&CURSOR_COL=${#BUFFER[$CURSOR_ROW]}
        elif [[ "$ACTIVE" == explorer ]]; then ((EXPLORER_INDEX>1))&&((EXPLORER_INDEX--))
        else ((AI_SCROLL>0))&&((AI_SCROLL--)); fi;;
      'ESC[B')
        if [[ "$ACTIVE" == editor ]]; then ((CURSOR_ROW<${#BUFFER}))&&((CURSOR_ROW++)); ((CURSOR_COL>${#BUFFER[$CURSOR_ROW]}))&&CURSOR_COL=${#BUFFER[$CURSOR_ROW]}
        elif [[ "$ACTIVE" == explorer ]]; then ((EXPLORER_INDEX<${#FILES}))&&((EXPLORER_INDEX++))
        else ((AI_SCROLL++)); fi;;
      'ESC[C') [[ "$ACTIVE" == editor ]] && ((CURSOR_COL<${#BUFFER[$CURSOR_ROW]})) && ((CURSOR_COL++));;
      'ESC[D') [[ "$ACTIVE" == editor ]] && ((CURSOR_COL>0)) && ((CURSOR_COL--));;
      MOUSE|ESC) ;;
      *)
        if [[ "$REPLY" == [[:print:]] ]]; then
          if [[ "$ACTIVE" == editor ]]; then insert_char "$REPLY"
          elif [[ "$ACTIVE" == ai_input ]]; then AI_PROMPT+="$REPLY"; fi
        fi;;
    esac
  done
}

main_loop
