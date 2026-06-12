#!/bin/bash
# ==============================================================================
# CORE Docker 컨테이너 내부용 우주 통신 시뮬레이션 환경 구축 스크립트
# 구성 요소: Python3, NASA 42 Simulator, ION-DTN (Bundle Protocol)
#
#   * coreemu(예: d3f0/coreemu_vnc) 컨테이너 안에서 root 로 실행하는 것을 전제로 합니다.
#     sudo 가 없거나 root 가 아닌 환경에서도 동작하도록 SUDO 변수를 자동 선택합니다.
# ==============================================================================

set -euo pipefail # 에러/미정의 변수/파이프 실패 시 즉시 중단

# apt/dpkg 가 설치 중 tzdata 등에서 대화형 프롬프트로 멈추지 않도록 함 (docker 빌드 무한대기 방지)
export DEBIAN_FRONTEND=noninteractive

# root 가 아니면 sudo 를 앞에 붙임 (root 면 빈 값)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# 스크립트 자신이 위치한 디렉토리 (이후 cd 로 작업 경로가 바뀌어도 유지)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설치 작업 디렉터리 (root 홈이 없을 수도 있으므로 보정)
WORK_DIR="${HOME:-/root}"
mkdir -p "$WORK_DIR"

echo "[0/4] 시뮬레이션 셸 스크립트에 실행 권한 부여..."
chmod +x "$SCRIPT_DIR"/*.sh

echo "[1/4] 시스템 패키지 업데이트 및 기본 필수 도구 설치..."
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends apt-transport-https ca-certificates
$SUDO apt-get install -y --no-install-recommends \
    git \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    cmake \
    curl \
    wget \
    libssl-dev \
    tcl-dev \
    freeglut3-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    iptables \
    iproute2

echo "[2/4] Python3 및 개발/네트워크 라이브러리 설치..."
$SUDO apt-get install -y --no-install-recommends python3 python3-pip python3-tk
# bridging.py / configure_42.py 는 표준 라이브러리만 사용하므로 추가 pip 패키지는 불필요.
# pip 업그레이드는 실패해도 시뮬레이션에 영향이 없으므로 비치명적으로 처리.
pip3 install --upgrade pip 2>/dev/null \
    || pip3 install --upgrade pip --break-system-packages 2>/dev/null \
    || echo "  (pip 업그레이드 생략 — 시뮬레이션에는 영향 없음)"

echo "[3/4] NASA 42 Simulator 설치 및 컴파일..."
cd "$WORK_DIR"
if [ ! -d "42" ]; then
    git clone --depth 1 https://github.com/ericstoneking/42.git
fi
cd 42
make
echo "=> 42 Simulator 설치 완료 (위치: $WORK_DIR/42/42)"

echo "[4/4] NASA JPL ION-DTN (GitHub) 설치 및 컴파일..."
cd "$WORK_DIR"
# 공식 GitHub 저장소에서 안정 릴리스 태그를 받아옴 (sourceforge 대신)
#   저장소: https://github.com/nasa-jpl/ION-DTN
#   릴리스 태그 형식: ion-open-source-X.Y.Z  (필요 시 변경)
ION_REPO="https://github.com/nasa-jpl/ION-DTN.git"
ION_TAG="ion-open-source-4.1.3s"
ION_DIR="ION-DTN"

if [ ! -d "$ION_DIR" ]; then
    git clone --depth 1 --branch "$ION_TAG" "$ION_REPO" "$ION_DIR"
fi
cd "$ION_DIR"

# git 체크아웃에는 (tarball 과 달리) configure 스크립트가 포함되어 있지 않으므로
# autotools 로 직접 생성한다. autogen.sh 가 있으면 우선 사용.
if [ -x "./autogen.sh" ]; then
    ./autogen.sh
elif [ ! -x "./configure" ]; then
    autoreconf -fi
fi

./configure
make
$SUDO make install
$SUDO ldconfig
echo "=> ION-DTN 설치 완료 (ionadmin 명령어 사용 가능)"

echo "=============================================================================="
echo " 모든 환경 구성이 완료되었습니다!"
echo " - 42 실행 파일: $WORK_DIR/42/42"
echo " - ION-DTN 검증: 'ionadmin'을 입력하여 셸이 정상 작동하는지 확인하세요."
echo "=============================================================================="