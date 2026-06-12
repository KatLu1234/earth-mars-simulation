# 동작 원리 (How It Works)

지구–화성 간 **DTN(Delay-Tolerant Networking)** 시뮬레이션의 내부 동작을 파일 단위로
정리한 문서입니다. README가 "어떻게 실행하는가"를 설명한다면, 이 문서는
"각 구성요소가 무엇을 어떻게 계산·반영하는가"를 설명합니다.

---

## 0. 한눈에 보는 전체 그림

세 개의 독립 시스템이 맞물려 동작합니다.

```
 ┌──────────────┐   위치벡터(TCP 4242)   ┌──────────────┐   tc/netem + ionadmin   ┌──────────────┐
 │  NASA 42      │ ────────────────────▶ │  bridging.py  │ ──────────────────────▶ │  CORE + ION   │
 │ (궤도 물리)    │   "Key = x y z\n...    │  (브릿지)     │   지연/손실/접촉 계획     │ (네트워크 실체) │
 │  Inp_*.txt 입력│    [EOF]"             │ 거리·가시성 계산│                         │ 4 노드 Bundle  │
 └──────────────┘                       └──────────────┘                         └──────────────┘
        ▲                                                                                 │
        │ configure_42.py 가 입력파일 생성                       send.sh/receive.sh/read_node.sh로 번들 송수신
```

| 시스템 | 역할 | 이 프로젝트의 담당 파일 |
|---|---|---|
| **42** (NASA 궤도 시뮬레이터) | 위성·천체의 실제 물리 위치를 시간에 따라 계산하여 TCP로 송출 | `configure_42.py` (입력파일 생성) |
| **bridging.py** (브릿지) | 42의 위치 → 링크별 거리/가시성 → 네트워크 파라미터로 변환·반영 | `bridging.py` |
| **CORE + ION-DTN** | 실제 가상 노드/링크를 만들고 Bundle Protocol로 데이터 전송 | `space_network.imn`, `*/`(노드별 설정), `start_ion_nodes.sh`, 송수신 스크립트 |

핵심 아이디어: **42는 "지금 위성이 어디 있는가"만 알려주고, 가시성·지연·대역폭 같은
"네트워크가 어떻게 보여야 하는가"는 브릿지가 직접 계산해서 실제 가상 네트워크에 실시간 반영**합니다.

---

## 1. 네트워크 토폴로지와 노드 매핑

4개 노드가 직렬로 연결된 사슬 구조입니다.

```
Earth_Station ──(100Mbps)── Earth_Orbiter ──(1Mbps, 심우주)── Mars_Orbiter ──(10Mbps)── Mars_Lander
  IPN 1                       IPN 2                            IPN 3                      IPN 4
 (서울 지상국)               (LEO 500km)                      (화성궤도 400km)            (착륙선)
```

| CORE 노드명 | 설정 디렉터리 | ION 노드번호 | IP (172.20.0.x) | 역할 |
|---|---|---|---|---|
| Earth_Station | `earth/` | 1 | .10 | 지구 지상국 |
| Earth_Orbiter | `earth_orbit/` | 2 | .20 | 지구 위성 (중계) |
| Mars_Orbiter | `mars_orbit/` | 3 | .30 | 화성 위성 (중계) |
| Mars_Lander | `mars/` | 4 | .40 | 화성 착륙선 |

이 매핑은 여러 파일에 일관되게 등장합니다:
- 토폴로지/이름: `space_network.imn`
- CORE노드↔디렉터리↔번호: `start_ion_nodes.sh`의 `NODES[]`, `lib_nodes.sh`의 `resolve_node()`
- IP/포트: 각 노드의 `*.ltprc` span 정의 (`udplclcli 172.20.0.x0:1113`)

---

## 2. CORE 토폴로지 — `space_network.imn`

CORE(Common Open Research Emulator)가 읽는 토폴로지 정의 파일입니다.

- `node n1~n4`: 4개의 `host` 모델 노드. `name`으로 Earth_Station 등 지정.
- `interface-peer {e0 n2}`: 각 노드의 인터페이스가 어느 노드와 연결되는지 — 직렬 사슬을 형성.
- `link l1~l3`: 노드 간 링크. **초기값은 모두 100Mbps, delay 0, loss 0**.
  - 이 초기값은 "출발선"일 뿐이며, 실행 중에는 브릿지가 `tc`로 계속 덮어씁니다.
