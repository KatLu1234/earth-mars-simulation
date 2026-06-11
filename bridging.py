import socket
import subprocess
import time
import math
import sys

# ==========================================================================
# 42 ↔ ION-DTN 동기화 브릿지
#
#  [동작 방식 — 42 IPC 규격에 맞춤]
#   - 42는 Inp_IPC.txt 에서 TX / SERVER 로 설정됨 → 이 스크립트가 TCP 클라이언트로 접속.
#   - 42는 ASCII 텍스트 프레임을 송출하며, 각 프레임은 "[EOF]" 라인으로 끝남.
#   - 각 라인은 "Key = v1 v2 v3 ..." 형식 (TX prefix 로 선택된 변수들).
#   - 42는 "가시성 플래그"를 보내지 않으므로, 위치 벡터로부터 거리/가시성을
#     이 브릿지가 직접 계산하여 tc(netem) 지연/손실 + ION contact/range 에 반영.
#
#  ★ 검증 필요: TX prefix 변수명/프레임 형식은 42 버전마다 다를 수 있음.
#    `python3 bridging.py --debug` 로 띄우면 42가 보내는 원시 프레임과
#    파싱된 Key 목록을 출력하므로, 아래 POS_KEYS 매핑을 실제 이름에 맞추세요.
# ==========================================================================

# ---- 1. 설정 매개변수 -----------------------------------------------------
IPC_HOST = "127.0.0.1"
IPC_PORT = 4242
CLIGHT = 299792458.0            # 빛의 속도 (m/s)
FRAME_TERMINATOR = "[EOF]"      # 42 프레임 종료 마커

# 천체 반지름 (가림/occultation 계산용, 단위: m)
BODY_RADIUS = {
    "EARTH": 6_371_000.0,
    "MARS": 3_389_500.0,
    "SUN": 695_700_000.0,
}

# 42가 송출하는 위치 변수명 매핑 (실제 TX prefix 출력에 맞게 수정).
# 값은 공통 관성/일심(heliocentric) 프레임의 3차원 위치(m)라고 가정.
#   SC[0] = 지구 위성, SC[1] = 화성 위성
#   World[3] = EARTH, World[4] = MARS 의 일심 위치
POS_KEYS = {
    "earth_orbiter": "SC[0].PosN",
    "mars_orbiter":  "SC[1].PosN",
    "earth_body":    "World[3].PosH",
    "mars_body":     "World[4].PosH",
}

# CORE 가상 노드 / veth 인터페이스 / ION EID 매핑
#   occluder: 해당 링크가 가려지는지 검사할 천체 목록
LINKS = {
    "earth_to_eo": {  # 지구 지상국(1) ↔ 지구 위성(2)
        "node": "Earth_Station", "dev": "veth1.0",
        "src_eid": 1, "dst_eid": 2,
        "endpoints": ("earth_body", "earth_orbiter"),
        "occluders": ["EARTH"],
    },
    "eo_to_mo": {     # 지구 위성(2) ↔ 화성 위성(3)  — 심우주 구간
        "node": "Earth_Orbiter", "dev": "veth2.0",
        "src_eid": 2, "dst_eid": 3,
        "endpoints": ("earth_orbiter", "mars_orbiter"),
        "occluders": ["SUN", "EARTH", "MARS"],
    },
    "mo_to_mars": {   # 화성 위성(3) ↔ 화성 착륙선(4)
        "node": "Mars_Orbiter", "dev": "veth3.0",
        "src_eid": 3, "dst_eid": 4,
        "endpoints": ("mars_orbiter", "mars_body"),
        "occluders": ["MARS"],
    },
}

DEBUG = "--debug" in sys.argv


# ---- 2. 기하 계산 유틸 ----------------------------------------------------
def vsub(a, b):
    return [a[i] - b[i] for i in range(3)]


def vnorm(a):
    return math.sqrt(sum(c * c for c in a))


def is_occluded(p_a, p_b, p_body, radius):
    """선분 A-B 가 중심 p_body, 반지름 radius 인 구에 의해 가려지는지 검사.
    가려지면 True (즉, A와 B 사이 시선이 천체 표면을 통과)."""
    ab = vsub(p_b, p_a)
    ab_len2 = sum(c * c for c in ab)
    if ab_len2 == 0:
        return False
    # A->body 를 A->B 위에 정사영하여 가장 가까운 점의 매개변수 t 계산
    ap = vsub(p_body, p_a)
    t = sum(ap[i] * ab[i] for i in range(3)) / ab_len2
    # 천체가 두 노드 "사이"에 있을 때만 가림 (t in [0,1])
    if t <= 0.0 or t >= 1.0:
        return False
    closest = [p_a[i] + t * ab[i] for i in range(3)]
    dist_to_axis = vnorm(vsub(p_body, closest))
    return dist_to_axis < radius


