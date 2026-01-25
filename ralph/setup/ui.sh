#!/usr/bin/env bash
# UI utilities: colors, ASCII art, prompts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Emoji support check
EMOJI_ROCKET="🚀"
EMOJI_MOVIE="🎬"
EMOJI_BOOK="📚"
EMOJI_CHECK="✓"
EMOJI_CROSS="✗"
EMOJI_WARN="⚠"
EMOJI_PARTY="🎉"

show_logo() {
  echo -e "${CYAN}"
  cat << 'EOF'

  ╦  ╦╦╔╗ ╔═╗   ┬   ╔╦╗╦ ╦╦═╗╦╦  ╦╔═╗
  ╚╗╔╝║╠╩╗║╣   ┌┼─   ║ ╠═╣╠╦╝║╚╗╔╝║╣
   ╚╝ ╩╚═╝╚═╝  └┘    ╩ ╩ ╩╩╚═╩ ╚╝ ╚═╝

EOF
  echo -e "${NC}"
  echo -e "  ${DIM}Tools to help you thrive with agentic coding${NC}"
  echo -e "  ${DIM}by AllThrive.ai${NC}"
  echo -e "  ${DIM}─────────────────────────────────${NC}"
  echo ""
}

show_welcome() {
  echo -e "  ${BOLD}Welcome!${NC} How would you like to get started?"
  echo ""
  echo -e "  ${GREEN}[1]${NC} ${EMOJI_ROCKET} ${BOLD}Quick Setup${NC}"
  echo -e "      ${DIM}I know what I'm doing, just configure my project${NC}"
  echo ""
  echo -e "  ${GREEN}[2]${NC} ${EMOJI_MOVIE} ${BOLD}Feature Tour${NC}"
  echo -e "      ${DIM}Show me what agentic-loop can do (auto-demo)${NC}"
  echo ""
  echo -e "  ${GREEN}[3]${NC} ${EMOJI_BOOK} ${BOLD}New to Claude Code${NC}"
  echo -e "      ${DIM}Teach me the basics (interactive tutorial)${NC}"
  echo ""
}

prompt_menu() {
  local choice
  while true; do
    echo -ne "  Press ${GREEN}1${NC}, ${GREEN}2${NC}, or ${GREEN}3${NC} (or ${DIM}q${NC} to quit): "
    read -r -n 1 choice
    echo ""
    case "$choice" in
      1|2|3|q|Q) echo "$choice"; return ;;
      *) echo -e "  ${RED}Invalid choice${NC}" ;;
    esac
  done
}

# Typewriter effect for demos
typewrite() {
  local text="$1" delay="${2:-0.02}"
  for ((i=0; i<${#text}; i++)); do
    echo -n "${text:$i:1}"
    sleep "$delay"
  done
  echo ""
}

# Progress indicator
show_step() {
  local current="$1" total="$2" desc="$3"
  echo -e "\n  ${CYAN}[$current/$total]${NC} ${BOLD}$desc${NC}\n"
}

# Continue prompt with skip option
# Returns 0 to continue, 1 to skip to setup
press_enter() {
  echo ""
  echo -ne "  ${DIM}Press Enter to continue, or 's' to skip to setup...${NC} "
  read -r -n 1 key
  echo ""
  [[ "$key" == "s" || "$key" == "S" ]] && return 1
  return 0
}

# Print success message
print_success() {
  echo -e "  ${GREEN}${EMOJI_CHECK}${NC} $1"
}

# Print error message
print_error() {
  echo -e "  ${RED}${EMOJI_CROSS}${NC} $1"
}

# Print warning message
print_warning() {
  echo -e "  ${YELLOW}${EMOJI_WARN}${NC} $1"
}

# Print info message
print_info() {
  echo -e "  ${CYAN}→${NC} $1"
}

# Spinner for long operations
spin() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf "  [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "      \b\b\b\b\b\b"
}

# Confirmation prompt
confirm() {
  local prompt="${1:-Proceed?}"
  echo -ne "  $prompt ${GREEN}[Y/n]${NC} "
  read -r -n 1 confirm
  echo ""
  [[ "$confirm" != "n" && "$confirm" != "N" ]]
}
