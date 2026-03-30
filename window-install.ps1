<#
.SYNOPSIS
    Claude Code 설치 스크립트 (한글 경로 완벽 지원)
.DESCRIPTION
    npm 전역 경로를 영문으로 변경하여 Claude Code를 설치합니다.
    한글 사용자 이름으로 인한 경로 문제를 완전히 해결합니다.
#>

# UTF-8 인코딩
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# ExecutionPolicy 자동 설정 (PSSecurityException 방지)
# ============================================================
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
$policyChanged = $false

if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "Undefined") {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        $policyChanged = $true
    } catch {
        # 실패해도 설치는 계속 진행 (나중에 .ps1 삭제로 우회)
    }
}

# 출력 함수
function Write-Step { param([string]$Message) Write-Host "`n▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }

function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# PATH 새로고침 (레지스트리에서 최신 값을 다시 읽어 현재 세션에 반영)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# VS Code 터미널 감지
$isVSCode = $false
if ($env:TERM_PROGRAM -eq "vscode" -or $env:VSCODE_PID -or $env:VSCODE_CWD) {
    $isVSCode = $true
}

# PATH에 영구 추가
function Add-ToPathPermanent {
    param([string]$NewPath)
    
    if (-not (Test-Path $NewPath)) { return $false }
    
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentPath -like "*$NewPath*") {
        Write-Info "이미 PATH에 존재: $NewPath"
        return $true
    }
    
    $newPathValue = if ($currentPath) { "$currentPath;$NewPath" } else { $NewPath }
    
    try {
        [Environment]::SetEnvironmentVariable("Path", $newPathValue, "User")
        $env:Path = "$env:Path;$NewPath"
        Write-Info "PATH 추가됨: $NewPath"
        return $true
    } catch {
        Write-Error-Custom "PATH 설정 실패: $_"
        return $false
    }
}

# ============================================================
# 설정
# ============================================================

$NpmGlobalPath = "C:\npm-global"
$ClaudeBinPath = "C:\claude-code\bin"

# ============================================================
# 메인
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 설치 (한글 경로 지원)      ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($isVSCode) {
    Write-Host "  💡 VS Code 터미널 감지됨 - 설치 완료 후 PATH를 자동 적용합니다." -ForegroundColor Cyan
    Write-Host ""
}

# ExecutionPolicy 변경 결과 표시
if ($policyChanged) {
    Write-Host "  ✅ PowerShell 보안 정책 자동 설정 완료 (RemoteSigned)" -ForegroundColor Green
    Write-Host ""
}

# 한글 경로 확인
$isKoreanPath = Test-NonAsciiPath $env:USERPROFILE
if ($isKoreanPath) {
    Write-Host "  ⚠️  한글 사용자 이름 감지: $env:USERNAME" -ForegroundColor Yellow
    Write-Host "     npm 전역 경로를 $NpmGlobalPath 로 설정합니다." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  ℹ️  npm 전역 경로: $NpmGlobalPath" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
# 1. winget 확인 (없으면 직접 다운로드 모드로 전환)
# ============================================================
Write-Step "winget 확인 중..."
$useWinget = Test-Command "winget"
if ($useWinget) {
    Write-Success "winget 확인됨"
} else {
    Write-Info "winget이 없습니다. 직접 다운로드 방식으로 설치합니다."
}

# 직접 다운로드 함수
function Download-File {
    param(
        [string]$Name,
        [string]$Url,
        [string]$OutFile
    )
    Write-Info "$Name 다운로드 중: $Url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($Url, $OutFile)
}

function Install-Exe {
    param(
        [string]$Name,
        [string]$FilePath,
        [string]$Arguments
    )
    Write-Info "$Name 설치 중... (1-3분 소요)"
    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru
    return $proc.ExitCode -eq 0
}

function Install-Msi {
    param(
        [string]$Name,
        [string]$FilePath
    )
    Write-Info "$Name 설치 중... (관리자 권한 필요, UAC 팝업이 뜰 수 있습니다)"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$FilePath`" /qn /norestart" -Verb RunAs -Wait
}

# ============================================================
# 2. Git 설치
# ============================================================
Write-Step "Git 확인 중..."
Update-Path

if (Test-Command "git") {
    $gitVer = git --version 2>$null
    Write-Success "Git 이미 설치됨 ($gitVer)"
} else {
    if ($useWinget) {
        Write-Info "Git 설치 중... (1-2분 소요)"
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    } else {
        Write-Info "Git 직접 다운로드 설치 중..."
        $gitInstaller = "$env:TEMP\Git-installer.exe"
        try {
            Download-File -Name "Git" `
                -Url "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" `
                -OutFile $gitInstaller
            Install-Exe -Name "Git" -FilePath $gitInstaller `
                -Arguments "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`"" | Out-Null
        } catch {
            Write-Error-Custom "Git 다운로드/설치 실패: $_"
        } finally {
            if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue }
        }
    }

    # Git PATH 추가
    if (Test-Path "$env:ProgramFiles\Git\cmd") {
        Add-ToPathPermanent "$env:ProgramFiles\Git\cmd" | Out-Null
    }

    Update-Path

    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Info "Git 설치됨 (새 터미널에서 확인 필요)"
    }
}

