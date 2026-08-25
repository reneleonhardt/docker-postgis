#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034,SC2329
set -Eeuo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    echo "update-warnings.sh requires Bash 4 or newer" >&2
    exit 2
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
update_sh="$repo/update.sh"
cd "$repo"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    local value="$1"
    local needle="$2"
    local message="$3"
    [[ "$value" == *"$needle"* ]] || fail "$message (missing '$needle')"
}

assert_not_contains() {
    local value="$1"
    local needle="$2"
    local message="$3"
    [[ "$value" != *"$needle"* ]] || fail "$message (unexpected '$needle')"
}

source_block() {
    local start="$1"
    local end="$2"
    local first="$3"
    local last="$4"
    local actual_first actual_last

    actual_first="$(sed -n "${start}p" "$update_sh")"
    actual_last="$(sed -n "${end}p" "$update_sh")"
    [[ "$actual_first" == "$first"* ]] || fail "update.sh changed before test block ${start}-${end}"
    [[ "$actual_last" == "$last" ]] || fail "update.sh changed after test block ${start}-${end}"
    source <(sed -n "${start},${end}p" "$update_sh")
}

warnings=()
warning() {
    warnings+=("$*")
    echo "WARNING: $*" >&2
}

matrixVersions=(14-3.5 14-3.6 14-3.7 19beta3-3.7)
officialPostgresLibrary=$'Tags: 13, 14\nArchitectures: amd64, arm64v8\nDirectory: 14/alpine3.24\n\nTags: 19, 19beta3-alpine, 19-alpine\nArchitectures: amd64, arm64v8\nDirectory: 19/alpine3.24\n'
officialPostgresReleaseTags=$'13\n14\n19'
source_block 99 152 'declare -A knownPostgresTags=()' 'done'
postgresWarnings="${warnings[*]}"
assert_contains "$postgresWarnings" '19' 'stable PostgreSQL promotion warning'
assert_not_contains "$postgresWarnings" '13' 'represented PostgreSQL release warning'
assert_not_contains "$postgresWarnings" '14' 'represented PostgreSQL release warning'

warnings=()
knownPostgisSeries=(3.5 3.6 3.7)
warnedPostgisSeries=()
maxKnownPostgisMinor=7
source_block 184 191 'function version_reverse_sort() {' '}'
postgis_all_v3_versions=$'3.8.0rc1\n3.8.0beta1\n3.7.0\n3.7.0rc1'
officialPostgisReleaseTags=$'3.8.0rc1\n3.8.0beta1\n3.7.0'
source_block 254 283 'officialPostgisReleaseTags=' 'done'
postgisWarnings="${warnings[*]}"
assert_contains "$postgisWarnings" '3.8' 'new PostGIS series warning'
assert_contains "$postgisWarnings" '3.7.0' 'stable PostGIS promotion warning'

warnings=()
defaultAlpineSuite=3.24
source_block 285 349 'declare -A alpineSuiteByPostgresTag=()' '}'
assert_equal 3.24 "$(alpine_suite_for 19)" 'complete multi-platform Alpine metadata'
officialPostgresLibrary=$'Tags: 15-alpine\nArchitectures: amd64\nDirectory: 15/alpine3.25\n'
fallback_output="$(alpine_suite_for 15 2>&1)"
assert_contains "$fallback_output" '3.24' 'incomplete Alpine metadata fallback'
assert_contains "$fallback_output" 'no official Alpine image' 'Alpine fallback warning'

source_block 353 357 'declare -A suitePackageList=()' '}'
debianPackages=$'Package: postgresql-14\nVersion: 14.18-1.pgdg110+1\n\nPackage: postgresql-14-postgis-3\nVersion: 3.5.7+dfsg-1.pgdg110+1\n\nPackage: postgresql-14-h3\nVersion: 4.2.2-1.pgdg110+1\n\nPackage: postgresql-14-pgrouting\nVersion: 3.8.0-1.pgdg110+1\n'
assert_equal '14.18-1.pgdg110+1' "$(printf '%s\n' "$debianPackages" | package_version postgresql-14)" 'PostgreSQL package lookup'
assert_equal '3.5.7+dfsg-1.pgdg110+1' "$(printf '%s\n' "$debianPackages" | package_version postgresql-14-postgis-3)" 'PostGIS package lookup'
assert_equal '4.2.2-1.pgdg110+1' "$(printf '%s\n' "$debianPackages" | package_version postgresql-14-h3)" 'H3 package lookup'
assert_equal '3.8.0-1.pgdg110+1' "$(printf '%s\n' "$debianPackages" | package_version postgresql-14-pgrouting)" 'pgRouting package lookup'
assert_equal '' "$(printf '%s\n' "$debianPackages" | package_version postgresql-19-h3)" 'missing H3 package lookup'
assert_equal '' "$(printf '%s\n' "$debianPackages" | package_version postgresql-14-postgis-4)" 'missing PostGIS package lookup'
mapping_source="$(sed -n '31,65p' "$update_sh")"
assert_contains "$mapping_source" "[14]='bullseye-slim'" 'Debian suite mapping'
assert_contains "$mapping_source" "[3.6]='trixie-slim'" 'PostGIS suite mapping'
assert_contains "$(sed -n '370,377p' "$update_sh")" 'debianSuiteByPostgis' 'PostGIS suite selection'
assert_contains "$mapping_source" "[3.5]='3'" 'PostGIS package suffix mapping'
assert_contains "$(sed -n '154,168p' "$update_sh")" 'nlohmannJsonVersion=' 'nlohmann/json source discovery'
assert_contains "$(sed -n '154,175p' "$update_sh")" 'pgroutingLatestVersion=' 'pgRouting source discovery'
assert_contains "$(sed -n '540,555p' "$update_sh")" 'pgrouting-version.txt' 'pgRouting version substitution'
pgroutingTags=$'v4.1.0rc1\nref v4.0.1\nv4.0.0'
assert_equal '4.0.1' "$(printf '%s\n' "$pgroutingTags" | sed -n 's#.*v\([0-9][0-9.]*\)$#\1#p' | sort -V | tail -n 1)" 'stable pgRouting release selection'
assert_contains "$(sed -n '1,25p' "$repo/Dockerfile.alpine.template")" '%%TIGER_GEOCODER_VERSION%%' 'Alpine Tiger version placeholder'

fetch_output=""
fetch_rc=0
if fetch_output="$(
    curl_download() { return 1; }
    warning() { echo "WARNING: $*" >&2; }
    source <(sed -n '89,97p' "$update_sh") 2>&1
)" 2>&1; then
    fetch_rc=0
else
    fetch_rc=$?
fi
assert_equal 1 "$fetch_rc" 'metadata fetch failure status'
assert_contains "$fetch_output" 'Alpine suite discovery is unavailable' 'metadata fetch warning'

echo 'synthetic update warning/package checks passed'
