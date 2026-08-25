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
        ROOT / "scripts" / "build-portable.ps1",
        ROOT / ".github" / "workflows" / "build-portable.yml",
        ROOT / "THIRD_PARTY_NOTICES.md",
    ]
    for path in required_files:
        require(path.is_file(), f"필수 파일 없음: {path.relative_to(ROOT)}")

    launcher = (ROOT / "곰도리 미러 시작.cmd").read_text(encoding="ascii")
    require("%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" in launcher,
            "Windows PowerShell 절대 경로 실행이 없습니다.")

    source = APP.read_text(encoding="utf-8")
    xaml_match = re.search(r"\[xml\]\$xaml\s*=\s*@'\n(.*?)\n'@", source, re.DOTALL)
    require(xaml_match is not None, "XAML 블록을 찾을 수 없습니다.")
    ET.fromstring(xaml_match.group(1))

    required_fragments = [
        "'--no-control'",
        "'--fullscreen'",
        "'--stay-awake'",
        "'unauthorized'",
        "AutoConnectCheck",
        "Get-AndroidDevices",
        "Stop-Mirror",
        "ReadToEndAsync",
        "Add-MirrorExitDiagnostics",
        "LastAutoStartSerial",
        "'--no-audio'",
        "Stop-ProcessTree",
        "Restore-ControlWindow",
        "MirrorStopRequested",
    ]
    for fragment in required_fragments:
        require(fragment in source, f"필수 기능 누락: {fragment}")

    builder = (ROOT / "scripts" / "build-portable.ps1").read_text(encoding="utf-8")
    require("Get-FileHash" in builder, "scrcpy 다운로드 무결성 검증이 없습니다.")
    require("[regex]::Replace" in builder and '"`r`n"' in builder,
            "CMD 줄바꿈 CRLF 정규화가 없습니다.")
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