# ============================================================
# 3. Node.js 설치
# ============================================================
Write-Step "Node.js 확인 중..."
Update-Path

$nodeExists = $false
try {
    $nodeVer = & cmd.exe /c "node --version" 2>$null
    if ($nodeVer -match "^v\d+") {
        $nodeExists = $true
    }
} catch { }

if ($nodeExists) {
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다 ($nodeVer). 업그레이드 중..."
        if ($useWinget) {
            winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
        } else {
            $nodeInstaller = "$env:TEMP\node-lts-installer.msi"
            try {
                Download-File -Name "Node.js" -Url "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $nodeInstaller
                Install-Msi -Name "Node.js" -FilePath $nodeInstaller | Out-Null
            } catch {
                Write-Error-Custom "Node.js 다운로드/설치 실패: $_"
            } finally {
                if (Test-Path $nodeInstaller) { Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue }
            }
        }
        Update-Path
    }
} else {
    if ($useWinget) {
        Write-Info "Node.js LTS 설치 중... (1-2분 소요)"
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    } else {
        Write-Info "Node.js LTS 직접 다운로드 설치 중..."
        $nodeInstaller = "$env:TEMP\node-lts-installer.msi"
        try {
            Download-File -Name "Node.js" -Url "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $nodeInstaller
            Install-Msi -Name "Node.js" -FilePath $nodeInstaller | Out-Null
        } catch {
            Write-Error-Custom "Node.js 다운로드/설치 실패: $_"
        } finally {
            if (Test-Path $nodeInstaller) { Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue }
        }
    }

    if (Test-Path "$env:ProgramFiles\nodejs") {
        Add-ToPathPermanent "$env:ProgramFiles\nodejs" | Out-Null
    }

    Update-Path

    # 다시 확인
    try {
        $nodeVer = & cmd.exe /c "node --version" 2>$null
        if ($nodeVer) {
            Write-Success "Node.js 설치 완료! ($nodeVer)"
        } else {
            Write-Error-Custom "Node.js 설치 실패"
            Read-Host "Enter를 눌러 종료"
            exit 1
        }
    } catch {
        Write-Error-Custom "Node.js 확인 실패"
        Read-Host "Enter를 눌러 종료"
        exit 1
    }
}

# npm 확인
$npmExists = $false
try {
    $npmVer = & cmd.exe /c "npm --version" 2>$null
    if ($npmVer -match "^\d+") {
        $npmExists = $true
        Write-Info "npm 버전: $npmVer"
    }
} catch { }

if (-not $npmExists) {
    Write-Error-Custom "npm을 찾을 수 없습니다."
    Write-Info "Node.js를 다시 설치해주세요."
    Read-Host "Enter를 눌러 종료"
    exit 1
}

# ============================================================
# 4. npm 전역 경로 설정 (한글 경로 우회)
# ============================================================
Write-Step "npm 전역 경로 설정 중..."

# 디렉토리 생성
if (-not (Test-Path $NpmGlobalPath)) {
    New-Item -ItemType Directory -Path $NpmGlobalPath -Force | Out-Null
    Write-Info "디렉토리 생성: $NpmGlobalPath"
}

