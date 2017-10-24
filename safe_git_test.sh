#!/bin/sh

# If you only want to run a subset of tests, run this with the
# tests you want to run as arguments.  You can get a list by
# running this script with `-l` or `--list`.

# If you're trying to run the tests on OSX, and they're failing, you may be
# missing flock, git-new-workdir, and/or timeout.
# To install flock:
# `brew tap discoteq/discoteq`
# `brew install flock`
# To install git-new-workdir (assuming you have git via homebrew):
# `ln -s /usr/local/share/git-core/contrib/workdir/git-new-workdir /usr/local/bin/git-new-workdir`
# You may also have `timeout` installed as `gtimeout`; link it to the other name with:
# `ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout`


# All failures are fatal!
set -e

ROOT=/tmp/safe_git_test_repos
SAFE_GIT="$PWD/safe_git.sh"


# $1: filename to check
# $2: expected contents.  Can use "\n" for newline.  Be sure to put it in
#     single-quotes!
_assert_file() {
    /bin/echo -ne "$2" | cmp - "$1" || {
        echo "$1: unexpected contents."
        echo "Expected:"
        echo "---"
        /bin/echo -ne "$2"
        echo "---"
        echo "Actual:"
        echo "---"
        cat "$1"
        echo "---"
        exit 1
    }
}


# $1: the dir of the repo you want to verify is at master.
# $2: the dir of the same repo in "origin"
_verify_at_master() {
    diff -r -u -x .git "$1" "$2"
}


# $1: filename (relative to the repo-root)
# $2 (optional): text to append to the filename each commit, defaults to $1
# $3 (optional): number of commits to do (defaults to 1)
create_git_history() {
    for i in `seq ${3-1}`; do
        echo "${2-$1}" >> "$1"
        git add "$1"
        git commit -m "$1: commit #$i"
    done
}



create_test_repos() {
    (
        mkdir -p origin
        cd origin

        git init subrepo1
        git init subrepo2
        git init subrepo3
        cd subrepo1
        create_git_history "foo" "foo subrepo1" 3
        create_git_history "bar" "bar subrepo1" 3
        cd ../subrepo2
        create_git_history "foo" "foo subrepo2" 3
        cd ../subrepo3
        create_git_history "foo" "foo subrepo3" 3
        cd ..

        git init repo
        cd repo
        git submodule add ../subrepo1
        git submodule add ../subrepo2
        git submodule add ../subrepo3
        git commit -a -m "Added subrepos"
        create_git_history "foo" "foo" 3
        create_git_history "bar" "bar" 3
    )
}


# --- Tests that we overwrite local changes (that are not reflected
# --- in the remote)

test_make_sure_sync_to_origin_actually_takes_us_to_master() {
    _verify_at_master repo ../origin/repo
}