- `annotation`: GUI에 IPN 번호를 표시하는 라벨(동작에는 영향 없음).

> CORE가 토폴로지를 Start하면 `/tmp/pycore.<PID>/` 세션 디렉터리가 생기고, 각 노드는
> 네트워크 네임스페이스로 격리됩니다. 이후 모든 스크립트는 `ls -d /tmp/pycore.*`로
> 이 세션을 찾아 `vcmd -c <세션>/<노드명> -- <명령>` 형태로 노드 내부에서 명령을 실행합니다.

---

## 3. 42 시뮬레이터 입력 생성 — `configure_42.py`

42가 부팅할 때 읽는 `/root/42/InOut/` 의 입력 파일들을 생성합니다.

생성하는 4개 파일:

1. **`Inp_IPC.txt`** — IPC(소켓) 설정 [가장 중요]
   - `TX` + `SERVER` + `localhost 4242` + `TRUE(blocking)`:
     → **42가 TCP 서버**가 되어 4242 포트를 열고, 클라이언트(브릿지) 접속을 기다린 뒤
     상태를 **송신(TX)**.
   - `Number of TX prefixes = 4` + 변수 목록:
     ```
     "SC[0].PosN"     # 지구 위성의 위치
     "SC[1].PosN"     # 화성 위성의 위치
     "World[3].PosH"  # EARTH의 일심(heliocentric) 위치
     "World[4].PosH"  # MARS의 일심 위치
     ```
     → 이 접두사로 시작하는 42 내부 변수를 매 프레임 ASCII로 내보냅니다.

2. **`Inp_Sim.txt`** — 시뮬레이션 모드/시간/IPC 활성화 (개념 템플릿)
   - External 모드, 시간 스텝 0.5초, 시작 시각, Orbit Center=SUN, IPC 활성화, 그래픽 끔.

3. **`Inp_Sats.txt`** — 위성 2기: `SC[0]`=지구 LEO 500km, `SC[1]`=화성궤도 400km.

4. **`Inp_Ground.txt`** — 지상국 2개: 지구(서울 37.57N/126.98E), 화성 착륙선(18.38N/77.58E).

> ⚠️ **버전 의존성**: TX prefix로 쓰는 변수명(`SC[0].PosN` 등)과 World 인덱스(EARTH=3, MARS=4)는
> 42 버전마다 다를 수 있습니다. `Inp_Sim.txt`/`Inp_Sats.txt`/`Inp_Ground.txt`는 단순화된
> 개념 템플릿이라 실제 42의 기본 템플릿 키 순서에 맞춰야 할 수 있습니다.
> 그래서 README는 첫 실행 전 `bridging.py --debug`로 실제 송출 변수명을 확인하라고 안내합니다.

---

## 4. 브릿지 — `bridging.py` (시뮬레이션의 두뇌)

42의 물리 위치를 받아 **링크별 거리·가시성을 계산하고, 이를 tc(netem)와 ION에 반영**하는
핵심 컴포넌트. 동작은 5단계로 나뉩니다.

### 4-1. 설정 (`POS_KEYS`, `LINKS`, `BODY_RADIUS`)

- `POS_KEYS`: 42 변수명 → 내부 별칭 매핑.
  `SC[0].PosN`→`earth_orbiter`, `SC[1].PosN`→`mars_orbiter`,
  `World[3].PosH`→`earth_body`, `World[4].PosH`→`mars_body`.
- `LINKS`: 계산할 3개 링크. 각 링크는 다음을 가집니다.
  - `node`/`dev`: tc를 적용할 CORE 노드와 veth 인터페이스.
  - `src_eid`/`dst_eid`: ION 접촉 계획에 쓸 노드 번호.
  - `endpoints`: 거리를 잴 두 끝점(별칭).
  - `occluders`: 이 시선을 가릴 수 있는 천체 목록.
    - `earth_to_eo` → `[EARTH]`
    - `eo_to_mo` → `[SUN, EARTH, MARS]` (심우주 구간, 태양 합 등 고려)
    - `mo_to_mars` → `[MARS]`