# 현재 npm prefix 확인
$currentPrefix = & cmd.exe /c "npm config get prefix" 2>$null
$currentPrefix = $currentPrefix.Trim()
Write-Info "현재 npm prefix: $currentPrefix"

# npm prefix 설정
if ($currentPrefix -ne $NpmGlobalPath) {
    Write-Info "npm prefix 변경 중..."
    & cmd.exe /c "npm config set prefix $NpmGlobalPath"
    Write-Info "npm prefix 변경됨: $NpmGlobalPath"
}

# PATH에 추가
Add-ToPathPermanent $NpmGlobalPath | Out-Null

Write-Success "npm 전역 경로 설정 완료"

# ============================================================
# 5. Claude Code 설치 (npm)
# ============================================================
Write-Step "Claude Code 설치 중 (npm)..."
Write-Info "npm install -g @anthropic-ai/claude-code"
Write-Info "설치에 1-3분 정도 소요됩니다..."
Write-Host ""

# cmd.exe를 통해 npm 실행 (실행 정책 우회)
$installProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install -g @anthropic-ai/claude-code" -Wait -PassThru -NoNewWindow

if ($installProcess.ExitCode -eq 0) {
    Write-Success "Claude Code npm 설치 완료!"
} else {
    Write-Info "npm 설치 종료 코드: $($installProcess.ExitCode)"
    Write-Info "계속 진행합니다..."
}

# ============================================================
# 6. .ps1 파일 삭제 (실행 정책 문제 해결)
# ============================================================
Write-Step ".ps1 파일 정리 중 (실행 정책 문제 방지)..."

$ps1Files = Get-ChildItem -Path $NpmGlobalPath -Filter "*.ps1" -ErrorAction SilentlyContinue
if ($ps1Files) {
    foreach ($file in $ps1Files) {
        Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        Write-Info "삭제됨: $($file.Name)"
    }
    Write-Success ".ps1 파일 정리 완료"
} else {
    Write-Info ".ps1 파일 없음"
}

# 설치 확인
Write-Step "Claude Code 설치 확인 중..."

$claudeCmd = "$NpmGlobalPath\claude.cmd"

if (Test-Path $claudeCmd) {
    Write-Success "발견: $claudeCmd"
} else {
    Write-Info "$NpmGlobalPath 내용:"
    Get-ChildItem $NpmGlobalPath -ErrorAction SilentlyContinue | ForEach-Object { Write-Info "  $($_.Name)" }
    
    # node_modules 확인
    $nodeModulesPath = "$NpmGlobalPath\node_modules\@anthropic-ai\claude-code"
    if (Test-Path $nodeModulesPath) {
        Write-Info "패키지는 설치됨: $nodeModulesPath"
    } else {
        Write-Error-Custom "Claude Code 패키지를 찾을 수 없습니다."
    }
}

# ============================================================
# 7. dsclaude 래퍼 생성
# ============================================================
Write-Step "dsclaude 래퍼 생성 중..."

if (-not (Test-Path $ClaudeBinPath)) {
    New-Item -ItemType Directory -Path $ClaudeBinPath -Force | Out-Null
}

# dsclaude.cmd 생성
$dsclaudeContent = @"
@echo off
chcp 65001 >nul 2>&1
"$NpmGlobalPath\claude.cmd" --dangerously-skip-permissions %*
"@

$dsclaudePath = "$ClaudeBinPath\dsclaude.cmd"
Set-Content -Path $dsclaudePath -Value $dsclaudeContent -Encoding ASCII -Force

if (Test-Path $dsclaudePath) {
    Write-Success "dsclaude.cmd 생성됨: $dsclaudePath"
    Add-ToPathPermanent $ClaudeBinPath | Out-Null
} else {
    Write-Error-Custom "dsclaude.cmd 생성 실패"
}

# ============================================================
# 8. 최종 PATH 설정 및 확인
# ============================================================
Write-Step "최종 PATH 설정 중..."

Add-ToPathPermanent $NpmGlobalPath | Out-Null
Add-ToPathPermanent $ClaudeBinPath | Out-Null

Update-Path

# PATH 검증
Write-Step "설치 검증 중..."

$verifyOk = $true