test_sync_to_a_previous_commit_and_make_sure_we_go_back() {
    ( cd repo && git reset --hard HEAD^ )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_check_in_a_change_local_only_and_make_sure_sync_to_origin_ignores_it() {
    sha1=`cd repo && git rev-parse HEAD`
    ( cd repo && create_git_history "foo" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "$sha1"
    _verify_at_master repo ../origin/repo
}

test_check_in_some_submodule_changes() {
    sha1=`cd repo && git rev-parse HEAD`
    ( cd repo/subrepo1 && create_git_history "foo" )
    ( cd repo/subrepo2 && create_git_history "foo" )
    ( cd repo && git commit -am "Submodules" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "$sha1"
    _verify_at_master repo ../origin/repo
}

test_change_some_files_without_checking_them_in() {
    # Likewise, check in a submodule change but don't update substate.
    sha1=`cd repo && git rev-parse HEAD`
    echo "foo" >> repo/foo
    echo "foo" >> repo/subrepo1/foo
    ( cd repo/subrepo2 && create_git_history "foo" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "$sha1"
    _verify_at_master repo ../origin/repo
}

test_delete_a_submodule_directory_and_make_sure_we_get_it_back() {
    rm -rf repo/subrepo2
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_add_a_directory_and_make_sure_it_goes_away() {
    mkdir -p repo/empty_dir
    echo "new" repo/empty_dir/new
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    # TODO(csilvers): delete empty dirs
    #_verify_at_master repo ../origin/repo
}

# --- Tests that changes to the remote are reflected faithfully locally

test_update_a_file() {
    ( cd ../origin/repo && create_git_history "foo" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_add_a_file() {
    ( cd ../origin/repo && create_git_history "baz" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_delete_a_file() {
    ( cd ../origin/repo && git rm bar && git commit -am "deleted bar" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_update_substate() {
    ( cd ../origin/subrepo1 && create_git_history "foo" 2 )
    ( cd ../origin/repo/subrepo1 && git pull &&
        cd .. && git commit -am "Submodules" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_rollback_some_substate() {
    ( cd ../origin/subrepo1 && git reset --hard HEAD^ )
    ( cd ../origin/repo/subrepo1 && git pull &&
        cd .. && git commit -am "Submodules" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_add_a_new_submodule() {
    ( cd ../origin/repo && git submodule add ../subrepo3 subrepo3_again &&
        git commit -am "New submodule" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_delete_a_submodule() {
    ( cd ../origin/repo && git rm subrepo3 && git commit -am "Nix subrepo" )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_change_what_a_submodule_points_to() {
    ( cd ../origin/repo &&
        perl -pli -e 's,url = ../subrepo2,url = ../subrepo1,' .gitmodules &&
        git submodule sync && git submodule update &&
        cd subrepo2 && git checkout master &&
        git reset --hard origin/master && cd - &&
        git commit -am "Repointed submodule" &&
        git submodule update --init --recursive )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}

test_rollback_some_substate_when_rolling_back_the_repo() {
    ( cd ../origin/subrepo1 &&
        create_git_history "Subrepo history (to be rolled back)" )
    ( cd ../origin/repo/subrepo1 && git fetch origin &&
        git reset --hard origin/master &&
        cd .. && git commit -am "Substate repo1 (to be rolled back)")
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
    ( cd ../origin/repo && git reset --hard HEAD^ )
    "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"
    _verify_at_master repo ../origin/repo
}


# To automatically update this, run
#    grep -o '^test_[^(]*()' safe_git_test.sh | tr -d '()'
# But first run
#    grep -o '^test_[^(]*()' safe_git_test.sh | sort | uniq -d
# to make sure you don't accidentally use the same test-name twice!
# (It should give no output.)
ALL_TESTS="
test_make_sure_sync_to_origin_actually_takes_us_to_master
test_sync_to_a_previous_commit_and_make_sure_we_go_back
test_check_in_a_change_local_only_and_make_sure_sync_to_origin_ignores_it
test_check_in_some_submodule_changes
test_change_some_files_without_checking_them_in
test_delete_a_submodule_directory_and_make_sure_we_get_it_back
test_add_a_directory_and_make_sure_it_goes_away
test_update_a_file
test_add_a_file
test_delete_a_file
test_update_substate
test_rollback_some_substate
test_add_a_new_submodule
test_delete_a_submodule
test_change_what_a_submodule_points_to
test_rollback_some_substate_when_rolling_back_the_repo
"

if [ "$1" = "-l" -o "$1" = "--list" ]; then
    echo "Tests you can run:"
    echo "$ALL_TESTS"
    exit 0
elif [ -n "$1" ]; then          # they specified which tests to run
    tests_to_run="$@"
else
    tests_to_run="$ALL_TESTS"
fi


rm -rf "$ROOT"
mkdir -p "$ROOT"
cd "$ROOT"

# Set the envvars that safe_git.sh looks at
export WORKSPACE_ROOT="$ROOT"
export REPOS_ROOT="$ROOT/repositories"
export SLACK_CHANNEL=.
mkdir -p "$WORKSPACE_ROOT" "$REPOS_ROOT"

create_test_repos
cp -a origin origin.clean

failed_tests=""
for test in $tests_to_run; do
    (
        echo "--- $test"

        # Reset origin/ back to the start state.
        rm -rf origin
        cp -a origin.clean origin

        # Set up the workspace to match master.
        mkdir -p "$test"
        cd "$test"
        export WORKSPACE_ROOT=.
        "$SAFE_GIT" sync_to_origin "$ROOT/origin/repo" "master"

        # Run the test!
        $test
    ) && echo "PASS: $test" || failed_tests="$failed_tests $test"
done

if [ -n "$failed_tests" ]; then
    echo "FAILED"
    echo "To re-run failed tests, run $0$failed_tests"
else
   echo "All done!  PASS"
fi