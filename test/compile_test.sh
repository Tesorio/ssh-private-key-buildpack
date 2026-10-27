#!/usr/bin/env bash
# Smoke tests for bin/compile. Runs it with a throwaway HOME and a fake ssh.
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Run bin/compile in a fresh sandbox; sets $out, $sandbox. Config vars go in $@ as NAME=value
# (written to the env dir, like Heroku does); SSH_HOSTS is read from the process environment.
run_compile() {
	sandbox="$(mktemp -d)"
	mkdir "$sandbox/home" "$sandbox/build" "$sandbox/cache" "$sandbox/env" "$sandbox/bin"
	printf '#!/usr/bin/env bash\necho "fake ssh $*"\n' > "$sandbox/bin/ssh"
	chmod +x "$sandbox/bin/ssh"
	for kv in "$@"; do printf '%s' "${kv#*=}" > "$sandbox/env/${kv%%=*}"; done
	out="$(HOME="$sandbox/home" PATH="$sandbox/bin:$PATH" bash "$repo/bin/compile" \
		"$sandbox/build" "$sandbox/cache" "$sandbox/env" 2>&1)"
}

echo "no SSH_KEY and no GITHUB_TOKEN: nothing is written"
run_compile
[[ "$out" == *"No SSH private key"* ]] || fail "expected 'No SSH private key', got: $out"
[ ! -e "$sandbox/home/.gitconfig" ] || fail "wrote .gitconfig without GITHUB_TOKEN"
[ ! -e "$sandbox/home/.ssh" ] || fail "created .ssh without SSH_KEY"

echo "GITHUB_TOKEN: both GitHub SSH URL forms are rewritten to HTTPS, token stays out of the build dir"
run_compile GITHUB_TOKEN=tok123
got="$(HOME="$sandbox/home" git config --global --get-all url."https://x-access-token:tok123@github.com/".insteadOf | sort)"
want="$(printf '%s\n' 'git@github.com:' 'ssh://git@github.com/' | sort)"
[ "$got" = "$want" ] || fail "insteadOf rules differ: $got"
[ -z "$(ls -A "$sandbox/build")" ] || fail "build dir is not empty: $(ls -A "$sandbox/build")"
[[ "$out" != *"tok123"* ]] || fail "token printed in compile output"

echo "SSH_KEY: key is decoded to ~/.ssh/id_rsa, known hosts are probed"
SSH_HOSTS=git@example.com run_compile SSH_KEY="$(printf 'KEYDATA' | base64)"
[ "$(cat "$sandbox/home/.ssh/id_rsa" 2>/dev/null)" = "KEYDATA" ] || fail "id_rsa not written"
[[ "$out" == *"fake ssh -oStrictHostKeyChecking=no -T git@example.com"* ]] || fail "ssh host probe missing: $out"

if [ "$failures" -gt 0 ]; then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
