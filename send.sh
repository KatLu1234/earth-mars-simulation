#!/bin/bash
# ==============================================================================
# DTN Bundle 송신 스크립트 (텍스트 또는 파일)
#
#   사용법:
#     ./send.sh <from> <to> text "<보낼 메시지>"
#     ./send.sh <from> <to> file <파일경로>
#
#   노드 키: earth(1) | eo(2) | mo(3) | mars(4)
#
#   예시:
#     # 지구 -> 화성 텍스트
#     ./send.sh earth mars text "Hello Mars from Earth"
#     # 화성 -> 지구 파일
#     ./send.sh mars earth file /root/shared/report.bin
#
#   * bpsource(텍스트) / bpsendfile(파일) 로 번들을 생성합니다.
#   * 수신측에서 받는 앱이 없어도 번들은 노드 SDR 에 저장(store-and-forward)되며,
#     링크가 연결되면 다음 홉으로 전달됩니다.
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_nodes.sh"

if [ "$#" -lt 4 ]; then
    echo "사용법: $0 <from> <to> text \"<메시지>\"" >&2
    echo "        $0 <from> <to> file <파일경로>" >&2
    echo "  노드 키: earth(1) | eo(2) | mo(3) | mars(4)" >&2
    exit 1
fi

FROM_KEY="$1"; TO_KEY="$2"; MODE="$3"; PAYLOAD="$4"

FROM=$(resolve_node "$FROM_KEY"); TO=$(resolve_node "$TO_KEY")
if [ -z "$FROM" ] || [ -z "$TO" ]; then
    echo "ERROR: 알 수 없는 노드 키. (earth|eo|mo|mars)" >&2
    exit 1
fi
FROM_CORE="${FROM%%:*}"; FROM_NUM="${FROM##*:}"
TO_CORE="${TO%%:*}";     TO_NUM="${TO##*:}"

SRC_EID="ipn:${FROM_NUM}.${APP_SERVICE}"
DST_EID="ipn:${TO_NUM}.${APP_SERVICE}"

echo "================================================================"
echo " 송신: ${FROM_CORE}(${SRC_EID})  ->  ${TO_CORE}(${DST_EID})"
echo "================================================================"

case "$MODE" in
    text)
        # 메시지를 송신 노드 wd 에 임시 파일로 쓴 뒤 stdin 으로 주입
        # (명령줄에 사용자 텍스트를 직접 넣지 않아 따옴표/특수문자 안전)
        TMP="${ION_WD_PREFIX}${FROM_CORE}/.send_msg.txt"
        printf '%s' "$PAYLOAD" > "$TMP"
        echo "[텍스트] \"$PAYLOAD\""
        ion_exec "$FROM_CORE" "bpsource '$DST_EID' < '$TMP'"
        echo "[✓] 텍스트 번들 송신 완료."
        ;;
    file)
        if [ ! -f "$PAYLOAD" ]; then
            echo "ERROR: 파일을 찾을 수 없습니다: $PAYLOAD" >&2
            exit 1
        fi
        echo "[파일] $PAYLOAD ($(stat -c%s "$PAYLOAD" 2>/dev/null || echo '?') bytes)"
        # bpsendfile <source EID> <dest EID> <file> 는 파일을 그대로 읽으므로
        # 절대경로면 어느 wd 에서 실행해도 무방.
        ion_exec "$FROM_CORE" "bpsendfile '$SRC_EID' '$DST_EID' '$PAYLOAD'"
        echo "[✓] 파일 번들 송신 완료."
        ;;
    *)
        echo "ERROR: MODE 는 text 또는 file 이어야 합니다. (입력: $MODE)" >&2
        exit 1
        ;;
esac