#!/bin/bash

#
# Codex CLI 원클릭 설치 스크립트 (macOS)
# 완전 자동 설치 - Homebrew 없어도 OK!
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

# 현재 쉘 설정 즉시 적용
reload_shell_config() {
    for rc_file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            eval "$(grep -E '^export PATH=|^eval ' "$rc_file" 2>/dev/null)" 2>/dev/null || true
        fi
    done

    # Homebrew 환경 설정
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
}

# .bash_profile에서 .bashrc를 source하도록 설정
setup_bash_profile_source() {
    if [ ! -f "$HOME/.bash_profile" ]; then
        touch "$HOME/.bash_profile"
    fi
    if ! grep -q "source.*bashrc\|\..*bashrc" "$HOME/.bash_profile" 2>/dev/null; then
        local temp_file
        temp_file=$(mktemp)
        echo '# Load .bashrc if it exists
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
' > "$temp_file"
        cat "$HOME/.bash_profile" >> "$temp_file"
        mv "$temp_file" "$HOME/.bash_profile"
    fi
}

# 쉘 설정 파일에 PATH 추가하는 함수
add_to_shell_config() {
    local path_to_add="$1"
    local export_line="export PATH=\"$path_to_add:\$PATH\""

    # zsh 설정 (macOS 기본)
    if [ ! -f "$HOME/.zshrc" ]; then
        touch "$HOME/.zshrc"
    fi
    if ! grep -qF "$path_to_add" "$HOME/.zshrc" 2>/dev/null; then
        echo "$export_line" >> "$HOME/.zshrc"
    fi

    # bash 설정 - .bashrc에만 추가
    if [ ! -f "$HOME/.bashrc" ]; then
        touch "$HOME/.bashrc"
    fi
    if ! grep -qF "$path_to_add" "$HOME/.bashrc" 2>/dev/null; then
        echo "$export_line" >> "$HOME/.bashrc"
    fi
}

# brew 명령어 찾기
find_brew() {
    if command -v brew &> /dev/null; then
        echo "brew"
        return 0
    elif [ -f "/opt/homebrew/bin/brew" ]; then
        echo "/opt/homebrew/bin/brew"
        return 0
    elif [ -f "/usr/local/bin/brew" ]; then
        echo "/usr/local/bin/brew"
        return 0
    fi
    return 1
}

# ============================================================
# 메인 설치
# ============================================================

clear
echo ""
echo -e "${CYAN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║   Codex CLI 원클릭 설치 스크립트         ║${NC}"
echo -e "${CYAN}  ║              (macOS)                     ║${NC}"
echo -e "${CYAN}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GRAY}  모든 설치가 자동으로 진행됩니다.${NC}"
echo ""

# 변수 초기화
USE_HOMEBREW=false
BREW_CMD=""

# 1. Xcode Command Line Tools 확인
print_step "Xcode Command Line Tools 확인 중..."
if xcode-select -p &> /dev/null; then
    print_success "Xcode CLT 설치됨"
else
    print_info "Xcode Command Line Tools 설치 중..."
    print_info "팝업이 뜨면 '설치'를 클릭하세요..."
    xcode-select --install

    echo ""
    print_info "설치가 완료될 때까지 기다리는 중..."
    until xcode-select -p &> /dev/null; do
        sleep 5
    done
    print_success "Xcode CLT 설치 완료!"
fi

# 2. Homebrew 확인
echo ""
print_step "Homebrew 확인 중..."
if BREW_CMD=$(find_brew); then
    brew_ver=$($BREW_CMD --version | head -n 1)
    print_success "Homebrew 발견 ($brew_ver)"
    USE_HOMEBREW=true
    eval "$($BREW_CMD shellenv)" 2>/dev/null
else
    print_info "Homebrew 없음 - 대안 방법으로 진행"
    USE_HOMEBREW=false
fi

# 3. Git 확인 (Xcode CLT에 포함)
echo ""
print_step "Git 확인 중..."
if command_exists git; then
    git_ver=$(git --version)
    print_success "Git 설치됨 ($git_ver)"
else
    print_info "Git은 Xcode CLT에 포함되어 있습니다."
fi

# bash 사용자를 위해 .bash_profile → .bashrc 연결 설정
setup_bash_profile_source

# 4. Node.js 확인 및 설치 (Codex CLI는 npm으로만 설치 가능)
echo ""
print_step "Node.js 확인 중..."

NODE_INSTALLED=false

if command_exists node; then
    node_ver=$(node --version 2>/dev/null)
    if [ -n "$node_ver" ]; then
        version_num=$(echo "$node_ver" | sed 's/v\([0-9]*\).*/\1/')
        if [ "$version_num" -ge 18 ] 2>/dev/null; then
            print_success "Node.js 설치됨 ($node_ver)"
            NODE_INSTALLED=true
        else
            print_info "Node.js 버전이 낮습니다 ($node_ver). 업그레이드 필요..."
        fi
    fi