- `BODY_RADIUS`: 가림 판정에 쓸 천체 반지름(지구/화성/태양).

### 4-2. 기하 계산

- `vsub`, `vnorm`: 벡터 뺄셈·크기(=거리).
- `is_occluded(p_a, p_b, p_body, radius)`: **선분 A–B가 천체 구에 가려지는지** 판정.
  1. A→body 벡터를 A→B 위에 정사영하여 가장 가까운 점의 매개변수 `t` 계산.
  2. `t`가 0~1 사이(천체가 두 노드 "사이"에 있음)일 때만 검사.
  3. 그 최근접점과 천체 중심 거리가 반지름보다 작으면 → 시선이 천체를 통과 → **가림(True)**.
  - 태양(`SUN`)은 일심 프레임 원점 `(0,0,0)`으로 가정.
- `compute_link_geometry(positions, link)`: 두 끝점 위치로 **거리**를 구하고,
  `occluders`를 하나씩 검사해 하나라도 가리면 `visible=0`. 결과는 `(visibility, distance)`.
  필요한 위치가 없으면 `None`(→ "위치 데이터 부족" 로그).

### 4-3. 네트워크 반영 — `update_network_env()`

거리/가시성을 실제 가상 네트워크 파라미터로 변환합니다.

- 전파 지연 = 거리 ÷ 빛의 속도(`CLIGHT`). 초 단위 → ms로 변환.
- **연결(가시 visible=1)일 때**:
  - `tc qdisc change ... netem delay <ms> loss 0%` — 해당 노드 veth에 전파 지연 반영.
  - `ionadmin 'a contact +0 +10 src dst 1000000'` — 향후 10초 접촉(대역폭) 추가.
  - `ionadmin 'a range +0 +10 src dst <초>'` — 향후 10초 전파 지연(거리) 추가.
- **가림(visible=0)일 때**:
  - `tc ... netem loss 100%` — 패킷 100% 손실 = 물리적 단절.
  - `ionadmin 'd contact +0 src dst'` — 접촉 계획 삭제 → ION이 "지금은 못 보냄"을 인지하고
    번들을 **보관(store-and-forward)**.

> 이 부분이 DTN의 핵심을 만들어냅니다: 행성 가림 동안 링크는 끊기지만, ION은 번들을
> 버리지 않고 SDR에 쌓아두었다가 다음 접촉이 생기면 자동 전달합니다.

### 4-4. 42 프레임 파싱 — `parse_frame()`

- 42는 `"Key = v1 v2 v3 ...\n"` 라인들을 보내고 한 프레임을 `"[EOF]"` 라인으로 끝냅니다
  (`FRAME_TERMINATOR`).
- 각 라인을 `=`로 분리해 우변을 float 리스트로 파싱, 3개 이상이면 위치로 인정.
- `POS_KEYS`로 별칭 재매핑하여 `{earth_orbiter: [...], ...}` 형태로 반환.
- `--debug`면 원시 Key 목록과 매핑 성공 목록을 출력(변수명 맞추기용).

### 4-5. 메인 루프 — `main()` / `connect_to_42()`

- `connect_to_42()`: 42(TCP 서버)에 **클라이언트로 접속**, 실패 시 2초 간격 재시도
  (그래서 42·브릿지 기동 순서에 민감하지 않음).
- 루프: 소켓에서 청크 수신 → 버퍼에 누적 → `\n` 단위로 라인 분리 →
  `[EOF]`를 만나면 모인 라인을 파싱 → 3개 링크 각각 `compute_link_geometry` →
  `update_network_env`로 반영.
- 연결이 끊기면(`recv`가 빈 청크) 재접속. `Ctrl+C`로 안전 종료.

---

## 5. ION-DTN 노드 설정 (`earth/`, `earth_orbit/`, `mars_orbit/`, `mars/`)

각 노드 디렉터리에는 4개 admin이 읽는 설정 파일이 있습니다. 적용 순서와 의미:

### 5-1. `*.ionrc` — ionadmin (ION 초기화 + 초기 접촉 계획)

```
1 <노드번호> ""     # 이 컨테이너의 ION 노드 번호 초기화
s                   # ION 시작
a contact +0 +3600 <from> <to> <대역폭bps>   # 접촉(언제~언제 누구→누구 몇 bps)
a range   +0 +3600 <from> <to> <지연초>       # 거리(전파 지연)
m start
```

