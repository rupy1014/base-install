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

# 현재 쉘 설정 즉시 적용
reload_shell_config() {
    # 현재 세션에 PATH 즉시 적용
    for rc_file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        if [ -f "$rc_file" ]; then
            eval "$(grep -E '^export PATH=|^eval ' "$rc_file" 2>/dev/null)" 2>/dev/null || true
        fi
    done

    # fnm이 있으면 환경 설정
    if [ -f "$HOME/.local/share/fnm/fnm" ]; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$($HOME/.local/share/fnm/fnm env)" 2>/dev/null || true
        $HOME/.local/share/fnm/fnm use default 2>/dev/null || true

        # fnm env/multishell이 실패할 경우 대비: node 바이너리 직접 탐색
        if ! command -v node &>/dev/null; then
            local fnm_default="$HOME/.local/share/fnm/aliases/default/bin"
            if [ -d "$fnm_default" ]; then
                export PATH="$fnm_default:$PATH"
            else
                # aliases가 없으면 설치된 버전 중 최신을 직접 찾기
                local node_bin
                node_bin=$(find "$HOME/.local/share/fnm/node-versions" -maxdepth 3 -name "node" -path "*/bin/node" 2>/dev/null | sort -V | tail -1)
                if [ -n "$node_bin" ]; then
                    export PATH="$(dirname "$node_bin"):$PATH"
                fi
            fi
        fi
    fi

    # Homebrew 환경 설정
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
    fi
}

