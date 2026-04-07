#!/bin/bash

#
# oh-my-codex (OMX) 설치 스크립트 (macOS)
# Codex CLI 설치 이후 실행
#

# ============================================================
# 콘솔 출력 함수들
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${GRAY}   $1${NC}"
}

command_exists() {
    command -v "$1" &> /dev/null
}

# 쉘 설정 파일에 내용 추가 (중복 방지)
add_to_shell_configs() {
    local marker="$1"
    local content="$2"

    for rc_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [ ! -f "$rc_file" ]; then
            touch "$rc_file"
        fi
        if ! grep -q "$marker" "$rc_file" 2>/dev/null; then
            echo "" >> "$rc_file"
            echo "$content" >> "$rc_file"
        fi
    done
}

# ============================================================
# 메인 설치
# ============================================================

clear
echo ""
echo -e "${CYAN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║   oh-my-codex (OMX) 설치 스크립트        ║${NC}"
echo -e "${CYAN}  ║              (macOS)                     ║${NC}"
echo -e "${CYAN}  ╚══════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. 사전 요구사항 확인
# ============================================================
print_step "사전 요구사항 확인 중..."

# Node.js 확인
if ! command_exists node; then
    print_error "Node.js가 설치되어 있지 않습니다."
    print_info "먼저 codex-mac-install.sh 를 실행하세요."
    exit 1
fi

node_ver=$(node --version 2>/dev/null)
version_num=$(echo "$node_ver" | sed 's/v\([0-9]*\).*/\1/')
if [ "$version_num" -lt 20 ] 2>/dev/null; then
    print_error "Node.js 20+ 필요 (현재: $node_ver)"
    print_info "Node.js를 업그레이드하세요."
    exit 1
fi
print_success "Node.js $node_ver"

# npm 확인
if ! command_exists npm; then
    print_error "npm이 설치되어 있지 않습니다."
    exit 1
fi
print_success "npm $(npm --version 2>/dev/null)"

# Codex CLI 확인
if ! command_exists codex; then
    print_error "Codex CLI가 설치되어 있지 않습니다."
    print_info "먼저 codex-mac-install.sh 를 실행하세요."
    exit 1
fi
print_success "Codex CLI $(codex --version 2>/dev/null || echo 'installed')"

# ============================================================
# 2. oh-my-codex 설치
# ============================================================
echo ""
print_step "oh-my-codex 설치 중..."

if command_exists omx; then
    omx_ver=$(omx --version 2>/dev/null || echo "installed")
    print_success "oh-my-codex 이미 설치됨 ($omx_ver)"
else
    print_info "npm install -g oh-my-codex"
    print_info "설치에 1-2분 정도 소요됩니다..."
    echo ""

    if npm install -g oh-my-codex 2>&1; then
        print_success "oh-my-codex 설치 완료!"
    else
        print_info "npm 설치 실패 - sudo로 재시도 중..."
        if sudo npm install -g oh-my-codex 2>&1; then
            print_success "oh-my-codex 설치 완료!"
        else
            print_error "oh-my-codex 설치 실패"
            exit 1
        fi
    fi
fi

# ============================================================
# 3. tmux 설치 (team 모드용)
# ============================================================
echo ""
print_step "tmux 확인 중..."

if command_exists tmux; then
    tmux_ver=$(tmux -V 2>/dev/null)
    print_success "tmux 설치됨 ($tmux_ver)"
else
    print_info "tmux 설치 중 (team 모드에 필요)..."

    if command_exists brew; then
        brew install tmux 2>/dev/null
    elif [ -f "/opt/homebrew/bin/brew" ]; then
        /opt/homebrew/bin/brew install tmux 2>/dev/null
    elif [ -f "/usr/local/bin/brew" ]; then
        /usr/local/bin/brew install tmux 2>/dev/null
    else
        print_info "Homebrew 없음 - tmux 수동 설치 필요: brew install tmux"
    fi

    if command_exists tmux; then
        print_success "tmux 설치 완료!"
    else
        print_info "tmux 미설치 - team 모드 없이도 기본 기능은 사용 가능"
    fi
fi