- 예) `earth.ionrc`: 노드1, 1→2 100Mbps / range 1초.
- 예) `earth_orbit.ionrc`: 2→1 100Mbps, **2→3 1Mbps(심우주), range 666초**(초기 지연 주입).
- 이 값들은 **초기값**이며, 실행 중에는 브릿지가 `a contact`/`a range`/`d contact`로 갱신.

### 5-2. `*.ltprc` — ltpadmin (LTP 엔진/Span = UDP 링크 계층)

```
1 32000                 # LTP 초기화 (세션 메모리)
a engine <노드번호> ...  # 로컬 LTP 엔진
a span <상대> ... <대역폭> 1 'udplclcli 172.20.0.x0:1113'   # 상대 노드로의 UDP 링크
s 'udplclso'            # LTP 송신 데몬 시작
```

- **span = 어느 IP:포트로 LTP 세그먼트를 보낼지** 정의. 여기서 실제 노드 간 UDP 경로가 결정됩니다.
- 예) `earth_orbit.ltprc`: 노드1(.10)과 노드3(.30) 양쪽으로 span — 중계 노드이므로 두 개.
- `mars.ltprc`: 노드3(.30)으로만 span — 사슬의 끝.

### 5-3. `*.bprc` — bpadmin (Bundle Protocol 엔드포인트/덕트)

```
1
a scheme ipn 'ipnfw' 'ipnadminep'    # ipn 스킴 등록
a endpoint ipn:<N>.0 q               # 엔드포인트 (서비스 0/1/2)
a endpoint ipn:<N>.1 q               #  → 앱(.1)을 송수신에 사용
a endpoint ipn:<N>.2 q
a protocol ltp 1400 100              # BP가 LTP 위에서 동작
a induct  ltp <N> ""                 # 수신(induct)
a outduct ltp <상대> ""              # 송신(outduct) — 중계 노드는 여러 개
s                                    # BP 시작
```

- 송수신 유틸(bpsource/bpsink 등)이 붙는 `ipn:N.1` 엔드포인트가 여기서 등록됩니다.

### 5-4. `*.ipnrc` — ipnadmin (IPN egress = 다음 홉 라우팅)

```
a plan <목적지노드> ltp/<다음홉노드>
```

- "어느 노드로 가려면 LTP로 어느 노드에 넘겨라"를 정의 — 정적 라우팅 테이블.
- 예) `earth.ipnrc`: 2/3/4 모두 `ltp/2` (지구는 항상 위성2로 전달 → 사슬 따라 이동).
- 예) `mars.ipnrc`: 1/2/3 모두 `ltp/3` (착륙선은 항상 화성위성3으로).
- 이 정적 plan + ION의 접촉 그래프 라우팅(CGR)으로 다중 홉 전달이 이뤄집니다.

---

## 6. 멀티노드 ION 기동 — `start_ion_nodes.sh`

한 컨테이너 안에서 4개 ION 노드를 **동시에** 띄우는 스크립트.

- **왜 멀티노드 모드인가**: CORE 가상 노드는 네트워크 네임스페이스만 분리하고
  SysV IPC(공유메모리)는 호스트와 공유합니다. 그래서 여러 ION 인스턴스가 충돌하지 않도록
  `ION_NODE_LIST_DIR=/tmp/ion_nodes`를 공유하는 **멀티노드 모드**가 필요합니다.
- `NODES[]`: `"CORE노드명:설정디렉터리:설정파일베이스"` 매핑.
- `start_node()`: `vcmd -c <세션>/<노드명> -- bash -c "..."`로 노드 내부에 들어가
  - `ION_NODE_LIST_DIR` 설정, 노드별 작업 디렉터리 `/tmp/ion_<노드명>` 생성 후 그곳으로 `cd`,
  - **순서대로** `ionadmin → ltpadmin → bpadmin → ipnadmin` 적용.
  - 이 작업 디렉터리(wd)가 **"내가 어느 ION 노드인가"의 식별자**가 됩니다(아래 7장과 연결).
- `stop_node()`: `ionstop`이 있으면 사용, 없으면 admin 역순 정지 + `killm`으로 공유메모리 정리.
- 사용법: `start_ion_nodes.sh [start|stop]`.

