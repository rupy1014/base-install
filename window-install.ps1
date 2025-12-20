<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치하고 PATH 설정까지 완료합니다.
    
    ⚠️ 한글 사용자 이름 디렉토리 문제 해결 버전 v3
    ⚠️ PATH 설정 강화 (setx 직접 사용)
#>

# UTF-8 인코딩 설정
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 콘솔 출력 함수
function Write-Step { param([string]$Message) Write-Host "▶ $Message" -ForegroundColor Yellow }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error-Custom { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "   $Message" -ForegroundColor Gray }
function Write-Warning-Custom { param([string]$Message) Write-Host "⚠️  $Message" -ForegroundColor DarkYellow }
function Write-Debug-Custom { param([string]$Message) Write-Host "   [DEBUG] $Message" -ForegroundColor DarkGray }

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# 경로에 비-ASCII 문자(한글 등) 포함 여부 확인
function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# 8.3 짧은 경로로 변환
function Get-ShortPath {
    param([string]$LongPath)
    
    if (-not (Test-Path $LongPath)) {
        return $LongPath
    }
    
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $LongPath -PathType Container) {
            return $fso.GetFolder($LongPath).ShortPath
        } else {
            return $fso.GetFile($LongPath).ShortPath
        }
    } catch {
        return $LongPath
    }
}

# PATH 새로고침
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# PATH에 경로 추가 (setx 직접 사용 - 가장 확실한 방법)
function Add-ToPathWithSetx {
    param([string]$NewPath)
    
    Write-Debug-Custom "추가할 경로: $NewPath"
    
    if (-not (Test-Path $NewPath)) { 
        Write-Debug-Custom "경로가 존재하지 않음"
        return $false 
    }
    
    # 현재 User PATH 가져오기
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Debug-Custom "현재 User PATH 길이: $($currentPath.Length)"
    
    # 이미 존재하는지 확인
    if ($currentPath -and $currentPath -like "*$NewPath*") {
        Write-Info "이미 PATH에 존재: $NewPath"
        return $true
    }
    
    # 새 PATH 값 생성
    $newPathValue = if ($currentPath) { "$currentPath;$NewPath" } else { $NewPath }
    
    Write-Debug-Custom "새 PATH 길이: $($newPathValue.Length)"
    
    # setx는 1024자 제한이 있음
    if ($newPathValue.Length -gt 1024) {
        Write-Warning-Custom "PATH가 1024자를 초과합니다. 레지스트리 직접 수정 시도..."
        
        try {
            Set-ItemProperty -Path "HKCU:\Environment" -Name Path -Value $newPathValue -Type ExpandString
            Write-Info "레지스트리로 PATH 설정됨"
            
            # 현재 세션에도 적용
            $env:Path = "$env:Path;$NewPath"
            return $true
        } catch {
            Write-Error-Custom "레지스트리 설정 실패: $_"
            return $false
        }
    }
    
    # setx로 PATH 설정
    Write-Debug-Custom "setx 실행 중..."
    
    try {
        $setxOutput = & setx PATH "$newPathValue" 2>&1
        Write-Debug-Custom "setx 결과: $setxOutput"
        
        if ($LASTEXITCODE -eq 0 -or $setxOutput -match "SUCCESS|성공") {
            Write-Info "setx로 PATH 설정됨: $NewPath"
            
            # 현재 세션에도 적용
            $env:Path = "$env:Path;$NewPath"
            return $true
        } else {
            Write-Warning-Custom "setx 실패, 레지스트리 직접 수정 시도..."
            
            Set-ItemProperty -Path "HKCU:\Environment" -Name Path -Value $newPathValue -Type ExpandString
            $env:Path = "$env:Path;$NewPath"
            return $true
        }
    } catch {
        Write-Error-Custom "PATH 설정 실패: $_"
        return $false
    }
}

# 안전한 bin 디렉토리
function Get-SafeBinPath {
    $globalBin = "C:\claude-code\bin"
    
    if (-not (Test-Path $globalBin)) {
        New-Item -ItemType Directory -Path $globalBin -Force | Out-Null
        Write-Info "디렉토리 생성: $globalBin"
    }
    
    return $globalBin
}

