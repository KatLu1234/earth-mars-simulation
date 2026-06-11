#!/bin/bash
# ==============================================================================
# CORE Docker 컨테이너 내부용 우주 통신 시뮬레이션 환경 구축 스크립트
# 구성 요소: Python3, NASA 42 Simulator, ION-DTN (Bundle Protocol)
# ==============================================================================

set -e # 에러 발생 시 즉시 중단

echo "[1/4] 시스템 패키지 업데이트 및 기본 필수 도구 설치..."
apt-get update && apt-get install -y \\
    git \\
    build-essential \\
    cmake \\
    curl \\
    wget \\
    libssl-dev \\
    tcl-dev \\
    freeglut3-dev \\
    libgl1-mesa-dev \\
    libglu1-mesa-dev \\
    iptables \\
    iproute2

echo "[2/4] Python3 및 개발/네트워크 라이브러리 설치..."
apt-get install -y python3 python3-pip python3-tk
# 브릿지 스크립트 작성 및 데이터 분석용 필수 패키지 설치
pip3 install --upgrade pip

echo "[3/4] NASA 42 Simulator 설치 및 컴파일..."
cd /root
if [ ! -d "42" ]; then
    git clone https://github.com/ericstoneking/42.git
fi
cd 42
make
echo "=> 42 Simulator 설치 완료 (위치: /root/42/42)"

echo "[4/4] NASA JPL ION-DTN 설치 및 컴파일..."
cd /root
# 안정 버전 다운로드 (버전은 필요에 따라 변경 가능)
ION_VERSION="4.1.2"
if [ ! -f "ion-${ION_VERSION}.tar.gz" ]; then
    wget https://sourceforge.net/projects/ion-dtn/files/ion-${ION_VERSION}.tar.gz
fi

if [ ! -d "ion-${ION_VERSION}" ]; then
    tar -xvf ion-${ION_VERSION}.tar.gz
fi

cd list-ion-* 2>/dev/null || cd ion-${ION_VERSION}
./configure
make
make install
ldconfig
echo "=> ION-DTN 설치 완료 (ionadmin 명령어 사용 가능)"

echo "=============================================================================="
echo " 모든 환경 구성이 완료되었습니다!"
echo " - 42 실행 파일: /root/42/42"
echo " - ION-DTN 검증: 'ionadmin'을 입력하여 셸이 정상 작동하는지 확인하세요."
echo "=============================================================================="