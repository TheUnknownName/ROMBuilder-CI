#!/bin/bash
NAME_SRC_FILE="$1"
GIT_USER="$(grep git_user $NAME_SRC_FILE | cut -f2 -d"=" )"
GIT_EMAIL="$(grep git_email $NAME_SRC_FILE | cut -f2 -d"=" )"
MANIFEST="$(grep MANIFEST $NAME_SRC_FILE | cut -f2 -d"=" )"
BRANCH="$(grep BRANCH $NAME_SRC_FILE | cut -f2 -d"=" )"
DEVICE="$(grep vendor $NAME_SRC_FILE | cut -f2 -d"=" )"
MODEL="$(grep device_model $NAME_SRC_FILE | cut -f2 -d"=" )"
PACKAGE="$(grep PACKAGE $NAME_SRC_FILE | cut -f2 -d"=" )"
BUILD_TYPE="$(grep BUILD_TYPE $NAME_SRC_FILE | cut -f2 -d"=" )"
LDEVICE="$(grep link_device $NAME_SRC_FILE | cut -f2 -d"=" )"
LVENDOR="$(grep link_vendor $NAME_SRC_FILE | cut -f2 -d"=" )"
LKERNEL="$(grep link_kernel $NAME_SRC_FILE | cut -f2 -d"=" )"
get_patches="$(grep patch $NAME_SRC_FILE | cut -f2 -d"=" )"

#BASE SETUP
# Setup TG message and build posts
telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOTTOKEN}/sendMessage" -d chat_id="${CHATID}" \
    -d "parse_mode=Markdown" \
    -d text="$1"
}

telegram_build() {
    curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot${BOTTOKEN}/sendDocument" \
    -F chat_id="${CHATID}" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=Markdown" \
    -F caption="$2"
}


# Setup build dir
build_dir() {
    mkdir -p /tmp/rom
    cd /tmp/rom || exit
}

# Git configuration values
git_setup() {
    git config --global user.name $GIT_USER
    git config --global user.email $GIT_EMAIL
    
    git clone $LDEVICE device/$DEVICE/$MODEL
    git clone $LVENDOR vendor/$DEVICE
    git clone $LKERNEL kernel/$DEVICE/$MODEL
    eval $get_patches
} > git_log.txt

# Build post-gen variables (optional)
lazy_build_post_var() {
    LAZY_BUILD_POST=true
    INCLUDE_GAPPS="$(grep INCLUDE_GAPPS $NAME_SRC_FILE | cut -f2 -d"=" )"
    ROM_VERSION="$(grep ROM_VERSION $NAME_SRC_FILE | cut -f2 -d"=" )"
    ROM_TYPE="$(grep ROM_TYPE $NAME_SRC_FILE | cut -f2 -d"=" )"
    ANDROID_VERSION="$(grep ANDROID_VERSION $NAME_SRC_FILE | cut -f2 -d"=" )"
    RELEASE_TYPE="$(grep RELEASE_TYPE $NAME_SRC_FILE | cut -f2 -d"=" )"
    DEV="$(grep DEV $NAME_SRC_FILE | cut -f2 -d"=" )"
    TG_LINK="$(grep TG_LINK $NAME_SRC_FILE | cut -f2 -d"=" )"
    GRP_LIN="$(grep GRP_LIN $NAME_SRC_FILE | cut -f2 -d"=" )"
}

# SSH configuration using priv key
ssh_authenticate() {
    sudo chmod 0600 /tmp/rom/ssh_ci
    sudo mkdir ~/.ssh && sudo chmod 0700 ~/.ssh
    eval `ssh-agent -s` && ssh-add /tmp/rom/ssh_ci
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
}

# Export time, time format for telegram messages
time_sec() {
    export $1=$(date +"%s")
}

# Repo sync and additional configurations
build_configuration() {
    repo init --depth=1 --no-repo-verify -u $MANIFEST  -b $BRANCH -g default,-mips,-darwin,-notdefault
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j13
}

time_diff() {
    export $1=$(($3 - $2))
}

