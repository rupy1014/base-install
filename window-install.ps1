<#
.SYNOPSIS
    Claude Code 원클릭 설치 스크립트 (Windows)
.DESCRIPTION
    Git, Node.js, Claude Code를 자동으로 설치하고 PATH 설정까지 완료합니다.
    dsclaude 명령어도 함께 설치됩니다.
    
    ⚠️ 한글 사용자 이름 디렉토리 문제 해결 버전
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

# 명령어 존재 확인
function Test-Command { param([string]$Command) return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# 경로에 비-ASCII 문자(한글 등) 포함 여부 확인
function Test-NonAsciiPath {
    param([string]$Path)
    return $Path -match '[^\x00-\x7F]'
}

# 8.3 짧은 경로로 변환 (한글 경로 문제 해결)
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

# PATH 새로고침 (시스템 + 사용자)
function Update-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# 환경 변수 변경 브로드캐스트
function Send-EnvironmentChangeMessage {
    try {
        $signature = @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        Add-Type -MemberDefinition $signature -Name "Win32BroadcastEnv" -Namespace "PInvoke" -ErrorAction SilentlyContinue | Out-Null
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1a
        $result = [UIntPtr]::Zero
        [PInvoke.Win32BroadcastEnv]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
    } catch { }
}

# PATH에 경로 추가 (레지스트리 직접 수정)
function Add-ToPathPermanent {
    param([string]$NewPath)
    
    if (-not (Test-Path $NewPath)) { 
        return $false 
    }
    
    # 한글 경로면 Short Path로 변환
    $safePath = $NewPath
    if (Test-NonAsciiPath $NewPath) {
        $shortPath = Get-ShortPath $NewPath
        if (-not (Test-NonAsciiPath $shortPath)) {
            $safePath = $shortPath
            Write-Info "경로 변환: $NewPath → $safePath"
        }
    }
    
    # 현재 User PATH 가져오기
    $regPath = "HKCU:\Environment"
    $currentPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction SilentlyContinue).Path
    
    if (-not $currentPath) {
        $currentPath = ""
    }
    
    # 이미 존재하는지 확인
    $pathList = $currentPath -split ';' | Where-Object { $_ -ne '' }
    foreach ($p in $pathList) {
        if ($p.TrimEnd('\') -eq $safePath.TrimEnd('\')) {
            Write-Info "이미 PATH에 존재: $safePath"
            # 현재 세션에도 적용
            if ($env:Path -notlike "*$safePath*") {
                $env:Path = "$env:Path;$safePath"
            }
            return $true
        }
    }
    
    # PATH에 추가
    $newPathValue = if ($currentPath) { "$currentPath;$safePath" } else { $safePath }
    
    try {
        # 레지스트리에 직접 설정
        Set-ItemProperty -Path $regPath -Name Path -Value $newPathValue -Type ExpandString -ErrorAction Stop
        Write-Info "PATH 추가됨 (레지스트리): $safePath"
        
        # .NET으로도 설정 (백업)
        [System.Environment]::SetEnvironmentVariable("Path", $newPathValue, "User")
        
        # 현재 세션에도 적용
        if ($env:Path -notlike "*$safePath*") {
            $env:Path = "$env:Path;$safePath"
        }
        
        # 브로드캐스트
        Send-EnvironmentChangeMessage
        
        return $true
    } catch {
        Write-Error-Custom "PATH 설정 실패: $_"
        return $false
    }
}

# 안전한 bin 디렉토리 (항상 영문 경로 사용)
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
        if (Test-Path $path) {
            return $path
        }
    }
    
    # where.exe로 검색
    try {
        $whereClaude = where.exe claude.exe 2>$null | Select-Object -First 1
        if ($whereClaude -and (Test-Path $whereClaude)) {
            return $whereClaude
        }
    } catch { }
    
    # 추가 검색: LOCALAPPDATA 하위 폴더들
    $searchPaths = @(
        "$env:LOCALAPPDATA\Programs",
        "$env:LOCALAPPDATA"
    )
    
    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $found = Get-ChildItem -Path $searchPath -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                return $found.FullName
            }
        }
    }
    
    return $null
}

# Claude 래퍼 스크립트 생성 (핵심!)
function Install-ClaudeWrapper {
    param([string]$ClaudeExePath)
    
    Write-Step "claude 명령어 래퍼 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    if (-not $ClaudeExePath -or -not (Test-Path $ClaudeExePath)) {
        Write-Error-Custom "Claude 실행 파일을 찾을 수 없습니다."
        return $false
    }
    
    # Short Path 변환 (한글 경로 문제 해결)
    $safeClaudePath = $ClaudeExePath
    if (Test-NonAsciiPath $ClaudeExePath) {
        $shortPath = Get-ShortPath $ClaudeExePath
        if ($shortPath -and -not (Test-NonAsciiPath $shortPath)) {
            $safeClaudePath = $shortPath
            Write-Info "Claude 경로 변환: $ClaudeExePath"
            Write-Info "                → $safeClaudePath"
        } else {
            Write-Warning-Custom "Short Path 변환 실패, 원본 경로 사용"
        }
    }
    
    # claude.cmd 래퍼 생성
    $claudeWrapper = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" %*
