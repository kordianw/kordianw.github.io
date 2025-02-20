#!/bin/bash
# manage the overall process of backing up dirs/files ready for a tar transfer and syncing between machines
#
# ############################################################################################################
#
# **** Quick Start on a new machine:
# $ wget http://kordy.com/dl.sh && bash dl.sh
# $ curl -sS http://kordy.com/dl.sh -o dl.sh && bash dl.sh
#
##############################################################################################################
#
# NOTE: script can be downloaded from: https://kordy.com/dl.sh /or/ << https://tinyurl.com/k-dl-sh >>
#
# HW-INFO: # curl -Ss https://raw.githubusercontent.com/kordianw/HW-Info/master/hw-info.sh | bash
#
# PS: Manual location of tar.gpg: https://github.com/kordianw/kordianw.github.io/raw/master/example-scripts.tar.gz.gpg
#
#
# * By Kordian Witek <code [at] kordy.com>, Jan 2019
#

#######BACKUP

# what is the target & name for the backup - where to place backup tar file?
# - this is usually a public dir that a file can be picked up remotely via wget, eg: public_html
SERVER_TARGET_PUBLIC_DIR="$HOME/public_html/kordianw.github.io"
TAR_BACKUP_NAME="example-scripts.tar.gz"

#######RESTORE
# restore settings
LOCAL_SRC_RESTORE_DIR="$HOME/src"                                     # Primary
[ -d "$HOME/playground" ] && LOCAL_SRC_RESTORE_DIR="$HOME/playground" # Secondary (fallback)

REMOTE_RESTORE_TAR_LOCATION="http://kordy.com/$TAR_BACKUP_NAME"
ALT_REMOTE_RESTORE_TAR_LOCATION="https://github.com/kordianw/kordianw.github.io/raw/master/$TAR_BACKUP_NAME"
REMOTE_TAR_DIR_STRUCTURE="kordy/bin/scripts"
TAR_EXCLUSIONS="Combined-AHK-Scripts.ahk"

#######UPLOAD MASTER DEST
REMOTE_SERVER="kordy@nexus.kordy.com"
REMOTE_REPOSITORY='/home/kordy/bin/scripts'

#######OTHER
CONFIG_FILES_DIR="Config-Files"
LOCAL_SCRIPTS_DIR="$HOME/bin/scripts"

# any client-side dir/file patterns to ignore?
# - these will not be processed in any function such as -add, -diff, etc
FILE_EXCLUSIONS="_gsdata_|README.md"

# Strategic script name and MISC settings:
# - in `setup' will try to rename to this
SCRIPT_NAME="bkup-and-transfer.sh"
FAVE_TIMEZONE="America/New_York|US/Eastern"

##############################

#
# FUNCTIONS
#
function set_files_list() {
  # FILES IN SCOPE:
  # - searches both files and symbolic links
  # - searches for scripts files: *.pm *.pl *.sh *.py *.bat *.java *.c *.h
  # - searches for config files:  .*rc* *conf* *profile* *.local*
  # - searches for other files:   *.json* *.yml *.txt *.ini *.cfg
  # - excluded searches:          *.ahk
  TYPES_OF_FILES='-type f -o -type l'

  if [ -n "$1" ]; then
    FILES_LIST=$(find . -maxdepth 2 \( $TYPES_OF_FILES \) \( -iname "*.pm" -o -iname "*.pl" -o -iname "*.sh" -o -iname "*.py" -o -iname "*.bat" -o -iname "*.java" -o -iname "*.c" -o -iname "*.h" -o -iname "*.json*" -o -iname "*.yml" -o -iname "*.yaml" -o -iname "*.txt" -o -iname "*.md" -o -iname ".*rc*" -o -iname "*conf*" -o -iname "*profile*" -o -iname "*.local*" -o -iname "*.ini" -o -iname "*.cfg" -o -iname "Dockerfile" -o -iname "Makefile" -o -iname "requirements.txt" -o -iname "Readme.md" \) | egrep -v "$FILE_EXCLUSIONS" | sort -f | sed 's/^.\///' | egrep -i "$1")
  else
    FILES_LIST=$(find . -maxdepth 2 \( $TYPES_OF_FILES \) \( -iname "*.pm" -o -iname "*.pl" -o -iname "*.sh" -o -iname "*.py" -o -iname "*.bat" -o -iname "*.java" -o -iname "*.c" -o -iname "*.h" -o -iname "*.json*" -o -iname "*.yml" -o -iname "*.yaml" -o -iname "*.txt" -o -iname "*.md" -o -iname ".*rc*" -o -iname "*conf*" -o -iname "*profile*" -o -iname "*.local*" -o -iname "*.ini" -o -iname "*.cfg" -o -iname "Dockerfile" -o -iname "Makefile" -o -iname "requirements.txt" -o -iname "Readme.md" \) | egrep -v "$FILE_EXCLUSIONS" | sort -f | sed 's/^.\///')
  fi
}

function check_sshpass() {
  # only allow sshpass in certain locations
  WHERE=$(command -v sshpass)
  [ ! -x "$WHERE" ] && {
    echo "--FATAL: not allowing sshpass << $WHERE >> to be non-executable!" >&2
    exit 9
  }
  [ ! -s "$WHERE" ] && {
    echo "--FATAL: not allowing sshpass << $WHERE >> to be empty!" >&2
    exit 9
  }
  if [ "$OSTYPE" = "linux-gnu" -o "$OSTYPE" = "linux" ]; then
    [ -L "$WHERE" ] && {
      echo "--FATAL: not allowing sshpass << $WHERE >> to be a symbolic link!" >&2
      exit 9
    }

    # linux
    if ! egrep -q '^/usr/bin/sshpass$' <<<$WHERE; then
      echo "--FATAL: not allowing sshpass << $WHERE >> to be in this path on $OSTYPE!" >&2
      exit 9
    fi
  else
    # darwin
    if ! egrep -q '^/usr/local/bin/sshpass$' <<<$WHERE; then
      echo "--FATAL: not allowing sshpass << $WHERE >> to be in this path on $OSTYPE!" >&2
      exit 9
    fi
  fi
}

function run_ssh() {
  # get params
  CMD=$1
  [ -z "$CMD" ] && {
    echo "--FATAL: need type param!" >&2
    exit 1
  }
  [ "$CMD" != "ssh" -a "$CMD" != "scp" ] && {
    echo "--FATAL: need CMD type param to be SSH or SCP!" >&2
    exit 1
  }
  shift
  [ -z "$1" ] && {
    echo "--FATAL: no enough additional $CMD params!" >&2
    exit 2
  }

  if command -v sshpass >&/dev/null; then
    check_sshpass

    # get password if not already there
    if [ -z "$SSHPASS" ]; then
      F_CMD=$(echo "$CMD $@" | sed 's/-o StrictHostKeyChecking=no//')

      echo -e "   ... Enter password to exec \`$F_CMD': \c" 1>&2
      read -s PASSWORD
      echo 1>&2
      export SSHPASS="$PASSWORD"
    fi

    # SSHPASS EXEC
    sshpass -e $CMD $@

    [ $? -ne 0 ] && {
      echo "------last SSHPASS command non-zero abort code, ABORTING!" >&2
      exit 99
    }
  else
    # STANDARD EXEC
    eval $CMD $@

    [ $? -ne 0 ] && {
      echo "------last DIRECT_SSH command non-zero abort code, ABORTING!" >&2
      exit 99
    }
  fi
}

function fmt_ls() {
  # nicely formatted ls
  echo "-> $(/bin/ls -lho "$1")" | sed 's/ -r[^ ]* //; s/>[0-9] /> /; s/> [0-9] /> /; s/lrwx[^ ]* //; s/> [0-9] /> /;' | awk '{printf "%s %s%5s %s %2s %-5s %s %s %s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'
}

