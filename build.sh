#!/bin/bash
NAME_SRC_FILE="$1"
dir_work=/tmp/rom
log_build=/tmp/ci/build_error
GIT_USER=$(grep git_user $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
GIT_EMAIL=$(grep git_email $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
MANIFEST=$(grep name_MANIFEST $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
BRANCH=$(grep name_BRANCH $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
DEVICE=$(grep name_vendor $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
MODEL=$(grep device_model $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
lunch_type_rom=$(grep name_lunch_type $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
PACKAGE=$(grep build_PACKAGE_command $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
BUILD_TYPE=$(grep name_BUILD_TYPE $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
LDEVICE=$(grep link_device $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
LVENDOR=$(grep link_vendor $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
LKERNEL=$(grep link_kernel $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
get_patches=$(grep patch $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')
echo $(pwd)/build_error

#BASE SETUP
# Setup TG message and build posts
telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot${BOTTOKEN}/sendMessage" -d chat_id="${CHATID}" \
    -d "parse_mode=Markdown" \
    -d text="$1" 2>&1 | tee -a ${log_build}
}

telegram_build() {
    curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot${BOTTOKEN}/sendDocument" \
    -F chat_id="${CHATID}" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=Markdown" \
    -F caption="$2" 2>&1 | tee -a ${log_build}
}


# Setup build dir
build_dir() {
    mkdir -p $dir_work
    cd $dir_work || exit
}


tree_path() {
    # Device,vendor & kernel Tree paths
    DEVICE_TREE=device/$DEVICE/$MODEL
    VENDOR_TREE=vendor/$DEVICE/$MODEL
    KERNEL_TREE=kernel/$DEVICE/$MODEL
}

# Git configuration values
git_setup() {
    
    git clone --depth 1 $LDEVICE $DEVICE_TREE 2>&1 | tee -a ${log_build}
    git clone --depth 1 $LVENDOR $VENDOR_TREE 2>&1 | tee -a ${log_build}
    git clone --depth 1 $LKERNEL $KERNEL_TREE 2>&1 | tee -a ${log_build}
}

apply_patch() {
    eval $get_patches 2>&1 | tee -a ${log_build}
}

# Build post-gen variables (optional)
lazy_build_post_var() {
    LAZY_BUILD_POST=true
    INCLUDE_GAPPS="$(grep INCLUDE_GAPPS $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    ROM_VERSION="$(grep ROM_VERSION $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    ROM_TYPE="$(grep ROM_TYPE $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    ANDROID_VERSION="$(grep ANDROID_VERSION $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    RELEASE_TYPE="$(grep RELEASE_TYPE $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    DEV="$(grep DEV $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    TG_LINK="$(grep TG_LINK $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
    GRP_LIN="$(grep GRP_LIN $NAME_SRC_FILE | cut -f2 -d"=" | tr -d '\r')"
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
    repo init -u $MANIFEST -b $BRANCH  2>&1 | tee ${log_build}
    repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j4 2>&1 | tee -a ${log_build}
    {
    echo ""
    echo ""
    echo ""
    printf "\nFinal Repository kernel Should Look Like...\n" && ls -lAog $dir_work
    echo ""
    echo ""
    echo ""
    echo ""
    } 2>&1 | tee -a ${log_build}
}

time_diff() {
    export $1=$(($3 - $2))
}

telegram_post_sync() {
    telegram_message "
	*🌟 $NAME Build Triggered 🌟*
	*Date:* \`$(date +"%d-%m-%Y %T")\`
    *✅ Sync finished after $((SDIFF / 60)) minute(s) and $((SDIFF % 60)) seconds*"  2>&1 | tee -a ${log_build}
}

# Build commands for rom
build_command() {
    source build/envsetup.sh
    lunch ${lunch_type_rom}_${MODEL}-${BUILD_TYPE} 2>&1 | tee -a ${log_build}
    eval $PACKAGE 2>&1 | tee -a ${log_build}
}

# Sorting final zip ( commonized considering ota zips, .md5sum etc with similiar names  in diff roms)
post=()
compiled_zip() {
    OUT=$(pwd)/out/target/product/${DEVICE}
    ZIP=$(find ${OUT}/ -maxdepth 1 -name "*${DEVICE}*.zip" | perl -e 'print sort { length($b) <=> length($a) } <>' | head -n 1)
    ZIPNAME=$(basename ${ZIP})
    ZIPSIZE=$(du -sh ${ZIP} |  awk '{print $1}')
    MD5CHECK=$(md5sum ${ZIP} | cut -d' ' -f1)
    echo "${ZIP}" 2>&1 | tee -a ${log_build}
    post+=("${ZIP}") && post+=("${ZIPNAME}") && post+=("${ZIPSIZE}") && post+=("${MD5CHECK}")
}

# Branch name & Head commit sha for ease of tracking
commit_sha() {
    for repo in ${DEVICE_TREE} ${VENDOR_TREE} ${KERNEL_TREE}
    do
        printf "[$(echo $repo | cut -d'/' -f1 )/$(git -C ./$repo/.git rev-parse --short=10 HEAD)]" 2>&1 | tee -a ${log_build}
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
        echo "CHECK BUILD LOG" >> ${log_build}
        ERROR_LOG=${log_build}
        telegram_build ${ERROR_LOG} "
	*❌ Build failed to compile after $(($BDIFF / 3600)) hour(s) and $(($BDIFF % 3600 / 60)) minute(s) and $(($BDIFF % 60)) seconds*
        _Date:  $(date +"%d-%m-%Y %T")_"
    fi
}

compile_moment() {
    build_dir # 2>&1 | tee ${log_build}
    git config --global user.name $GIT_USER
    git config --global user.email $GIT_EMAIL
    tree_path # 2>&1 | tee -a ${log_build}
    build_configuration # 2>&1 | tee -a ${log_build}
    git_setup # 2>&1 | tee -a ${log_build}
    lazy_build_post_var # 2>&1 | tee -a ${log_build}
    #ssh_authenticate # 2>&1 | tee -a ${log_build}
    time_sec SYNC_START # 2>&1 | tee -a ${log_build}
    apply_patch # 2>&1 | tee -a ${log_build}
    time_sec SYNC_END # 2>&1 | tee -a ${log_build}
    time_diff SDIFF SYNC_START SYNC_END # 2>&1 | tee -a ${log_build}
    telegram_post_sync # 2>&1 | tee -a ${log_build}
    time_sec BUILD_START # 2>&1 | tee -a ${log_build}
    build_command # 2>&1 | tee -a ${log_build}
    time_sec BUILD_END # 2>&1 | tee -a ${log_build}
    time_diff BDIFF BUILD_START BUILD_END # 2>&1 | tee -a ${log_build}
    compiled_zip # 2>&1 | tee -a ${log_build}
    if [ ! $INCLUDE_GAPPS = true ]; then
        telegram_post # 2>&1 | tee -a ${log_build}
    fi
    build_gapps # 2>&1 | tee -a ${log_build}
}

compile_moment