"@
    
    $wrapperPath = "$binPath\claude.cmd"
    Set-Content -Path $wrapperPath -Value $claudeWrapper -Encoding ASCII
    
    if (Test-Path $wrapperPath) {
        Write-Success "claude.cmd 생성 완료: $wrapperPath"
        return $true
    } else {
        Write-Error-Custom "claude.cmd 생성 실패"
        return $false
    }
}

# dsclaude 명령어 생성
function Install-DsClaude {
    param([string]$ClaudeExePath)
    
    Write-Step "dsclaude 명령어 생성 중..."
    
    $binPath = Get-SafeBinPath
    
    # 기존 파일들 정리
    $oldFiles = @("$binPath\dsclaude.ps1", "$binPath\dsclaude.bat")
    foreach ($f in $oldFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Claude 경로 결정
    $safeClaudePath = "claude"
    if ($ClaudeExePath -and (Test-Path $ClaudeExePath)) {
        if (Test-NonAsciiPath $ClaudeExePath) {
            $shortPath = Get-ShortPath $ClaudeExePath
            if ($shortPath -and -not (Test-NonAsciiPath $shortPath)) {
                $safeClaudePath = $shortPath
            }
        } else {
            $safeClaudePath = $ClaudeExePath
        }
    }
    
    # dsclaude.cmd 파일 생성
    $dsclaudeCmd = @"
@echo off
chcp 65001 >nul 2>&1
"$safeClaudePath" --dangerously-skip-permissions %*
"@
    
    $cmdPath = "$binPath\dsclaude.cmd"
    Set-Content -Path $cmdPath -Value $dsclaudeCmd -Encoding ASCII
    
    if (Test-Path $cmdPath) {
        Write-Success "dsclaude.cmd 생성 완료: $cmdPath"
        return $true
    } else {
        Write-Error-Custom "dsclaude 생성 실패"
        return $false
    }
}

# ============================================================
# 메인 설치
# ============================================================

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Claude Code 원클릭 설치 스크립트       ║" -ForegroundColor Cyan
Write-Host "  ║   (한글 경로 지원 버전 v2)               ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 한글 사용자 이름 경고
$isKoreanPath = Test-NonAsciiPath $env:USERPROFILE
if ($isKoreanPath) {
    Write-Host "  ⚠️  한글 사용자 이름이 감지되었습니다!" -ForegroundColor Yellow
    Write-Host "     사용자: $env:USERNAME" -ForegroundColor Gray
    Write-Host "     래퍼 스크립트를 C:\claude-code\bin에 생성합니다." -ForegroundColor Gray
    Write-Host ""
}

# 1. winget 확인
Write-Step "winget 확인 중..."
if (-not (Test-Command "winget")) {
    Write-Error-Custom "winget이 설치되어 있지 않습니다."
    Write-Info "Windows 10 1709 이상 또는 Windows 11이 필요합니다."
    Write-Info "Microsoft Store에서 'App Installer'를 설치해주세요."
    Read-Host "Enter 키를 눌러 종료"
    exit 1
}
Write-Success "winget 확인됨"

# 2. Git 설치
Write-Host ""
Write-Step "Git 확인 중..."
Update-Path
if (Test-Command "git") {
    $gitVer = git --version 2>$null
    Write-Success "Git 이미 설치됨 ($gitVer)"
} else {
    Write-Info "Git 설치 중... (1-2분 소요)"
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
    
    # Git 경로 추가
    $gitPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin"
    )
    foreach ($p in $gitPaths) {
        if (Test-Path $p) { Add-ToPathPermanent $p | Out-Null }
    }
    
    Update-Path
    if (Test-Command "git") {
        Write-Success "Git 설치 완료!"
    } else {
        Write-Warning-Custom "Git 설치됨 - 새 터미널에서 확인 필요"
    }
}

# 3. Node.js 설치
Write-Host ""
Write-Step "Node.js 확인 중..."
Update-Path
if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    $versionNum = [int]($nodeVer -replace 'v(\d+)\..*', '$1')
    if ($versionNum -ge 18) {
        Write-Success "Node.js 이미 설치됨 ($nodeVer)"
    } else {
        Write-Info "Node.js 버전이 낮습니다 ($nodeVer). 업그레이드 중..."
        winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
        Update-Path
    }
} else {
    Write-Info "Node.js LTS 설치 중... (1-2분 소요)"
    winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
    
    # Node.js 경로 추가
    $nodePaths = @(
        "$env:ProgramFiles\nodejs"
    )
    foreach ($p in $nodePaths) {
        if (Test-Path $p) { Add-ToPathPermanent $p | Out-Null }
    }
    
    Update-Path
    if (Test-Command "node") {
        $nodeVer = node --version 2>$null
        Write-Success "Node.js 설치 완료! ($nodeVer)"
    } else {
        Write-Warning-Custom "Node.js 설치됨 - 새 터미널에서 확인 필요"
    }
}

