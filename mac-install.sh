#!/bin/bash

#
# Claude Code 원클릭 설치 스크립트 (macOS)
# Homebrew, Git, Node.js, Claude Code를 자동으로 설치합니다.
#

# ============================================================
# 🎨 콘솔 출력 함수들
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

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

# 명령어 존재 확인
command_exists() {
    command -v "$1" &> /dev/null
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

# 1. Xcode Command Line Tools 확인
print_step "Xcode Command Line Tools 확인 중..."
if xcode-select -p &> /dev/null; then
    print_success "Xcode CLT 이미 설치됨"
else
    print_info "Xcode Command Line Tools 설치 중..."
    xcode-select --install
    echo ""
    print_info "⚠️  설치 팝업이 뜨면 '설치'를 클릭하세요."
    print_info "   설치 완료 후 이 스크립트를 다시 실행해주세요."
    read -p "   설치가 완료되면 Enter를 누르세요..."
fi

# 2. Homebrew 설치
echo ""
print_step "Homebrew 확인 중..."
if command_exists brew; then
    brew_ver=$(brew --version | head -n 1)
    print_success "Homebrew 이미 설치됨 ($brew_ver)"
else
    print_info "Homebrew 설치 중... (비밀번호 입력 필요)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Apple Silicon Mac PATH 설정
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    if command_exists brew; then
        print_success "Homebrew 설치 완료!"
    else
        print_error "Homebrew 설치 실패"
        print_info "수동 설치: https://brew.sh"
        exit 1
    fi
fi

# 3. Git 설치
echo ""
print_step "Git 확인 중..."
if command_exists git; then
    git_ver=$(git --version)
    print_success "Git 이미 설치됨 ($git_ver)"
else
    print_info "Git 설치 중..."
    brew install git
    
    if command_exists git; then
        print_success "Git 설치 완료!"
    else
        print_error "Git 설치 실패"
    fi
fi

# 4. Node.js 설치
echo ""
print_step "Node.js 확인 중..."
if command_exists node; then
    node_ver=$(node --version)
    version_num=$(echo $node_ver | sed 's/v\([0-9]*\).*/\1/')
    
    if [ "$version_num" -ge 18 ]; then
        print_success "Node.js 이미 설치됨 ($node_ver)"
    else
        print_info "Node.js 버전이 낮습니다 ($node_ver). 업그레이드 중..."
        brew install node@20
        brew link node@20 --overwrite --force
    fi
else
    print_info "Node.js LTS 설치 중..."
    brew install node@20
    brew link node@20 --overwrite --force
    
    if command_exists node; then
        node_ver=$(node --version)
        print_success "Node.js 설치 완료! ($node_ver)"
    else
        print_error "Node.js 설치 실패"
    fi
fi

# 5. Claude Code 설치
echo ""
print_step "Claude Code 설치 중..."

# 공식 설치 스크립트 실행
curl -fsSL https://claude.ai/install.sh | bash

# PATH 설정 확인 및 추가
CLAUDE_PATHS=(
    "$HOME/.claude/bin"
    "$HOME/.local/bin"
)

for claude_path in "${CLAUDE_PATHS[@]}"; do
    if [ -d "$claude_path" ]; then
        if [[ ":$PATH:" != *":$claude_path:"* ]]; then
            export PATH="$claude_path:$PATH"
            
            # .zshrc에 추가 (없으면)
            if [ -f "$HOME/.zshrc" ]; then
                if ! grep -q "$claude_path" "$HOME/.zshrc"; then
                    echo "export PATH=\"$claude_path:\$PATH\"" >> "$HOME/.zshrc"
                    print_info "PATH에 추가됨: $claude_path"
                fi
            fi
            
            # .bashrc에도 추가 (없으면)
            if [ -f "$HOME/.bashrc" ]; then
                if ! grep -q "$claude_path" "$HOME/.bashrc"; then
                    echo "export PATH=\"$claude_path:\$PATH\"" >> "$HOME/.bashrc"
                fi
            fi
        fi
    fi
done

# 설치 확인
sleep 2
if command_exists claude; then
    claude_ver=$(claude --version 2>/dev/null || echo "installed")
    print_success "Claude Code 설치 완료! ($claude_ver)"
else
    print_info "⚠️  새 터미널을 열어야 claude 명령어가 인식됩니다."
fi

# ============================================================
# 완료 메시지
# ============================================================

echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║            설치 완료! 🎉                 ║${NC}"
echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}  📌 중요: 새 터미널 창을 열어주세요!${NC}"
echo ""
echo -e "  그 다음:"
echo -e "${GRAY}     1. claude --version  (설치 확인)${NC}"
echo -e "${GRAY}     2. claude            (시작 & 로그인)${NC}"
echo ""

# 새 터미널에서 PATH 적용을 위해
echo -e "${GRAY}  또는 현재 터미널에서 바로 사용하려면:${NC}"
echo -e "${CYAN}     source ~/.zshrc${NC}"
echo ""