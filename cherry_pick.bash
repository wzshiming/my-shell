#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

TMP_DIR="${TMPDIR:-/tmp/}"
SITE="https://github.com"
STARTING_BRANCH="$(git symbolic-ref --short HEAD)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
REBASE_APPLY="${REPO_ROOT}/.git/rebase-apply"
MAIN_REMOTE="${MAIN_REMOTE:-upstream}"
FORK_REMOTE="${FORK_REMOTE:-origin}"
FORK_REPO_ORG="${FORK_REPO_ORG:-$(git remote get-url "$FORK_REMOTE" | awk '{gsub(/http[s]:\/\/|git@/,"")}1' | awk -F'[@:./]' 'NR==1{print $3}')}"
FORK_REPO_NAME="${FORK_REPO_NAME:-$(git remote get-url "$FORK_REMOTE" | awk '{gsub(/http[s]:\/\/|git@/,"")}1' | awk -F'[@:./]' 'NR==1{print $4}')}"
MAIN_REPO_ORG="${MAIN_REPO_ORG:-$(git remote get-url "$MAIN_REMOTE" | awk '{gsub(/http[s]:\/\/|git@/,"")}1' | awk -F'[@:./]' 'NR==1{print $3}')}"
MAIN_REPO_NAME="${MAIN_REPO_NAME:-$(git remote get-url "$MAIN_REMOTE" | awk '{gsub(/http[s]:\/\/|git@/,"")}1' | awk -F'[@:./]' 'NR==1{print $4}')}"

if [[ "$#" -lt 2 ]]; then
    echo "${0} <remote branch> <pr-number>...: cherry pick one or more <pr> onto <remote branch> and leave instructions for proposing pull request"
    echo
    echo "  Checks out <remote branch> and handles the cherry-pick of <pr> (possibly multiple) for you."
    echo "  Examples:"
    echo "    $0 upstream/release-3.14 12345        # Cherry-picks PR 12345 onto upstream/release-3.14 and proposes that as a PR."
    echo "    $0 upstream/release-3.14 12345 56789  # Cherry-picks PR 12345, then 56789 and proposes the combination as a single PR."
    echo
    echo "  Set MAIN_REMOTE (default: upstream) and FORK_REMOTE (default: origin)"
    echo "  to override the default remote names to what you have locally."
    exit 2
fi

if git_status=$(git status --porcelain --untracked=no 2>/dev/null) && [[ -n "${git_status}" ]]; then
    echo "!!! Dirty tree. Clean up and try again."
    exit 1
fi

if [[ -e "${REBASE_APPLY}" ]]; then
    echo "!!! 'git rebase' or 'git am' in progress. Clean up and try again."
    exit 1
fi

cd "${REPO_ROOT}"

BRANCH="$1"
shift 1
PULLS=("$@")

function join() {
    IFS="$1"
    shift
    echo "$*"
}
PULLDASH=$(join - "${PULLS[@]/#/#}")   # Generates something like "#12345-#56789"
PULLSUBJ=$(join " " "${PULLS[@]/#/#}") # Generates something like "#12345 #56789"

NEW_BRANCH="$(echo "cherry-pick/${BRANCH}/${PULLDASH}")"
NEW_BRANCH_UNIQ="${NEW_BRANCH}-$(date +%s)"
UPSTREAM_REMOTE_BRAMCH="${BRANCH#*/}"

function make-a-pr() {
    NUM_AND_TITLE="${SUBJECTS[@]}"

    TITLE="$(echo "[${UPSTREAM_REMOTE_BRAMCH}] Cherry pick of ${NUM_AND_TITLE}" | sed 's/#/%23/g' | sed 's/ /+/g' | sed 's/\n/%0A/g')"
    BODY="$(echo "Cherry pick of ${PULLSUBJ} on ${UPSTREAM_REMOTE_BRAMCH}.\n\n${NUM_AND_TITLE}\n" | sed 's/#/%23/g' | sed 's/ /+/g' | sed 's/\\n/%0A/g')"
    PR_URL="${SITE}/${MAIN_REPO_ORG}/${MAIN_REPO_NAME}/compare/${UPSTREAM_REMOTE_BRAMCH}...${FORK_REPO_ORG}:$(echo "$NEW_BRANCH" | sed 's/#/%23/g')?expand=1&title=${TITLE}&body=${BODY}"

    echo
    echo "+++ Creating a pull request on GitHub at ${FORK_REPO_ORG}:${NEW_BRANCH}"
    echo
    echo "  open '$PR_URL'"
    echo
    read -p "+++ Proceed (anything but 'y' aborts the open in browser)? [y/n] " -r
    if ! [[ "${REPLY}" =~ ^[yY]$ ]]; then
        echo "Aborting." >&2
        exit 1
    fi
    open "$PR_URL"
}

