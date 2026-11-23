# 강림 컷신 영상 — 출처 기록

- `feronia.ogv`(화염), `marzanna.ogv`(냉기), `tacita.ogv`(번개): 1280x720, 30fps, 약 3초, 소리 없음, Ogg Theora.
- 만든 날: 2026-11-23 (지시 장부 U-100·U-101).
- 원본: Seedance 2.0 Mini(Dreamina CLI, first_last_frame, 720p, 5초, 개당 25크레딧). 첫 프레임은 같은 악마의 메인 이미지(`ui/descent/ATTRIBUTION.ko.md`).
- 요청문: 작업 폴더 `D:/Project/witch-moira-work/tools/dreamina/prompt_demon_video_{ember,frost,arc}.txt`(저장소 밖). 원본 영상은 `D:/Project/witch-moira-work/video/demon/`.
- 가공: ffmpeg로 3초를 자름(화염 1.9~4.9초, 냉기 0.3~3.3초, 번개 1.7~4.7초), 1280x720 30fps, `-an`, libtheora q4. 이 PC의 ffmpeg 8.0.1 libtheora는 예측 프레임이 있으면 깨져서 모든 프레임을 키프레임으로 만들었다(`-g 1`).
- 라이선스: 출시 전 약관 확인(Dreamina 유료 구독 생성물).