---

## 7. 통합 실행 — `run_simulation.sh`

전체를 순서대로 묶어 실행하고, 종료 시 정리까지 담당.

| 단계 | 동작 |
|---|---|
| 1 | `/tmp/pycore.*` 확인 — CORE 세션이 떠 있어야 함(없으면 에러로 중단) |
| 2 | `configure_42.py` 실행 — 42 입력파일 생성 |
| 3 | `start_ion_nodes.sh start` — 4개 노드 ION 기동 |
| 4 | `/root/42/42`를 InOut/ 기준 디렉터리에서 백그라운드 실행 (TCP 4242 서버 오픈), 로그 `sim42.log` |
| 5 | `bridging.py` 백그라운드 실행 (42에 접속 → tc/ion 반영), 로그 `bridge.log` |

- 기동 직후 `kill -0`로 프로세스 생존을 확인하고, 실패하면 로그를 출력하며 `cleanup`.
- 실행 중에는 `tail -f bridge.log`로 브릿지 로그를 실시간 출력.
- `trap cleanup INT TERM`: **Ctrl+C** 시 42·브릿지 종료 + `start_ion_nodes.sh stop`까지 자동 처리.
- 둘 중 한 프로세스라도 죽으면 루프를 빠져나와 정리.
- 로그 위치: `/tmp/em_sim_logs/`.

> 전제: 이 스크립트는 CORE 세션이 **이미 실행 중**이어야 합니다(2-2 단계). 42를 먼저 띄우고
> 브릿지가 클라이언트로 접속하지만, 브릿지가 재시도하므로 순서에 민감하지 않습니다.

---

## 8. 노드 간 송수신 유틸 (`lib_nodes.sh`, `send.sh`, `receive.sh`, `read_node.sh`)

ION이 떠 있는 상태에서 실제로 번들을 주고받고 데이터를 확인하는 도구들.

### 8-1. `lib_nodes.sh` — 공통 헬퍼 (나머지 셋이 `source`)

- `resolve_node(키)`: `earth|eo|mo|mars`(및 번호/별칭) → `"CORE노드명:ION노드번호"`.
- `find_session_dir()`: `/tmp/pycore.*` 세션 탐색.
- **`ion_exec(노드, 명령)`** [핵심]: 해당 노드의 ION 컨텍스트로 명령 실행.
  ```bash
  vcmd -c <세션>/<노드> -- bash -c \
    "export ION_NODE_LIST_DIR=...; cd /tmp/ion_<노드> || exit 1; <명령>"
  ```
  - **왜 `cd`가 중요한가**: 멀티노드 모드에서 BP 유틸은 "현재 작업 디렉터리"로 자신이
    어느 ION 노드인지 판별합니다. `start_ion_nodes.sh`가 각 노드를 `/tmp/ion_<노드명>`에서
    띄웠으므로, 송수신 유틸도 **반드시 같은 wd**에서 실행해야 그 노드 인스턴스에 붙습니다.
- EID 규칙: `ipn:<노드번호>.1` (서비스 1번을 앱용으로 사용, `APP_SERVICE=1`).

### 8-2. `send.sh <from> <to> text|file <payload>` — 송신

- `text`: 메시지를 송신 노드 wd에 임시파일로 쓴 뒤 `bpsource '<dst EID>' < tmp`로 stdin 주입
  (따옴표/특수문자 안전).
- `file`: `bpsendfile '<src EID>' '<dst EID>' '<파일>'`. 절대경로면 어느 wd에서도 OK.
- 수신 앱이 없어도 번들은 SDR에 저장되어 링크 연결 시 다음 홉으로 전달.

### 8-3. `receive.sh <node> text|file` — 수신 (포그라운드 리스너)

- `text`: `bpsink '<own EID>'` 출력을 `tee -a inbox_text.log`로 화면+파일 동시 기록.
- `file`: `bprecvfile '<own EID>'` → 노드 wd에 `testfile1, testfile2, ...`로 저장
  (ION 사양상 원본 이름이 아닌 순번).
- 별도 터미널에서 실행, `Ctrl+C`로 종료. 늦게 띄워도 보관된 번들을 받습니다(store-and-forward).

