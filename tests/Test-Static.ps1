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
$core = Join-Path $projectRoot 'app\GomdoryMirror.Core.psm1'
$builder = Join-Path $projectRoot 'scripts\build-portable.ps1'

Assert-True (Test-Path -LiteralPath $launcher) '실행 파일이 없습니다.'
Assert-True (Test-Path -LiteralPath $app) 'GUI 스크립트가 없습니다.'
Assert-True (Test-Path -LiteralPath $core) 'Android 공통 연결 모듈이 없습니다.'
Assert-True (Test-Path -LiteralPath $builder) '포터블 빌드 스크립트가 없습니다.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($app, [ref]$tokens, [ref]$parseErrors) | Out-Null
$parseMessages = @($parseErrors | ForEach-Object { $_.Message })
Assert-True ($parseErrors.Count -eq 0) ("GUI PowerShell 문법 오류: " + ($parseMessages -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($core, [ref]$tokens, [ref]$parseErrors) | Out-Null
$parseMessages = @($parseErrors | ForEach-Object { $_.Message })
Assert-True ($parseErrors.Count -eq 0) ("공통 연결 모듈 PowerShell 문법 오류: " + ($parseMessages -join '; '))

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($builder, [ref]$tokens, [ref]$parseErrors) | Out-Null
$parseMessages = @($parseErrors | ForEach-Object { $_.Message })
Assert-True ($parseErrors.Count -eq 0) ("빌드 PowerShell 문법 오류: " + ($parseMessages -join '; '))

$appText = Get-Content -LiteralPath $app -Raw
Assert-True ($appText.Contains("'--no-control'")) '보기 전용 옵션이 누락되었습니다.'
Assert-True ($appText.Contains("'--fullscreen'")) '전체 화면 옵션이 누락되었습니다.'
Assert-True ($appText.Contains("'--no-audio'")) '화면 전용 안정화 옵션이 누락되었습니다.'
Assert-True ($appText.Contains("'unauthorized'")) 'USB 승인 대기 상태가 누락되었습니다.'
Assert-True ($appText.Contains('AutoConnectCheck')) '자동 연결 기능이 누락되었습니다.'
Assert-True ($appText.Contains('DeviceCombo')) '복수 Android 기기 선택 기능이 누락되었습니다.'
Assert-True ($appText.Contains('Get-DeviceInfo')) 'Android 기기 정보 판별 기능이 누락되었습니다.'
Assert-True ($appText.Contains('Stop-ProcessTree')) '프로세스 트리 종료 처리가 누락되었습니다.'
Assert-True ($appText.Contains('WaitForMirrorWindow')) '미러 창 준비 확인이 누락되었습니다.'
Assert-True ($appText.Contains('MirrorWindowShown')) '영상 창 한 번 종료 상태 처리가 누락되었습니다.'
Assert-True ($appText.Contains('$window.Close()')) '영상 창 종료 후 앱 전체 종료 처리가 누락되었습니다.'
Assert-True ($appText.Contains('Dispatcher]::Run')) '비모달 앱 메시지 루프가 누락되었습니다.'
Assert-True (-not ($appText -match '\$window\.ShowDialog\(')) '숨김 시 종료되는 모달 창 호출이 남아 있습니다.'

Import-Module -Name $core -Force
$sampleDevices = @'
List of devices attached
R52N123456A device usb:1-3 product:gts7 model:SM_T870 device:gts7wifi transport_id:1
ZY22ABC unauthorized usb:2-1 transport_id:2
192.168.0.12:5555 offline product:husky model:Pixel_8_Pro device:husky transport_id:3
'@
$parsedDevices = @(ConvertFrom-AdbDevicesOutput -OutputText $sampleDevices)
Assert-True ($parsedDevices.Count -eq 3) 'ADB 기기 목록 개수 해석에 실패했습니다.'
Assert-True ($parsedDevices[0].Serial -eq 'R52N123456A') 'ADB 일련번호가 모델명 해석 중 덮어써졌습니다.'
Assert-True ($parsedDevices[0].State -eq 'device') 'ADB 연결 상태 해석에 실패했습니다.'
Assert-True ($parsedDevices[0].Model -eq 'SM T870') 'ADB 모델명 해석에 실패했습니다.'
Assert-True ($parsedDevices[0].ConnectionType -eq 'usb') 'USB 연결 유형 판별에 실패했습니다.'
Assert-True ($parsedDevices[2].ConnectionType -eq 'wireless') '무선 ADB 연결 유형 판별에 실패했습니다.'

$sampleProps = @'
[ro.product.manufacturer]: [samsung]
[ro.product.model]: [SM-T870]
[ro.build.version.release]: [13]
[ro.build.version.sdk]: [33]
[ro.build.characteristics]: [tablet]
'@
$parsedProps = ConvertFrom-AndroidGetPropOutput -OutputText $sampleProps
Assert-True ($parsedProps['ro.product.model'] -eq 'SM-T870') 'Android 시스템 속성 해석에 실패했습니다.'
Assert-True ((Get-AndroidDeviceKind -Properties $parsedProps) -eq 'tablet') '태블릿 유형 판별에 실패했습니다.'
$phoneProps = @{ 'ro.product.model' = 'Pixel 8'; 'ro.build.characteristics' = 'nosdcard' }
Assert-True ((Get-AndroidDeviceKind -Properties $phoneProps -SizeOutput 'Physical size: 1080x2400' -DensityOutput 'Physical density: 420') -eq 'phone') '휴대전화 유형 판별에 실패했습니다.'

$builderText = Get-Content -LiteralPath $builder -Raw
Assert-True ($builderText.Contains("app\*")) '공통 연결 모듈이 포터블 ZIP에 포함되지 않습니다.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host '정적 검증 통과'
