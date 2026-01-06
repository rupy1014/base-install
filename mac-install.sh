#!/bin/bash

#
# Claude Code 원클릭 설치 스크립트 (macOS)
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
echo -e "${CYAN}  ║   Claude Code 원클릭 설치 스크립트       ║${NC}"
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

    # 설치 완료 대기
    echo ""
    print_info "설치가 완료될 때까지 기다리는 중..."
    until xcode-select -p &> /dev/null; do
        sleep 5
    done
    print_success "Xcode CLT 설치 완료!"
fi

# 2. Homebrew 확인 (있으면 사용, 없으면 대안 사용)
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

# 4. Node.js 설치
echo ""
print_step "Node.js 확인 중..."

install_node_with_fnm() {
    print_info "fnm으로 Node.js 설치 중..."

    # fnm 설치
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell

    # fnm 경로
    FNM_PATH="$HOME/.local/share/fnm"

    if [ -f "$FNM_PATH/fnm" ]; then
        export PATH="$FNM_PATH:$PATH"
        eval "$($FNM_PATH/fnm env)"

        # Node.js LTS 설치
        $FNM_PATH/fnm install --lts
        $FNM_PATH/fnm use lts-latest
        $FNM_PATH/fnm default lts-latest

        # 쉘 설정에 fnm 추가
        FNM_SETUP='
# fnm (Node.js)
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"'

        # .zshrc 설정
        if [ ! -f "$HOME/.zshrc" ]; then
            touch "$HOME/.zshrc"
        fi
        if ! grep -q "fnm env" "$HOME/.zshrc"; then
            echo "$FNM_SETUP" >> "$HOME/.zshrc"
        fi

        # .bashrc 설정
        if [ -f "$HOME/.bashrc" ]; then
            if ! grep -q "fnm env" "$HOME/.bashrc"; then
                echo "$FNM_SETUP" >> "$HOME/.bashrc"
            fi
        fi

        eval "$(fnm env)" 2>/dev/null
        return 0
    fi
    return 1
}

NODE_OK=false
if command_exists node; then
    node_ver=$(node --version)
    version_num=$(echo $node_ver | sed 's/v\([0-9]*\).*/\1/')

    if [ "$version_num" -ge 18 ]; then
        print_success "Node.js 설치됨 ($node_ver)"
        NODE_OK=true
    else
        print_info "Node.js 버전이 낮습니다 ($node_ver). 업그레이드 중..."
    fi
fi

if [ "$NODE_OK" = false ]; then
    if [ "$USE_HOMEBREW" = true ]; then
        $BREW_CMD install node@20
        $BREW_CMD link node@20 --overwrite --force 2>/dev/null
    else
        install_node_with_fnm
    fi

    # 설치 확인
    if command_exists node; then
        node_ver=$(node --version)
        print_success "Node.js 설치 완료! ($node_ver)"
    else
        # fnm 경로 다시 확인
        if [ -f "$HOME/.local/share/fnm/fnm" ]; then
            eval "$($HOME/.local/share/fnm/fnm env)" 2>/dev/null
            if command_exists node; then
                node_ver=$(node --version)
                print_success "Node.js 설치 완료! ($node_ver)"
            fi
        fi
    fi
fi

# 5. Claude Code 설치
echo ""
print_step "Claude Code 설치 중..."

CLAUDE_INSTALLED=false

# Homebrew로 설치 시도 (있으면)
if [ "$USE_HOMEBREW" = true ]; then
    print_info "Homebrew로 설치 중..."
    if $BREW_CMD install --cask claude-code 2>/dev/null; then
        CLAUDE_INSTALLED=true
    fi
fi

# Homebrew 실패 또는 없으면 공식 스크립트 사용
if [ "$CLAUDE_INSTALLED" = false ]; then
    print_info "공식 스크립트로 설치 중..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# PATH 설정
CLAUDE_PATHS=(
    "$HOME/.claude/bin"
    "$HOME/.local/bin"
)

for claude_path in "${CLAUDE_PATHS[@]}"; do
    if [ -d "$claude_path" ]; then
        if [[ ":$PATH:" != *":$claude_path:"* ]]; then
            export PATH="$claude_path:$PATH"

            # .zshrc 설정
            if [ ! -f "$HOME/.zshrc" ]; then
                touch "$HOME/.zshrc"
            fi
            if ! grep -q "$claude_path" "$HOME/.zshrc"; then
                echo "export PATH=\"$claude_path:\$PATH\"" >> "$HOME/.zshrc"
            fi

            # .bashrc 설정
            if [ -f "$HOME/.bashrc" ]; then
                if ! grep -q "$claude_path" "$HOME/.bashrc"; then
                    echo "export PATH=\"$claude_path:\$PATH\"" >> "$HOME/.bashrc"
                fi
            fi
        fi
    fi
done

sleep 2
if command_exists claude; then
    claude_ver=$(claude --version 2>/dev/null || echo "installed")
    print_success "Claude Code 설치 완료! ($claude_ver)"
else
    print_info "설치 완료 (새 터미널에서 사용 가능)"
fi

# 6. dsclaude 명령어 생성
echo ""
print_step "dsclaude 명령어 생성 중..."

DSCLAUDE_BIN="$HOME/.local/bin"
mkdir -p "$DSCLAUDE_BIN"

cat > "$DSCLAUDE_BIN/dsclaude" << 'EOF'
#!/bin/bash
claude --dangerously-skip-permissions "$@"
EOF

chmod +x "$DSCLAUDE_BIN/dsclaude"

if [[ ":$PATH:" != *":$DSCLAUDE_BIN:"* ]]; then
    export PATH="$DSCLAUDE_BIN:$PATH"

    if [ ! -f "$HOME/.zshrc" ]; then
        touch "$HOME/.zshrc"
    fi
    if ! grep -q "$DSCLAUDE_BIN" "$HOME/.zshrc"; then
        echo "export PATH=\"$DSCLAUDE_BIN:\$PATH\"" >> "$HOME/.zshrc"
    fi
fi

print_success "dsclaude 명령어 생성 완료!"

# ============================================================
# 완료
# ============================================================

echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║            설치 완료!                    ║${NC}"
echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}  중요: 새 터미널 창을 열어주세요!${NC}"
echo ""
echo -e "  사용법:"
echo -e "${CYAN}     claude${NC}     - Claude Code 실행"
echo -e "${CYAN}     dsclaude${NC}   - 권한 확인 스킵 모드"
echo ""
echo -e "  시작하기:"
echo -e "${GRAY}     1. 새 터미널 열기${NC}"
echo -e "${GRAY}     2. claude 입력${NC}"
echo -e "${GRAY}     3. 로그인하면 끝!${NC}"
echo ""
