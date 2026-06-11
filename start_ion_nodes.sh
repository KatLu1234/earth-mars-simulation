#!/bin/bash
# ==============================================================================
# 4개 CORE 노드 각각의 ION-DTN admin 프로그램에 설정 파일을 적용하는 스크립트
#
#   적용 순서 (노드별):
#     1) ionadmin  <node>.ionrc  : ION 초기화 + contact/range plan
#     2) ltpadmin  <node>.ltprc  : LTP 엔진/span (UDP 링크 계층)
#     3) bpadmin   <node>.bprc   : Bundle Protocol induct/outduct (+ 시작)
#     4) ipnadmin  <node>.ipnrc  : IPN egress plan (다음 홉 라우팅)
#
#   * 한 호스트에서 여러 ION 노드를 동시에 구동하므로 ION 멀티노드 모드
#     (ION_NODE_LIST_DIR 공유)를 사용합니다. CORE 가상 노드는 네트워크
#     네임스페이스만 분리하고 SysV IPC(공유메모리)는 공유하기 때문입니다.
#   * 각 admin 명령은 vcmd 를 통해 해당 CORE 노드 내부에서 실행됩니다.
#
#   사용법:
#     ./start_ion_nodes.sh           # 4개 노드 ION 기동 (기본값: start)
#     ./start_ion_nodes.sh start
#     ./start_ion_nodes.sh stop      # 4개 노드 ION 종료 및 공유메모리 정리
# ==============================================================================

set -e

# 스크립트가 위치한 디렉터리 (설정 파일들의 기준 경로)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 모든 ION 노드가 공유하는 노드 목록 디렉터리 (멀티노드 모드 필수)
export ION_NODE_LIST_DIR="/tmp/ion_nodes"

# 노드 매핑  ->  "CORE노드명:설정디렉터리:설정파일베이스명"
NODES=(
    "Earth_Station:earth:earth"
    "Earth_Orbiter:earth_orbit:earth_orbit"
    "Mars_Orbiter:mars_orbit:mars_orbit"
    "Mars_Lander:mars:mars"
)

# ------------------------------------------------------------------------------
# 실행 중인 CORE 세션 디렉터리 (/tmp/pycore.*) 탐색
# ------------------------------------------------------------------------------
find_session_dir() {
    local s
    s=$(ls -d /tmp/pycore.* 2>/dev/null | head -n1)
    if [ -z "$s" ]; then
        echo "ERROR: 실행 중인 CORE 세션(/tmp/pycore.*)을 찾을 수 없습니다." >&2
        echo "       먼저 CORE에서 space_network.imn 토폴로지를 실행하세요." >&2
        exit 1
    fi
    echo "$s"
}

# ------------------------------------------------------------------------------
# 단일 노드 ION 기동
#   $1=CORE노드명  $2=설정디렉터리  $3=설정파일베이스명  $4=세션디렉터리
# ------------------------------------------------------------------------------
start_node() {
    local core_name="$1" dir="$2" base="$3" session="$4"
    local cfg="$SCRIPT_DIR/$dir"
    local node_path="$session/$core_name"

    echo "==================================================================="
    echo "[$core_name] ION 노드 기동 (설정: $dir/)"
    echo "==================================================================="

    # vcmd 로 해당 CORE 노드 내부에서 admin 들을 순차 실행.
    # ION_NODE_LIST_DIR 와 노드별 작업 디렉터리(로그용)를 설정한 뒤 적용.
    vcmd -c "$node_path" -- bash -c "
        set -e
        export ION_NODE_LIST_DIR='$ION_NODE_LIST_DIR'
        mkdir -p \"\$ION_NODE_LIST_DIR\"
        mkdir -p '/tmp/ion_$core_name'
        cd '/tmp/ion_$core_name'

        echo '  -> ionadmin (ION 초기화 + contact plan)'
        ionadmin '$cfg/$base.ionrc'

        echo '  -> ltpadmin (LTP 엔진/span)'
        ltpadmin '$cfg/$base.ltprc'

        echo '  -> bpadmin  (Bundle Protocol induct/outduct + start)'
        bpadmin  '$cfg/$base.bprc'

        echo '  -> ipnadmin (IPN egress plan)'
        ipnadmin '$cfg/$base.ipnrc'
    "
    echo "[$core_name] 완료."
    echo ""
}

# ------------------------------------------------------------------------------
# 단일 노드 ION 종료
# ------------------------------------------------------------------------------
stop_node() {
    local core_name="$1" session="$2"
    local node_path="$session/$core_name"

    echo "[$core_name] ION 종료 중..."
    # ionstop 가 있으면 사용, 없으면 admin 들을 역순으로 정지 후 killm 으로 공유메모리 정리
    vcmd -c "$node_path" -- bash -c "
        export ION_NODE_LIST_DIR='$ION_NODE_LIST_DIR'
        cd '/tmp/ion_$core_name' 2>/dev/null || true
        if command -v ionstop >/dev/null 2>&1; then
            ionstop
        else
            bpadmin  . 2>/dev/null || true
            ltpadmin . 2>/dev/null || true
            ionadmin . 2>/dev/null || true
            killm     2>/dev/null || true
        fi
    " || true
    echo "[$core_name] 종료 완료."
}

# ==============================================================================
# 메인
# ==============================================================================
ACTION="${1:-start}"
SESSION_DIR="$(find_session_dir)"
echo "CORE 세션 디렉터리: $SESSION_DIR"
echo "ION 노드 목록 디렉터리: $ION_NODE_LIST_DIR"
echo ""

case "$ACTION" in
    start)
        for entry in "${NODES[@]}"; do
            IFS=':' read -r core_name dir base <<< "$entry"
            start_node "$core_name" "$dir" "$base" "$SESSION_DIR"
        done
        echo "==================================================================="
        echo " 4개 노드 ION 기동 완료."
        echo " 검증 예시: vcmd -c $SESSION_DIR/Earth_Station -- bpadmin"
        echo "==================================================================="
        ;;
    stop)
        for entry in "${NODES[@]}"; do
            IFS=':' read -r core_name dir base <<< "$entry"
            stop_node "$core_name" "$SESSION_DIR"
        done
        echo "4개 노드 ION 종료 완료."
        ;;
    *)
        echo "사용법: $0 [start|stop]" >&2
        exit 1
        ;;
esac