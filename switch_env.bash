#!/usr/bin/env bash
set -e

if [[ $# -lt 1  ]]; then
    echo "Usage: $(basename $0) goversion" 1>&2
    exit
fi

VERSION=$1

if [[ -z "${GOOS}"  ]]; then
    GOOS="linux"
fi

if [[ -z "${GOARCH}"  ]]; then
    GOARCH="amd64"
fi

if [[ -z "${GOPATH}" ]]; then
    GOPATH="${HOME}/go"
fi
GOROOT="${GOPATH}/go${VERSION}"

PACK="go${VERSION}.${GOOS}-${GOARCH}.tar.gz"
DOWNLOADS="${GOPATH}/downloads/"
if [[ ! -d "${GOROOT}"  ]]; then
    wget "https://dl.google.com/go/${PACK}" -c -P ${DOWNLOADS}
    TEMPDIR=$(mktemp -d)
    tar -zxf "${DOWNLOADS}/${PACK}" -C "${TEMPDIR}"
    mv "${TEMPDIR}/go" "${GOROOT}"
fi

if [[ -z "${GOBIN}"  ]]; then
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
echo "# source <($(basename $0) $1)"
