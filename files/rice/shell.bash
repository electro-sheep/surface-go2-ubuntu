# rice — Catppuccin Mocha shell (sourced from ~/.bashrc)
[[ $- == *i* ]] || return

# ~/.local/bin only joins PATH at login if it already existed; make sure now
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac

__rice_git() {
  local b
  b=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null) || return
  [[ -n $(git status --porcelain --untracked-files=no 2>/dev/null | head -1) ]] && b+='*'
  printf ' \001\e[38;2;108;112;134m\002on \001\e[1;38;2;245;194;231m\002⎇ %s\001\e[0m\002' "$b"
}

__rice_prompt() {
  local s=$?
  local r='\[\e[0m\]' dim='\[\e[38;2;108;112;134m\]'
  local mauve='\[\e[1;38;2;203;166;247m\]' blue='\[\e[1;38;2;137;180;250m\]'
  local yellow='\[\e[38;2;249;226;175m\]' red='\[\e[38;2;243;139;168m\]'
  local arrow='\[\e[38;2;166;227;161m\]'
  local host='' venv='' code=''
  [[ -n $SSH_CONNECTION ]] && host="${dim}@\h"
  [[ -n $VIRTUAL_ENV ]] && venv=" ${dim}via ${yellow}${VIRTUAL_ENV##*/}"
  if (( s != 0 )); then code=" ${red}✘ $s"; arrow=$red; fi
  PS1="\n${dim}╭─ ${mauve}\u${r}${host} ${dim}in ${blue}\w${r}\$(__rice_git)${venv}${code}${r}\n${dim}╰─${arrow}❯${r} "
}

if [[ $PROMPT_COMMAND != *__rice_prompt* ]]; then
  if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
    PROMPT_COMMAND=(__rice_prompt "${PROMPT_COMMAND[@]}")
  else
    PROMPT_COMMAND="__rice_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
fi

# Catppuccin-tinted ls / grep
export GREP_COLORS='ms=01;38;2;243;139;168:fn=38;2;203;166;247:ln=38;2;137;180;250'
export LS_COLORS="di=1;38;2;203;166;247:ln=38;2;148;226;213:ex=1;38;2;166;227;161:*.tar=38;2;250;179;135:*.gz=38;2;250;179;135:*.zip=38;2;250;179;135:*.png=38;2;245;194;231:*.jpg=38;2;245;194;231:*.md=38;2;249;226;175"

# fetch once per new terminal window/tab (not in nested shells or other terminals)
if [[ -n $VTE_VERSION && -z $RICE_FETCHED ]] && command -v rice-fetch >/dev/null; then
  export RICE_FETCHED=1
  rice-fetch
fi
