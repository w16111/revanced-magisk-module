MINAPI=21
#MAXAPI=25
#DEBUG=true

set_permissions() {
	:
}

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
. $TMPDIR/functions.sh