def compute_link_geometry(positions, link):
    """positions 딕셔너리로부터 (visibility, distance_m) 계산.
    필요한 위치가 없으면 None 반환."""
    a_key, b_key = link["endpoints"]
    if a_key not in positions or b_key not in positions:
        return None
    p_a = positions[a_key]
    p_b = positions[b_key]
    distance = vnorm(vsub(p_b, p_a))

    visible = 1
    for body_name in link["occluders"]:
        body_key = {"EARTH": "earth_body", "MARS": "mars_body"}.get(body_name)
        # SUN 은 일심 프레임 원점(0,0,0) 으로 가정
        p_body = [0.0, 0.0, 0.0] if body_name == "SUN" else positions.get(body_key)
        if p_body is None:
            continue
        if is_occluded(p_a, p_b, p_body, BODY_RADIUS[body_name]):
            visible = 0
            break
    return visible, distance


# ---- 3. tc / ION 반영 ----------------------------------------------------
def update_network_env(link_name, visibility, distance):
    link = LINKS[link_name]
    node, dev = link["node"], link["dev"]
    src, dst = link["src_eid"], link["dst_eid"]

    prop_delay_sec = distance / CLIGHT
    prop_delay_ms = int(prop_delay_sec * 1000)

    if visibility == 1:
        print(f"[{link_name.upper()}] 연결 활성화 | 지연: {prop_delay_sec:.2f}초 "
              f"({prop_delay_ms}ms) | 거리: {distance/1000:,.1f}km")
        subprocess.run(
            f"vcmd -c /tmp/pycore.*/{node} -- tc qdisc change dev {dev} root "
            f"netem delay {prop_delay_ms}ms loss 0%",
            shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"ionadmin 'a contact +0 +10 {src} {dst} 1000000'",
                       shell=True, stdout=subprocess.DEVNULL)
        subprocess.run(f"ionadmin 'a range +0 +10 {src} {dst} {int(prop_delay_sec)}'",
                       shell=True, stdout=subprocess.DEVNULL)
    else:
        print(f"[{link_name.upper()}] 행성 가림 발생 (단절) | 데이터 보존 모드 진입")
        subprocess.run(
            f"vcmd -c /tmp/pycore.*/{node} -- tc qdisc change dev {dev} root "
            f"netem loss 100%",
            shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(f"ionadmin 'd contact +0 {src} {dst}'",
                       shell=True, stdout=subprocess.DEVNULL)


# ---- 4. 42 프레임 파싱 ----------------------------------------------------
def parse_frame(lines):
    """["Key = v1 v2 v3", ...] -> {Key: [floats]}"""
    positions = {}
    for line in lines:
        if "=" not in line:
            continue
        key, _, rhs = line.partition("=")
        key = key.strip()
        try:
            vals = [float(x) for x in rhs.split()]
        except ValueError:
            continue
        if len(vals) >= 3:
            positions[key] = vals[:3]
    # 설정된 POS_KEYS(별칭) 기준으로 재매핑
    aliased = {}
    for alias, real_key in POS_KEYS.items():
        if real_key in positions:
            aliased[alias] = positions[real_key]
    if DEBUG:
        print(f"[DEBUG] 파싱된 Key {len(positions)}개: {list(positions.keys())}")
        print(f"[DEBUG] 매핑 성공: {list(aliased.keys())}")
    return aliased


def connect_to_42():
    """42(TCP SERVER)에 클라이언트로 접속. 접속될 때까지 재시도."""
    while True:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect((IPC_HOST, IPC_PORT))
            print(f"=== 42 시뮬레이터에 접속 성공 ({IPC_HOST}:{IPC_PORT}) ===")
            return sock
        except (ConnectionRefusedError, OSError) as e:
            print(f"42 접속 대기 중... ({e})")
            time.sleep(2)


# ---- 5. 메인 루프 ---------------------------------------------------------
def main():
    print(f"=== 우주 통신 동기화 브릿지 기동 (TCP {IPC_HOST}:{IPC_PORT}) ===")
    if DEBUG:
        print(">>> DEBUG 모드: 42 원시 프레임/파싱 Key 를 출력합니다.\n")

    sock = connect_to_42()
    buffer = ""
    frame_lines = []

    try:
        while True:
            try:
                chunk = sock.recv(8192)
                if not chunk:
                    print("42 연결이 종료되었습니다. 재접속을 시도합니다.")
                    sock.close()
                    sock = connect_to_42()
                    buffer, frame_lines = "", []
                    continue

                buffer += chunk.decode("utf-8", errors="replace")
                while "\n" in buffer:
                    line, _, buffer = buffer.partition("\n")
                    line = line.strip()

                    if line.startswith(FRAME_TERMINATOR):
                        # 한 프레임 완성 → 기하 계산 후 반영
                        if DEBUG:
                            print("-" * 60)
                            print(f"[DEBUG] 프레임 수신 ({len(frame_lines)} 라인)")
                        positions = parse_frame(frame_lines)
                        frame_lines = []

                        print("-" * 60)
                        for link_name, link in LINKS.items():
                            geo = compute_link_geometry(positions, link)
                            if geo is None:
                                print(f"[{link_name.upper()}] 위치 데이터 부족 "
                                      f"(POS_KEYS 매핑 확인 필요)")
                                continue
                            visibility, distance = geo
                            update_network_env(link_name, visibility, distance)
                    elif line:
                        frame_lines.append(line)

            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"데이터 처리 오류: {e}")
                time.sleep(1)
    except KeyboardInterrupt:
        print("\n브릿지 스크립트를 안전하게 종료합니다.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
