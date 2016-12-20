#!/bin/sh

test_description='git-serve tests'

. ./setup.sh

test_expect_success 'Test interactive shell.' '
	"$GIT_SERVE" 2>&1 | grep -q "Interactive shell is disabled."
'

test_expect_success 'Test help.' '
	SSH_ORIGINAL_COMMAND=help "$GIT_SERVE" 2>actual &&
	save_IFS=$IFS
	IFS=
	while read -r line; do
		echo $line | grep -q "^Commands:$" && continue
		echo $line | grep -q "^  [a-z]" || return 1
		[ ${#line} -le 80 ] || return 1
	done <actual
	IFS=$save_IFS
'

test_expect_success 'Test maintenance mode.' '
	mv config config.old &&
	sed "s/^\(enable-maintenance = \)0$/\\11/" config.old >config &&
	SSH_ORIGINAL_COMMAND=help test_must_fail "$GIT_SERVE" 2>actual &&
	cat >expected <<-EOF &&
	The AUR is down due to maintenance. We will be back soon.
	EOF
	test_cmp expected actual &&
	mv config.old config
'

test_expect_success 'Test setup-repo and list-repos.' '
	SSH_ORIGINAL_COMMAND="setup-repo foobar" AUR_USER=user \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="setup-repo foobar2" AUR_USER=tu \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	*foobar
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success 'Test git-receive-pack.' '
	cat >expected <<-EOF &&
	user
	foobar
	foobar
	EOF
	SSH_ORIGINAL_COMMAND="git-receive-pack /foobar.git/" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success 'Test git-receive-pack with an invalid repository name.' '
	SSH_ORIGINAL_COMMAND="git-receive-pack /!.git/" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1 >actual
'

test_expect_success "Test git-upload-pack." '
	cat >expected <<-EOF &&
	user
	foobar
	foobar
	EOF
	SSH_ORIGINAL_COMMAND="git-upload-pack /foobar.git/" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Try to pull from someone else's repository." '
	cat >expected <<-EOF &&
	user
	foobar2
	foobar2
	EOF
	SSH_ORIGINAL_COMMAND="git-upload-pack /foobar2.git/" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Try to push to someone else's repository." '
	SSH_ORIGINAL_COMMAND="git-receive-pack /foobar2.git/" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1
'

test_expect_success "Try to push to someone else's repository as Trusted User." '
	cat >expected <<-EOF &&
	tu
	foobar
	foobar
	EOF
	SSH_ORIGINAL_COMMAND="git-receive-pack /foobar.git/" \
	AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Test restore." '
	echo "DELETE FROM PackageBases WHERE Name = \"foobar\";" | \
	sqlite3 aur.db &&
	cat >expected <<-EOF &&
	user
	foobar
	EOF
	SSH_ORIGINAL_COMMAND="restore foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual
	test_cmp expected actual
'

test_expect_success "Try to restore an existing package base." '
	SSH_ORIGINAL_COMMAND="restore foobar2" AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1
'

test_expect_success "Disown all package bases." '
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="disown foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Adopt a package base as a regular user." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	*foobar
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Adopt an already adopted package base." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1
'

test_expect_success "Adopt a package base as a Trusted User." '
	SSH_ORIGINAL_COMMAND="adopt foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	*foobar2
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Disown one's own package base as a regular user." '
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Disown one's own package base as a Trusted User." '
	SSH_ORIGINAL_COMMAND="disown foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual
'

test_expect_success "Try to steal another user's package as a regular user." '
	SSH_ORIGINAL_COMMAND="adopt foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="adopt foobar2" AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	cat >expected <<-EOF &&
	*foobar2
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	SSH_ORIGINAL_COMMAND="disown foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1
'

test_expect_success "Try to steal another user's package as a Trusted User." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	cat >expected <<-EOF &&
	*foobar
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1
'

test_expect_success "Try to disown another user's package as a regular user." '
	SSH_ORIGINAL_COMMAND="adopt foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="disown foobar2" AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	*foobar2
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	SSH_ORIGINAL_COMMAND="disown foobar2" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1
'

test_expect_success "Try to disown another user's package as a Trusted User." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1
'

test_expect_success "Adopt a package base and add co-maintainers." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	SSH_ORIGINAL_COMMAND="set-comaintainers foobar user3 user4" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	5|3|1
	6|3|2
	EOF
	echo "SELECT * FROM PackageComaintainers ORDER BY Priority;" | \
	sqlite3 aur.db >actual &&
	test_cmp expected actual
'

test_expect_success "Update package base co-maintainers." '
	SSH_ORIGINAL_COMMAND="set-comaintainers foobar user2 user3 user4" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	4|3|1
	5|3|2
	6|3|3
	EOF
	echo "SELECT * FROM PackageComaintainers ORDER BY Priority;" | \
	sqlite3 aur.db >actual &&
	test_cmp expected actual
'

test_expect_success "Try to add co-maintainers to an orphan package base." '
	SSH_ORIGINAL_COMMAND="set-comaintainers foobar2 user2 user3 user4" \
	AUR_USER=user AUR_PRIVILEGED=0 \
	test_must_fail "$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	4|3|1
	5|3|2
	6|3|3
	EOF
	echo "SELECT * FROM PackageComaintainers ORDER BY Priority;" | \
	sqlite3 aur.db >actual &&
	test_cmp expected actual
'

test_expect_success "Disown a package base and check (co-)maintainer list." '
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	*foobar
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user2 AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	cat >expected <<-EOF &&
	5|3|1
	6|3|2
	EOF
	echo "SELECT * FROM PackageComaintainers ORDER BY Priority;" | \
	sqlite3 aur.db >actual &&
	test_cmp expected actual
'

test_expect_success "Force-disown a package base and check (co-)maintainer list." '
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=tu AUR_PRIVILEGED=1 \
	"$GIT_SERVE" 2>&1 &&
	cat >expected <<-EOF &&
	EOF
	SSH_ORIGINAL_COMMAND="list-repos" AUR_USER=user3 AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 >actual &&
	test_cmp expected actual &&
	cat >expected <<-EOF &&
	EOF
	echo "SELECT * FROM PackageComaintainers ORDER BY Priority;" | \
	sqlite3 aur.db >actual &&
	test_cmp expected actual
'

test_expect_success "Check whether package requests are closed when disowning." '
	SSH_ORIGINAL_COMMAND="adopt foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat <<-EOD | sqlite3 aur.db &&
	INSERT INTO PackageRequests (ID, ReqTypeID, PackageBaseID, PackageBaseName, UsersID) VALUES (1, 2, 3, "foobar", 4);
	INSERT INTO PackageRequests (ID, ReqTypeID, PackageBaseID, PackageBaseName, UsersID) VALUES (2, 3, 3, "foobar", 5);
	INSERT INTO PackageRequests (ID, ReqTypeID, PackageBaseID, PackageBaseName, UsersID) VALUES (3, 2, 2, "foobar2", 6);
	EOD
	>sendmail.out &&
	SSH_ORIGINAL_COMMAND="disown foobar" AUR_USER=user AUR_PRIVILEGED=0 \
	"$GIT_SERVE" 2>&1 &&
	cat <<-EOD >expected &&
	Subject: [PRQ#1] Request Accepted
	EOD
	grep "^Subject.*PRQ" sendmail.out >sendmail.parts &&
	test_cmp sendmail.parts expected &&
	cat <<-EOD >expected &&
	1|2|3|foobar||4||The user user disowned the package.|0|2
	EOD
	echo "SELECT * FROM PackageRequests WHERE Status = 2;" | sqlite3 aur.db >actual &&
	test_cmp actual expected
'

test_done