fi

if [ "$NODE_INSTALLED" = false ]; then
    if [ "$USE_HOMEBREW" = true ]; then
        print_info "Homebrew로 Node.js 설치 중..."
        $BREW_CMD install node 2>/dev/null
        reload_shell_config
        if command_exists node; then
            node_ver=$(node --version 2>/dev/null)
            print_success "Node.js 설치 완료! ($node_ver)"
            NODE_INSTALLED=true
        fi
    fi

    # Homebrew 실패 또는 없으면 공식 설치 스크립트 (nvm) 사용
    if [ "$NODE_INSTALLED" = false ]; then
        print_info "nvm으로 Node.js 설치 중..."

        # nvm 설치
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash 2>/dev/null

        # nvm 즉시 로드
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        # Node.js LTS 설치
        nvm install --lts 2>/dev/null
        nvm use --lts 2>/dev/null

        if command_exists node; then
            node_ver=$(node --version 2>/dev/null)
            print_success "Node.js 설치 완료! ($node_ver)"
            NODE_INSTALLED=true
        else
            print_error "Node.js 설치 실패"
            print_info "수동으로 설치해주세요: https://nodejs.org"
            exit 1
        fi
    fi
fi

# npm 확인
if ! command_exists npm; then
    print_error "npm을 찾을 수 없습니다."
    print_info "Node.js를 다시 설치해주세요."
    exit 1
fi

npm_ver=$(npm --version 2>/dev/null)
print_info "npm 버전: $npm_ver"

# 5. Codex CLI 설치
echo ""
print_step "Codex CLI 설치 중..."

CODEX_INSTALLED=false

# 이미 설치되어 있는지 확인
if command_exists codex; then
    codex_ver=$(codex --version 2>/dev/null || echo "installed")
    print_success "Codex CLI 이미 설치됨 ($codex_ver)"
    CODEX_INSTALLED=true
fi

if [ "$CODEX_INSTALLED" = false ]; then
    print_info "npm install -g @openai/codex"
    print_info "설치에 1-3분 정도 소요됩니다..."
    echo ""

    if npm install -g @openai/codex 2>&1; then
        CODEX_INSTALLED=true
    else
        # 권한(EACCES) 등으로 실패 시: sudo 대신 사용자 홈에 npm 전역 prefix 설정 후 재시도 (권장 방식)
        # sudo npm -g 는 root 소유 파일을 만들어 이후 npm 을 망가뜨리므로 사용하지 않는다.
        print_info "전역 설치 실패 - 사용자 홈(~/.npm-global)에 전역 경로를 설정하고 재시도합니다 (sudo 미사용)..."
        export npm_config_prefix="$HOME/.npm-global"
        mkdir -p "$HOME/.npm-global/bin"
        export PATH="$HOME/.npm-global/bin:$PATH"
        add_to_shell_config "$HOME/.npm-global/bin"
        if npm install -g @openai/codex 2>&1; then
            CODEX_INSTALLED=true
        fi
    fi
fi

# npm global bin PATH 확인 및 추가
NPM_GLOBAL_BIN=$(npm config get prefix 2>/dev/null)/bin
if [ -d "$NPM_GLOBAL_BIN" ]; then
    if [[ ":$PATH:" != *":$NPM_GLOBAL_BIN:"* ]]; then
        export PATH="$NPM_GLOBAL_BIN:$PATH"
    fi
    add_to_shell_config "$NPM_GLOBAL_BIN"
fi

# 쉘 설정 즉시 적용
reload_shell_config

