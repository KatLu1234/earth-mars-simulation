#!/bin/bash
# ==============================================================================
# 노드에 저장된 데이터 읽기 스크립트
#
#   사용법:
#     ./read_node.sh <node>        # 특정 노드
#     ./read_node.sh all           # 4개 노드 전부
#
#   노드 키: earth(1) | eo(2) | mo(3) | mars(4)
#
#   출력 내용:
#     1) 수신 텍스트 로그 (inbox_text.log — receive.sh text 로 누적)
#     2) 수신 파일 목록   (testfile* — receive.sh file 로 저장)
#     3) 노드에 현재 보관 중인 번들 목록 (bplist — store-and-forward 상태)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_nodes.sh"

read_one() {
    local key="$1"
    local node core num
    node=$(resolve_node "$key")
    if [ -z "$node" ]; then
        echo "ERROR: 알 수 없는 노드 키: $key" >&2
        return 1
    fi
    core="${node%%:*}"; num="${node##*:}"
    local wd="${ION_WD_PREFIX}${core}"

    echo "================================================================"
    echo " 노드: ${core}  (ipn:${num}.${APP_SERVICE})   [데이터 위치: ${wd}]"
    echo "================================================================"

    # 1) 수신 텍스트 로그
    echo "---- [1] 수신 텍스트 (inbox_text.log) ----"
    if [ -s "${wd}/inbox_text.log" ]; then
        cat "${wd}/inbox_text.log"
    else
        echo "  (수신된 텍스트 없음)"
    fi

    # 2) 수신 파일 목록
    echo "---- [2] 수신 파일 (testfile*) ----"
    if ls "${wd}"/testfile* >/dev/null 2>&1; then
        ls -lh "${wd}"/testfile*
    else
        echo "  (수신된 파일 없음)"
    fi

    # 3) 노드에 보관 중인 번들 (store-and-forward 상태)
    echo "---- [3] 보관 중 번들 (bplist) ----"
    ion_exec "$core" "command -v bplist >/dev/null 2>&1 && bplist || echo '  (bplist 미지원 또는 보관 번들 없음)'" \
        || echo "  (조회 실패 — 해당 노드 ION 이 실행 중인지 확인)"
    echo ""
}

if [ "$#" -lt 1 ]; then
    echo "사용법: $0 <node|all>   (노드 키: earth|eo|mo|mars)" >&2
    exit 1
fi

if [ "$1" = "all" ]; then
    for k in earth eo mo mars; do
        read_one "$k"
    done
else
    read_one "$1"
fi