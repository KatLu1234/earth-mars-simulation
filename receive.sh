#!/bin/bash
# ==============================================================================
# DTN Bundle 수신 스크립트 (노드의 엔드포인트에서 번들을 받아 저장)
#
#   사용법:
#     ./receive.sh <node> text     # 텍스트 번들 수신 (bpsink) -> inbox_text.log 에 누적
#     ./receive.sh <node> file     # 파일 번들 수신 (bprecvfile) -> testfile1, 2, ...
#
#   노드 키: earth(1) | eo(2) | mo(3) | mars(4)
#
#   * 이 스크립트는 "포그라운드 리스너"입니다. 별도 터미널에서 실행하고 Ctrl+C 로 종료.
#   * 송신이 먼저 일어났어도, 번들이 노드에 저장되어 있다가 리스너 기동 시 수신됩니다.
#   * 수신 데이터는 노드 작업 디렉터리(${ION_WD_PREFIX}<CORE노드명>)에 저장되며,
#     read_node.sh 로 읽을 수 있습니다.
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_nodes.sh"

if [ "$#" -lt 2 ]; then
    echo "사용법: $0 <node> text|file   (노드 키: earth|eo|mo|mars)" >&2
    exit 1
fi

NODE_KEY="$1"; MODE="$2"
NODE=$(resolve_node "$NODE_KEY")
if [ -z "$NODE" ]; then
    echo "ERROR: 알 수 없는 노드 키. (earth|eo|mo|mars)" >&2
    exit 1
fi
CORE="${NODE%%:*}"; NUM="${NODE##*:}"
OWN_EID="ipn:${NUM}.${APP_SERVICE}"

echo "================================================================"
echo " 수신 대기: ${CORE} (${OWN_EID}) | 모드: ${MODE}"
echo " 종료하려면 Ctrl+C"
echo "================================================================"

case "$MODE" in
    text)
        # bpsink 는 수신 번들 페이로드를 stdout 으로 출력 → 화면 + 로그파일에 동시 기록
        ion_exec "$CORE" "bpsink '$OWN_EID' 2>&1 | tee -a inbox_text.log"
        ;;
    file)
        # bprecvfile 은 현재 wd(=노드 wd)에 testfile1, testfile2 ... 로 저장
        ion_exec "$CORE" "bprecvfile '$OWN_EID'"
        ;;
    *)
        echo "ERROR: MODE 는 text 또는 file 이어야 합니다. (입력: $MODE)" >&2
        exit 1
        ;;
esac