set -eu

die() {
	echo "$@" >&2
	export test_result=1
	exit 1
}

# usage: mock_cmd <cmd name> <code to run>
mock_cmd() {
	local cmd_name="$1"
	shift

	# https//stackoverflow.com/a/31969136
	if [ $# -eq 0 ]; then
		source /dev/stdin <<EOF
function ${cmd_name}() {
	register_mock_call ${cmd_name} "\$@"
	true
}
EOF
	else
		source /dev/stdin <<EOF
function ${cmd_name}() {
	register_mock_call ${cmd_name} "\$@"
	$@
}
EOF
	fi
}

# makes a note of a mock command being called
# usage: register_mock_call <cmd> <args>
register_mock_call() {
	#set -x
	local mcmd="$1"
	shift

	# get/set variable
	local varname="mock__cmd__${mcmd}"

	# create arrayjson, which is a JSON array of
	# the args passed to the command
	local arrayjson=`for i; do printf \"%s\", "$i"; done`
	arrayjson=${arrayjson%%,} # strip trailing comma
	arrayjson="[$arrayjson]"

	if [ -z "`declare | egrep ^${varname}=`" ]; then
		eval "${varname}='[]'"
	fi

	local dollar='$'
	local curval=`eval echo ${dollar}${varname}`
	local newval=`echo $curval | jq ". |= .+ [${arrayjson}]"`
	eval "${varname}='${newval}'"

	#echo "register_mock_call $mcmd $arrayjson" >&2
	#set +x
}

# find a call to a mock - returns the args given to the command;
# if call # is ignored, the last call is returned
# usage: retrieve_mock_call <cmd> [<call #>]
retrieve_mock_call() {
	#set -x
	local mcmd="$1"
	local mcall="${2:--1}" # in jq [-1] means last array item

	local varname="mock__cmd__${mcmd}"
	local dollar='$'

	if [ -z "`declare | egrep ^${varname}=`" ]; then
		return 1
	fi

	# nb output caught by callers
	eval "echo ${dollar}${varname} | jq .[$mcall][]"
	#set +x
}

# mainly used for single-line files (e.g. in /proc or /sys)
# usage: assert_file_content <file> <content>
assert_file_content() {
	[ -f "$1" ] || die "file $1 does not exist"
	local con=`cat $1`
	[ "$con" == "$2" ] || die "assert: file $1 content was wrong (expected $2, actual $con"
}

# assert a path exists and is a directory
# usage: assert_dir <path>
assert_dir() {
	[ -d "$1" ] || die "assert: $1 does not exist or is not a directory"
}

assert_file() {
	[ -f "$1" ] || die "assert: $1 does not exist or is not a file"
}

# assert a path does not exist
# usage: assert_missing <path>
assert_missing() {
	[ ! -e "$1" ] || die "assert: $1 exists, but we wanted it to be missing"
}

# asserts that a mocked command was called
# assert_called <cmd> [<args>]
assert_called() {
	if [ $# -eq 1 ]; then
		set +e
		if ! retrieve_mock_call $1; then
			set -e
			[ "$call_args" == "$margs" ] || die "$mcmd not called"
		fi
		set -e

	else
		[ $# -ge 2 ] || die "usage: assert_called <cmd> [<nth time>] <args>"
		local mcmd="$1"
		shift
		local margs="$@"

		# output: "arg1"\n"arg2"\n"etc"\n so we remove the double-quotes
		# (otherwise callers to assert_called_with would need to call it
		# like: assert_called_with \"3\" \"4\" \"5\"  which is terrible)
		local call_args=`retrieve_mock_call $mcmd | while read a; do
			echo $a| sed -e 's/^"//' -e 's/"$//'
		done`

		call_args=`echo $call_args | tr -d '\n'`

		[ "$call_args" == "$margs" ] || die "$mcmd not called with correct \
	parameters (expected: $margs, actual: $call_args)"
	fi
}

# asserts that a mocked command was called with particular args
# usage: assert_called_n <nth time> <cmd> <args>
assert_called_n() {
	[ $# -ge 3 ] || die "usage: assert_called_n <nth time> <cmd> <args>"
	local mtime="$1"
	shift
	local mcmd="$1"
	shift
	local margs="$@"

	# output: "arg1"\n"arg2"\n"etc"\n so we remove the double-quotes
	# (otherwise callers to assert_called_with would need to call it
	# like: assert_called_with \"3\" \"4\" \"5\"  which is terrible)
	local call_args=`retrieve_mock_call $mcmd $mtime | while read a; do
		echo $a| sed -e 's/^"//' -e 's/"$//'
	done`

	call_args=`echo $call_args | tr -d '\n'`

	[ "$call_args" == "$margs" ] || die "$mcmd not called with correct \
parameters (expected: $margs, actual: $call_args)"
}

test_result=0

begin_testing() {
	declare -F | egrep '^declare -f should' | while read f; do
		local actual_name=${f:11}

		echo "running test $actual_name"
		setup

		eval $actual_name

		# unset any mock calls that were made ($mock__cmd__*)
		vars_to_unset=`declare | egrep ^mock__cmd__ | while read f; do
			local actual_name=${f%%=*}
			echo $actual_name
		done`

		local d='$'
		for g in $vars_to_unset; do
			[ -z "`declare|egrep ^${g}=`" ] && continue
			unset $g
		done

		teardown
		echo ""
	done
}

for i; do
	source $i
done

begin_testing
