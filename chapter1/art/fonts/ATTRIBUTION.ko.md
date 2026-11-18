# 글꼴 출처 기록

게임 안에 들어 있는 글꼴은 아래 둘이다. 둘 다 SIL Open Font License 1.1이다. 글꼴 파일은 고치지 않았고(부분 집합·이름 변경 없음) 파일 이름만 바꾼 것이 하나 있다. 시스템 글꼴은 쓰지 않는다(`allow_system_fallback` 끔, `chapter1/view/loc.gd`의 `Loc.font(role)`가 유일한 입구).

| 파일 | 글꼴 | 판 | 받은 곳 | 받은 날 | 라이선스 | 이름 변경 |
|---|---|---|---|---|---|---|
| `NotoSerifKR-VF.ttf` | Noto Serif KR (가변, wght 200~900) | 2.003 (파일 내부 판 문자열 `2.003-H1`) | google/fonts 저장소 `ofl/notoserifkr` (https://github.com/google/fonts/tree/main/ofl/notoserifkr) | 2026-11-18 | SIL OFL 1.1, 원문 `NotoSerifKR-OFL.txt` | 원래 이름 `NotoSerifKR[wght].ttf` → `NotoSerifKR-VF.ttf`(대괄호를 Godot 가져오기 파일 이름에서 피하려는 것. 글꼴 내부의 이름표는 그대로) |
| `PretendardVariable.ttf` | Pretendard (가변, wght 45~930) | v1.3.9 (파일 내부 `1.309`) | orioncactus/pretendard (https://github.com/orioncactus/pretendard) | 2026-11-18 | SIL OFL 1.1, 원문 `Pretendard-LICENSE.txt` | 없음 |

sha256

- `NotoSerifKR-VF.ttf` 11f8d5de6f1b79195efba3828aaa2ec95c1178f5ae976fb23c8d53250a9938f3 (23,795,420바이트)
- `PretendardVariable.ttf` 3090ccde0442bb347aa7685d9ba8b17436a60682df6e8f92a9a670de14056e22 (6,739,336바이트)

예약 글꼴 이름(Reserved Font Name): Pretendard 원문 첫머리에 "Reserved Font Name Pretendard"가 있다. 파일을 고치지 않고 그대로 담았으므로 이름 변경 의무는 없다. 나중에 부분 집합 같은 수정판을 만들면 그 이름을 쓸 수 없으니 이름을 바꿔야 한다(T3 지시서 2.6절). Noto Serif KR 원문에는 예약 이름 표시가 없다(원문 첫 줄이 저작권 문구이고 RFN 지정이 없다. 사람이 한 번 더 읽어 볼 것).

쓰임(`Loc.font(role)`)

- body: Pretendard 400, bold: Pretendard 700, number: Pretendard 600 + `tnum`(고정폭 숫자), heading: Noto Serif KR 700. 둘 다 서로의 대체 글꼴이다.
- 기울임꼴 파일은 없다. 예전 숫자 글꼴(시스템 Georgia 기울임)은 기울이지 않은 Pretendard 숫자로 바뀌었다.
- 게임 안 크레딧 화면과 배포 폴더에 OFL 원문을 넣는 일은 T4 고지 항목에서 한다.