# npm 전역 경로 확인
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$NpmGlobalPath*") {
    Write-Success "npm 전역 경로 PATH 등록됨"
} else {
    Write-Error-Custom "npm 전역 경로 PATH 등록 실패"
    $verifyOk = $false
}

# claude 명령어 테스트
Write-Info "claude 명령어 테스트..."
try {
    $claudeVersion = & cmd.exe /c "claude --version" 2>$null
    if ($claudeVersion) {
        Write-Success "claude 명령어 작동: $claudeVersion"
    } else {
        Write-Info "claude 응답 없음 (새 터미널에서 확인 필요)"
    }
} catch {
    Write-Info "claude 테스트 실패 (새 터미널에서 확인 필요)"
}

# ============================================================
# 완료
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($isVSCode) {
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  ⚠️  VS Code 터미널에서 설치하셨습니다     ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  VS Code는 실행 시점의 PATH를 캐시하므로," -ForegroundColor Yellow
    Write-Host "  설치 후에도 'claude'를 못 찾을 수 있습니다." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  아래에서 PATH를 자동 적용했지만, 안 될 경우:" -ForegroundColor White
    Write-Host "     → VS Code 완전 종료(모든 창) 후 재실행" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "  📌 중요: 새 PowerShell/터미널 창을 열어주세요!" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  설치된 명령어:" -ForegroundColor White
Write-Host "     claude      - Claude Code 실행" -ForegroundColor Gray
Write-Host "     dsclaude    - 권한 스킵 모드" -ForegroundColor Gray
Write-Host ""
Write-Host "  설치 경로:" -ForegroundColor White
Write-Host "     npm 전역: $NpmGlobalPath" -ForegroundColor Gray
Write-Host "     dsclaude: $ClaudeBinPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  시작하기:" -ForegroundColor White
if ($isVSCode) {
    Write-Host "     1. VS Code 재시작 (또는 위 PATH 명령어 실행)" -ForegroundColor Gray
} else {
    Write-Host "     1. 새 터미널 열기" -ForegroundColor Gray
}
Write-Host "     2. claude --version" -ForegroundColor Gray
Write-Host "     3. claude" -ForegroundColor Gray
Write-Host ""

# ExecutionPolicy 최종 확인 (자동 설정 실패한 경우만 안내)
$finalPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($finalPolicy -eq "Restricted" -or $finalPolicy -eq "Undefined") {
    Write-Host "  ⚠️  보안 정책 자동 설정 실패 - claude 실행 시 오류 발생 가능" -ForegroundColor Yellow
    Write-Host "     해결: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Gray
    Write-Host "     또는: cmd.exe에서 claude 실행" -ForegroundColor Gray
    Write-Host ""
}

if (-not $verifyOk) {
    Write-Host "  ⚠️  PATH 등록 실패 시 수동 추가:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  # PowerShell에서 실행:" -ForegroundColor Cyan
    Write-Host "  `$p = [Environment]::GetEnvironmentVariable('Path', 'User')" -ForegroundColor White
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"`$p;$NpmGlobalPath;$ClaudeBinPath`", 'User')" -ForegroundColor White
    Write-Host ""
}

if ($isVSCode) {
    # VS Code에서는 새 PowerShell 창을 열지 않음 (혼란 방지)
    # 대신 현재 세션의 PATH를 즉시 갱신
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Success "현재 터미널 세션의 PATH가 갱신되었습니다."
    Write-Host ""
    Write-Host "  지금 바로 claude 를 실행해보세요!" -ForegroundColor Green
    Write-Host "  (안 되면 VS Code를 완전히 재시작하세요)" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  3초 후 새 PowerShell이 열립니다..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3

    # 자동으로 새 PowerShell 열기
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Clear-Host; Write-Host '✅ Claude Code 준비 완료!' -ForegroundColor Green; Write-Host ''; Write-Host '아래 명령어를 입력하세요:' -ForegroundColor White; Write-Host ''; Write-Host '  claude       - Claude Code 실행' -ForegroundColor Cyan; Write-Host '  dsclaude     - 권한 스킵 모드' -ForegroundColor Cyan; Write-Host ''"

    Write-Host ""
    Write-Host "  새 PowerShell 창에서 claude 를 입력하세요!" -ForegroundColor Green
    Write-Host ""
}