# 4. Claude Code 설치
Write-Host ""
Write-Step "Claude Code 설치 중..."

$claudeExePath = $null

try {
    # 공식 설치 스크립트 실행
    Write-Info "공식 설치 스크립트 실행 중..."
    $installScript = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $installScript
    
    Write-Info "설치 완료 대기 중..."
    Start-Sleep -Seconds 3
    
    # Claude 실행 파일 찾기
    $claudeExePath = Find-ClaudeExecutable
    
    if ($claudeExePath) {
        Write-Success "Claude Code 발견: $claudeExePath"
    } else {
        Write-Error-Custom "Claude Code 실행 파일을 찾을 수 없습니다."
        Write-Info "수동 설치 후 다시 실행해주세요: irm https://claude.ai/install.ps1 | iex"
    }
    
} catch {
    Write-Error-Custom "Claude Code 설치 실패: $_"
    Write-Info "수동 설치: irm https://claude.ai/install.ps1 | iex"
}

# 5. 래퍼 스크립트 설치 (핵심!)
Write-Host ""
if ($claudeExePath) {
    # claude 래퍼 생성
    Install-ClaudeWrapper -ClaudeExePath $claudeExePath
    
    # dsclaude 래퍼 생성
    Install-DsClaude -ClaudeExePath $claudeExePath
} else {
    Write-Warning-Custom "Claude 실행 파일을 찾지 못해 래퍼를 생성할 수 없습니다."
}

# 6. PATH 설정
Write-Host ""
Write-Step "PATH 설정 중..."

$safeBin = Get-SafeBinPath
$pathResult = Add-ToPathPermanent $safeBin

if ($pathResult) {
    Write-Success "PATH 설정 완료: $safeBin"
} else {
    Write-Error-Custom "PATH 설정 실패"
    Write-Info "수동으로 PATH에 추가해주세요: $safeBin"
}

# npm global 경로도 추가 (필요시)
$npmGlobalPath = "$env:APPDATA\npm"
if (Test-Path $npmGlobalPath) { 
    Add-ToPathPermanent $npmGlobalPath | Out-Null
}

Update-Path

# 7. 설치 확인
Write-Host ""
Write-Step "설치 확인 중..."

# 현재 세션에서 테스트
$testClaudeCmd = "$safeBin\claude.cmd"
$testDsclaudeCmd = "$safeBin\dsclaude.cmd"

$claudeOk = Test-Path $testClaudeCmd
$dsclaudeOk = Test-Path $testDsclaudeCmd

if ($claudeOk) {
    Write-Success "claude 명령어 준비됨"
} else {
    Write-Error-Custom "claude 명령어 없음"
}

if ($dsclaudeOk) {
    Write-Success "dsclaude 명령어 준비됨"
} else {
    Write-Error-Custom "dsclaude 명령어 없음"
}

# ============================================================
# 완료 메시지
# ============================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║            설치 완료! 🎉                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($isKoreanPath) {
    Write-Host "  ℹ️  한글 경로 문제 해결됨" -ForegroundColor Cyan
    Write-Host "     래퍼 위치: $safeBin" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "  📌 중요: 새 PowerShell/터미널 창을 열어주세요!" -ForegroundColor Yellow
Write-Host ""
Write-Host "  설치된 명령어:" -ForegroundColor White
Write-Host "     claude      - Claude Code 실행" -ForegroundColor Gray
Write-Host "     dsclaude    - 권한 확인 스킵 모드" -ForegroundColor Gray
Write-Host ""
Write-Host "  시작하기:" -ForegroundColor White
Write-Host "     1. 새 터미널 열기" -ForegroundColor Gray
Write-Host "     2. claude --version  (설치 확인)" -ForegroundColor Gray
Write-Host "     3. claude            (시작 & 로그인)" -ForegroundColor Gray
Write-Host ""
Write-Host "  설치 경로:" -ForegroundColor White
Write-Host "     래퍼: $safeBin" -ForegroundColor Gray
if ($claudeExePath) {
    Write-Host "     실제: $claudeExePath" -ForegroundColor Gray
}
Write-Host ""

# 새 터미널 열기 제안
$openNew = Read-Host "새 PowerShell 창을 열까요? (Y/N)"
if ($openNew -eq "Y" -or $openNew -eq "y") {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "chcp 65001 >`$null; Write-Host '✅ Claude Code 준비 완료!' -ForegroundColor Green; Write-Host ''; claude --version; Write-Host ''; Write-Host '사용 가능한 명령어: claude, dsclaude' -ForegroundColor Cyan"
}
