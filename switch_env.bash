#!/usr/bin/env bash
set -e

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename $0) goversion" 1>&2
  exit
fi

VERSION=$1

if [[ -z "${GOOS}" ]]; then
  if [ "$(uname)" = "Darwin" ]; then
    GOOS="darwin"
  elif [ "$(uname -s)" == "Linux" ]; then
    GOOS="linux"
  else
    echo "This system, $(uname), isn't supported"
    exit 1
  fi
fi

if [[ -z "${GOARCH}" ]]; then
  ARCH="$(uname -m)"
  case "${ARCH}" in
  x86_64 | amd64)
    GOARCH=amd64
    ;;
  armv8* | aarch64* | arm64)
    GOARCH=arm64
    ;;
  armv*)
    GOARCH=arm
    ;;
  i386 | i486 | i586 | i686)
    GOARCH=386
    ;;
  *)
    echo "This system's architecture, ${ARCH}, isn't supported"
    exit 1
    ;;
  esac
fi

if [[ -z "${GOPATH}" ]]; then
  GOPATH="${HOME}/go"
fi
GOROOT="${GOPATH}/go${VERSION}"

function command_exists() {
  local COMMAND="$1"
  type "${COMMAND}" >/dev/null 2>&1
}

if [[ ! -d "${GOROOT}" ]]; then
  DOWNLOADS="${GOPATH}/downloads/"
  mkdir -p "${DOWNLOADS}"
  PACK="go${VERSION}.${GOOS}-${GOARCH}.tar.gz"
  TARGET="https://dl.google.com/go/${PACK}"
  SAVE="${DOWNLOADS}/${PACK}"
  if command_exists wget; then
    wget "${TARGET}" -c -O "${SAVE}"
  elif command_exists curl; then
    curl "${TARGET}" -o "${SAVE}"
  else
    echo "No download tool available"
    exit 1
  fi
  TEMPDIR=$(mktemp -d)
  tar -zxf "${SAVE}" -C "${TEMPDIR}"
  mv "${TEMPDIR}/go" "${GOROOT}"
fi

if [[ -z "${GOBIN}" ]]; then
  GOBIN="$GOPATH/bin"
fi

PATH=$(echo "${GOROOT}/bin:${GOBIN}:${PATH}" | sed 's#//#/#g' | tr ':' '\n' | cat -n | sort -k2,2 -k1,1n | uniq -f1 | sort -k1,1n | cut -f2- | tr '\n' ':')

echo "export GOOS=${GOOS}"
echo "export GOARCH=${GOARCH}"
echo "export GOROOT=${GOROOT}"
echo "export GOPATH=${GOPATH}"
echo "export GOBIN=${GOBIN}"
echo "export PATH=${PATH}"
echo "# $(go version)"
echo "# source <($0 $1)"
