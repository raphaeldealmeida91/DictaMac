#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly DERIVED_DATA_PATH="${HOME}/Library/Caches/DictaMac-Codex-DD"
readonly BUILT_APPLICATION="${DERIVED_DATA_PATH}/Build/Products/Release/DictaMac.app"
readonly INSTALLED_APPLICATION="/Applications/DictaMac.app"
readonly BUNDLE_IDENTIFIER="com.raphaeldealmeida.DictaMac"
typeset -g INCREMENT_BUILD=false

parse_arguments() {
    for argument in "$@"; do
        case "${argument}" in
            --increment-build) INCREMENT_BUILD=true ;;
            --help)
                print "Usage : ./scripts/install.sh [--increment-build]"
                exit 0
                ;;
            *)
                print -u2 "Option inconnue : ${argument}"
                exit 2
                ;;
        esac
    done
}

increment_build_number() {
    [[ "${INCREMENT_BUILD}" == true ]] || return
    print "Incrément du numéro de build…"
    (cd "${PROJECT_DIRECTORY}" && xcrun agvtool next-version -all)
}

ensure_build_is_available() {
    if pgrep -x xcodebuild >/dev/null; then
        print -u2 "Un autre xcodebuild est en cours. Réessayez après sa fin."
        exit 1
    fi
}

build_application() {
    print "Compilation Release de DictaMac…"
    taskpolicy -b xcodebuild \
        -project "${PROJECT_DIRECTORY}/DictaMac.xcodeproj" \
        -scheme DictaMac \
        -configuration Release \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        -jobs 4 \
        build
}

stop_installed_application() {
    if ! pgrep -x DictaMac >/dev/null; then
        return
    fi

    print "Fermeture de DictaMac…"
    osascript -e "tell application id \"${BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x DictaMac >/dev/null || return
        sleep 0.25
    done
    pkill -TERM -x DictaMac
}

copy_application() {
    if [[ ! -d "${BUILT_APPLICATION}" ]]; then
        print -u2 "Application Release introuvable : ${BUILT_APPLICATION}"
        exit 1
    fi

    print "Installation dans ${INSTALLED_APPLICATION}…"
    if [[ -w /Applications ]]; then
        rm -rf "${INSTALLED_APPLICATION}"
        ditto "${BUILT_APPLICATION}" "${INSTALLED_APPLICATION}"
    else
        sudo rm -rf "${INSTALLED_APPLICATION}"
        sudo ditto "${BUILT_APPLICATION}" "${INSTALLED_APPLICATION}"
    fi
}

launch_application() {
    open "${INSTALLED_APPLICATION}"
    print "DictaMac est installé et relancé."
}

parse_arguments "$@"
ensure_build_is_available
increment_build_number
build_application
stop_installed_application
copy_application
launch_application