# ============================================================
# 4. omx setup 실행
# ============================================================
echo ""
print_step "omx setup 실행 중..."
print_info "프롬프트, 스킬, 설정, AGENTS 스캐폴딩을 설치합니다..."

if command_exists omx; then
    if omx setup 2>&1; then
        print_success "omx setup 완료!"
    else
        print_error "omx setup 실패 - 수동으로 실행해주세요: omx setup"
    fi
else
    print_error "omx 명령어를 찾을 수 없습니다"
fi

# ============================================================
# 5. alias 설정
# ============================================================
echo ""
print_step "alias 설정 중..."

ALIAS_BLOCK='# dscodex: omx madmax shortcut
alias dscodex='"'"'omx --madmax --high'"'"''

add_to_shell_configs "alias dscodex=" "$ALIAS_BLOCK"

# 현재 세션에도 즉시 적용
alias dscodex='omx --madmax --high' 2>/dev/null || true

print_success "dscodex alias 설정 완료"
print_info "dscodex = omx --madmax --high"

# ============================================================
# 6. 설치 검증
# ============================================================
echo ""
print_step "설치 검증 중..."

FINAL_CHECK_PASSED=true

if command_exists omx; then
    omx_ver=$(omx --version 2>/dev/null || echo "installed")
    print_success "omx 명령어 확인됨 ($omx_ver)"
else
    print_error "omx 명령어를 찾을 수 없습니다"
    FINAL_CHECK_PASSED=false
fi

# alias 확인 (zshrc에 등록됐는지)
if grep -q "alias dscodex=" "$HOME/.zshrc" 2>/dev/null; then
    print_success "dscodex alias (zsh)"
else
    print_error "dscodex alias 누락 (zsh)"
    FINAL_CHECK_PASSED=false
fi

if grep -q "alias dscodex=" "$HOME/.bashrc" 2>/dev/null; then
    print_success "dscodex alias (bash)"
else
    print_error "dscodex alias 누락 (bash)"
    FINAL_CHECK_PASSED=false
fi

if command_exists tmux; then
    print_success "tmux 확인됨 (team 모드 사용 가능)"
else
    print_info "tmux 미설치 (team 모드 사용 불가)"
fi

# ============================================================
# 완료
# ============================================================

echo ""
if [ "$FINAL_CHECK_PASSED" = true ]; then
    echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║         ✅ OMX 설치 완료!                ║${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}사용 가능한 명령어:${NC}"
    echo ""
    echo -e "  ${CYAN}dscodex${NC}    - omx --madmax --high (풀파워 모드)"
    echo -e "  ${CYAN}omx${NC}        - oh-my-codex 기본 실행"
    echo -e "  ${CYAN}codex${NC}      - Codex CLI 기본 실행"
    echo ""
    echo -e "  ${CYAN}OMX 워크플로우:${NC}"
    echo ""
    echo -e "  ${GRAY}  dscodex 로 시작한 뒤:${NC}"
    echo -e "  ${GRAY}  \$deep-interview \"작업 내용 명확화\"${NC}"
    echo -e "  ${GRAY}  \$ralplan \"구현 계획 승인\"${NC}"
    echo -e "  ${GRAY}  \$ralph \"승인된 계획 실행\"${NC}"
    echo -e "  ${GRAY}  \$team 3:executor \"병렬 실행\"${NC}"
    echo ""
    echo -e "${YELLOW}  새 터미널을 열거나 source ~/.zshrc 를 실행하세요.${NC}"
    echo ""
else
    echo -e "${RED}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${RED}  ║       ⚠️  설치 중 문제 발생              ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}  해결 방법:${NC}"
    echo ""
    echo -e "  1. 수동 설치:"
    echo -e "${CYAN}     npm install -g oh-my-codex${NC}"
    echo -e "${CYAN}     omx setup${NC}"
    echo ""
    echo -e "  2. alias 수동 추가 (~/.zshrc 에):"
    echo -e "${CYAN}     alias dscodex='omx --madmax --high'${NC}"
    echo ""
    echo -e "  문제가 계속되면: https://github.com/Yeachan-Heo/oh-my-codex/issues"
    echo ""
fi
