#!/bin/bash
#
# OpenStack Swift backup backend
# By Fabien CRESPEL <fabien@crespel.net>
#

# Script variables
BACKUP_DIR="${BACKUP_DIR:-/home/backups}"
BACKUP_SWIFT_OPENRC_FILE="${BACKUP_SWIFT_OPENRC_FILE:-$BACKUP_DIR/backup-openrc.sh}"
BACKUP_SWIFT_CONTAINER="${BACKUP_SWIFT_CONTAINER:-backups}"
BACKUP_SWIFT_REMOTE="${BACKUP_SWIFT_REMOTE:-pca}"

# Check backend
function backup_check
{
	if [ ! -e "$BACKUP_SWIFT_OPENRC_FILE" ]; then
		echo "OpenStack RC file '$BACKUP_SWIFT_OPENRC_FILE' does not exist (BACKUP_SWIFT_OPENRC_FILE environment variable)"
		return 1
	fi
	if [ -z "$BACKUP_SWIFT_CONTAINER" ]; then
		echo "OpenStack backup container must be specified (BACKUP_SWIFT_CONTAINER environment variable)"
		return 1
	fi
	if ! command -v swift > /dev/null 2>&1; then
		echo "OpenStack Swift client is missing, please install it first"
		return 1
	fi
	source "$BACKUP_SWIFT_OPENRC_FILE"
	return 0
}

# List backup files
function backup_list
{
	local SUBDIR="$1"
	source "$BACKUP_SWIFT_OPENRC_FILE"
	swift list -p "$SUBDIR/" -d "/" "$BACKUP_SWIFT_CONTAINER" | sed "s#^$SUBDIR/##g"
}

# Save a backup
function backup_save
{
	local SUBDIR="$1"
	local FILE="$2"
	local TEMPDIR=`mktemp -d`
	local RET=0
	source "$BACKUP_SWIFT_OPENRC_FILE"
	if mkdir -p "$TEMPDIR/$SUBDIR" && cp "$FILE" "$TEMPDIR/$SUBDIR"; then
		( cd "$TEMPDIR" && swift upload "$BACKUP_SWIFT_CONTAINER" "$SUBDIR" )
		RET=$?
	else
		echo "Failed to copy archive file ($FILE) to temporary directory before upload"
		RET=1
	fi
	rm -Rf "$TEMPDIR"
	return $RET
}

# Delete a backup
function backup_delete
{
	local SUBDIR="$1"
	local FILE_NAME="$2"
	source "$BACKUP_SWIFT_OPENRC_FILE"
	swift delete "$BACKUP_SWIFT_CONTAINER" "$SUBDIR/$FILE_NAME"
}

# Prune outdated backups
function backup_prune
{
	local SUBDIR="$1"
	local FILE_NAME_REGEX="$2"
	local MAX_BACKUPS="$3"
	local NUMBER=1
	backup_list "$SUBDIR" | grep "$FILE_NAME_REGEX" | sort -r | while read BACKUPFILE; do
		if [ "$NUMBER" -gt "$MAX_BACKUPS" ] ; then
			echo "Removing backup file $BACKUPFILE"
			backup_delete "$SUBDIR" "$BACKUPFILE"
		fi
		NUMBER=`expr $NUMBER + 1`
	done
}

# Sync files
function backup_sync
{
	local SUBDIR="$1"
	local SRC_DIR="$2"
	local EXT_OPTS="${@:3}"
	local DEF_OPTS="--fast-list --links --delete-excluded --ignore-errors -v"
	if [ -e "$SRC_DIR/backup.filter" ]; then
		DEF_OPTS="$DEF_OPTS --filter-from=$SRC_DIR/backup.filter"
	fi
	source "$BACKUP_SWIFT_OPENRC_FILE"
	rclone sync $DEF_OPTS $EXT_OPTS "$SRC_DIR/" "$BACKUP_SWIFT_REMOTE:$BACKUP_SWIFT_CONTAINER/$SUBDIR/"
}
