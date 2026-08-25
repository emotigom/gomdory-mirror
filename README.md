# 곰도리 미러

교실 Wi-Fi 상태와 무관하게 Android 태블릿 화면을 Windows 노트북을 거쳐 TV로 전달하는 포터블 현장지원 도구입니다.

기본 동작은 `보기 전용`입니다. 주강사가 태블릿을 직접 조작하고, 보조강사의 노트북은 HDMI로 연결된 TV에 화면만 전달합니다.

## 첫 번째 목표

- 설치 없이 ZIP 압축 해제 후 실행
- USB C-to-C 및 C-to-A 데이터 케이블 지원
- 태블릿 연결 자동 감지 및 자동 미러링
- 승인 필요·드라이버 문제·복수 기기 등 현장 상태를 한국어로 안내
- 전체 화면, 화질 프리셋, 자동 재연결
- 노트북에서 태블릿을 조작하지 않는 발표용 기본값

## 개발 상태

`v0.1.0`은 Galaxy Tab S7 계열과 Windows 10/11을 우선 검증 대상으로 삼습니다. 실제 배포 ZIP은 GitHub Actions의 `build-portable` 작업으로 생성합니다.

## 개발 환경에서 실행

공식 scrcpy Windows ZIP의 내용물을 `tools/scrcpy/`에 넣고 다음 파일을 실행합니다.

```text
곰도리 미러 시작.cmd
```

필수 파일은 `tools/scrcpy/adb.exe`, `tools/scrcpy/scrcpy.exe`입니다.

## 포터블 ZIP 만들기

Windows PowerShell에서 다음 명령을 실행합니다.

```powershell
.\tests\Test-Static.ps1
.\scripts\build-portable.ps1 -Version 0.1.0
```

빌드 스크립트는 scrcpy v4.1 Windows 64-bit 공식 배포본을 내려받고 SHA-256을 검증한 후 `dist/`에 포터블 ZIP을 생성합니다.

## 중요한 제한

- 최초 1회 Android 개발자 옵션과 USB 디버깅을 활성화해야 합니다.
- 최초 연결 때 태블릿에서 해당 노트북을 승인해야 합니다.
- 충전 전용 케이블은 사용할 수 없습니다.
- 학교 관리 정책으로 USB 디버깅이 차단된 기기는 지원하지 못합니다.
- DRM으로 보호되는 일부 영상은 검은 화면으로 나타날 수 있습니다.

## 라이선스

곰도리 미러는 Apache License 2.0으로 공개합니다. 배포본에 포함되는 scrcpy와 관련 구성요소는 각 원 저작자의 라이선스를 따릅니다. 자세한 내용은 [LICENSE](LICENSE), [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인하세요.
