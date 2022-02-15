#!/usr/bin/env bash
set -eo pipefail

main() {
	parse_arguments "$@"
}

parse_arguments() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-l | --local)
				ARGS_LOCAL=1
				;;
			-h | --help)
				usage
				exit 0
				;;
		esac
		shift
	done
}

usage() {
	echo "Syntax: transactional-update [options] command"
	echo ""
	echo "Applies package updates to a new snapshot without touching the running system."
	echo ""
	echo "Commands:"
	echo "    bin    (bi)                 Update this script"
	echo "    etc    (et)                 Update /etc to a new subvolume"
	echo "    rw                          Make root subvolume rw"
	echo "    ro                          Make root subvolume ro"
	echo "    shell  (sh)                 Open rw shell in new snapshot before exiting"
	echo "    system (dup)                Update system to a new subvolume"
	echo ""
	echo "Options:"
	echo "    -h, --help                  Print this help message"
}

main "$@"
