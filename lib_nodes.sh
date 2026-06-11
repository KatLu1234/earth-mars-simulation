#!/bin/bash
# ==============================================================================
# 공통 노드 매핑 + ION 실행 헬퍼 (send.sh / receive.sh / read_node.sh 가 source)
#
#  ION 멀티노드 모드에서 각 프로세스는 "현재 작업 디렉터리(wd)"로 자신이 어느
#  ION 노드인지 판별합니다. start_ion_nodes.sh 가 각 노드를 /tmp/ion_<CORE노드명>
#  에서 기동했으므로, 노드의 BP 유틸(bpsource/bpsink/...)도 반드시 같은 wd 에서
#  실행해야 해당 노드 인스턴스에 붙습니다. (ion_exec 가 이를 처리)
# ==============================================================================

# 모든 ION 노드가 공유하는 노드 목록 디렉터리 (start_ion_nodes.sh 와 동일)
export ION_NODE_LIST_DIR="/tmp/ion_nodes"

# 노드 작업/데이터 디렉터리 접두사
ION_WD_PREFIX="/tmp/ion_"

# 애플리케이션 서비스 번호 (EID = ipn:<노드번호>.<서비스>)
APP_SERVICE=1

# ------------------------------------------------------------------------------
# 노드 키 -> "CORE노드명:ION노드번호"
#   허용 키: earth/1, eo|earth_orbit/2, mo|mars_orbit/3, mars/4
# ------------------------------------------------------------------------------
resolve_node() {
    case "$1" in
        earth|earth_station|1)            echo "Earth_Station:1" ;;
        eo|earth_orbit|earth_orbiter|2)   echo "Earth_Orbiter:2" ;;
        mo|mars_orbit|mars_orbiter|3)     echo "Mars_Orbiter:3" ;;
        mars|mars_lander|4)               echo "Mars_Lander:4" ;;
        *)                                echo "" ;;
    esac
}

# 실행 중인 CORE 세션 디렉터리(/tmp/pycore.*) 탐색
find_session_dir() {
    local s
    s=$(ls -d /tmp/pycore.* 2>/dev/null | head -n1)
    if [ -z "$s" ]; then
        echo "ERROR: 실행 중인 CORE 세션(/tmp/pycore.*)이 없습니다." >&2
        echo "       먼저 CORE 토폴로지(space_network.imn)와 start_ion_nodes.sh 를 실행하세요." >&2
        return 1
    fi
    echo "$s"
}

# ------------------------------------------------------------------------------
# 특정 CORE 노드의 ION 컨텍스트(올바른 wd + ION_NODE_LIST_DIR) 안에서 명령 실행
#   $1 = CORE 노드명,  $2 = 노드 안에서 실행할 명령 문자열
# ------------------------------------------------------------------------------
ion_exec() {
    local core="$1"
    local cmd="$2"
    local session
    session="$(find_session_dir)" || return 1
    vcmd -c "$session/$core" -- bash -c \
        "export ION_NODE_LIST_DIR='$ION_NODE_LIST_DIR'; cd '${ION_WD_PREFIX}${core}' || exit 1; $cmd"
}