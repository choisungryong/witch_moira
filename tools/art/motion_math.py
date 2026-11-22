#!/usr/bin/env python3
"""걸음 계약 계산(표준 라이브러리만). 관리 툴(characters.py), 적용 도구(motion_apply.py), 검증 도구가 모두 이 식을 부른다.

기호(docs/specs/T9-asset-pipeline-and-manager-views-20261122.ko.md 2.3절)
  v  이동 속도(m/s)               게임에서는 combat_core.gd 의 BASE_SPEED x 장비 이동 속도 보정
  L  한 주기의 길이(s)            계약 칸 이름은 pose.run_time_scale 이지만 뜻은 "배율"이 아니라 주기 길이다.
                                  (chapter_actors.gd: clip_time = phase x run_time_scale)
  stride  보폭 계약 값(m)         pose.stride_world_m. 게임은 이동 거리를 stride로 나눠 걸음 위상을 올린다.
  r  동작 배율                    클립을 원래 속도의 몇 배로 돌리는가. 게임에서 r = v x L / stride
  g  클립 지면 속도(m/s)          디딘 발이 몸 기준으로 뒤로 가는 속도. model.pack-report.json 의 값(모델 공간, 배율 전). +-6% 추정
  s  몸 배율                      contract.scale (냉기 1.32)

발 미끄러짐의 정의: 몸이 v로 앞으로 갈 때 디딘 발이 땅에 대해 갖는 앞쪽 속도의 평균.
  slip = v - r x g x s   양수면 발이 땅 위로 앞으로 끌려가고, 음수면 러닝머신처럼 헛돈다. 비율은 slip / v.
측정 미끄러짐(화면): 클립을 1/120 s 간격으로 샘플해, 발끝 뼈 높이가 그 클립의 최저 높이 + 3 cm 안인 프레임(디딤)의
땅 기준 수평 속도(= 발끝의 몸 기준 앞뒤 속도 + v)의 RMS. gen3d_mixamo_blender.py 의 ground_speed() 와 같은 생각이다.

모든 값은 모델의 답이다(지면 속도의 오차 +-6%). 게임에서 잰 값이 아니다.
"""
import math

SCALE_NOW = 1.32       # 냉기 몸 배율. 자리표의 값이 아니라 기본값이다. 호출하는 쪽이 자리표 값을 넘긴다.
GROUND_ERR = 0.06      # 지면 속도 추정 오차(HM-2 보고)


def rate_from_contract(v, length_s, stride):
    """계약 값에서 게임이 내는 동작 배율: r = v x L / stride."""
    if stride <= 0:
        raise ValueError("stride must be positive")
    return v * length_s / stride


def stride_for(v, length_s, rate):
    """원하는 배율 r 에서 필요한 보폭 계약 값: stride = v x L / r."""
    if rate <= 0:
        raise ValueError("rate must be positive")
    return v * length_s / rate


def rate_no_slip(v, g, s):
    """발이 미끄러지지 않는 배율: r0 = v / (g x s)."""
    if g <= 0 or s <= 0:
        raise ValueError("g and s must be positive")
    return v / (g * s)


def slip(v, rate, g, s):
    """평균 미끄러짐 속도(m/s): v - r x g x s."""
    return v - rate * g * s


def slip_ratio(v, rate, g, s):
    return slip(v, rate, g, s) / v if v else 0.0


def speed_no_slip(rate, g, s):
    """배율을 고정하고 미끄러짐을 없애려면 필요한 이동 속도: v = r x g x s (코어 값 제안용)."""
    return rate * g * s


def summary(v, length_s, rate, g, s):
    """화면과 고름 기록이 같은 말로 쓰는 한 묶음."""
    return {
        "rate": rate,
        "L": length_s,
        "stride_world_m": stride_for(v, length_s, rate),
        "slip_calc_mps": slip(v, rate, g, s),
        "slip_calc_ratio": slip_ratio(v, rate, g, s),
        "rate_no_slip": rate_no_slip(v, g, s),
        "speed_no_slip": speed_no_slip(rate, g, s),
        "ground_err": GROUND_ERR,
    }


def rms(values):
    values = list(values)
    return math.sqrt(sum(x * x for x in values) / len(values)) if values else None


def selfcheck_cases():
    """JS 쪽 즉석 계산이 같은 식인지 화면이 스스로 보는 입력 표. 기대값은 위 함수로 만든다."""
    cases = []
    for v, length_s, rate, g, s in [(5.8, 0.5333333, 0.606, 7.25, 1.32), (5.8, 0.96667, 1.3, 2.2125, 1.32),
                                    (5.8, 0.96667, 1.99, 2.2125, 1.32), (3.8, 0.96667, 1.3, 2.2125, 1.32)]:
        cases.append({"v": v, "L": length_s, "r": rate, "g": g, "s": s,
                      "stride": stride_for(v, length_s, rate), "slip": slip(v, rate, g, s),
                      "r0": rate_no_slip(v, g, s), "rate_from_stride": rate_from_contract(v, length_s, stride_for(v, length_s, rate))})
    return cases
