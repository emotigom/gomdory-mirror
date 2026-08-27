from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app" / "GomdoryMirror.ps1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    required_files = [
        ROOT / "곰도리 미러 시작.cmd",
        APP,
        ROOT / "app" / "GomdoryMirror.Core.psm1",
        ROOT / "scripts" / "build-portable.ps1",
        ROOT / ".github" / "workflows" / "build-portable.yml",
        ROOT / "THIRD_PARTY_NOTICES.md",
    ]
    for path in required_files:
        require(path.is_file(), f"필수 파일 없음: {path.relative_to(ROOT)}")

    source = APP.read_text(encoding="utf-8")
    xaml_match = re.search(r"\[xml\]\$xaml\s*=\s*@'\n(.*?)\n'@", source, re.DOTALL)
    require(xaml_match is not None, "XAML 블록을 찾을 수 없습니다.")
    ET.fromstring(xaml_match.group(1))

    required_fragments = [
        "'--no-control'",
        "'--fullscreen'",
        "'--stay-awake'",
        "'--no-audio'",
        "'unauthorized'",
        "AutoConnectCheck",
        "Get-AndroidDevices",
        "Get-DeviceInfo",
        "DeviceCombo",
        "Get-AndroidDeviceKind",
        "Stop-Mirror",
        "Stop-ProcessTree",
        "Restore-ControlWindow",
        "WaitForMirrorWindow",
        "Dispatcher]::Run",
        "ReadToEndAsync",
    ]
    for fragment in required_fragments:
        require(fragment in source, f"필수 기능 누락: {fragment}")

    builder = (ROOT / "scripts" / "build-portable.ps1").read_text(encoding="utf-8")
    require("app\\*" in builder, "Android 공통 연결 모듈 패키징이 없습니다.")
    require("Get-FileHash" in builder, "scrcpy 다운로드 무결성 검증이 없습니다.")
    require("5b12172b3264b2889f4583ee64752ce832e29bc8b1089dca81093459697165db" in builder,
            "scrcpy v4.1 SHA-256 고정값이 없습니다.")

    print("소스 구조 검증 통과")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"검증 실패: {exc}", file=sys.stderr)
        raise SystemExit(1)
