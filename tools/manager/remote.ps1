# 제작실 원격 접속 켜기·끄기·상태. 사용: powershell -File tools/manager/remote.ps1 start|stop|status [-Port 8781] [-DryRun]
#
#   start   관리 서버가 안 떠 있으면 띄우고(127.0.0.1 전용), cloudflared 터널을 띄운다. 이 스크립트는 cloudflared 를 내려받거나 설치하지 않고,
#           Cloudflare 에 로그인하거나 터널을 만들지 않는다(그것은 사용자가 사용안내의 차례대로 한다). cloudflared 가 없으면 안내만 하고 끝낸다.
#   stop    터널만 내린다(이 스크립트가 띄워 기록해 둔 프로세스, 명령줄에 cloudflared 가 있을 때만). 관리 서버는 그대로 둔다.
#   status  서버·터널·local-remote.json 의 enabled 를 보여 준다. 아무것도 바꾸지 않는다.
#   -DryRun 무엇을 띄울지 명령만 찍고 아무것도 하지 않는다.
#
# 두 겹의 스위치: 터널이 떠 있어도 local-remote.json 의 enabled 가 false 면 서버가 원격 요청을 모두 403 으로 거절한다.
# 터널은 local-remote.json 의 "tunnel" 칸으로 정한다:  {"tunnel": {"token_file": "tools/manager/local-remote.token"}}  (대시보드에서 만든 터널의 토큰 파일, git 밖)
#                                                  또는 {"tunnel": {"name": "<터널 이름>"}}  (cloudflared tunnel login 으로 만든 터널)
param(
    [Parameter(Position = 0)][ValidateSet('start', 'stop', 'status')][string]$Action = 'status',
    [int]$Port = 8781,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..\..')).Path
$ConfigPath = Join-Path $Here 'local-remote.json'
$StateDir = Join-Path $Root '_local\manager'
$StateFile = Join-Path $StateDir 'remote-state.json'
$Python = 'C:/Users/twins/AppData/Local/Programs/Python/Python310/python.exe'
if (-not (Test-Path $Python)) { $Python = (Get-Command python -ErrorAction SilentlyContinue).Source }

function Get-RemoteConfig {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try { return Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json } catch { return $false }
}
function Get-Listener([int]$P) {
    $c = Get-NetTCPConnection -LocalPort $P -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return $null }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)"
    return [pscustomobject]@{ Pid = $c.OwningProcess; Address = $c.LocalAddress; CommandLine = $proc.CommandLine }
}
function Read-State { if (Test-Path $StateFile) { try { return Get-Content -Raw $StateFile | ConvertFrom-Json } catch { } } return $null }
function Write-State($obj) { New-Item -ItemType Directory -Force $StateDir | Out-Null; ($obj | ConvertTo-Json) | Set-Content -Encoding UTF8 $StateFile }
function Get-TunnelProcess {
    $s = Read-State
    if (-not $s -or -not $s.tunnel_pid) { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($s.tunnel_pid)" -ErrorAction SilentlyContinue
    if ($p -and $p.CommandLine -match 'cloudflared') { return $p }
    return $null
}
function Get-TunnelArgs($cfg) {
    $t = $cfg.tunnel
    if ($t -and $t.token_file) {
        $tf = if ([System.IO.Path]::IsPathRooted($t.token_file)) { $t.token_file } else { Join-Path $Root $t.token_file }
        if (-not (Test-Path $tf)) { throw "토큰 파일이 없습니다: $tf (Cloudflare 대시보드의 터널 토큰을 이 파일에 한 줄로 저장하세요. git 에 올리지 않습니다)" }
        return @('tunnel', 'run', '--token-file', $tf)
    }
    if ($t -and $t.name) { return @('tunnel', 'run', [string]$t.name) }
    throw 'local-remote.json 에 "tunnel": {"token_file": "..."} 또는 {"name": "..."} 가 없습니다.'
}

$cfg = Get-RemoteConfig
$enabled = ($cfg -and $cfg.enabled -eq $true)

if ($Action -eq 'status') {
    $l = Get-Listener $Port
    if ($l) { "관리 서버: 켜짐 (포트 $Port, 주소 $($l.Address), PID $($l.Pid))`n  명령줄: $($l.CommandLine)" } else { "관리 서버: 꺼짐 (포트 $Port)" }
    if ($l -and $l.Address -notin @('127.0.0.1', '::1')) { Write-Warning "서버가 루프백(127.0.0.1)이 아닌 주소($($l.Address))에 열려 있습니다. 이 도구의 서버는 127.0.0.1 에만 열어야 합니다." }
    $t = Get-TunnelProcess
    if ($t) { "터널(cloudflared): 켜짐 (PID $($t.ProcessId))" } else { '터널(cloudflared): 이 스크립트가 띄운 것은 없음' }
    if ($null -eq $cfg) { "local-remote.json: 없음 -> 원격 꺼짐(루프백만)" }
    elseif ($cfg -eq $false) { "local-remote.json: 읽지 못함(JSON 오류) -> 서버는 원격을 꺼 둠" }
    else { "local-remote.json: enabled = $($cfg.enabled), 호스트 = $((@($cfg.hosts)) -join ', ')" }
    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) { 'cloudflared: PATH 에 없음 (설치는 사용안내.ko.md 의 「원격 접속」 차례 5)' }
    return
}

