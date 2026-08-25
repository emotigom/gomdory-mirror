Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $script:failures.Add($Message) }
}

$launcher = Join-Path $projectRoot '곰도리 미러 시작.cmd'
$app = Join-Path $projectRoot 'app\GomdoryMirror.ps1'
$builder = Join-Path $projectRoot 'scripts\build-portable.ps1'

Assert-True (Test-Path -LiteralPath $launcher) '실행 파일이 없습니다.'
Assert-True (Test-Path -LiteralPath $app) 'GUI 스크립트가 없습니다.'
Assert-True (Test-Path -LiteralPath $builder) '포터블 빌드 스크립트가 없습니다.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($app, [ref]$tokens, [ref]$parseErrors) | Out-Null
$parseMessages = @($parseErrors | ForEach-Object { $_.Message })
Assert-True ($parseErrors.Count -eq 0) ("GUI PowerShell 문법 오류: " + ($parseMessages -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($builder, [ref]$tokens, [ref]$parseErrors) | Out-Null
$parseMessages = @($parseErrors | ForEach-Object { $_.Message })
Assert-True ($parseErrors.Count -eq 0) ("빌드 PowerShell 문법 오류: " + ($parseMessages -join '; '))

$appText = Get-Content -LiteralPath $app -Raw
$launcherText = Get-Content -LiteralPath $launcher -Raw
Assert-True ($appText.Contains("'--no-control'")) '보기 전용 옵션이 누락되었습니다.'
Assert-True ($appText.Contains("'--fullscreen'")) '전체 화면 옵션이 누락되었습니다.'
Assert-True ($appText.Contains("'unauthorized'")) 'USB 승인 대기 상태가 누락되었습니다.'
Assert-True ($appText.Contains('AutoConnectCheck')) '자동 연결 기능이 누락되었습니다.'
Assert-True ($appText.Contains('ReadToEndAsync')) 'ADB/scrcpy 비동기 출력 처리가 누락되었습니다.'
Assert-True ($appText.Contains('Add-MirrorExitDiagnostics')) 'scrcpy 종료 진단이 누락되었습니다.'
Assert-True ($appText.Contains('LastAutoStartSerial')) '자동 재시작 반복 방지가 누락되었습니다.'
Assert-True ($appText.Contains("'--no-audio'")) '화면 전용 안정화 옵션이 누락되었습니다.'
Assert-True ($appText.Contains('Stop-ProcessTree')) '프로세스 트리 종료 처리가 누락되었습니다.'
Assert-True ($appText.Contains('Restore-ControlWindow')) '단일 미러 창 전환 처리가 누락되었습니다.'
Assert-True ($appText.Contains('MirrorStopRequested')) '창 닫기 재시작 방지 처리가 누락되었습니다.'
Assert-True ($launcherText.Contains('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe')) 'Windows PowerShell 절대 경로 실행이 누락되었습니다.'
Assert-True (-not ($launcherText.ToCharArray() | Where-Object { [int]$_ -gt 127 })) 'CMD 시작 파일은 코드페이지 충돌 방지를 위해 ASCII만 사용해야 합니다.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host '정적 검증 통과'
