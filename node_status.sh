#!/bin/bash
# ==============================================================================
# 노드 상태 확인 도구 (지구-화성 DTN 시뮬레이션)
#
#   폴더 구조(각 노드의 ionrc/ipnrc/ltprc/bprc)를 읽어 "정적 토폴로지"를 보여주고,
#   CORE 세션이 떠 있으면 각 노드 ION 의 "실시간 상태"(contact/range/induct/plan/번들)
#   까지 함께 확인합니다.
#
#   사용법:
#     ./node_status.sh                # 전체: 정적 토폴로지 + 실시간 상태 요약
#     ./node_status.sh topo           # 정적 토폴로지만 (ION 미실행 상태에서도 동작)
#     ./node_status.sh live           # 실시간 요약(노드별 RUNNING/DOWN + 핵심 수치)
#     ./node_status.sh <node>         # 특정 노드 상세 (live 깊은 조회)
#     ./node_status.sh tree           # 프로젝트/노드 폴더 구조 출력
#
#   노드 키: earth(1) | eo(2) | mo(3) | mars(4)
# ==============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_nodes.sh"

# 노드 출력 순서:  "CORE노드명:설정디렉터리:ION노드번호"
NODES=(
    "Earth_Station:earth:1"
    "Earth_Orbiter:earth_orbit:2"
    "Mars_Orbiter:mars_orbit:3"
    "Mars_Lander:mars:4"
)

C_HDR="================================================================"
C_SUB="----------------------------------------------------------------"

# CORE 세션이 있으면 경로, 없으면 빈 문자열 (오류 출력 억제)
session_or_empty() { ls -d /tmp/pycore.* 2>/dev/null | head -n1; }

# ------------------------------------------------------------------------------
# 설정 파일 1개의 base 경로 헬퍼:  $1=설정디렉터리  $2=확장자(ionrc 등)
# ------------------------------------------------------------------------------
cfg_file() { echo "$SCRIPT_DIR/$1/$1.$2"; }