telegram_post_sync() {
    telegram_message "
	*🌟 $NAME Build Triggered 🌟*
	*Date:* \`$(date +"%d-%m-%Y %T")\`
    *✅ Sync finished after $((SDIFF / 60)) minute(s) and $((SDIFF % 60)) seconds*"  &> /dev/null
}

tree_path() {
    # Device,vendor & kernel Tree paths
    DEVICE_TREE=device/$DEVICE/$MODEL
    VENDOR_TREE=vendor/$DEVICE
    KERNEL_TREE=kernel/$DEVICE/$MODEL
}

# Build commands for rom
build_command() {
    source build/envsetup.sh
    tree_path
    lunch $(basename -s .mk $(find $DEVICE_TREE -maxdepth 1 -name "*$DEVICE*.mk"))-${BUILD_TYPE}
    m ${PACKAGE} -j 20
}

# Sorting final zip ( commonized considering ota zips, .md5sum etc with similiar names  in diff roms)
post=()
compiled_zip() {
    OUT=$(pwd)/out/target/product/${DEVICE}
    ZIP=$(find ${OUT}/ -maxdepth 1 -name "*${DEVICE}*.zip" | perl -e 'print sort { length($b) <=> length($a) } <>' | head -n 1)
    ZIPNAME=$(basename ${ZIP})
    ZIPSIZE=$(du -sh ${ZIP} |  awk '{print $1}')
    MD5CHECK=$(md5sum ${ZIP} | cut -d' ' -f1)
    echo "${ZIP}"
    post+=("${ZIP}") && post+=("${ZIPNAME}") && post+=("${ZIPSIZE}") && post+=("${MD5CHECK}")
}

# Branch name & Head commit sha for ease of tracking
commit_sha() {
    for repo in ${DEVICE_TREE} ${VENDOR_TREE} ${KERNEL_TREE}
    do
        printf "[$(echo $repo | cut -d'/' -f1 )/$(git -C ./$repo/.git rev-parse --short=10 HEAD)]"
    done
}

# Setup Gapps package on release post generation
build_gapps() {
    if [ $INCLUDE_GAPPS = true ]; then
        rm -rf ${post[0]}
        export WITH_GAPPS=true
        build_command
        compiled_zip
        telegram_post
    fi
}

build_upload() {
    if [ -f ${OUT}/${post[1]} ]; then
        rclone copy ${post[0]} brrbrr:rom -P
        DWD1=${TDRIVE}${post[1]}
        ZIPS="[Vanilla](${DWD1}) (${post[2]})"
        elif [ -f ${OUT}/${post[5]} ]; then
        rclone copy ${post[4]} brrbrr:rom -P
        DWD2=${TDRIVE}${post[5]}
        ZIPS="[Vanilla](${DWD1}) (${post[2]}) | [Gapps](${DWD2}) (${post[6]})"
    fi
}

telegram_post() {
    if [[ -f ${OUT}/${post[1]} ]]; then
        telegram_build ${OUT}/${post[1]} "
    Build SUCCESFULL to compile after $(($BDIFF / 3600)) hour(s) and $(($BDIFF % 3600 / 60)) minute(s) and $(($BDIFF % 60)) seconds*
        _Date:  $(date +"%d-%m-%Y %T")_"
        elif [[ -f ${OUT}/${post[5]} ]];then
        telegram_build ${OUT}/${post[5]} "
    Build SUCCESFULL to compile after $(($BDIFF / 3600)) hour(s) and $(($BDIFF % 3600 / 60)) minute(s) and $(($BDIFF % 60)) seconds*
        _Date:  $(date +"%d-%m-%Y %T")_"
    else
        echo "CHECK BUILD LOG" >> $(pwd)/out/build_error
        ERROR_LOG=$(pwd)/out/build_error
        telegram_build ${ERROR_LOG} "
	*❌ Build failed to compile after $(($BDIFF / 3600)) hour(s) and $(($BDIFF % 3600 / 60)) minute(s) and $(($BDIFF % 60)) seconds*
        _Date:  $(date +"%d-%m-%Y %T")_"
    fi
}

compile_moment() {
    build_dir
    git_setup
    lazy_build_post_var
    ssh_authenticate
    time_sec SYNC_START
    rom
    build_configuration
    time_sec SYNC_END
    time_diff SDIFF SYNC_START SYNC_END
    telegram_post_sync
    time_sec BUILD_START
    build_command
    time_sec BUILD_END
    time_diff BDIFF BUILD_START BUILD_END
    compiled_zip
    if [ ! $INCLUDE_GAPPS = true ]; then
        telegram_post
    fi
    build_gapps
}

compile_moment