### 8-4. `read_node.sh <node|all>` — 저장 데이터 조회

각 노드에 대해 세 가지를 보여줍니다.
1. **수신 텍스트** — `inbox_text.log`.
2. **수신 파일** — `testfile*` 목록.
3. **보관 중 번들** — `bplist` 결과 = 아직 전달 안 된 채 노드에 쌓인 번들(=store-and-forward 상태).

---

## 9. 설치 — `setup.sh`

(최초 1회) 컨테이너에 의존 도구를 빌드/설치.

1. `chmod +x *.sh` (스크립트 실행 권한).
2. apt로 빌드 도구/라이브러리(build-essential, cmake, tcl-dev, freeglut3-dev, iproute2 등).
3. Python3 / pip.
4. **NASA 42**: `git clone … 42` → `make` → `/root/42/42`.
5. **ION-DTN 4.1.2**: 다운로드 → `./configure && make && make install && ldconfig` → `ionadmin` 등 사용 가능.

---

## 10. 데이터 흐름 — 처음부터 끝까지

지구에서 화성으로 메시지를 보내는 한 사이클:

1. **42**가 매 시간스텝 위성/천체 위치를 계산해 `"SC[0].PosN = x y z ... [EOF]"` 형태로 TCP 송출.
2. **bridging.py**가 프레임을 파싱 → 3개 링크의 거리·가시성 계산.
   - 예: 지구–화성 구간이 보이면 거리로 전파 지연(수백 초) 계산 →
     `tc netem delay`로 CORE 링크에 반영 + `ionadmin a contact/range`로 ION에 접촉 추가.
   - 태양/행성에 가려지면 → `tc loss 100%` + `ionadmin d contact` → 링크 단절.
3. **사용자**가 `send.sh earth mars text "..."` 실행 → `bpsource`가 `ipn:4.1`로 가는 번들 생성.
4. **ION**이 `ipnrc` plan(다음 홉)과 접촉 계획(CGR)을 보고 사슬을 따라 1→2→3→4로 전달.
   - 중간에 가림 구간이 있으면 해당 노드 SDR에 번들 **보관**, 다음 접촉에 재개.
5. 화성에서 `receive.sh mars text` 리스너(또는 나중에 기동)가 번들 수신 → `inbox_text.log` 기록.
6. `read_node.sh all`로 어느 노드에 무엇이 도착했고 무엇이 보관 중인지 확인.

이 흐름에서 **행성 가림으로 끊겨도 데이터가 보존되었다가 재연결 시 전달되는 것**이
이 시뮬레이션이 보여주려는 DTN의 핵심 특성입니다.

---

## 11. 파일별 역할 요약

| 파일 | 한 줄 요약 |
|---|---|
| `space_network.imn` | CORE 4노드 직렬 토폴로지(초기 링크값) 정의 |
| `configure_42.py` | 42 입력파일(IPC/Sim/Sats/Ground) 생성 — 42가 위치를 TCP로 송출하도록 설정 |
| `bridging.py` | 42 위치 수신 → 거리/가시성 계산 → tc(netem) + ionadmin 실시간 반영 |
| `*/ *.ionrc` | ION 초기화 + 초기 접촉/거리 계획 |
| `*/ *.ltprc` | LTP 엔진/span — 노드 간 UDP 링크 경로(IP:포트) |
| `*/ *.bprc` | Bundle Protocol 엔드포인트(`ipn:N.x`)/induct/outduct |
| `*/ *.ipnrc` | IPN 다음 홉 라우팅 plan |
| `start_ion_nodes.sh` | 멀티노드 모드로 4개 노드 ION admin 순차 적용(start/stop) |
| `run_simulation.sh` | configure→ION→42→브릿지 통합 실행 + Ctrl+C 정리 |
| `lib_nodes.sh` | 노드 매핑 + `ion_exec`(올바른 wd에서 노드별 ION 명령 실행) |
| `send.sh` | 노드 간 텍스트/파일 번들 송신(bpsource/bpsendfile) |
| `receive.sh` | 노드에서 번들 수신·저장(bpsink/bprecvfile) |
| `read_node.sh` | 노드의 수신 텍스트/파일/보관 번들(bplist) 조회 |
| `setup.sh` | 42 + ION-DTN 빌드·설치(최초 1회) |