# Claude Code 실행 파일 찾기
function Find-ClaudeExecutable {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\claude-code\claude.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\claude.exe",
        "$env:USERPROFILE\.claude\bin\claude.exe",
        "$env:USERPROFILE\.local\bin\claude.exe",
        "C:\Program Files\claude-code\claude.exe",
        "C:\claude-code\claude.exe"
    )
    
    foreach ($path in $possiblePaths) {
        Write-Debug-Custom "검색 중: $path"
        if (Test-Path $path) {
            return $path
        }
    }
    
    # LOCALAPPDATA 하위 검색
    $searchPath = "$env:LOCALAPPDATA\Programs"
    if (Test-Path $searchPath) {
        Write-Debug-Custom "하위 폴더 검색: $searchPath"
        $found = Get-ChildItem -Path $searchPath -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }
    
    return $null
}

# Claude 래퍼 스크립트 생성
function Install-ClaudeWrapper {
    param([string]$ClaudeExePath)
    
    Write-Step "claude 래퍼 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    if (-not $ClaudeExePath -or -not (Test-Path $ClaudeExePath)) {
        Write-Error-Custom "Claude 실행 파일 없음: $ClaudeExePath"
        return $false
    }
    
    # Short Path 변환
    $safeClaudePath = $ClaudeExePath
    if (Test-NonAsciiPath $ClaudeExePath) {
        $shortPath = Get-ShortPath $ClaudeExePath
        if ($shortPath -and -not (Test-NonAsciiPath $shortPath)) {
            $safeClaudePath = $shortPath
            Write-Info "Short Path 변환: $shortPath"
        } else {
            Write-Warning-Custom "Short Path 변환 실패"
        }
    }
    
    # claude.cmd 생성
    $wrapperContent = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" %*
"@
    
    $wrapperPath = "$binPath\claude.cmd"
    Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding ASCII -Force
    
    Write-Debug-Custom "claude.cmd 내용:"
    Write-Debug-Custom $wrapperContent
    
    if (Test-Path $wrapperPath) {
        Write-Success "claude.cmd 생성됨: $wrapperPath"
        return $true
    }
    return $false
}

# dsclaude 래퍼 생성
function Install-DsClaude {
    param([string]$ClaudeExePath)
    
    Write-Step "dsclaude 래퍼 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    $safeClaudePath = $ClaudeExePath
    if ($ClaudeExePath -and (Test-NonAsciiPath $ClaudeExePath)) {
        $shortPath = Get-ShortPath $ClaudeExePath
        if ($shortPath -and -not (Test-NonAsciiPath $shortPath)) {
            $safeClaudePath = $shortPath
        }
    }
    
    $wrapperContent = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" --dangerously-skip-permissions %*
"@
    
    $wrapperPath = "$binPath\dsclaude.cmd"
    Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding ASCII -Force
    
    if (Test-Path $wrapperPath) {
        Write-Success "dsclaude.cmd 생성됨: $wrapperPath"
        return $true
    }
    return $false
}

# ============================================================
# 메인 설치
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 설치 스크립트 v3           ║" -ForegroundColor Cyan
Write-Host "  ║   (한글 경로 + PATH 강화 버전)           ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$isKoreanPath = Test-NonAsciiPath $env:USERPROFILE
if ($isKoreanPath) {
    Write-Warning-Custom "한글 사용자 이름 감지: $env:USERNAME"
    Write-Info "래퍼를 C:\claude-code\bin에 생성합니다."
    Write-Host ""
}

# 1. winget 확인
Write-Step "winget 확인 중..."
if (-not (Test-Command "winget")) {
    Write-Error-Custom "winget이 없습니다. Windows 10 1709+ 또는 Windows 11 필요"
    Read-Host "Enter 키를 눌러 종료"
    exit 1
}
Write-Success "winget 확인됨"

# 2. Git 설치
Write-Host ""
Write-Step "Git 확인 중..."
Update-Path
if (Test-Command "git") {
    Write-Success "Git 이미 설치됨"
} else {
    Write-Info "Git 설치 중..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    Start-Sleep -Seconds 2
    Update-Path
    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Warning-Custom "Git 설치됨 (새 터미널에서 확인)"
    }
}

# 3. Node.js 설치
Write-Host ""
Write-Step "Node.js 확인 중..."
Update-Path
if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    Write-Success "Node.js 이미 설치됨 ($nodeVer)"
} else {
    Write-Info "Node.js 설치 중..."
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>$null
    Start-Sleep -Seconds 2
    Update-Path
    if (Test-Command "node") {
        Write-Success "Node.js 설치 완료!"
    } else {
        Write-Warning-Custom "Node.js 설치됨 (새 터미널에서 확인)"
    }
}