if ($Action -eq 'stop') {
    $t = Get-TunnelProcess
    if (-not $t) { '내릴 터널이 없습니다(이 스크립트가 띄운 cloudflared 기록 없음). 관리 서버는 건드리지 않습니다.'; return }
    if ($DryRun) { "[DryRun] 터널 PID $($t.ProcessId) 를 내립니다: $($t.CommandLine)"; return }
    Stop-Process -Id $t.ProcessId -Force
    $s = Read-State; $s.tunnel_pid = $null; Write-State $s
    "터널을 내렸습니다(PID $($t.ProcessId)). 관리 서버는 그대로입니다."
    return
}

# start
if ($cfg -eq $false -or $null -eq $cfg) { throw "tools/manager/local-remote.json 이 없거나 읽을 수 없습니다. 사용안내.ko.md 의 「원격 접속」을 먼저 따라 하세요." }
if (-not $enabled) { Write-Warning 'local-remote.json 의 enabled 가 false 입니다. 터널을 띄워도 서버가 원격 요청을 모두 403 으로 거절합니다. 켜려면 enabled 를 true 로 바꾸세요(서버를 다시 켤 필요 없음).' }
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
$tunnelArgs = Get-TunnelArgs $cfg
$serverArgs = @((Join-Path $Here 'server.py'), '--port', "$Port")
if ($DryRun) {
    "[DryRun] 서버: $Python $($serverArgs -join ' ')   (포트 $Port 가 비어 있을 때만)"
    "[DryRun] 터널: cloudflared $($tunnelArgs -join ' ')"
    if (-not $cf) { '[DryRun] cloudflared 가 PATH 에 없어 실제 start 는 안내만 하고 끝납니다.' }
    return
}
if (-not $cf) {
    '관리 서버도 터널도 띄우지 않았습니다: cloudflared 가 PATH 에 없습니다.'
    '설치(사용자가 직접): winget install --id Cloudflare.cloudflared   -> 새 터미널에서 cloudflared --version 확인'
    return
}
if (Get-TunnelProcess) { '터널이 이미 떠 있습니다(status 로 확인).'; return }
$l = Get-Listener $Port
if (-not $l) {
    $p = Start-Process -FilePath $Python -ArgumentList $serverArgs -WorkingDirectory $Root -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    "관리 서버를 띄웠습니다(PID $($p.Id), 127.0.0.1:$Port)."
} else {
    "관리 서버가 이미 포트 $Port 에 떠 있습니다(PID $($l.Pid)). 명령줄을 확인하세요: $($l.CommandLine)"
}
$tp = Start-Process -FilePath $cf.Source -ArgumentList $tunnelArgs -WorkingDirectory $Root -WindowStyle Hidden -PassThru
Write-State ([pscustomobject]@{ tunnel_pid = $tp.Id; started = (Get-Date).ToString('s') })
"터널을 띄웠습니다(cloudflared PID $($tp.Id)). 주소: $((@($cfg.hosts)) -join ', ')  / 끄려면: powershell -File tools/manager/remote.ps1 stop"