function do_backup() {
  # check that target-dir exists
  if [ ! -d "$SERVER_TARGET_PUBLIC_DIR" ]; then
    echo "$(basename $0): backup target dir: <$SERVER_TARGET_PUBLIC_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  # make sure we have the password file
  PASS_FILE="$(sed 's/\.[a-z][a-z]*$//' <<<$0)-pass.txt"
  if [ ! -s "$PASS_FILE" ]; then
    echo "***" >&2
    echo "*** $(basename $0): No Password File! In order to protect the backup, please create a password file: $PASS_FILE" >&2
    echo "***" >&2
    sleep 2
    exit 9
  fi

  # first, we back it up
  echo "1) get everything together"

  # ensure we have at least a blank FileCache
  mkdir /tmp/FileCache 2>/dev/null

  # work out whether we're doing incremental or full mode
  # - this is done via backing up files newer than start of year or DIFF years ago
  # - when file already exists, we also use a month for more granular incremental
  YEAR=$(date "+%Y")
  MONTH=01
  if [ "$1" = "-full" -o "$1" = "-all" ]; then
    # for FULL bkup, we do the last 3 years...
    echo "--WARN: choosing a full backup of the last 10 years..." 1>&2
    YEAR=$(($YEAR - 10))
  else
    DIFF=1
    if [ -e "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" -a -s "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" -a -z "$2" ]; then
      MONTH=$(date "+%m")
      DAY=$(date "+%d")
      if [ $DAY -lt 5 -a $MONTH -eq 1 ]; then
        MONTH=12
      elif [ $DAY -lt 10 -a $MONTH -gt 1 ]; then
        MONTH=$(sed 's/^0//' <<<$MONTH)
        MONTH=$(($MONTH - 1))
        [ $MONTH -lt 10 ] && MONTH="0$MONTH"
      fi
      echo "--WARN: \"$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME\" already exists, turning on >$YEAR-$MONTH-01 incremental bkup mode..." 1>&2
      echo "        ... use \`$0 -bkup -all' to backup all data" 1>&2
      DIFF=0
    else
      [ -n "$2" ] && DIFF=15
      echo "--WARN: $TAR_BACKUP_NAME doesn't exist, turning on >$YEAR - $DIFF year(s) bkup mode..." 1>&2
      [ -z "$2" ] && echo "        ... use \`$0 -bkup -all' to backup all data" 1>&2
    fi
    YEAR=$(($YEAR - $DIFF))
  fi

  # find links
  # - we want to exclude them from the tar file
  find $LOCAL_SCRIPTS_DIR -maxdepth 1 -type l >/tmp/exclude-patterns-$$.tmp

  # add any other exclusions
  if [ -n "$TAR_EXCLUSIONS" ]; then
    find $LOCAL_SCRIPTS_DIR -type f | egrep "$TAR_EXCLUSIONS" >>/tmp/exclude-patterns-$$.tmp
  fi

  ############################################################################################################################
  #### WHAT TO BACKUP?
  #### - contains a list of filemasks to backup
  #### NOTE: ensure that you end the last item with \
  ############################################################################################################################
  echo "* Step 1 of 3: creating initial tar file..."
  tar --newer-mtime="$YEAR-$MONTH-01 00:00:00" --exclude-from /tmp/exclude-patterns-$$.tmp -cvf "/tmp/tmp-$$.tar" \
    $LOCAL_SCRIPTS_DIR/*.pl \
    $LOCAL_SCRIPTS_DIR/*.pm \
    $LOCAL_SCRIPTS_DIR/*.sh \
    $LOCAL_SCRIPTS_DIR/lib/*.pm \
    $LOCAL_SCRIPTS_DIR/Shell-Tools/* \
    $LOCAL_SCRIPTS_DIR/HW-Info/* \
    $LOCAL_SCRIPTS_DIR/KW-Guides/* \
    $LOCAL_SCRIPTS_DIR/KW-Weather/* \
    $LOCAL_SCRIPTS_DIR/Google-Rank/* \
    $LOCAL_SCRIPTS_DIR/CloudRun-Exec/* \
    $LOCAL_SCRIPTS_DIR/MacOS-Utils/* \
    $LOCAL_SCRIPTS_DIR/Movies-Mgmt/*.pl \
    $LOCAL_SCRIPTS_DIR/Movies-Mgmt/*.sh \
    $LOCAL_SCRIPTS_DIR/Hotel-Prices/* \
    $LOCAL_SCRIPTS_DIR/FlickrUpload/*.pl \
    $LOCAL_SCRIPTS_DIR/FlickrUpload/*.sh \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/* \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.??*

  # can add these at will (end with \):
  # $LOCAL_SCRIPTS_DIR/*.py \
  # /tmp/FileCache \
  ############################################################################################################################

  # check tar status
  if [ $? -ne 0 ]; then
    echo -e "\n\n*** #1 ERROR BACKING up via TAR... exiting! ***\n" 1>&2
    exit 97
  fi

  # certain files should ALWAYS be added
  # -r: add to an existing tar
  # NB: AWS, GCP, Azure cloud keys - for AWS, allow private-key, for the rest, just PUB keys
  echo "* Step 2 of 3: adding certain key files (SSH keys, etc) to the tar..."
  tar --exclude-from /tmp/exclude-patterns-$$.tmp -rvf "/tmp/tmp-$$.tar" \
    $LOCAL_SCRIPTS_DIR/$(basename $0) \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.bash_profile \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.zshrc \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.vimrc \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.screenrc \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.tmux.conf \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.gitignore \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.gitconfig \
    $LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.ssh/config \
    $LOCAL_SCRIPTS_DIR/HW-Info/hw-info* \
    $LOCAL_SCRIPTS_DIR/Shell-Tools/setup* \
    $LOCAL_SCRIPTS_DIR/Shell-Tools/ip-location* \
    $LOCAL_SCRIPTS_DIR/Shell-Tools/*test* \
    $LOCAL_SCRIPTS_DIR/CommonFuncs.pm \
    ~/.ssh/*key*pub

  # can add these (end with \):
  #$LOCAL_SCRIPTS_DIR/$CONFIG_FILES_DIR/.??*
  #~/.ssh/*aws*pem \

  # check tar status
  if [ $? -ne 0 ]; then
    echo -e "\n\n*** #2 ERROR BACKING up via TAR... exiting! ***\n" 1>&2
    exit 98
  fi

  ############################################################################################################################

  # clean-up exclude file
  rm -f /tmp/exclude-patterns-$$.tmp

  # temporarily move the whole set of backed-up files to a temp dir
  echo "* Step 3 of 3: reconstructing the tar file..."
  mkdir /tmp/tmp-bkup-$$ && cd /tmp/tmp-bkup-$$ && tar xf ../tmp-$$.tar || exit 2

  DATE=$(date "+%Y%m%d")
  echo && echo "2) rename to current dates"
  for a in *; do
    [ -d "$a" ] && mv -iv "/tmp/tmp-bkup-$$/$a" "/tmp/tmp-bkup-$$/$a-$DATE" || exit 3
  done

  #
  # FINAL STEPS:
  #

  echo && echo "3) FINAL: tar-up & gzip again"
  NON_GZ_TAR_BACKUP_NAME=$(sed 's/.gz$//' <<<$TAR_BACKUP_NAME)
  tar cf "$SERVER_TARGET_PUBLIC_DIR/$NON_GZ_TAR_BACKUP_NAME" * || exit 5
  rm -f "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" # remove any pre-existing file in prep for the new gzip
  gzip -9v "$SERVER_TARGET_PUBLIC_DIR/$NON_GZ_TAR_BACKUP_NAME" || exit 6
  chmod 644 "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" || exit 7

  # test archive & print out the files backed-up, other than tmp
  echo "- testing archive..."
  #tar tvfz "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" | awk '{print $4,$NF}' | egrep -v ' tmp-|/$' | sort
  tar tvfz "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME" | awk '{print $4,$NF}' | egrep -v ' tmp-|/$' | sort | xargs dirname | sort -u | grep -v "^\.$"

  # ALSO copy this script itself to TARGET dir
  # -> as a `dl.sh' file
  cd - >&/dev/null
  cp -pf "$0" "$SERVER_TARGET_PUBLIC_DIR" || exit 6
  mv "$SERVER_TARGET_PUBLIC_DIR/$(basename $0)" "$SERVER_TARGET_PUBLIC_DIR/dl.sh"
  [ $? -ne 0 ] && {
    echo "------last mv command non-zero abort code, ABORTING!" >&2
    exit 99
  }
  chmod 755 "$SERVER_TARGET_PUBLIC_DIR/dl.sh" || exit 8
  if [ -s "$SERVER_TARGET_PUBLIC_DIR/dl.sh" ]; then
    echo "4) backed up $(basename $0) as \`$SERVER_TARGET_PUBLIC_DIR/dl.sh' for easy retrieval as << wget $(dirname $REMOTE_RESTORE_TAR_LOCATION)/dl.sh >>"
  else
    echo "**** ERROR: wasn't able to backup $0 to $SERVER_TARGET_PUBLIC_DIR" 1>&2
  fi

  # list and clean-up
  echo "5) non-encrypted tar file:"
  ls -lh "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME"

  ####################################################

  #
  # encrypt via gpg
  #
  if ! command -v gpg >&/dev/null; then
    echo "--FATAL: no gpg binary found on this system - can't encrypt the backup!" >&2
    echo "**NB**: please install \`gpg', eg run:" >&2

    if [ $(whoami) = "root" ]; then
      echo "$ apt -q update && apt install -q -y gpg"
    else
      echo "$ sudo apt -q update && sudo apt install -q -y gpg"
    fi

    exit 99
  fi

  PASS_FILE="$(sed 's/\.[a-z][a-z]*$//' <<<$0)-pass.txt"
  if [ ! -s "$PASS_FILE" ]; then
    echo "No Password File! In order to protect the files, please create a password file: $PASS_FILE" >&2
    exit 9
  fi

  # entrypt with the password
  rm -f "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME.gpg"
  gpg --batch -c --passphrase-file "$PASS_FILE" "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME"
  [ $? -ne 0 ] && {
    echo "*** gpg encrypt returned error!" >&2
    exit 99
  }

  if [ -s "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME.gpg" ]; then
    rm "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME"
    [ $? -ne 0 ] && {
      echo "*** rm returned error!" >&2
      exit 99
    }
  else
    echo "non-successful encryption - gpg tar file missing!" >&2
    exit 11
  fi

  echo "6) encrypted tar file:"
  ls -lh "$SERVER_TARGET_PUBLIC_DIR/$TAR_BACKUP_NAME.gpg"

  ####################################################

  #
  # upload via GIT
  #
  if [ "$1" != "-nogit" ]; then

    echo "7) upload to github [~5 secs publish delay]:"

    cd $SERVER_TARGET_PUBLIC_DIR >&/dev/null
    [ $? -ne 0 ] && {
      echo "*** last CD cmd to $SERVER_TARGET_PUBLIC_DIR returned error" >&2
      exit 99
    }

    # are we in initialized GIT dir?
    if [ ! -d .git -a ! -d ../.git ]; then
      echo "Invalid DIR: No .git dir in $(pwd)!" >&2
      exit 11
    fi

    # is git working properly?
    # - 2 methods of checking
    git status >&/dev/null
    if [ $? -ne 0 ]; then
      echo "*** GIT-STATUS \`git status' cmd returned error:" >&2
      git status >&2
      exit 98
    fi

    git status --porcelain >&/dev/null
    if [ $? -ne 0 ]; then
      echo "*** GIT-STATUS \`git status --porcelain' cmd returned error:" >&2
      git status --porcelain >&2
      exit 99
    fi

    # do we have anything to do?
    CHANGED=$(git status --porcelain $TAR_BACKUP_NAME.gpg dl.sh 2>&1)
    if [ -n "$CHANGED" ]; then
      git pull --quiet
      [ $? -ne 0 ] && {
        echo "*** last GIT-COMMIT cmd returned error" >&2
        exit 99
      }

      # do we need to add the file?
      # - just in case
      git add $TAR_BACKUP_NAME.gpg dl.sh

      git commit -m "$TAR_BACKUP_NAME.gpg+dl.sh commit: $(hostname | sed 's/\..*//') on $(date)" --quiet $TAR_BACKUP_NAME.gpg dl.sh
      [ $? -ne 0 ] && {
        echo "*** last GIT-COMMIT cmd returned error" >&2
        exit 99
      }

      #git push --quiet
      git push
      [ $? -ne 0 ] && {
        echo "*** last GIT-PUSH cmd returned error" >&2
        exit 99
      }
    else
      echo "*** GIT-STATUS \`git status $TAR_BACKUP_NAME.gpg dl.sh' says THERE IS NOTHING TO UPLOAD:" >&2
      git status --porcelain $TAR_BACKUP_NAME.gpg dl.sh >&2
    fi

  fi

  ####################################################

  # make the pass file be the same as main file
  PASS_FILE="$(sed 's/\.[a-z][a-z]*$//' <<<$0)-pass.txt"
  if [ -r $PASS_FILE ]; then
    touch -r "$0" "$PASS_FILE"
    chmod 600 "$PASS_FILE"
  fi

  # clean-up
  rm -f /tmp/tmp-$$.tar /tmp/tmp-$$.tar.gz
  rm -rf /tmp/tmp-bkup-$$
}