# .bash_profile에서 .bashrc를 source하도록 설정 (한 번만 실행)
setup_bash_profile_source() {
    if [ ! -f "$HOME/.bash_profile" ]; then
        touch "$HOME/.bash_profile"
    fi
    # .bash_profile에서 .bashrc를 source하는 코드가 없으면 추가
    if ! grep -q "source.*bashrc\|\..*bashrc" "$HOME/.bash_profile" 2>/dev/null; then
        # 파일 맨 앞에 추가 (다른 설정보다 먼저 실행되도록)
        local temp_file=$(mktemp)
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
    if ! grep -q "$path_to_add" "$HOME/.zshrc" 2>/dev/null; then
        echo "$export_line" >> "$HOME/.zshrc"
    fi

    # bash 설정 - .bashrc에만 추가 (VSCode, non-login 쉘)
    # .bash_profile은 .bashrc를 source하므로 여기만 추가하면 됨
    if [ ! -f "$HOME/.bashrc" ]; then
        touch "$HOME/.bashrc"
    fi
    if ! grep -q "$path_to_add" "$HOME/.bashrc" 2>/dev/null; then
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

# bash 사용자를 위해 .bash_profile → .bashrc 연결 설정
setup_bash_profile_source

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

        # 쉘 설정에 fnm 추가 (.zshrc와 .bashrc에만 - .bash_profile은 .bashrc를 source함)
        FNM_SETUP='
# fnm (Node.js)
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"'

        for rc_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
            if [ ! -f "$rc_file" ]; then
                touch "$rc_file"
            fi
            if ! grep -q "fnm env" "$rc_file" 2>/dev/null; then
                echo "$FNM_SETUP" >> "$rc_file"
            fi
        done

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
        fi
        # 모든 쉘 설정 파일에 PATH 추가 (zsh, bash 모두 지원)
        add_to_shell_config "$claude_path"
    fi
done

# 쉘 설정 즉시 적용
reload_shell_config

# Claude 실행 파일 직접 찾기
find_claude() {
    local paths=(
        "$HOME/.claude/bin/claude"
        "$HOME/.local/bin/claude"
        "/opt/homebrew/bin/claude"
        "/usr/local/bin/claude"
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
CLAUDE_BIN=$(find_claude)
if [ -n "$CLAUDE_BIN" ]; then
    # PATH에 추가되어 있는지 확인하고, 없으면 추가
    CLAUDE_DIR=$(dirname "$CLAUDE_BIN")
    if [[ ":$PATH:" != *":$CLAUDE_DIR:"* ]]; then
        export PATH="$CLAUDE_DIR:$PATH"
    fi
    claude_ver=$("$CLAUDE_BIN" --version 2>/dev/null || echo "installed")
    print_success "Claude Code 설치 완료! ($claude_ver)"
else
    print_error "Claude Code 설치 실패 - 수동 설치가 필요합니다"
    print_info "https://claude.ai/download 에서 직접 다운로드하세요"
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
fi
# 모든 쉘 설정 파일에 PATH 추가 (zsh, bash 모두 지원)
add_to_shell_config "$DSCLAUDE_BIN"

print_success "dsclaude 명령어 생성 완료!"

# ============================================================
# 최종 검증 및 완료
# ============================================================

echo ""
print_step "설치 검증 중..."

# 모든 PATH 다시 한번 적용
reload_shell_config

# 최종 검증
FINAL_CHECK_PASSED=true
FINAL_CLAUDE_PATH=""
SHELL_CONFIG_OK=true

# 1. Claude 실행 파일 존재 확인
if command_exists claude; then
    FINAL_CLAUDE_PATH=$(command -v claude)
    print_success "claude 실행 파일: $FINAL_CLAUDE_PATH"
elif [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then
    FINAL_CLAUDE_PATH="$CLAUDE_BIN"
    print_success "claude 실행 파일: $FINAL_CLAUDE_PATH"
else
    print_error "claude 실행 파일을 찾을 수 없습니다"
    FINAL_CHECK_PASSED=false
fi

# 2. 쉘 설정 파일에 PATH가 제대로 추가됐는지 확인 (새 터미널에서 작동하려면 필수)
CLAUDE_DIR=$(dirname "$FINAL_CLAUDE_PATH" 2>/dev/null)
if [ -n "$CLAUDE_DIR" ]; then
    # zsh 설정 확인
    if grep -q "$CLAUDE_DIR" "$HOME/.zshrc" 2>/dev/null; then
        print_success "zsh 설정 완료 (~/.zshrc)"
    else
        print_error "zsh 설정 누락 (~/.zshrc에 PATH 없음)"
        SHELL_CONFIG_OK=false
    fi

    # bash 설정 확인
    if grep -q "$CLAUDE_DIR" "$HOME/.bashrc" 2>/dev/null; then
        print_success "bash 설정 완료 (~/.bashrc)"
    else
        print_error "bash 설정 누락 (~/.bashrc에 PATH 없음)"
        SHELL_CONFIG_OK=false
    fi

    # .bash_profile → .bashrc 연결 확인
    if grep -q "bashrc" "$HOME/.bash_profile" 2>/dev/null; then
        print_success "bash_profile → bashrc 연결됨"
    else
        print_error "bash_profile에서 bashrc를 source하지 않음"
        SHELL_CONFIG_OK=false
    fi
fi

# 3. dsclaude 명령어 확인
if [ -x "$HOME/.local/bin/dsclaude" ]; then
    print_success "dsclaude 명령어 확인됨"
else
    print_error "dsclaude 명령어를 찾을 수 없습니다"
fi

# 4. Node.js 확인
# fnm 환경이 제대로 안 잡힐 수 있으므로 직접 탐색
if ! command_exists node && [ -f "$HOME/.local/share/fnm/fnm" ]; then
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$($HOME/.local/share/fnm/fnm env)" 2>/dev/null || true
    $HOME/.local/share/fnm/fnm use default 2>/dev/null || true

    # 그래도 안 되면 node 바이너리 직접 찾기
    if ! command_exists node; then
        FNM_DEFAULT_BIN="$HOME/.local/share/fnm/aliases/default/bin"
        if [ -d "$FNM_DEFAULT_BIN" ]; then
            export PATH="$FNM_DEFAULT_BIN:$PATH"
        else
            NODE_BIN=$(find "$HOME/.local/share/fnm/node-versions" -maxdepth 3 -name "node" -path "*/bin/node" 2>/dev/null | sort -V | tail -1)
            if [ -n "$NODE_BIN" ]; then
                export PATH="$(dirname "$NODE_BIN"):$PATH"
            fi
        fi
    fi
fi

if command_exists node; then
    print_success "node 확인됨: $(node --version)"
else
    print_error "node 명령어를 찾을 수 없습니다"
    print_info "새 터미널을 열면 정상 작동할 수 있습니다"
    FINAL_CHECK_PASSED=false
fi

# 쉘 설정 문제가 있으면 자동 복구 시도
if [ "$SHELL_CONFIG_OK" = false ] && [ -n "$CLAUDE_DIR" ]; then
    echo ""
    print_step "쉘 설정 자동 복구 중..."
    add_to_shell_config "$CLAUDE_DIR"
    setup_bash_profile_source
    print_success "쉘 설정 복구 완료"
    SHELL_CONFIG_OK=true
fi

echo ""
if [ "$FINAL_CHECK_PASSED" = true ]; then
    echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║         ✅ 설치 완료!                    ║${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}claude${NC}     - Claude Code 실행"
    echo -e "  ${CYAN}dsclaude${NC}   - 권한 확인 스킵 모드"
    echo ""
    echo ""
    echo -e "${YELLOW}  3초 후 새 터미널이 열립니다...${NC}"
    sleep 3

    # 자동으로 새 터미널 열기 시도
    osascript -e 'tell application "Terminal" to do script ""' -e 'tell application "Terminal" to activate' 2>/dev/null || true

    echo ""
    echo -e "${GREEN}  새 터미널 창에서 claude 를 입력하세요!${NC}"
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
    echo -e "  3. VSCode 터미널에서 안 되면:"
    echo -e "${GRAY}     VSCode 완전 종료 후 다시 열기${NC}"
    echo -e "${GRAY}     또는 터미널 설정에서 기본 쉘 확인${NC}"
    echo ""
    echo -e "  4. 그래도 안 되면 수동 설치:"
    echo -e "${CYAN}     curl -fsSL https://claude.ai/install.sh | bash${NC}"
    echo ""
    echo -e "  문제가 계속되면: https://github.com/anthropics/claude-code/issues"
    echo ""
fi