# 4. Claude Code 설치
Write-Host ""
Write-Step "Claude Code 설치 중..."

$claudeExePath = $null

try {
    Write-Info "공식 설치 스크립트 실행..."
    $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $installScript
    
    Start-Sleep -Seconds 3
    
    $claudeExePath = Find-ClaudeExecutable
    
    if ($claudeExePath) {
        Write-Success "Claude Code 발견: $claudeExePath"
    } else {
        Write-Error-Custom "Claude Code를 찾을 수 없습니다."
    }
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
}

# 5. 래퍼 스크립트 생성
Write-Host ""
if ($claudeExePath) {
    Install-ClaudeWrapper -ClaudeExePath $claudeExePath
    Install-DsClaude -ClaudeExePath $claudeExePath
} else {
    Write-Warning-Custom "Claude를 찾지 못해 래퍼 생성 불가"
}

# 6. PATH 설정 (핵심!)
Write-Host ""
Write-Step "PATH 설정 중..."

$safeBin = Get-SafeBinPath

# 파일 존재 확인
Write-Info "파일 확인:"
Write-Info "  claude.cmd: $(Test-Path "$safeBin\claude.cmd")"
Write-Info "  dsclaude.cmd: $(Test-Path "$safeBin\dsclaude.cmd")"

# PATH 추가
$pathResult = Add-ToPathWithSetx -NewPath $safeBin

if ($pathResult) {
    Write-Success "PATH 설정 완료"
} else {
    Write-Error-Custom "PATH 자동 설정 실패"
}

# 7. PATH 검증
Write-Host ""
Write-Step "PATH 검증 중..."

# 레지스트리에서 확인
$regPath = (Get-ItemProperty -Path "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
$pathInRegistry = $regPath -like "*$safeBin*"

Write-Info "레지스트리 PATH에 포함: $pathInRegistry"
Write-Info "현재 세션 PATH에 포함: $($env:Path -like "*$safeBin*")"

if (-not $pathInRegistry) {
    Write-Host ""
    Write-Warning-Custom "PATH 자동 등록이 실패했습니다!"
    Write-Host ""
    Write-Host "  ▼ 수동으로 PATH를 추가하세요 ▼" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  방법 1: PowerShell에서 실행" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host '  $oldPath = [Environment]::GetEnvironmentVariable("Path", "User")' -ForegroundColor White
    Write-Host "  [Environment]::SetEnvironmentVariable(`"Path`", `"`$oldPath;$safeBin`", `"User`")" -ForegroundColor White
    Write-Host ""
    Write-Host "  방법 2: 시스템 설정에서 추가" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  1. Win + R → sysdm.cpl → Enter" -ForegroundColor White
    Write-Host "  2. [고급] 탭 → [환경 변수] 버튼" -ForegroundColor White
    Write-Host "  3. 사용자 변수에서 'Path' 선택 → [편집]" -ForegroundColor White
    Write-Host "  4. [새로 만들기] → $safeBin 입력" -ForegroundColor White
    Write-Host "  5. [확인] 클릭" -ForegroundColor White
    Write-Host ""
}

# ============================================================
# 완료
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📌 반드시 새 터미널을 열어주세요!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  명령어:" -ForegroundColor White
Write-Host "     claude      - Claude Code 실행" -ForegroundColor Gray
Write-Host "     dsclaude    - 권한 스킵 모드" -ForegroundColor Gray
Write-Host ""
Write-Host "  설치 위치:" -ForegroundColor White
Write-Host "     래퍼: $safeBin" -ForegroundColor Gray
if ($claudeExePath) {
    Write-Host "     실제: $claudeExePath" -ForegroundColor Gray
}
Write-Host ""

# 직접 실행 테스트 제안
Write-Host "  💡 지금 바로 테스트하려면:" -ForegroundColor Cyan
Write-Host "     & '$safeBin\claude.cmd' --version" -ForegroundColor White
Write-Host ""

$openNew = Read-Host "새 PowerShell을 열까요? (Y/N)"
if ($openNew -eq "Y" -or $openNew -eq "y") {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$safeBin\claude.cmd' --version; Write-Host ''; Write-Host '사용: claude, dsclaude' -ForegroundColor Cyan"
}