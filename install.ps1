<#
.SYNOPSIS
    Claude Code 설치 스크립트 (Windows PowerShell)
.DESCRIPTION
    이 스크립트는 Windows에서 Claude Code를 자동으로 설치합니다.
    - 시스템 요구사항 확인
    - 필수 도구 설치 (Git for Windows)
    - Claude Code 설치
    - 설치 확인
.NOTES
    PowerShell 5.1 이상 또는 PowerShell 7.x에서 실행하세요.
    관리자 권한이 필요할 수 있습니다.
#>

# ============================================================
# 🎨 콘솔 출력 함수들
# ============================================================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $Message" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "▶ $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Gray
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor DarkYellow
}

# ============================================================
# 🔍 시스템 체크 함수들
# ============================================================

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsVersion {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return @{
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        Caption = $os.Caption
    }
}

function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-WingetAvailable {
    return Test-CommandExists "winget"
}

function Test-GitInstalled {
    return Test-CommandExists "git"
}

function Test-NodeInstalled {
    return Test-CommandExists "node"
}

function Get-NodeVersion {
    if (Test-NodeInstalled) {
        $version = node --version 2>$null
        return $version
    }
    return $null
}

# ============================================================
# 📦 설치 함수들
# ============================================================

function Install-GitForWindows {
    Write-Step "Git for Windows 설치 중..."
    
    if (Test-WingetAvailable) {
        Write-Info "winget을 사용하여 Git 설치..."
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        
        # PATH 새로고침
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Test-GitInstalled) {
            Write-Success "Git 설치 완료!"
            return $true
        }
    }
    else {
        Write-Warning-Custom "winget이 설치되어 있지 않습니다."
        Write-Info "Git for Windows를 수동으로 설치해주세요: https://git-scm.com/download/win"
        return $false
    }
    
    return $false
}

function Install-NodeJS {
    Write-Step "Node.js 설치 중..."
    
    if (Test-WingetAvailable) {
        Write-Info "winget을 사용하여 Node.js LTS 설치..."
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
        
        # PATH 새로고침
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Test-NodeInstalled) {
            Write-Success "Node.js 설치 완료!"
            return $true
        }
    }
    else {
        Write-Warning-Custom "winget이 설치되어 있지 않습니다."
        Write-Info "Node.js를 수동으로 설치해주세요: https://nodejs.org/"
        return $false
    }
    
    return $false
}

function Install-ClaudeCodeNative {
    Write-Step "Claude Code 네이티브 설치 중 (권장 방식)..."
    
    try {
        # 공식 설치 스크립트 실행
        $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
        Invoke-Expression $installScript
        
        Write-Success "Claude Code 네이티브 설치 완료!"
        return $true
    }
    catch {
        Write-Error-Custom "네이티브 설치 실패: $_"
        return $false
    }
}

function Install-ClaudeCodeNpm {
    Write-Step "Claude Code npm 설치 중 (대체 방식)..."
    
    if (-not (Test-NodeInstalled)) {
        Write-Error-Custom "Node.js가 설치되어 있지 않습니다."
        return $false
    }
    
    try {
        npm install -g @anthropic-ai/claude-code
        Write-Success "Claude Code npm 설치 완료!"
        return $true
    }
    catch {
        Write-Error-Custom "npm 설치 실패: $_"
        return $false
    }
}

# ============================================================
# 🎯 메인 설치 로직
# ============================================================

function Show-Menu {
    Write-Host ""
    Write-Host "설치 방법을 선택하세요:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] 네이티브 설치 (권장)" -ForegroundColor White
    Write-Host "      - Node.js 불필요" -ForegroundColor Gray
    Write-Host "      - 가장 빠르고 안정적" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] npm 글로벌 설치" -ForegroundColor White
    Write-Host "      - Node.js 18+ 필요" -ForegroundColor Gray
    Write-Host "      - 개발 환경과 통합" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [3] WSL 설치 가이드 보기" -ForegroundColor White
    Write-Host "      - Linux 환경 필요" -ForegroundColor Gray
    Write-Host "      - 가장 완전한 기능" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [Q] 종료" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "선택"
    return $choice
}

function Show-WSLGuide {
    Write-Header "WSL 설치 가이드"
    
    Write-Host @"
WSL을 통한 Claude Code 설치 단계:

1️⃣  WSL2 설치 (관리자 PowerShell에서 실행)
    wsl --install

2️⃣  컴퓨터 재시작

3️⃣  Ubuntu 터미널 열기

4️⃣  Node.js 설치 (Ubuntu 터미널에서)
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs

5️⃣  npm 글로벌 디렉토리 설정
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    echo 'export PATH=~/.npm-global/bin:`$PATH' >> ~/.bashrc
    source ~/.bashrc

6️⃣  Claude Code 설치
    npm install -g @anthropic-ai/claude-code

7️⃣  설치 확인
    claude --version
"@ -ForegroundColor White

    Write-Host ""
    Read-Host "Enter 키를 눌러 계속..."
}