echo "+++ Updating remotes..."
git remote update "${MAIN_REMOTE}" "${FORK_REMOTE}"

if ! git log -n1 --format=%H "${BRANCH}" >/dev/null 2>&1; then
    echo "!!! '${BRANCH}' not found. The second argument should be something like ${MAIN_REMOTE}/release-0.21."
    echo "    (In particular, it needs to be a valid, existing remote branch that I can 'git checkout'.)"
    exit 1
fi

echo "+++ Creating local branch ${NEW_BRANCH_UNIQ}"

GIT_AM_CLEANUP=false
function return_to_kansas() {
    if [[ "${GIT_AM_CLEANUP}" == "true" ]]; then
        echo
        echo "+++ Aborting in-progress git am."
        git am --abort >/dev/null 2>&1 || true
    fi

    # return to the starting branch and delete the PR text file
    echo
    echo "+++ Returning you to the ${STARTING_BRANCH} branch and cleaning up."
    git checkout -f "${STARTING_BRANCH}" >/dev/null 2>&1 || true
    git branch -D "${NEW_BRANCH_UNIQ}" >/dev/null 2>&1 || true
}
trap return_to_kansas EXIT

SUBJECTS=()

echo git checkout -b "${NEW_BRANCH_UNIQ}" "${BRANCH}"
git checkout -b "${NEW_BRANCH_UNIQ}" "${BRANCH}"

GIT_AM_CLEANUP=true
for PULL in "${PULLS[@]}"; do
    TMP_PATCH="${TMP_DIR}/${PULL}.patch"

    echo "+++ Downloading patch to ${TMP_PATCH} (in case you need to do this again)"
    curl -o "${TMP_PATCH}" -sSL "${SITE}/${MAIN_REPO_ORG}/${MAIN_REPO_NAME}/pull/${PULL}.patch"
    echo
    echo "+++ About to attempt cherry pick of PR. To reattempt:"
    echo "  $ git am -3 ${TMP_PATCH}"
    echo
    git am -3 "${TMP_PATCH}" || {
        CONFLICTS=false
        while UNMERGED=$(git status --porcelain | grep ^U) && [[ -n ${UNMERGED} ]] || [[ -e "${REBASE_APPLY}" ]]; do
            CONFLICTS=true # <-- We should have detected conflicts once
            echo
            echo "+++ Conflicts detected:"
            echo
            (git status --porcelain | grep ^U) || echo "!!! None. Did you git am --continue?"
            echo
            echo "+++ Please resolve the conflicts in another window (and remember to 'git add / git am --continue')"
            read -p "+++ Proceed (anything but 'y' aborts the cherry-pick)? [y/n] " -r
            echo
            if ! [[ "${REPLY}" =~ ^[yY]$ ]]; then
                echo "Aborting." >&2
                exit 1
            fi
        done

        if [[ "${CONFLICTS}" != "true" ]]; then
            echo "!!! git am failed, likely because of an in-progress 'git am' or 'git rebase'"
            exit 1
        fi
    }

    # set the subject
    SUBJECT=$(grep -m 1 "^Subject" "${TMP_PATCH}" | sed -e 's/Subject: \[PATCH//g' | sed 's/.*] //')
    SUBJECTS+=("#${PULL}: ${SUBJECT}")

    # remove the patch file from /tmp
    rm -f "${TMP_PATCH}"
done
GIT_AM_CLEANUP=false

if git remote -v | grep ^"${FORK_REMOTE}" | grep "${MAIN_REPO_ORG}/${MAIN_REPO_NAME}"; then
    echo "!!! You have ${FORK_REMOTE} configured as your ${MAIN_REPO_ORG}/${MAIN_REPO_NAME}"
    echo "This isn't normal. Leaving you with push instructions:"
    echo
    echo "+++ First manually push the branch this script created:"
    echo
    echo "  git push REMOTE ${NEW_BRANCH_UNIQ}:${NEW_BRANCH}"
    echo
    echo "where REMOTE is your personal fork (maybe ${MAIN_REMOTE}? Consider swapping those.)."
    echo "OR consider setting MAIN_REMOTE and FORK_REMOTE to different values."
    echo
    make-a-pr
    exit 0
fi

echo
echo "+++ I'm about to do the following to push to GitHub (and I'm assuming ${FORK_REMOTE} is your personal fork):"
echo
echo "  git push ${FORK_REMOTE} ${NEW_BRANCH_UNIQ}:${NEW_BRANCH}"
echo
read -p "+++ Proceed (anything but 'y' aborts the cherry-pick)? [y/n] " -r
if ! [[ "${REPLY}" =~ ^[yY]$ ]]; then
    echo "Aborting." >&2
    exit 1
fi

git push "${FORK_REMOTE}" -f "${NEW_BRANCH_UNIQ}:${NEW_BRANCH}"
make-a-pr