# ------------------------------------------------------------------------------
# [tree] 폴더 구조 출력
# ------------------------------------------------------------------------------
print_tree() {
    echo "$C_HDR"
    echo " 프로젝트 폴더 구조:  $SCRIPT_DIR"
    echo "$C_HDR"
    if command -v tree >/dev/null 2>&1; then
        tree -L 2 --noreport "$SCRIPT_DIR"
    else
        # tree 가 없으면 노드 설정 디렉터리를 직접 나열
        ( cd "$SCRIPT_DIR" && ls -1 *.sh *.py *.imn 2>/dev/null | sed 's/^/  /' )
        for entry in "${NODES[@]}"; do
            IFS=':' read -r core dir ipn <<< "$entry"
            echo "  $dir/   (CORE: $core, ipn:$ipn)"
            ( cd "$SCRIPT_DIR/$dir" 2>/dev/null && ls -1 | sed 's/^/      /' )
        done
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# [topo] 정적 토폴로지 — 폴더 구조의 설정 파일을 파싱해서 표시 (ION 미실행에서도 OK)
# ------------------------------------------------------------------------------
print_topology() {
    echo "$C_HDR"
    echo " 정적 토폴로지 (설정 파일 기준 — 실행 여부와 무관)"
    echo "$C_HDR"
    printf " %-15s %-12s %-6s %-10s %s\n" "CORE 노드" "설정폴더" "IPN" "설정파일" "상태"
    echo "$C_SUB"
    for entry in "${NODES[@]}"; do
        IFS=':' read -r core dir ipn <<< "$entry"
        local present="OK" missing=""
        for ext in ionrc ipnrc ltprc bprc; do
            [ -f "$(cfg_file "$dir" "$ext")" ] || missing="$missing $ext"
        done
        [ -n "$missing" ] && present="누락:$missing"
        printf " %-15s %-12s %-6s %-10s %s\n" "$core" "$dir/" "$ipn" "*.{4종}" "$present"
    done
    echo ""

    echo " [링크 / 접촉 계획]  (각 노드 ionrc 의 'a contact' / 'a range')"
    echo "$C_SUB"
    printf " %-15s %-22s %-10s %s\n" "노드(ionrc)" "구간(from->to)" "대역폭" "전파지연(range)"
    for entry in "${NODES[@]}"; do
        IFS=':' read -r core dir ipn <<< "$entry"
        local ionrc; ionrc="$(cfg_file "$dir" ionrc)"
        [ -f "$ionrc" ] || continue
        # contact:  a contact +start +end from to rate
        grep -E '^[[:space:]]*a[[:space:]]+contact' "$ionrc" 2>/dev/null | while read -r _ _ st en fr to rate _; do
            # 같은 from->to 의 range 값을 찾아 전파지연으로 표시
            local rng
            rng=$(grep -E "^[[:space:]]*a[[:space:]]+range[[:space:]]+\\${st}[[:space:]]+\\${en}[[:space:]]+${fr}[[:space:]]+${to}\b" "$ionrc" 2>/dev/null | awk '{print $6}' | head -n1)
            [ -z "$rng" ] && rng=$(grep -E "^[[:space:]]*a[[:space:]]+range" "$ionrc" | awk -v f="$fr" -v t="$to" '$5==f && $6==t {print $7}' | head -n1)
            local mbps; mbps=$(awk -v r="$rate" 'BEGIN{ if(r=="")print "-"; else printf "%g Mbps", r/1000000 }')
            printf " %-15s %-22s %-10s %s\n" "$dir" "${fr} -> ${to}" "$mbps" "${rng:-?} s"
        done
    done
    echo ""

    echo " [IPN 라우팅(egress) / 링크 서비스 주소]  (ipnrc 의 'a plan', ltprc 의 span)"
    echo "$C_SUB"
    for entry in "${NODES[@]}"; do
        IFS=':' read -r core dir ipn <<< "$entry"
        local ipnrc ltprc; ipnrc="$(cfg_file "$dir" ipnrc)"; ltprc="$(cfg_file "$dir" ltprc)"
        echo " - $core (ipn:$ipn)"
        if [ -f "$ipnrc" ]; then
            grep -E '^[[:space:]]*a[[:space:]]+plan' "$ipnrc" | awk '{printf "      egress: 목적지 ipn:%s  ->  %s\n", $3, $4}'
        fi
        if [ -f "$ltprc" ]; then
            # span:  a span <peerEngine> ... 'udplclcli IP:port'  /  '...so IP:port'
            grep -E '^[[:space:]]*a[[:space:]]+span' "$ltprc" | while read -r line; do
                local peer addr
                peer=$(echo "$line" | awk '{print $3}')
                addr=$(echo "$line" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+" | head -n1)
                printf "      LTP span: peer engine %s  ->  %s\n" "$peer" "${addr:-(주소 미지정)}"
            done
        fi
    done
    echo ""

    echo " [Bundle Protocol 엔드포인트]  (bprc 의 'a endpoint')"
    echo "$C_SUB"
    for entry in "${NODES[@]}"; do
        IFS=':' read -r core dir ipn <<< "$entry"
        local bprc; bprc="$(cfg_file "$dir" bprc)"
        [ -f "$bprc" ] || continue
        local eps
        eps=$(grep -E '^[[:space:]]*a[[:space:]]+endpoint' "$bprc" | awk '{print $3}' | paste -sd' ' -)
        printf " %-15s %s\n" "$core" "${eps:-(없음)}"
    done
    echo ""
}

# ------------------------------------------------------------------------------
# 한 노드의 ION 이 살아있는지 빠르게 판정 (RUNNING/DOWN)
# ------------------------------------------------------------------------------
node_alive() {
    local core="$1" out
    out=$(ion_exec "$core" "echo 'l contact' | ionadmin 2>&1" 2>/dev/null)
    if [ -z "$out" ]; then
        echo "UNKNOWN"
    elif echo "$out" | grep -qiE "can'?t attach|not been initialized|no such|cannot locate"; then
        echo "DOWN"
    else
        echo "RUNNING"
    fi
}

# ------------------------------------------------------------------------------
# [live] 실시간 상태 요약 — 노드별 RUNNING/DOWN + 핵심 수치
# ------------------------------------------------------------------------------
print_live_summary() {
    local session; session="$(session_or_empty)"
    echo "$C_HDR"
    echo " 실시간 상태 요약"
    echo "$C_HDR"
    if [ -z "$session" ]; then
        echo " CORE 세션(/tmp/pycore.*) 없음 — ION 이 아직 기동되지 않았습니다."
        echo " (CORE 토폴로지 실행 + start_ion_nodes.sh / run_simulation.sh 후 다시 확인)"
        echo ""
        return
    fi
    echo " CORE 세션:          $session"
    echo " ION 노드목록 DIR:   $ION_NODE_LIST_DIR  $( [ -d "$ION_NODE_LIST_DIR" ] && echo '(존재)' || echo '(없음)')"
    echo "$C_SUB"
    printf " %-15s %-9s %-9s %-9s %s\n" "노드" "ION" "접촉건수" "보관번들" "작업디렉터리"
    echo "$C_SUB"
    for entry in "${NODES[@]}"; do
        IFS=':' read -r core dir ipn <<< "$entry"
        local wd="${ION_WD_PREFIX}${core}"
        local state contacts bundles
        state=$(node_alive "$core")
        if [ "$state" = "RUNNING" ]; then
            contacts=$(ion_exec "$core" "echo 'l contact' | ionadmin 2>/dev/null | grep -cE 'From|contact'" 2>/dev/null | tail -n1)
            bundles=$(ion_exec "$core" "command -v bplist >/dev/null 2>&1 && bplist 2>/dev/null | grep -ciE 'bundle' || echo 0" 2>/dev/null | tail -n1)
        else
            contacts="-"; bundles="-"
        fi
        printf " %-15s %-9s %-9s %-9s %s\n" "$core" "$state" "${contacts:-?}" "${bundles:-?}" "$wd"
    done
    echo ""
    echo " * 상세 조회:  ./node_status.sh <earth|eo|mo|mars>"
    echo ""
}

# ------------------------------------------------------------------------------
# [<node>] 단일 노드 상세 (live 깊은 조회)
# ------------------------------------------------------------------------------
print_node_detail() {
    local key="$1"
    local node core ipn
    node=$(resolve_node "$key")
    if [ -z "$node" ]; then
        echo "ERROR: 알 수 없는 노드 키: $key  (earth|eo|mo|mars)" >&2
        return 1
    fi
    core="${node%%:*}"; ipn="${node##*:}"
    local wd="${ION_WD_PREFIX}${core}"

    echo "$C_HDR"
    echo " 노드 상세:  $core  (ipn:${ipn}.${APP_SERVICE})   [wd: $wd]"
    echo "$C_HDR"

    local session; session="$(session_or_empty)"
    if [ -z "$session" ]; then
        echo " CORE 세션이 없어 실시간 조회 불가 — 정적 설정만 표시합니다."
        echo "$C_SUB"
        local dir; dir="$core"
        case "$core" in
            Earth_Station) dir=earth ;; Earth_Orbiter) dir=earth_orbit ;;
            Mars_Orbiter) dir=mars_orbit ;; Mars_Lander) dir=mars ;;
        esac
        for ext in ionrc ltprc bprc ipnrc; do
            local f; f="$(cfg_file "$dir" "$ext")"
            echo "----- $dir/$dir.$ext -----"
            [ -f "$f" ] && cat "$f" || echo "  (파일 없음)"
            echo ""
        done
        return
    fi

    local state; state=$(node_alive "$core")
    echo " ION 상태: $state"
    if [ "$state" != "RUNNING" ]; then
        echo " (이 노드 ION 이 기동되지 않았습니다. start_ion_nodes.sh start 후 재시도)"
        echo ""
        return
    fi

    ion_exec "$core" "
        echo '----- [contacts] ionadmin l contact -----'
        echo 'l contact' | ionadmin 2>&1
        echo
        echo '----- [ranges] ionadmin l range -----'
        echo 'l range' | ionadmin 2>&1
        echo
        echo '----- [bp inducts/outducts/endpoints] bpadmin -----'
        printf 'l induct\nl outduct\nl endpoint\n' | bpadmin 2>&1
        echo
        echo '----- [ipn egress plans] ipnadmin l plan -----'
        echo 'l plan' | ipnadmin 2>&1
        echo
        echo '----- [ltp spans] ltpadmin l span -----'
        echo 'l span' | ltpadmin 2>&1
        echo
        echo '----- [보관 중 번들] bplist (최대 40줄) -----'
        command -v bplist >/dev/null 2>&1 && bplist 2>&1 | head -n 40 || echo '  (bplist 미지원/번들 없음)'
        echo
        echo '----- [BP 통계] bpstats (최대 30줄) -----'
        command -v bpstats >/dev/null 2>&1 && bpstats 2>&1 | head -n 30 || echo '  (bpstats 미지원)'
    "
    echo ""
}

# ==============================================================================
# 메인
# ==============================================================================
ACTION="${1:-all}"
case "$ACTION" in
    tree)        print_tree ;;
    topo)        print_topology ;;
    live)        print_live_summary ;;
    all)         print_topology; print_live_summary ;;
    earth|earth_station|1|eo|earth_orbit|earth_orbiter|2|mo|mars_orbit|mars_orbiter|3|mars|mars_lander|4)
                 print_node_detail "$ACTION" ;;
    -h|--help|help)
                 sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
                 echo "사용법: $0 [all|topo|live|tree|<node>]" >&2
                 echo "  노드 키: earth|eo|mo|mars" >&2
                 exit 1 ;;
esac