# Codex 실행 파일 직접 찾기
find_codex() {
    local paths=(
        "$NPM_GLOBAL_BIN/codex"
        "$HOME/.nvm/versions/node/$(node --version 2>/dev/null)/bin/codex"
        "/opt/homebrew/bin/codex"
        "/usr/local/bin/codex"
    )
    for p in "${paths[@]}"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

sleep 2
CODEX_BIN=$(find_codex)
if [ -n "$CODEX_BIN" ]; then
    CODEX_DIR=$(dirname "$CODEX_BIN")
    if [[ ":$PATH:" != *":$CODEX_DIR:"* ]]; then
        export PATH="$CODEX_DIR:$PATH"
    fi
    add_to_shell_config "$CODEX_DIR"
    codex_ver=$("$CODEX_BIN" --version 2>/dev/null || echo "installed")
    print_success "Codex CLI 설치 완료! ($codex_ver)"
else
    print_error "Codex CLI 설치 실패 - 수동 설치가 필요합니다"
    print_info "npm install -g @openai/codex"
fi

# 6. dscodex 명령어 생성
echo ""
print_step "dscodex 명령어 생성 중..."

DSCODEX_BIN="$HOME/.local/bin"
mkdir -p "$DSCODEX_BIN"

cat > "$DSCODEX_BIN/dscodex" << 'EOF'
#!/bin/bash
codex --dangerously-bypass-approvals-and-sandbox "$@"
EOF

chmod +x "$DSCODEX_BIN/dscodex"

if [[ ":$PATH:" != *":$DSCODEX_BIN:"* ]]; then
    export PATH="$DSCODEX_BIN:$PATH"
fi
add_to_shell_config "$DSCODEX_BIN"

print_success "dscodex 명령어 생성 완료!"

# ============================================================
# 최종 검증 및 완료
# ============================================================

echo ""
print_step "설치 검증 중..."

# 모든 PATH 다시 한번 적용
reload_shell_config

# 최종 검증
FINAL_CHECK_PASSED=true
FINAL_CODEX_PATH=""

# 1. Codex 실행 파일 존재 확인
if command_exists codex; then
    FINAL_CODEX_PATH=$(command -v codex)
    print_success "codex 실행 파일: $FINAL_CODEX_PATH"
elif [ -n "$CODEX_BIN" ] && [ -x "$CODEX_BIN" ]; then
    FINAL_CODEX_PATH="$CODEX_BIN"
    print_success "codex 실행 파일: $FINAL_CODEX_PATH"
else
    print_error "codex 실행 파일을 찾을 수 없습니다"
    FINAL_CHECK_PASSED=false
fi

# 2. 새 셸에서 PATH가 잡히도록 rc 파일에 등록됐는지 확인 (없으면 조용히 자동 복구)
#    brew/nvm 등 어디에 깔리든 실제 설치 위치(CODEX_DIR)를 기준으로 등록 → 거짓 에러 방지
CODEX_DIR=$(dirname "$FINAL_CODEX_PATH" 2>/dev/null)
if [ -n "$CODEX_DIR" ] && [ "$CODEX_DIR" != "." ]; then
    if ! grep -qF "$CODEX_DIR" "$HOME/.zshrc" 2>/dev/null || ! grep -qF "$CODEX_DIR" "$HOME/.bashrc" 2>/dev/null; then
        add_to_shell_config "$CODEX_DIR"
        setup_bash_profile_source
    fi
    print_success "셸 PATH 설정 완료 (~/.zshrc, ~/.bashrc)"
fi

# 3. dscodex 명령어 확인
if [ -x "$HOME/.local/bin/dscodex" ]; then
    print_success "dscodex 명령어 확인됨"
else
    print_info "dscodex 명령어를 찾을 수 없습니다 (codex 는 정상 사용 가능)"
fi

echo ""
if [ "$FINAL_CHECK_PASSED" = true ]; then
    echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║         ✅ 설치 완료!                    ║${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}codex${NC}      - Codex CLI 실행"
    echo -e "  ${CYAN}dscodex${NC}    - 승인/샌드박스 스킵 모드"
    echo ""
    echo -e "  ${YELLOW}첫 실행 시 ChatGPT 계정 또는 API 키로 로그인이 필요합니다.${NC}"
    echo -e "  ${GRAY}  codex login              - 브라우저 로그인${NC}"
    echo -e "  ${GRAY}  codex login --with-api-key - API 키 로그인${NC}"
    echo ""
    echo -e "${YELLOW}  올바른 시작 순서:${NC}"
    echo -e "     1) ${CYAN}새 터미널 창을 연다${NC} (또는 현재 창에서 ${CYAN}source ~/.zshrc${NC})"
    echo -e "     2) ${CYAN}codex --version${NC}   ← 버전이 뜨면 설치 정상"
    echo -e "     3) ${CYAN}codex login${NC}       ← 브라우저 로그인"
    echo -e "     4) ${CYAN}codex${NC}             ← 사용 시작"
    echo ""
else
    echo -e "${RED}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${RED}  ║       ⚠️  설치 중 문제 발생              ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}  해결 방법:${NC}"
    echo ""
    echo -e "  1. 터미널을 완전히 종료하고 다시 열기"
    echo ""
    echo -e "  2. 또는 쉘 설정 다시 로드:"
    echo -e "${GRAY}     zsh 사용자:${NC}  ${CYAN}source ~/.zshrc${NC}"
    echo -e "${GRAY}     bash 사용자:${NC} ${CYAN}source ~/.bash_profile${NC}"
    echo ""
    echo -e "  3. 수동 설치:"
    echo -e "${CYAN}     npm install -g @openai/codex${NC}"
    echo ""
    echo -e "  문제가 계속되면: https://github.com/openai/codex/issues"
    echo ""
fi