function Start-Installation {
    Clear-Host
    
    # 헤더 출력
    Write-Host ""
    Write-Host "   ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗" -ForegroundColor Magenta
    Write-Host "  ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝" -ForegroundColor Magenta
    Write-Host "  ██║     ██║     ███████║██║   ██║██║  ██║█████╗  " -ForegroundColor Magenta
    Write-Host "  ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝  " -ForegroundColor Magenta
    Write-Host "  ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗" -ForegroundColor Magenta
    Write-Host "   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝" -ForegroundColor Magenta
    Write-Host "   ██████╗ ██████╗ ██████╗ ███████╗                " -ForegroundColor Cyan
    Write-Host "  ██╔════╝██╔═══██╗██╔══██╗██╔════╝                " -ForegroundColor Cyan
    Write-Host "  ██║     ██║   ██║██║  ██║█████╗                  " -ForegroundColor Cyan
    Write-Host "  ██║     ██║   ██║██║  ██║██╔══╝                  " -ForegroundColor Cyan
    Write-Host "  ╚██████╗╚██████╔╝██████╔╝███████╗                " -ForegroundColor Cyan
    Write-Host "   ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝                " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "           Windows 설치 스크립트 v1.0" -ForegroundColor DarkGray
    Write-Host ""
    
    # 시스템 정보 표시
    Write-Header "시스템 정보 확인"
    
    $winInfo = Get-WindowsVersion
    Write-Info "OS: $($winInfo.Caption)"
    Write-Info "버전: $($winInfo.Version) (빌드 $($winInfo.BuildNumber))"
    Write-Info "PowerShell: $($PSVersionTable.PSVersion)"
    
    # 관리자 권한 체크
    if (Test-AdminPrivileges) {
        Write-Success "관리자 권한: 있음"
    }
    else {
        Write-Warning-Custom "관리자 권한: 없음 (일부 설치에 제한이 있을 수 있습니다)"
    }
    
    # 필수 도구 체크
    Write-Host ""
    Write-Step "필수 도구 확인 중..."
    
    # Git 체크
    if (Test-GitInstalled) {
        $gitVersion = git --version 2>$null
        Write-Success "Git: 설치됨 ($gitVersion)"
    }
    else {
        Write-Warning-Custom "Git: 설치되지 않음"
    }
    
    # Node.js 체크
    if (Test-NodeInstalled) {
        $nodeVersion = Get-NodeVersion
        Write-Success "Node.js: 설치됨 ($nodeVersion)"
    }
    else {
        Write-Warning-Custom "Node.js: 설치되지 않음"
    }
    
    # winget 체크
    if (Test-WingetAvailable) {
        Write-Success "winget: 사용 가능"
    }
    else {
        Write-Warning-Custom "winget: 사용 불가"
    }
    
    # 메뉴 표시 및 선택 처리
    while ($true) {
        $choice = Show-Menu
        
        switch ($choice.ToUpper()) {
            "1" {
                Write-Header "네이티브 설치 시작"
                
                # Git 설치 확인
                if (-not (Test-GitInstalled)) {
                    Write-Warning-Custom "Git이 설치되어 있지 않습니다. Git Bash가 Claude Code 실행에 권장됩니다."
                    $installGit = Read-Host "Git for Windows를 설치하시겠습니까? (Y/N)"
                    if ($installGit -eq "Y" -or $installGit -eq "y") {
                        Install-GitForWindows
                    }
                }
                
                # Claude Code 네이티브 설치
                Write-Host ""
                Write-Step "Claude Code 설치를 시작합니다..."
                Write-Host ""
                
                try {
                    # 직접 공식 설치 스크립트 실행
                    irm https://claude.ai/install.ps1 | iex
                }
                catch {
                    Write-Error-Custom "설치 중 오류 발생: $_"
                }
                
                break
            }
            "2" {
                Write-Header "npm 글로벌 설치 시작"
                
                # Node.js 설치 확인
                if (-not (Test-NodeInstalled)) {
                    Write-Warning-Custom "Node.js가 설치되어 있지 않습니다."
                    $installNode = Read-Host "Node.js LTS를 설치하시겠습니까? (Y/N)"
                    if ($installNode -eq "Y" -or $installNode -eq "y") {
                        $nodeInstalled = Install-NodeJS
                        if (-not $nodeInstalled) {
                            Write-Error-Custom "Node.js 설치에 실패했습니다."
                            continue
                        }
                        
                        Write-Warning-Custom "Node.js 설치 후 새 터미널을 열어야 합니다."
                        Write-Info "새 PowerShell 창을 열고 다시 이 스크립트를 실행해주세요."
                        break
                    }
                    else {
                        continue
                    }
                }
                
                # Node.js 버전 체크
                $nodeVersion = Get-NodeVersion
                $versionNum = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
                
                if ($versionNum -lt 18) {
                    Write-Error-Custom "Node.js 18 이상이 필요합니다. 현재 버전: $nodeVersion"
                    $updateNode = Read-Host "Node.js를 업데이트하시겠습니까? (Y/N)"
                    if ($updateNode -eq "Y" -or $updateNode -eq "y") {
                        Install-NodeJS
                        Write-Warning-Custom "새 PowerShell 창을 열고 다시 시도해주세요."
                    }
                    continue
                }
                
                # Claude Code 설치
                Write-Host ""
                Write-Step "npm을 통해 Claude Code 설치 중..."
                Write-Host ""
                
                npm install -g @anthropic-ai/claude-code
                
                break
            }
            "3" {
                Show-WSLGuide
            }
            "Q" {
                Write-Host ""
                Write-Info "설치를 취소했습니다."
                return
            }
            default {
                Write-Warning-Custom "잘못된 선택입니다. 다시 선택해주세요."
            }
        }
    }
    
    # 설치 후 안내
    Write-Host ""
    Write-Header "설치 완료!"
    
    Write-Host @"
📌 다음 단계:

1️⃣  새 터미널(PowerShell 또는 Git Bash)을 열어주세요

2️⃣  설치 확인
    claude --version

3️⃣  인증 설정
    claude
    (브라우저에서 로그인 진행)

4️⃣  프로젝트 디렉토리에서 사용
    cd your-project
    claude

📚 문서: https://docs.claude.com/en/docs/claude-code
💬 Discord: Claude Developers 커뮤니티

"@ -ForegroundColor White

    Write-Host "Happy Coding with Claude! 🚀" -ForegroundColor Magenta
    Write-Host ""
}

# ============================================================
# 🚀 스크립트 실행
# ============================================================

Start-Installation