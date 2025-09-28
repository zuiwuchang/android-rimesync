#!/usr/bin/env bash
set -e

if [[ "$Command" == "" ]];then
    Command="$0"
fi

function help(){
    echo "android build helper"
    echo
    echo "Usage:"
    echo "  $Command [flags]"
    echo
    echo "Flags:"
    echo "  -a, --apk         build apk default appbundle"
    echo "  -d, --debug       build debug default release"
    echo "  -p, --profile     build profile default release"
}
ARGS=`getopt -o hadp --long help,apk,debug,profile -n "$Command" -- "$@"`
eval set -- "${ARGS}"
output=appbundle
mode="--release"
while true
do
    case "$1" in
        -h|--help)
            help
            exit 0
        ;;
        -a|--apk)
            output=apk
            shift
        ;;
        -d|--debug)
            mode="--debug"
            shift
        ;;
        -p|--profile)
            mode="--profile"
            shift
        ;;
        --)
            shift
            break
        ;;
        *)
            echo Error: unknown flag "$1" for "$Command"
            echo "Run '$Command --help' for usage."
            exit 1
        ;;
    esac
done

args=(
    flutter build
    $output
    $mode
)
exec="${args[@]}"
echo $exec
eval "$exec"

mkdir bin -p

cp build/app/outputs/flutter-apk/app-release.apk bin/rimesync.apk
du bin/rimesync.apk -h
sha256sum bin/rimesync.apk > bin/rimesync.apk.sha256.txt
cat bin/rimesync.apk.sha256.txt