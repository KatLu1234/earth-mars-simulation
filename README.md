# earth-mars-simulation

지구–화성 간 **DTN(Delay-Tolerant Networking)** 통신 시뮬레이션입니다.
NASA **42**(궤도 시뮬레이터)가 계산한 위성/천체의 위치를 받아, **브릿지**가 링크별
전파 지연·가시성을 계산하고, 이를 **CORE**(네트워크 에뮬레이터)의 `tc`(netem)와
**ION-DTN**(Bundle Protocol)의 contact/range에 실시간 반영합니다.

## 네트워크 토폴로지

```
Earth_Station ── Earth_Orbiter ── Mars_Orbiter ── Mars_Lander
   IPN 1            IPN 2            IPN 3           IPN 4
 (서울 지상국)    (LEO 500km)     (화성궤도 400km)  (착륙선)
            100Mbps        1Mbps(심우주)      10Mbps
```

| CORE 노드 | 설정 디렉터리 | ION 노드번호 |
|---|---|---|
| Earth_Station | `earth/` | 1 |
| Earth_Orbiter | `earth_orbit/` | 2 |
| Mars_Orbiter | `mars_orbit/` | 3 |
| Mars_Lander | `mars/` | 4 |

---

## 1. Docker 환경 설치 및 실행

이 프로젝트는 [`d3f0/coreemu_vnc`](https://hub.docker.com/r/d3f0/coreemu_vnc/) 이미지
(CORE 네트워크 에뮬레이터 + VNC/noVNC)에서 동작합니다.

### 1-1. Docker 설치

- **Windows / macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치
- **Linux**: `curl -fsSL https://get.docker.com | sh`

### 1-2. 프로젝트를 공유 폴더에 배치

컨테이너의 `/root/shared` 에 마운트할 호스트 폴더(`shared/`)를 만들고 그 안에
이 프로젝트를 둡니다. (컨테이너 ↔ 호스트 간 파일 교환 경로)

```bash
# 호스트(이 저장소 상위)에서
mkdir -p shared
# 이 프로젝트 폴더(earth-mars-simulation)를 shared/ 안으로 복사 또는 클론
cp -r earth-mars-simulation shared/
```

> 결과적으로 컨테이너 안에서는 `/root/shared/earth-mars-simulation/` 으로 보입니다.

### 1-3. 이미지 받기 및 컨테이너 실행

CORE는 컨테이너 안에서 네임스페이스·내부 네트워크를 만들어야 하므로
`NET_ADMIN` / `SYS_ADMIN` 권한이 **필수**입니다.

```bash
docker pull d3f0/coreemu_vnc

docker run -d --name coreemu \
  --cap-add=NET_ADMIN --cap-add=SYS_ADMIN \
  -v "$(pwd)/shared:/root/shared" \
  -p 5900:5900 -p 8080:8080 \
  d3f0/coreemu_vnc
```

> **PowerShell(Windows)** 에서는 줄바꿈/경로를 아래처럼:
> ```powershell
> docker run -d --name coreemu --cap-add=NET_ADMIN --cap-add=SYS_ADMIN -v "${PWD}\shared:/root/shared" -p 5900:5900 -p 8080:8080 d3f0/coreemu_vnc
> ```

또는 `docker-compose.yml`:

```yaml
version: '3'
services:
  coreemu:
    image: d3f0/coreemu_vnc
    container_name: coreemu
    ports:
      - "8080:8080"
      - "5900:5900"
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    volumes:
      - $PWD/shared:/root/shared
```
```bash
docker compose up -d
```

### 1-4. GUI(CORE) 접속

| 방식 | 주소 | 비고 |
|---|---|---|
| 웹 브라우저 (noVNC) | http://localhost:8080 | 별도 설치 불필요 (권장) |
| VNC 클라이언트 | `localhost:5900` | RealVNC 등 |

- **VNC 비밀번호**: `coreemu`

---

## 2. 컨테이너 내부에서 프로젝트 실행

GUI에 접속한 뒤, 컨테이너 안의 터미널을 엽니다. (noVNC 데스크톱의 터미널, 또는
호스트에서 `docker exec -it coreemu bash`)

```bash
cd /root/shared/earth-mars-simulation
```

### 2-1. (최초 1회) 의존 도구 설치 — 42 + ION-DTN

```bash
chmod +x setup.sh start_ion_nodes.sh run_simulation.sh
bash setup.sh
```
> `setup.sh` 가 NASA 42 시뮬레이터(`/root/42/42`)와 ION-DTN(`ionadmin` 등)을
> 빌드·설치합니다.

### 2-2. CORE 토폴로지 실행 (선행 필수)

통합 스크립트는 실행 중인 CORE 세션(`/tmp/pycore.*`)을 전제로 합니다.
CORE GUI(noVNC 화면)에서 `space_network.imn` 을 열어 4개 노드 토폴로지를
**Start(실행)** 합니다.

- GUI: `File → Open → space_network.imn` 후 좌측 하단 ▶(Start) 버튼
- 실행되면 `Earth_Station / Earth_Orbiter / Mars_Orbiter / Mars_Lander` 노드가 활성화됩니다.

### 2-3. 통합 실행

```bash
./run_simulation.sh
```

이 한 줄이 다음을 **순서대로** 수행합니다:

| 단계 | 동작 | 담당 |
|---|---|---|
| 1 | CORE 세션 확인 | `run_simulation.sh` |
| 2 | 42 입력파일 생성 (`Inp_IPC.txt` 등) | `configure_42.py` |
| 3 | 4개 노드 ION 기동 (`ionadmin→ltpadmin→bpadmin→ipnadmin`) | `start_ion_nodes.sh start` |
| 4 | 42 시뮬레이터 기동 (TCP 서버 4242) | `run_simulation.sh` |
| 5 | 브릿지 기동 (42에 접속 → 거리/가시성 계산 → tc/ion 반영) | `bridging.py` |

- 브릿지 로그가 실시간 출력됩니다.
- **`Ctrl+C`** 로 42·브릿지 종료 + ION 정리까지 자동 처리됩니다.
- 로그 위치: `/tmp/em_sim_logs/`(`bridge.log`, `sim42.log`)

---

## 3. (권장) 첫 실행 전 IPC 형식 검증

42가 송출하는 변수명/프레임 형식은 **버전마다 다를 수 있습니다.** 통합 실행 전에
42가 실제로 무엇을 보내는지 확인하세요:

```bash
python3 configure_42.py          # 입력파일 생성
cd /root/42 && ./42 &            # 42 먼저 기동 (TCP 서버)
cd /root/shared/earth-mars-simulation
python3 bridging.py --debug      # 원시 프레임 + 파싱된 Key 출력
```

출력된 실제 변수명에 맞춰 다음을 조정합니다:
- `bridging.py` 의 `POS_KEYS`, `FRAME_TERMINATOR`
- `configure_42.py` 의 TX prefix 목록

---

## 4. 실행 순서 요약

```
[호스트] shared/ 에 프로젝트 배치 → docker run (coreemu_vnc)
   ↓
[브라우저] http://localhost:8080 (pw: coreemu) 로 CORE GUI 접속
   ↓
[컨테이너] cd /root/shared/earth-mars-simulation
   ↓ (최초 1회) bash setup.sh
   ↓ CORE GUI 에서 space_network.imn 토폴로지 Start
   ↓ ./run_simulation.sh
   ↓ Ctrl+C 로 종료/정리
```

---

## 5. 노드 간 데이터 송수신 및 읽기 (Bundle Protocol)

`run_simulation.sh`로 4개 노드 ION이 떠 있는 상태에서, 노드 간에 텍스트/파일을
번들(Bundle)로 주고받고 각 노드에 저장된 데이터를 읽을 수 있습니다.

> **EID 규칙**: `ipn:<노드번호>.1`  (서비스 1번을 앱용으로 사용)
> **노드 키**: `earth`(1) · `eo`(2) · `mo`(3) · `mars`(4)

```bash
chmod +x lib_nodes.sh send.sh receive.sh read_node.sh
```

### 5-1. 지구 → 화성 보내기

```bash
# (선택) 화성에서 수신 리스너를 별도 터미널에 띄움 — 나중에 띄워도 됨(store-and-forward)
./receive.sh mars text                       # 텍스트 수신 대기 (Ctrl+C 종료)
# 또는 파일 수신:  ./receive.sh mars file

# 지구에서 송신
./send.sh earth mars text "Hello Mars from Earth"
./send.sh earth mars file /root/shared/earth_payload.bin
```

### 5-2. 화성 → 지구 보내기

```bash
./receive.sh earth text                      # 지구에서 수신 대기 (별도 터미널)

./send.sh mars earth text "Hello Earth from Mars"
./send.sh mars earth file /root/shared/mars_report.bin
```

### 5-3. 각 노드에 저장된 데이터 읽기

```bash
./read_node.sh mars        # 특정 노드 (수신 텍스트 + 수신 파일 + 보관 중 번들)
./read_node.sh all         # 4개 노드 전부
```

`read_node.sh`가 보여주는 항목:
1. **수신 텍스트** — `receive.sh ... text`로 누적된 `inbox_text.log`
2. **수신 파일** — `receive.sh ... file`로 저장된 `testfile1, testfile2, ...`
3. **보관 중 번들** — `bplist` 결과 (아직 전달되지 않고 노드에 저장된 번들 = store-and-forward 상태)

> **동작 원리**
> - 송수신 유틸은 `vcmd`로 해당 CORE 노드 내부에서, 그리고 ION 멀티노드 규칙에 맞는
>   작업 디렉터리(`/tmp/ion_<노드명>`)에서 실행됩니다 (`lib_nodes.sh`의 `ion_exec`).
> - 수신 앱이 떠 있지 않아도 번들은 노드 SDR에 **보관**되며, 링크가 연결되거나
>   리스너가 기동되면 전달됩니다. 행성 가림(occultation) 구간에서 데이터가
>   끊기지 않고 보존되는 DTN의 핵심 동작을 이 흐름으로 확인할 수 있습니다.

> **참고**
> - 송수신이 동작하려면 각 노드 `.bprc`에 ipn 스킴(`a scheme ipn 'ipnfw' 'ipnadminep'`)과
>   엔드포인트(`a endpoint ipn:N.1 q`)가 등록되어 있어야 합니다 (이미 반영됨).
> - `bprecvfile`은 수신 파일을 원본 이름이 아닌 `testfileN`으로 저장합니다 (ION 사양).

---

## 5-4. 노드 상태 확인 (`node_status.sh`)

폴더 구조의 설정 파일을 읽어 **정적 토폴로지**를 보여주고, CORE 세션이 떠 있으면
각 노드 ION 의 **실시간 상태**까지 확인합니다.

```bash
chmod +x node_status.sh

./node_status.sh            # 전체: 정적 토폴로지 + 실시간 상태 요약 (기본)
./node_status.sh topo       # 정적 토폴로지만 (ION 미실행 상태에서도 동작)
./node_status.sh live       # 실시간 요약 (노드별 RUNNING/DOWN + 접촉/보관번들 수)
./node_status.sh tree       # 프로젝트/노드 폴더 구조
./node_status.sh earth      # 특정 노드 상세 (contact/range/induct/plan/span/bplist/bpstats)
```

- `topo` / `tree` 는 ION 이 떠 있지 않아도(=폴더만 있으면) 동작합니다.
- `live` / `<node>` 는 `/tmp/pycore.*` 세션과 기동된 ION 이 있어야 실시간 값을 보여줍니다.
- 보여주는 정보: 노드별 IPN 번호·설정파일 유무, 접촉계획(`a contact`)의 대역폭/전파지연,
  IPN egress 경로(`a plan`), LTP span 피어 주소, BP 엔드포인트, 그리고 실행 중이라면
  현재 적재된 contact/range·induct/outduct·보관 번들(bplist)·BP 통계(bpstats).

---

## 6. 파일 구조

```
earth-mars-simulation/
├── README.md              # 본 문서
├── setup.sh               # 42 + ION-DTN 설치 스크립트
├── configure_42.py        # 42 입력파일(Inp_IPC.txt 등) 생성
├── start_ion_nodes.sh     # 4개 노드 ION admin 적용 (start/stop)
├── run_simulation.sh      # 42 + 브릿지 통합 실행 + 종료 정리
├── bridging.py            # 42(TCP)→거리/가시성 계산→tc/ionadmin 반영
├── lib_nodes.sh           # 공통 노드 매핑 + ION 실행 헬퍼 (송수신 스크립트가 source)
├── node_status.sh         # 노드 상태 확인 (정적 토폴로지 + 실시간 ION 상태)
├── send.sh                # 노드 간 텍스트/파일 송신 (bpsource/bpsendfile)
├── receive.sh             # 노드에서 번들 수신·저장 (bpsink/bprecvfile)
├── read_node.sh           # 노드에 저장/수신된 데이터 읽기 (bplist 포함)
├── space_network.imn      # CORE 토폴로지(4노드)
├── earth/                 # 노드1 지구 지상국  (ionrc/ipnrc/ltprc/bprc)
├── earth_orbit/           # 노드2 지구 위성
├── mars_orbit/            # 노드3 화성 위성
└── mars/                  # 노드4 화성 착륙선
```

---

### 참고 자료
- [d3f0/coreemu_vnc — Docker Hub](https://hub.docker.com/r/d3f0/coreemu_vnc/)
- [D3f0/coreemu_vnc — GitHub](https://github.com/D3f0/coreemu_vnc)
- [CORE Network Emulator](https://github.com/coreemu/core)
- [NASA 42 Simulator](https://github.com/ericstoneking/42)
- [NASA JPL ION-DTN](https://github.com/nasa-jpl/ION-DTN)
