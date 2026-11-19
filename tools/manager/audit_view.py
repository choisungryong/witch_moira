"""점검 화면의 뒷면: 가장 최근 audit 결과를 읽고(읽기 전용), 다시 돌리기는 audit.py 를 하위 프로세스로 부른다.

게임 데이터·메모 파일을 쓰지 않는다. audit.py 가 쓰는 것은 _local/audit/<날짜-시각>/ 뿐이다.
동시에 하나만 돌리고, 시간 제한이 있다. 결과의 값은 audit.py 가 센 것을 그대로 보여 주며 이 모듈은 다시 세지 않는다.
"""
import json, os, subprocess, sys, threading
from pathlib import Path

try:
    from .catalog import ROOT
except ImportError:
    from catalog import ROOT

SCRIPT = ROOT / 'tools' / 'dev' / 'audit.py'
AUDIT_DIR = ROOT / '_local' / 'audit'
TIMEOUT = 600
_RUN = threading.Lock()


class BusyError(Exception):
    pass


class RunError(Exception):
    pass


def latest(audit_dir=None):
    """가장 최근 audit.json 의 내용과 폴더 이름. 없으면 {'result': None}."""
    audit_dir = Path(audit_dir or AUDIT_DIR)
    if audit_dir.is_dir():
        for folder in sorted((p for p in audit_dir.iterdir() if p.is_dir()), reverse=True):
            path = folder / 'audit.json'
            if path.is_file():
                try:
                    return {'result': json.loads(path.read_text(encoding='utf-8')), 'folder': folder.name, 'running': _RUN.locked()}
                except ValueError:
                    continue
    return {'result': None, 'folder': None, 'running': _RUN.locked()}


def run(script=None, audit_dir=None, timeout=None):
    """audit.py 를 돌리고 새 결과를 돌려준다. 이미 돌고 있으면 BusyError, 실패하거나 시간이 넘으면 RunError."""
    script = Path(script or SCRIPT)
    if not _RUN.acquire(blocking=False):
        raise BusyError('점검이 이미 돌고 있습니다. 끝날 때까지 기다리세요.')
    try:
        env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
        try:
            done = subprocess.run([sys.executable, str(script)], cwd=ROOT, capture_output=True, timeout=timeout or TIMEOUT, env=env)
        except subprocess.TimeoutExpired:
            raise RunError('점검이 시간 제한(%d초)을 넘어 멈췄습니다.' % (timeout or TIMEOUT))
        except OSError as error:
            raise RunError('점검을 실행하지 못했습니다: %s' % error.__class__.__name__)
        # 종료 코드 1은 "지난번보다 나빠진 줄이 있음"이라 실패가 아니다. 결과 파일이 새로 생겼는지로 본다.
        if done.returncode not in (0, 1):
            raise RunError('점검이 비정상으로 끝났습니다(종료 %d). %s' % (done.returncode, done.stderr.decode('utf-8', 'replace').strip()[-300:]))
    finally:
        _RUN.release()
    return latest(audit_dir)