function do_download() {
  # can't run in this dir
  if pwd | grep -q "$REMOTE_REPOSITORY"; then
    echo "$(basename $0): can't run in this directory - $REMOTE_REPOSITORY - this is the destination, not the src!" 1>&2
    exit 99
  fi

  if ! command -v gpg >&/dev/null; then
    echo "--FATAL: no gpg binary found on this system - won't be able to decrypt the backup!" >&2
    echo "**NB**: please install \`gpg', eg:" >&2

    if [ $(whoami) = "root" ]; then
      echo "$ apt -q update && apt install -q -y gpg"
    else
      echo "$ sudo apt -q update && sudo apt install -q -y gpg"
    fi

    exit 99
  fi

  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then

    # we can pre-create it!
    if [ $(pwd) = "$HOME" ]; then
      if [ ! -e "$HOME/src" ]; then
        echo "- creating: $LOCAL_SRC_RESTORE_DIR"
        mkdir $LOCAL_SRC_RESTORE_DIR
      fi
    fi

    if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
      echo "$(basename $0): main working & src scripts dir: << $LOCAL_SRC_RESTORE_DIR >> doesn't exist, nothing to do!" 1>&2
      exit 99
    fi
  fi

  # switch to the right dir
  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  echo "1) download the transfer file: $REMOTE_RESTORE_TAR_LOCATION.gpg"

  # deal with any existing backup
  if [ -e "$TAR_BACKUP_NAME" -a -s "$TAR_BACKUP_NAME" ]; then
    mkdir dl >&/dev/null
    mv "$TAR_BACKUP_NAME" dl || exit 2
  fi
  if [ -e "dl/$TAR_BACKUP_NAME.gpg" -a -s "dl/$TAR_BACKUP_NAME.gpg" ]; then
    echo "--WARN: $TAR_BACKUP_NAME.gpg already exists in << $LOCAL_SRC_RESTORE_DIR/dl >> ... using!" 1>&2
  elif [ -e "./$TAR_BACKUP_NAME.gpg" -a -s "./$TAR_BACKUP_NAME.gpg" ]; then
    echo "--WARN: $TAR_BACKUP_NAME.gpg already exists in << $LOCAL_SRC_RESTORE_DIR >> ... using!" 1>&2
    mkdir dl >&/dev/null
    mv "./$TAR_BACKUP_NAME.gpg" dl || exit 2
  else
    rm -f dl/$TAR_BACKUP_NAME 2>/dev/null
    if ! command -v wget >&/dev/null; then
      if command -v timeout >&/dev/null; then
        timeout 15 curl -sS -o "$TAR_BACKUP_NAME.gpg" $REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      else
        curl -sS -o "$TAR_BACKUP_NAME.gpg" $REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      fi
    else
      if command -v timeout >&/dev/null; then
        timeout 15 wget -4 -q --no-cache -o /dev/null $REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      else
        wget -4 -q --no-cache -o /dev/null $REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      fi
    fi

    # try again - was the DL successful?
    if [ $RC -ne 0 ]; then
      echo "--ALMOST-FATAL: download of \"$REMOTE_RESTORE_TAR_LOCATION.gpg\" failed with RC=$RC!" >&2
      echo "<*> retrying with alt-location: $ALT_REMOTE_RESTORE_TAR_LOCATION.gpg" >&2
      if command -v timeout >&/dev/null; then
        timeout 15 wget -4 -q --no-check-certificate --no-cache -o /dev/null $ALT_REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      else
        wget -4 -q --no-check-certificate --no-cache -o /dev/null $ALT_REMOTE_RESTORE_TAR_LOCATION.gpg
        RC=$?
      fi
    fi

    # was the DL successful?
    if [ $RC -ne 0 ]; then
      echo "--FATAL: download of \"$REMOTE_RESTORE_TAR_LOCATION.gpg\" failed with RC=$RC!" >&2
      exit 99
    fi

    mkdir dl >&/dev/null
    mv "$TAR_BACKUP_NAME.gpg" dl || exit 2
  fi

  if [ ! -s "dl/$TAR_BACKUP_NAME.gpg" ]; then
    echo "--FATAL: download of \"$REMOTE_RESTORE_TAR_LOCATION.gpg\" failed - EMPTY FILE!" >&2
    rm -f "dl/$TAR_BACKUP_NAME.gpg"
    exit 3
  fi
  cd dl >&/dev/null || exit 3

  # unencrypt
  # - check for GPG version, if less than gpg v2.1, then we can't use the pinentry param
  echo "2) Decrypt Process"
  echo "*** decrypting backup-file: \`$TAR_BACKUP_NAME.gpg' ..."
  GPG_VERSION=$(gpg --version | awk '/^gpg.*[0-9]/{print $NF}' | sed 's/\..*//')
  if [ "$GPG_VERSION" -eq 1 ]; then
    # VERSION 1.x
    gpg --decrypt $TAR_BACKUP_NAME.gpg >$TAR_BACKUP_NAME
  else
    # VERSION 2.x
    GPG_SUB_VERSION=$(gpg --version | awk '/^gpg.*[0-9]/{print $NF}' | sed 's/^[0-9]\.\([0-9][0-9]*\).*/\1/')
    if [ "$GPG_SUB_VERSION" -eq 0 ]; then
      # VERSION 2.0
      gpg --decrypt $TAR_BACKUP_NAME.gpg >$TAR_BACKUP_NAME
    else
      # VERSION 2.1 or higher
      gpg --decrypt --pinentry-mode=loopback $TAR_BACKUP_NAME.gpg >$TAR_BACKUP_NAME
    fi
  fi

  # did we get it ?
  if [ ! -s "$TAR_BACKUP_NAME" ]; then
    echo "ERROR: couldn't decrypt file \"$TAR_BACKUP_NAME.gpg\"! - target file << $TAR_BACKUP_NAME >> not present!" 1>&2
    echo "  - detail: error running: gpg --decrypt --pinentry-mode=loopback $TAR_BACKUP_NAME.gpg, see above" 1>&2
    exit 3
  fi

  # remove the gpg file - not needed
  rm -f $TAR_BACKUP_NAME.gpg

  # tar not installed?!
  if ! command -v tar >&/dev/null; then
    echo "*** trying to install \`tar'!" >&2
    [ -x /usr/bin/yum -a ! -x /bin/tar ] && yum -y -qq install tar
    [ -x /usr/bin/apt -a ! -x /bin/tar ] && apt-get install -y tar
  fi

  # untar
  tar xzvf $TAR_BACKUP_NAME || exit 4
  cd .. >&/dev/null || exit 4
  rm dl/$TAR_BACKUP_NAME || exit 5

  # list last 3 files
  DATE=$(date "+%Y%m%d")
  echo "3) last 3 modified scripts"
  if [ -d "dl/home-$DATE" ]; then
    cd dl/home-$DATE/$REMOTE_TAR_DIR_STRUCTURE >/dev/null || exit 3
    ls -ltroh | tail -3
    cd - >/dev/null || exit 4
  fi

  # process TMP - move & overwrite existing /tmp/FileCache
  echo "4) process temp dir"
  if [ -d "tmp-$DATE" ]; then
    cd tmp-$DATE/FileCache/KW >/dev/null || exit 5
    ls

    for a in *; do
      echo "*** $a: moving cache files..."
      mkdir /tmp/FileCache/KW/$a >&/dev/null
      mv $a/* /tmp/FileCache/KW/$a
    done
    cd - >/dev/null || exit 6

    # clean-up
    echo "... cleaning up dir: tmp-$DATE"
    rm -rf tmp-$DATE
  fi

  # make the pass file be the same as main file
  PASS_FILE="$(sed 's/\.[a-z][a-z]*$//' <<<$0)-pass.txt"
  if [ -r $PASS_FILE ]; then
    touch -r "$0" "$PASS_FILE"
    chmod 600 "$PASS_FILE"
  fi
}

function show_differences() {
  # swap dirs for the diff read-only function
  [ -e "$LOCAL_SRC_RESTORE_DIR" ] || LOCAL_SRC_RESTORE_DIR="$LOCAL_SCRIPTS_DIR"

  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): target/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  # get the latest date
  LATEST=$(ls -dtr dl/home-* 2>/dev/null | tail -1)
  if [ -z "$LATEST" ]; then
    echo "$(basename $0): there is no backup << ./dl/home-XXX >> dir in <$LOCAL_SRC_RESTORE_DIR>, need to run \`$(basename $0) -restore' first!" 1>&2
    exit 99
  fi

  # process the scripts
  set_files_list $1
  for a in $FILES_LIST; do
    LAST="$LATEST/$REMOTE_TAR_DIR_STRUCTURE/$a"
    if [ -e "$LAST" ]; then
      fmt_ls "$a"

      # DIFF?
      diff -q "$a" "$LAST" >&/dev/null
      DIFF=$?

      if [ $DIFF -ne 0 ]; then
        echo "*** File \"$a\" has changed, viewing differences..."
        sleep 1
        vimdiff -R -c ":set number" -c "cmap q qa" -c "set viminfo='0" "$a" "$LAST"
      fi
    elif [ $(grep -c "/" <<<$a) -eq 0 ]; then
      if [ -L "$a" ]; then
        echo "*** Symbolic LINK \"$a\" is NOT TRACKED..."
      else
        echo "*** File \"$a\" is NEW or NOT TRACKED..."
      fi
    fi
  done
}

function do_upload() {
  echo "* did you run with \`-diff' to check differences first...?" 1>&2
  sleep 1

  # swap dirs for the diff read-only function
  [ -e "$LOCAL_SRC_RESTORE_DIR" ] || LOCAL_SRC_RESTORE_DIR="$LOCAL_SCRIPTS_DIR"

  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): target/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  # get the latest date
  LATEST=$(ls -dtr dl/home-* 2>/dev/null | tail -1)
  if [ -z "$LATEST" ]; then
    echo "$(basename $0): there is no backup << ./dl/home-XXX >> dir in <$LOCAL_SRC_RESTORE_DIR>, need to run \`$(basename $0) -restore' first!" 1>&2
    exit 99
  fi

  UPLOAD_MASTER_DEST="$REMOTE_SERVER:$REMOTE_REPOSITORY"

  # process the scripts
  set_files_list $1
  for a in $FILES_LIST; do
    LAST="$LATEST/$REMOTE_TAR_DIR_STRUCTURE/$a"
    if [ -e "$LAST" ]; then
      fmt_ls "$a"

      # DIFF?
      diff -q "$a" "$LAST" >&/dev/null
      DIFF=$?

      PARENT="/$(dirname "$a")"
      [ "$PARENT" = "/." ] && PARENT=""

      if [ $DIFF -ne 0 ]; then
        echo -e "*** File \"$a\" changed; UPLOAD to: \"$UPLOAD_MASTER_DEST$PARENT\" ? [y/N] \c"
        read CONF
        if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
          DONE="yes"

          # PRE-FETCH SSH PASSWORD
          if command -v sshpass >&/dev/null; then
            check_sshpass

            # get password if not already there
            if [ -z "$SSHPASS" ]; then
              echo -e "   ... Enter password for \"$UPLOAD_MASTER_DEST\": \c" 1>&2
              read -s PASSWORD
              echo 1>&2
              export SSHPASS="$PASSWORD"
            fi
          fi

          if [[ "$OSTYPE" == darwin* ]]; then
            #
            # COPY & OVERWRITE
            #
            run_ssh scp -o StrictHostKeyChecking=no "$a" $UPLOAD_MASTER_DEST$PARENT
          else
            # check that we don't overwrite a newer file
            SRC_TIME=$(ls -lo --time-style=+%s "$a" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            if [ -L "$a" ]; then
              REAL_PATH=$(realpath $a || exit 9)
              SRC_TIME=$(ls -lo --time-style=+%s "$REAL_PATH" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            fi
            #run_ssh ssh $REMOTE_SERVER ls -lo --time-style=+%s "$REMOTE_REPOSITORY/$PARENT/$a" |awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}' >/tmp/ls-out.$$
            run_ssh ssh $REMOTE_SERVER ls -lo --time-style=+%s "$REMOTE_REPOSITORY/$a" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}' >/tmp/ls-out.$$
            DST_TIME=$(cat /tmp/ls-out.$$)
            rm -f /tmp/ls-out.$$
            if [ -z "$SRC_TIME" -o -z "$DST_TIME" ]; then
              echo "--FATAL: can't get mtime of << $UPLOAD_MASTER_DEST/$a >> or << $a >>!" >&2
              exit 99
            elif [ $DST_TIME -gt $SRC_TIME ]; then
              echo -e "\n\n***********************"
              echo -ne "--***PROTECTION*** << DEST: SSH-REMOTE: $a >> is NEWER than << ./$a >>:\n-REMOTE: " >&2
              run_ssh ssh $REMOTE_SERVER ls -loh "$REMOTE_REPOSITORY/$a"
              ls -loh "$a" | sed 's/^/-LOCAL:  /'
              echo -e "***********************\n\n"
            else
              #
              # COPY & OVERWRITE
              #
              run_ssh scp -o StrictHostKeyChecking=no "$a" $UPLOAD_MASTER_DEST$PARENT
            fi
          fi
        fi
      fi
    elif [ $(grep -c "/" <<<$a) -eq 0 ]; then
      if [ ! -L "$a" ]; then
        PARENT="/$(dirname "$a")"
        [ "$PARENT" = "/." ] && PARENT=""

        echo -e "*** File \"$a\" is NEW; UPLOAD to: \"$UPLOAD_MASTER_DEST$PARENT\" ? [y/N] \c"
        read CONF
        if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
          DONE="yes"

          # PRE-FETCH SSH PASSWORD
          if command -v sshpass >&/dev/null; then
            # get password if not already there
            if [ -z "$SSHPASS" ]; then
              echo -e "   ... Enter password for \"$UPLOAD_MASTER_DEST\": \c" 1>&2
              read -s PASSWORD
              echo 1>&2
              export SSHPASS="$PASSWORD"
            fi
          fi

          # check if the file already exists remotely?
          run_ssh ssh $REMOTE_SERVER ls "$REMOTE_REPOSITORY/$PARENT/$a" >/tmp/ls-out.$$ 2>/dev/null
          EXISTS_REMOTELY=$(cat /tmp/ls-out.$$)
          rm -f /tmp/ls-out.$$

          if [ -n "$EXISTS_REMOTELY" ]; then
            echo -e "\n\n***********************"
            echo -e "--***PROTECTION*** << DEST: SSH-REMOTE: $a >> already exists:" >&2
            run_ssh ssh $REMOTE_SERVER ls -loh "$REMOTE_REPOSITORY/$PARENT/$a"
            echo -e "***********************\n\n"
          else
            #
            # COPY
            #
            run_ssh scp -o StrictHostKeyChecking=no "$a" $UPLOAD_MASTER_DEST$PARENT
          fi
        fi
      fi
    fi
  done

  if [ -n "$DONE" ]; then
    UPLOAD_UPDATE_CMD="ssh $REMOTE_SERVER $REMOTE_REPOSITORY/$(basename $0) -bkup"
    echo -e "\n*** Do you want to regenerate remote BKUP: \"$UPLOAD_UPDATE_CMD\" ? [y/N] \c"
    read CONF
    if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
      run_ssh $UPLOAD_UPDATE_CMD
      do_download
    fi
  fi
}

function do_update() {
  echo "* did you run with \`-diff' to check differences first...?" 1>&2
  sleep 1

  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  # get the latest date
  LATEST=$(ls -dtr dl/home-* | tail -1)

  # process the scripts
  set_files_list $1
  for a in $FILES_LIST; do
    LAST="$LATEST/$REMOTE_TAR_DIR_STRUCTURE/$a"
    if [ -e "$LAST" ]; then
      fmt_ls "$LAST"

      # DIFF?
      diff "$a" "$LAST" >&/dev/null
      DIFF=$?

      if [ $DIFF -ne 0 ]; then
        echo -e "*** File \"$a\" changed, update from \`$LATEST'? [y/N] \c"
        read CONF
        if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
          if [[ "$OSTYPE" == darwin* ]]; then
            #
            # COPY & OVERWRITE
            #
            cp -vpf "$LAST" "$a"

            [ $? -ne 0 ] && {
              echo "------last cp command non-zero abort code, ABORTING!" >&2
              exit 99
            }
          else
            # check that we don't overwrite a newer file
            SRC_TIME=$(/bin/ls -lo --time-style=+%s "$LAST" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            DST_TIME=$(/bin/ls -lo --time-style=+%s "$a" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            if [ -L "$LAST" ]; then
              REAL_PATH_SRC=$(realpath $LAST || exit 9)
              SRC_TIME=$(ls -lo --time-style=+%s "$REAL_PATH_SRC" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            fi
            if [ -L "$a" ]; then
              REAL_PATH_DST=$(realpath $a || exit 9)
              DST_TIME=$(ls -lo --time-style=+%s "$REAL_PATH_DST" | awk '/[0-9][0-9][0-9][0-9][0-9]/{print $5}')
            fi
            if [ -z "$SRC_TIME" -o -z "$DST_TIME" ]; then
              echo "--FATAL: can't get mtime of << $LAST >> or << $a >>!" >&2
              exit 99
            elif [ $DST_TIME -gt $SRC_TIME ]; then
              echo -e "\n\n***********************"
              echo -e "--***PROTECTION*** << DEST: ./$a >> is NEWER than << $LAST >>:" >&2
              ls -loh "$a" | sed 's/^/-DEST: /'
              ls -loh "$LAST" | sed 's/^/-SRC:  /'
              echo -e "***********************\n\n"
            else
              #
              # COPY & OVERWRITE
              #
              cp -vpf "$LAST" "$a"

              [ $? -ne 0 ] && {
                echo "------last cp command non-zero abort code, ABORTING!" >&2
                exit 99
              }
            fi
          fi
        fi
      fi
    fi
  done
}

function show_conf_differences() {
  # check that Config-Files exists
  if [ ! -d "$CONFIG_FILES_DIR" ]; then
    echo "$(basename $0): config-files target dir: <$CONFIG_FILES_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $CONFIG_FILES_DIR >/dev/null || exit 1

  # process the scripts
  set_files_list
  for a in $FILES_LIST; do
    LAST="$HOME/$a"
    [ ! -e "$LAST" -a -e "$HOME/.ssh/$a" ] && LAST="$HOME/.ssh/$a"
    [ ! -e "$LAST" -a -e "$HOME/.config/$a" ] && LAST="$HOME/.config/$a"

    if [ -e "$LAST" ]; then
      fmt_ls "$a"

      # DIFF?
      diff -q "$a" "$LAST" >&/dev/null
      DIFF=$?

      if [ $DIFF -ne 0 ]; then
        echo "*** Local conf \"$a\" is different, viewing differences..."
        sleep 1
        vimdiff -R -c ":set number" -c "cmap q qa" -c "set viminfo='0" "$LAST" "$a"
      fi
    fi
  done
}

function show_script_differences() {
  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): src/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  # check that local-scripts dir exists
  if [ ! -d "$LOCAL_SCRIPTS_DIR" ]; then
    echo "$(basename $0): target/strategic scripts dir: <$LOCAL_SCRIPTS_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  # process the scripts
  set_files_list
  for a in $FILES_LIST; do
    LAST="$LOCAL_SCRIPTS_DIR/$a"
    [ ! -e "$LAST" -a -e "$LOCAL_SCRIPTS_DIR/$(basename $a)" ] && LAST="$LOCAL_SCRIPTS_DIR/$(basename $a)"
    [ ! -e "$LAST" -a -e "$HOME/bin/$a" ] && LAST="$HOME/bin/$a"
    [ ! -e "$LAST" -a -e "$HOME/$a" ] && LAST="$HOME/$a"

    if [ -e "$LAST" ]; then
      fmt_ls "$a"

      # DIFF?
      diff -q "$a" "$LAST" >&/dev/null
      DIFF=$?

      if [ $DIFF -ne 0 ]; then
        echo "*** Local script \"$a\" is different, viewing differences..."
        sleep 1
        vimdiff -R -c ":set number" -c "cmap q qa" -c "set viminfo='0" "$LAST" "$a"
      fi
    fi
  done
}

function link_strategic_scripts() {
  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): src/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  # check that local-scripts dir exists
  if [ ! -d "$LOCAL_SCRIPTS_DIR" ]; then
    echo "$(basename $0): target/strategic scripts dir: <$LOCAL_SCRIPTS_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR || exit 1

  # process the scripts
  set_files_list $1

  # do we have 1 match or more?
  # - if we do have just one match, don't bother asking for conf
  if [ -n "$1" ]; then
    if [ -n "$FILES_LIST" ]; then
      if grep -q "^[A-Za-z0-9\/\._-]*$" <<<$FILES_LIST; then
        ONE_MATCH=1
      fi
    else
      echo "* no match for \"$1\" to link..." >&2
    fi
  fi

  for a in $FILES_LIST; do
    LAST="$LOCAL_SCRIPTS_DIR/$a"
    CONF_FILE=$(basename $a)
    [ ! -f "$LAST" -a -f "$LOCAL_SCRIPTS_DIR/$(basename $a)" ] && LAST="$LOCAL_SCRIPTS_DIR/$(basename $a)"
    [ ! -f "$LAST" -a -f "$HOME/bin/$a" ] && LAST="$HOME/bin/$a"
    [ ! -f "$LAST" -a -f "$HOME/$a" ] && LAST="$HOME/$a"

    [ ! -f "$LAST" -a -f "$HOME/bin/$CONF_FILE" ] && LAST="$HOME/bin/$CONF_FILE"
    [ ! -f "$LAST" -a -f "$HOME/$CONF_FILE" ] && LAST="$HOME/$CONF_FILE"
    [ ! -f "$LAST" -a -f "$HOME/.ssh/$CONF_FILE" ] && LAST="$HOME/.ssh/$CONF_FILE"

    if [ -f "$LAST" ]; then
      # ALREADY FILE THERE, CONVERT TO LINK
      fmt_ls "$a"

      # DIFF?
      diff -q "$a" "$LAST" >&/dev/null
      DIFF=$?

      if [ $DIFF -ne 0 ]; then
        echo -e "***\n*** Local script \"$a\" is different, please update first via: $0 -diff_scripts...\n***"
      elif [ ! -L "$a" ]; then
        # files are the same, OK to link
        FOUND_DIR=$(dirname $LAST)

        if [ -n "$ONE_MATCH" ]; then
          CONF="y"
        else
          echo -e "*** File \"$a\" exists in \"$FOUND_DIR\", convert here to symbolic link? [y/N] \c"
          read CONF
        fi

        if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
          [ -f "$a" ] || exit 99
          [ -f "$LAST" ] || exit 99

          # FORCE LINK
          ln -vsf "$LAST" "$a" || exit 1
        fi
      else
        echo "   ... $a: already a link to [$LAST]..."
      fi
    else
      # FILE NOT THERE, CREATE TO LINK
      fmt_ls "$a"

      # assertions
      [ -f "$a" ] || exit 99
      [ -e "$LOCAL_SCRIPTS_DIR/$a" ] && exit 99
      [ -e "$HOME/bin/$a" ] && exit 99
      [ -e "$HOME/$a" ] && exit 99

      # what is the target dir?
      TARGET_DIR=$LOCAL_SCRIPTS_DIR
      if grep -q "Config-Files" <<<$a; then
        if egrep -q 'conf|rc|profile' <<<$a; then
          TARGET_DIR=$HOME
        fi
      fi

      # OK to move and create link - ask
      if [ -n "$ONE_MATCH" ]; then
        CONF="y"
      else
        echo -e "*** File \"$a\" doesn't exist yet in \`$TARGET_DIR' move & create a link? [y/N] \c"
        read CONF
      fi

      if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
        # MOVE and CREATE LINK
        mv -iv "$a" "$TARGET_DIR"
        [ $? -ne 0 ] && {
          echo "------last mv command non-zero abort code, ABORTING!" >&2
          exit 99
        }

        ln -vs "$TARGET_DIR/$(basename $a)" "$a" || exit 3
        [ $? -ne 0 ] && {
          echo "------last ln command non-zero abort code, ABORTING!" >&2
          exit 99
        }

        # add +x if not there
        if egrep -q 'sh$|pl$|py$|cgi$' <<<$a; then
          chmod -f +x "$TARGET_DIR/$(basename $a)"
        fi
      fi
    fi
  done
}

function do_add_files() {
  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): target/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR >/dev/null || exit 1
  mkdir Config-Files 2>/dev/null

  # get the latest date
  LATEST=$(ls -dtr dl/home-* | tail -1)

  if [ ! -d "$LATEST/$REMOTE_TAR_DIR_STRUCTURE" ]; then
    echo "$(basename $0): target/restore src dir: <$LATEST/$REMOTE_TAR_DIR_STRUCTURE> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd "$LATEST/$REMOTE_TAR_DIR_STRUCTURE" >/dev/null || exit 1

  # process the scripts
  set_files_list $1

  # do we have 1 match or more?
  # - if we do have just one match, don't bother asking for conf
  if [ -n "$1" ]; then
    if [ -n "$FILES_LIST" ]; then
      if grep -q "^[A-Za-z0-9\/\._-]*$" <<<$FILES_LIST; then
        ONE_MATCH=1
      fi
    else
      echo "* no match for \"$1\" to add..." >&2
    fi
  fi

  for a in $FILES_LIST; do
    LAST="$LOCAL_SRC_RESTORE_DIR/$a"
    if [ ! -e "$LAST" ]; then
      fmt_ls "$a"

      if [ -n "$ONE_MATCH" ]; then
        CONF="y"
      else
        echo -e "*** File \"$a\" doesn't exist in \"$LOCAL_SRC_RESTORE_DIR\", add from \`$LATEST'? [y/N] \c"
        read CONF
      fi

      if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
        # create a parent dir if it doesn't exist...
        if grep -q "/" <<<$a; then
          mkdir "$LOCAL_SRC_RESTORE_DIR/$(dirname $a)" >&/dev/null
        fi

        # COPY
        cp -vpf "$a" "$LAST"

        [ $? -ne 0 ] && {
          echo "------last cp command non-zero abort code, ABORTING!" >&2
          exit 99
        }

        # add +x if not there
        if egrep -q 'sh$|pl$|py$|cgi$' <<<$a; then
          chmod -f +x "$LAST/$(basename $a)"
        fi
      fi
    elif [ -n "$ONE_MATCH" ]; then
      echo "*** File \"$a\" already exists in \"$LOCAL_SRC_RESTORE_DIR\"..."
    fi
  done

  # change back to original dir
  if grep -q "dl/home" <<<$PWD; then
    cd - >&/dev/null
  fi
}

function do_add_from_remote() {
  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): target/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR >/dev/null || exit 1

  UPLOAD_MASTER_DEST="$REMOTE_SERVER:$REMOTE_REPOSITORY"
  if [ -z "$1" ]; then
    echo "$(basename $0): you need to provide a pattern of a file to download from $UPLOAD_MASTER_DEST" 1>&2
    exit 88
  fi

  #
  # EXEC
  #

  PATTERN="*$1*"
  if grep -q '\*' <<<$1; then
    PATTERN="$1"
  fi

  TARGET="."
  [ -n "$2" ] && TARGET="$2"

  echo "+ scp $UPLOAD_MASTER_DEST/$PATTERN $TARGET"
  run_ssh scp -o StrictHostKeyChecking=no "$UPLOAD_MASTER_DEST/$PATTERN" $TARGET
}

function gen_full_remote() {
  # check that target-dir exists
  if [ ! -d "$LOCAL_SRC_RESTORE_DIR" ]; then
    echo "$(basename $0): target/restore src dir: <$LOCAL_SRC_RESTORE_DIR> doesn't exist, nothing to do!" 1>&2
    exit 99
  fi

  cd $LOCAL_SRC_RESTORE_DIR >/dev/null || exit 1

  UPLOAD_UPDATE_CMD="ssh $REMOTE_SERVER $REMOTE_REPOSITORY/$(basename $0) -bkup"
  echo -e "*** Do you want to regenerate FULL remote BKUP: \"$UPLOAD_UPDATE_CMD -full\" ? [y/N] \c"
  read CONF
  if [ "$CONF" = "y" -o "$CONF" = "Y" ]; then
    run_ssh $UPLOAD_UPDATE_CMD -full
  fi
}

function do_setup() {
  ORIG_PWD=$PWD

  # if we're in home and not in src, then set up ~/src
  if ! grep -q src <<<$PWD; then
    if [ "$PWD" = "$HOME" ]; then
      echo && echo "- INITIAL SETUP: setting up main src dir: $HOME/src:" 1>&2
      chmod 755 $0 >&/dev/null
      cd >&/dev/null || exit 1
      mkdir src >&/dev/null
      chmod 755 src >&/dev/null
      cd src || exit 1

      # move the dl.sh file here
      [ -r ../dl.sh ] && mv -v ../dl.sh .
      [ -r ../kw-dl-sh ] && mv -v ../kw-dl-sh .
      [ -r ../k-dl-sh ] && mv -v ../k-dl-sh .
    fi
  fi

  # do we have the file locally?
  if [ -s "$TAR_BACKUP_NAME" -a ! -d dl ]; then
    # VIRGIN LOCAL RUN (do not use internet)
    mkdir dl >&/dev/null
    mv "$TAR_BACKUP_NAME" dl || exit 2
  else
    # get the latest updates
    do_download
  fi

  # add key files
  # - Note: we don't add tmux.conf in Google Cloud Shell, as that causes incompatibility, use screen instead
  WHOAMI=$(whoami)
  [ -z "$WHOAMI" ] && WHOAMI=$(who am I | awk '{print $1}')
  [ -z "$WHOAMI" ] && WHOAMI=$USER
  if [ "$WHOAMI" = "root" ]; then
    echo && echo "- ROOT MODE: copying key files:" 1>&2
    do_add_files vimrc
    do_add_files zshrc
    do_add_files bash_profile

    do_add_files hw-info.sh
    do_add_files ip-location.sh
    do_add_files setup-linux-system.sh
    do_add_files setup-aws-gcp.sh
    do_add_files test-system-speed.sh

    # we deploy/link just ONE file for root - VIMRC
    cp -v ~/src/Config-Files/.vimrc ~/
  else
    echo && echo "- Non-root mode: copying key files:" 1>&2
    do_add_files vimrc
    do_add_files zshrc
    do_add_files bash_profile
    do_add_files screenrc
    [ ! -n "$DEVSHELL_SERVER_URL" ] && do_add_files tmux.conf

    do_add_files hw-info.sh
    do_add_files ip-location.sh
    do_add_files setup-linux-system.sh
    do_add_files setup-aws-gcp.sh
    do_add_files test-system-speed.sh

    # add .ssh config
    # - special case
    echo && echo "- copying ssh config:" 1>&2
    mkdir $HOME/.ssh >&/dev/null
    chmod 700 $HOME/.ssh >&/dev/null

    # change to latest backup dir
    cd $LOCAL_SRC_RESTORE_DIR >/dev/null || exit 1
    # get the latest date
    LATEST=$(ls -dtr dl/home-* | tail -1)
    cd "$LATEST/$REMOTE_TAR_DIR_STRUCTURE" >/dev/null || exit 1

    [ -s "$CONFIG_FILES_DIR/.ssh/config" ] || {
      echo "--FATAL: can't find master SSH config file: << $CONFIG_FILES_DIR/.ssh/config >> (pwd=$(pwd)) !!!" 1>&2
      exit 99
    }
    cp -pf "$CONFIG_FILES_DIR/.ssh/config" $HOME/.ssh
    chmod 600 $HOME/.ssh/* >&/dev/null
    cd - >&/dev/null

    # create some key dirs
    echo && echo "- linking strategic scripts/files:"
    mkdir -p ~/bin/scripts >&/dev/null
    chmod 755 ~/bin ~/bin/scripts >&/dev/null

    # link
    link_strategic_scripts vimrc
    link_strategic_scripts zshrc
    link_strategic_scripts bash_profile
    link_strategic_scripts screenrc
    [ ! -n "$DEVSHELL_SERVER_URL" ] && link_strategic_scripts tmux.conf

    link_strategic_scripts hw-info.sh
    link_strategic_scripts setup-linux-system.sh
    link_strategic_scripts setup-aws-gcp.sh
    link_strategic_scripts ip-location.sh
    link_strategic_scripts test-system-speed.sh
  fi

  # execute the HW-INFO
  if [ -x ./HW-Info/hw-info.sh ]; then
    echo && echo "- running hw-info.sh:"
    ./HW-Info/hw-info.sh
  else
    echo && echo "--WARN: no HW-Info script?" >&2
  fi

  # rename to strategic script
  chmod 755 $0 >&/dev/null
  if [ "$0" != "$(dirname $0)/$SCRIPT_NAME" ]; then
    echo && echo "- renaming $(basename $0) to $SCRIPT_NAME:"
    cd $LOCAL_SRC_RESTORE_DIR >&/dev/null
    FROM_NAME=$0
    [ ! -e "$FROM_NAME" -a -e "../$FROM_NAME" ] && FROM_NAME="../$FROM_NAME"
    [ ! -e "$FROM_NAME" -a -e "../src/$FROM_NAME" ] && FROM_NAME="../src/$FROM_NAME"
    [ ! -e "$FROM_NAME" -a -e "../playground/$FROM_NAME" ] && FROM_NAME="../playground/$FROM_NAME"
    [ ! -e "$FROM_NAME" -a -e "./src/$FROM_NAME" ] && FROM_NAME="./src/$FROM_NAME"
    [ ! -e "$FROM_NAME" -a -e "./playground/$FROM_NAME" ] && FROM_NAME="./playground/$FROM_NAME"

    if [ -e "$FROM_NAME" ]; then
      mv -fv $FROM_NAME "$(dirname $0)/$SCRIPT_NAME" || exit 9
      chmod 755 $FROM_NAME >&/dev/null
    else
      echo "--WARN: having issues doing the rename of $0 to $(dirname $0)/$SCRIPT_NAME !!!" >&2
      echo "* this source file doesn't exist: $FROM_NAME  [ORIG=$0]" >&2
      echo "* didn't do the strategic rename [PWD=$PWD]!" >&2
    fi

    # create a link in HOME
    cd >&/dev/null
    [ -d src -a -s ./src/$SCRIPT_NAME -a ! -L $SCRIPT_NAME ] && ln -s ./src/$SCRIPT_NAME
    [ -d playground -a -s ./playground/$SCRIPT_NAME ] && ln -s ./playground/$SCRIPT_NAME
    cd - >&/dev/null
  fi

  # provide some info
  # NOTE: this only works on Linux
  if [ "$OSTYPE" = "linux-gnu" -o "$OSTYPE" = "linux" ]; then
    echo && echo "- now finalize via the following commands:"

    SRC_PREFIX=""
    if grep -q "\.\." <<<$FROM_NAME; then
      SRC_PREFIX="/$(basename $LOCAL_SRC_RESTORE_DIR)"
    fi
    if [ ! -e ".$SRC_PREFIX/Shell-Tools" ]; then
      [ -d ~/bin/scripts/Shell-Tools ] && SRC_PREFIX="/bin/scripts"
      [ -d ~/src/Shell-Tools ] && SRC_PREFIX="/src"
    fi

    # when during the original setup
    if [ -n "$ORIG_PWD" -a "$ORIG_PWD" = "$HOME" -a -r "$HOME/$SCRIPT_NAME" ]; then
      SRC_PREFIX="/src"
    fi

    # ZSH
    # - do we have it installed?
    # - is it set as the SHELL?

    #if [ ! -x /bin/zsh ]; then
    #  echo "$ sudo apt install -qq -y zsh"
    #fi
    if [ "$WHOAMI" = "root" ]; then
      [ ! -x /bin/zsh ] && echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -ZSH"
    elif grep -q "$USER.*zsh" /etc/passwd; then
      echo "... shell set to: ZSH" >&/dev/null
    else
      # this will install & set to ZSH in one operation
      # - for root, it doesn't do that
      echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -ZSH"
    fi

    # add-user
    if [ "$WHOAMI" = "root" -o "$WHOAMI" = "ubuntu" -o "$WHOAMI" = "ec2-user" ]; then
      echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -USER <user>"

      # make a link to the home
      ln -s .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh $HOME/ >&/dev/null
    fi

    # TZ
    [ -r /etc/timezone -a -s /etc/timezone ] && TZ=$(cat /etc/timezone)
    [ -z "$TZ" ] && TZ=$(ls -l /etc/localtime 2>/dev/null | grep zoneinfo | sed 's/.*zoneinfo\/\(.*\)$/\1/')
    if [ "$EUID" -eq 0 ] || command -v sudo >&/dev/null; then
      if [ -n "$TZ" ]; then
        if egrep -q "$FAVE_TIMEZONE" <<<$TZ; then
          echo "... timezone set to: $FAVE_TIMEZONE" >&/dev/null
        else
          TZ_CHANGE_NEEDED=1
          echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -TZ      [currently set to: $TZ]"
        fi
      else
        TZ_CHANGE_NEEDED=1
        echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -TZ"
      fi

      # additional check for UTC
      if [ -z "$TZ_CHANGE_NEEDED" ]; then
        TZ=$(unset TZ && sudo -in date >&/dev/null)
        [ -z "$TZ" ] && TZ=$(unset TZ && date)
        if grep -q UTC <<<$TZ; then
          echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -TZ      [currently set to: UTC]"
        fi
      fi
    else
      # no root access
      if [ -n "$TZ" ]; then
        echo "FYI: current timezone set to << $TZ >> but no root-access to change" >&2
      fi
    fi

    # DYNAMIC DNS
    if egrep -q "^gcp-|^ec2-|^az-|^cs-.*default" <<<$HOST; then
      echo "$ .$SRC_PREFIX/Shell-Tools/setup-aws-gcp.sh -dyn_dns   [can be done automatically via setup-aws-gcp.sh]"
    elif [ -n "$DEVSHELL_SERVER_URL" -o -n "$DEVSHELL_SERVER_BASE_URL" ]; then
      echo "$ .$SRC_PREFIX/Shell-Tools/setup-aws-gcp.sh -dyn_dns"
    fi

    # INSTALL PACKAGES
    if [ "$EUID" -eq 0 ] || command -v sudo >&/dev/null; then
      [ -x /usr/bin/apt ] && echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -SSH_CONF    [uses \`apt']"
      [ "$HOST" = "localhost" -o "$(uname -n 2>/dev/null)" = "localhost" ] && echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -HOSTNAME    [currently set to $(uname -n)]"
      echo "$ .$SRC_PREFIX/Shell-Tools/setup-linux-system.sh -GENPKG"
    fi

    # suggest: perf test
    echo "-> test performance: .$SRC_PREFIX/Shell-Tools/test-system-speed.sh -cpumark"
  fi
}

#
# MAIN
#
if [ "$1" = "-bkup" -o "$1" = "-backup" -o "$1" = "-tar" ]; then
  do_backup $2
elif [ "$1" = "-dl" -o "$1" = "-restore" -o "$1" = "-rest" -o "$1" = "-get" ]; then
  do_download
elif [ "$1" = "-diff" -o "$1" = "-diffs" ]; then
  show_differences $2
elif [ "$1" = "-upload" -o "$1" = "-upload_remote" -o "$1" = "-upl" ]; then
  do_upload $2
elif [ "$1" = "-update" -o "$1" = "-update_local" ]; then
  do_update $2
elif [ "$1" = "-dlupd" -o "$1" = "-dl_upd" -o "$1" = "dl_update" -o "$1" = "-dlup" -o "$1" = "-ldup" ]; then
  do_download
  echo && echo "- showing diffs:"
  show_differences $2
  echo && echo "- doing update:"
  do_update $2
elif [ "$1" = "-add" -o "$1" = "-add_files" ]; then
  do_add_files $2
elif [ "$1" = "-setup" ]; then
  do_setup
elif [ "$1" = "-add_from_remote" -o "$1" = "-add_remote" -o "$1" = "-dl_remote" -o "$1" = "-add_dl" ]; then
  do_add_from_remote $2 $3
elif [ "$1" = "-gen_full_remote" -o "$1" = "-gen_full" ]; then
  gen_full_remote
elif [ "$1" = "-diff_conf" -o "$1" = "-diff-conf" -o "$1" = "-diff-config" -o "$1" = "-diff_config" ]; then
  show_conf_differences
elif [ "$1" = "-diff_scripts" -o "$1" = "-diff-scripts" -o "$1" = "-diff_src" ]; then
  show_script_differences
elif [ "$1" = "-link_scripts" -o "$1" = "-link-scripts" -o "$1" = "-link_src" -o "$1" = "-link" -o "$1" = "-link-script" -o "$1" = "-link_script" ]; then
  link_strategic_scripts $2
elif [ $# -eq 0 ]; then
  if egrep -q 'dl.sh|k-dl-sh|kw-dl-sh' <<<$0; then
    echo "<--> assuming: $0 -setup [via dl.sh]" >&2
    do_setup
  elif [ -L "$0" -a "$PWD" = "$HOME" -a ! -e ./src/Config-Files -a ! -e ./src/Shell-Tools ]; then
    echo "<--> assuming: $0 -setup [1st-time setup]" >&2
    do_setup
  elif [ "$PWD" = "$HOME" -a ! -e ./src -a ! -e ./bin -a $(ls | wc -l) -eq 1 ]; then
      echo "<--> assuming: $0 -setup [empty-dir setup]" >&2
    do_setup
  elif [ -L "$0" -a "$PWD" = "$HOME" -a -e ./src/Config-Files -a -e ./src/Shell-Tools -a -r ./src/$SCRIPT_NAME ]; then
    echo "<--> assuming: $0 -dlupd [update, via link]" >&2
    do_download
    echo && echo "- showing diffs:"
    show_differences $2
    echo && echo "- doing update:"
    do_update $2
  else
    #exec $0 --help
    # exec not available on latest MacOS builds
    $0 --help
    exit $?
  fi
else
  UPLOAD_MASTER_DEST="$REMOTE_SERVER:$REMOTE_REPOSITORY"

  echo -e "Usage: $(basename $0) <-dl|-add|-diff|-update|-bkup [-all]|-upload>\n" 1>&2

  echo "CLIENT:" 1>&2
  echo -e "-dl            - download the latest backup from the remote host (run on client)" 1>&2
  echo -e "-add [crit]    - add files from a dl backup to local dir (run on the client)" 1>&2
  echo -e "-update [crit] - update the modified files from the latest backup (run on client)\n" 1>&2

  echo -e "-dlupd [crit]  - shortcut to re-download and re-update from remote (run on client)" 1>&2
  echo -e "-setup         - shortcut to setup a new machine by adding key files (run on client)\n" 1>&2

  echo -e "-diff [crit]   - check your differences with the latest backup (run on client)" 1>&2
  echo -e "-upload [crit] - upload the diffs to << $UPLOAD_MASTER_DEST >> (run on client)\n" 1>&2

  echo -e "-diff_conf     - check differences between Config-Files (run on client)" 1>&2
  echo -e "-diff_scripts  - check differences between ~/bin/scripts (run on client)" 1>&2
  echo -e "-link_scripts  - create strategic symbolic links to $LOCAL_SCRIPTS_DIR (run on client)\n" 1>&2

  echo -e "-gen_full_remote             - generate full remote TAR.GZ to get ALL files from remote (run on client)" 1>&2
  echo -e "-add_from_remote <pattern>   - adds a file from remote server << $UPLOAD_MASTER_DEST >> using pattern (run on client)\n" 1>&2

  echo "SERVER:" 1>&2
  echo -e "-bkup [-all]  - bkup (incremental|full) (run on the remote host)\n" 1>&2
fi

# EOF
