import os

# 42 시뮬레이터 설정 파일들이 위치한 경로 (본인의 42 설치 경로에 맞게 수정)
CONFIG_DIR = "/root/42/InOut"

# 브릿지가 접속할 IPC 소켓 포트 (bridging.py 와 동일해야 함)
IPC_PORT = 4242


def configure_42_sim():
    if not os.path.exists(CONFIG_DIR):
        print(f"Error: {CONFIG_DIR} 경로가 존재하지 않습니다. 42 폴더 구조를 확인하세요.")
        return

    # --------------------------------------------------------------------------
    # 1. Inp_IPC.txt — 42 IPC(소켓) 설정 [핵심]
    #
    #   42는 이 파일로 소켓을 구성합니다. 아래 설정의 의미:
    #     - TX        : 42가 상태(위치 등)를 송신
    #     - SERVER    : 42가 소켓 서버 → 브릿지(bridging.py)가 TCP 클라이언트로 접속
    #     - Port      : IPC_PORT (4242)
    #     - TRUE(blocking): 클라이언트(브릿지) 접속을 기다림
    #     - TX prefixes   : 42 내부 변수명 중 이 접두사로 시작하는 항목을 전송.
    #                       위치 벡터를 보내야 브릿지가 거리/가시성을 계산할 수 있음.
    #
    #   ★ 주의: TX prefix 로 쓰는 변수명(예: SC[0].PosN, World[3].PosH)은
    #     42 버전마다 다를 수 있습니다. 실제 송출 내용은 bridging.py 를
    #     DEBUG 모드로 띄워(원시 프레임 출력) 확인 후 맞추세요.
    #     42 World 인덱스: SOL=0, ..., EARTH=3, MARS=4
    # --------------------------------------------------------------------------
    inp_ipc_path = os.path.join(CONFIG_DIR, "Inp_IPC.txt")
    ipc_content = f"""<<<<<<<<<<<<<<<<<  42: InterProcess Comm Configuration File  >>>>>>>>>>>>>>>
**************************  IPC Configuration  **************************
1                          !  Number of Sockets
==============================  IPC 0  ==============================
TX                         !  IPC Mode (OFF,TX,RX,TXRX,ACS,WRITEFILE,READFILE)
0                          !  AC.ID for ACS mode
"State.42"                 !  File name for WRITE or READ
SERVER                     !  Socket Role (SERVER,CLIENT,GMSEC_CLIENT)
localhost  {IPC_PORT}            !  Server Host Name, Port
TRUE                       !  Allow Blocking (i.e. wait for connection)
FALSE                      !  Echo to stdout
4                          !  Number of TX prefixes
"SC[0].PosN"
"SC[1].PosN"
"World[3].PosH"
"World[4].PosH"
"""
    with open(inp_ipc_path, "w") as f:
        f.write(ipc_content)
    print(f"[✓] Inp_IPC.txt 구성 완료 (TX/SERVER, 포트 {IPC_PORT}, 위치 벡터 송출)")

    # --------------------------------------------------------------------------
    # 2. Inp_Sim.txt — 시뮬레이션 모드/시간/IPC 활성화
    #   (아래는 단순화된 개념 템플릿입니다. 실제 키 순서/형식은 42/InOut 의
    #    기본 Inp_Sim.txt 템플릿을 기준으로 맞추세요.)
    # --------------------------------------------------------------------------
    inp_sim_path = os.path.join(CONFIG_DIR, "Inp_Sim.txt")
    sim_content = f"""42 Simulation Configuration File
Simulation Mode (0: Standalone, 1: External, 2: Interleaved)
1
Time Step (sec)
0.5
Start Time (Year, Month, Day, Hour, Min, Sec)
2026 05 13 17 00 00
Orbit Center (EARTH, MARS, SUN, etc.)
SUN
Interprocess Communication (0: None, 1: Enabled via Inp_IPC.txt)
1
IPC Port Number
{IPC_PORT}
Graphics Front End (0: None, 1: OpenGL)
0
"""
    with open(inp_sim_path, "w") as f:
        f.write(sim_content.strip())
    print(f"[✓] Inp_Sim.txt 구성 완료 (External 모드, IPC 활성화, 포트 {IPC_PORT}, 그래픽 끔)")

    # --------------------------------------------------------------------------
    # 3. Inp_Sats.txt — 지구 위성 1기 + 화성 위성 1기 (SC[0], SC[1])
    # --------------------------------------------------------------------------
    inp_sats_path = os.path.join(CONFIG_DIR, "Inp_Sats.txt")
    sats_content = """42 Spacecraft Configuration File
Number of Spacecraft
2
-------------------- Spacecraft 1 (SC[0]): Earth Orbiter --------------------
Orbit Center
EARTH
Orbit Type (0: LEO, 1: Geostationary, 2: Custom)
0
Altitude (km)
500
Inclination (deg)
45.0
-------------------- Spacecraft 2 (SC[1]): Mars Orbiter --------------------
Orbit Center
MARS
Orbit Type (0: Low Mars Orbit, 1: Custom)
0
Altitude (km)
400
Inclination (deg)
90.0
"""
    with open(inp_sats_path, "w") as f:
        f.write(sats_content.strip())
    print("[✓] Inp_Sats.txt 구성 완료 (지구 위성 SC[0], 화성 위성 SC[1])")

    # --------------------------------------------------------------------------
    # 4. Inp_Ground.txt — 지구 지상국 + 화성 착륙선
    # --------------------------------------------------------------------------
    inp_ground_path = os.path.join(CONFIG_DIR, "Inp_Ground.txt")
    ground_content = """42 Ground Station Configuration File
Number of Ground Stations
2
-------------------- Station 1: Earth Station (Seoul) --------------------
Parent Body
EARTH
Latitude (deg)
37.5665
Longitude (deg)
126.9780
-------------------- Station 2: Mars Lander --------------------
Parent Body
MARS
Latitude (deg)
18.38
Longitude (deg)
77.58
"""
    with open(inp_ground_path, "w") as f:
        f.write(ground_content.strip())
    print("[✓] Inp_Ground.txt 구성 완료 (지구 서울 지상국, 화성 착륙선)")


if __name__ == "__main__":
    configure_42_sim()