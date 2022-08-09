#!/bin/bash

MODULE_TEMPLATE_DIR="revanced-magisk"
MODULE_SCRIPTS_DIR="scripts"
TEMP_DIR="temp"
BUILD_DIR="build"

ARM64_V8A="arm64-v8a"
ARM_V7A="arm-v7a"
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$GITHUB_REPO_FALLBACK}
NEXT_VER_CODE=${NEXT_VER_CODE:-$(date +'%Y%m%d')}
WGET_HEADER="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:102.0) Gecko/20100101 Firefox/102.0"

SERVICE_SH=$(cat $MODULE_SCRIPTS_DIR/service.sh)
POSTFSDATA_SH=$(cat $MODULE_SCRIPTS_DIR/post-fs-data.sh)
CUSTOMIZE_SH=$(cat $MODULE_SCRIPTS_DIR/customize.sh)

get_prebuilts() {
	echo "Getting prebuilts"
	mkdir -p "$TEMP_DIR"
	RV_CLI_URL=$(req https://api.github.com/repos/revanced/revanced-cli/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*jar\)".*/\1/p')
	RV_CLI_JAR="${TEMP_DIR}/$(echo "$RV_CLI_URL" | awk -F/ '{ print $NF }')"
	log "CLI: ${RV_CLI_JAR#"$TEMP_DIR/"}"
	RV_INTEGRATIONS_URL=$(req https://api.github.com/repos/revanced/revanced-integrations/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*apk\)".*/\1/p')
	RV_INTEGRATIONS_APK="${TEMP_DIR}/$(echo "$RV_INTEGRATIONS_URL" | awk '{n=split($0, arr, "/"); printf "%s-%s.apk", substr(arr[n], 0, length(arr[n]) - 4), arr[n-1]}')"
	log "Integrations: ${RV_INTEGRATIONS_APK#"$TEMP_DIR/"}"

	RV_PATCHES_URL=$(req https://api.github.com/repos/revanced/revanced-patches/releases/latest - | tr -d ' ' | sed -n 's/.*"browser_download_url":"\(.*jar\)".*/\1/p')
	RV_PATCHES_JAR="${TEMP_DIR}/$(echo "$RV_PATCHES_URL" | awk -F/ '{ print $NF }')"
	log "Patches: ${RV_PATCHES_JAR#"$TEMP_DIR/"}"

	dl_if_dne "$RV_CLI_JAR" "$RV_CLI_URL"
	dl_if_dne "$RV_INTEGRATIONS_APK" "$RV_INTEGRATIONS_URL"
	dl_if_dne "$RV_PATCHES_JAR" "$RV_PATCHES_URL"
}

extract_deb() {
	local output=$1 url=$2 path=$3
	if [ -f "$output" ] || [ -n "$(ls -A "$output")" ]; then return; fi
	local deb_path="${TEMP_DIR}/${url##*/}"
	dl_if_dne "$deb_path" "$url"
	ar x "$deb_path" data.tar.xz
	if [ "${output: -1}" = "/" ]; then
		tar -C "$output" -xf data.tar.xz --wildcards "$path" --strip-components 7
	else
		tar -C "$TEMP_DIR" -xf data.tar.xz "$path" --strip-components 7
		mv -f "${TEMP_DIR}/${path##*/}" "$output"
	fi
	rm -rf data.tar.xz
}

get_xdelta() {
	echo "Getting xdelta binaries"
	extract_deb "${MODULE_TEMPLATE_DIR}/bin/xdelta-aarch64" "https://grimler.se/termux/termux-main/pool/main/x/xdelta3/xdelta3_3.1.0-1_aarch64.deb" "./data/data/com.termux/files/usr/bin/xdelta3"
	extract_deb "${MODULE_TEMPLATE_DIR}/bin/xdelta-arm" "https://grimler.se/termux/termux-main/pool/main/x/xdelta3/xdelta3_3.1.0-1_arm.deb" "./data/data/com.termux/files/usr/bin/xdelta3"
	echo "Getting liblzma libs"
	extract_deb "${MODULE_TEMPLATE_DIR}/lib/arm/" "https://grimler.se/termux/termux-main/pool/main/libl/liblzma/liblzma_5.2.5-1_arm.deb" "./data/data/com.termux/files/usr/lib/*so*"
	extract_deb "${MODULE_TEMPLATE_DIR}/lib/aarch64/" "https://grimler.se/termux/termux-main/pool/main/libl/liblzma/liblzma_5.2.5-1_aarch64.deb" "./data/data/com.termux/files/usr/lib/*so*"
}

get_cmp() {
	echo "Getting cmp binaries"
	dl_if_dne "${MODULE_TEMPLATE_DIR}/bin/cmp-arm64" "https://github.com/Zackptg5/Cross-Compiled-Binaries-Android/blob/master/diffutils/cmp-arm64?raw=true"
	dl_if_dne "${MODULE_TEMPLATE_DIR}/bin/cmp-arm" "https://github.com/Zackptg5/Cross-Compiled-Binaries-Android/blob/master/diffutils/cmp-arm?raw=true"
}

abort() { echo "$1" && exit 1; }

set_prebuilts() {
	[ -d "$TEMP_DIR" ] || abort "${TEMP_DIR} directory could not be found"
	RV_CLI_JAR=$(find "$TEMP_DIR" -maxdepth 1 -name "revanced-cli-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced cli not found"
	log "CLI: ${RV_CLI_JAR#"$TEMP_DIR/"}"
	RV_INTEGRATIONS_APK=$(find "$TEMP_DIR" -maxdepth 1 -name "app-release-unsigned-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced integrations not found"
	log "Integrations: ${RV_INTEGRATIONS_APK#"$TEMP_DIR/"}"
	RV_PATCHES_JAR=$(find "$TEMP_DIR" -maxdepth 1 -name "revanced-patches-*" | tail -n1)
	[ -z "$RV_CLI_JAR" ] && abort "revanced patches not found"
	log "Patches: ${RV_PATCHES_JAR#"$TEMP_DIR/"}"
}

reset_template() {
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/service.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/post-fs-data.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/customize.sh"
	echo "# utils" >"${MODULE_TEMPLATE_DIR}/module.prop"
	rm -rf ${MODULE_TEMPLATE_DIR}/rvc.xdelta ${MODULE_TEMPLATE_DIR}/*.apk
	mkdir -p ${MODULE_TEMPLATE_DIR}/lib/arm ${MODULE_TEMPLATE_DIR}/lib/aarch64 ${MODULE_TEMPLATE_DIR}/bin
}

req() { wget -nv -O "$2" --header="$WGET_HEADER" "$1"; }
log() { echo -e "$1  " >>build.log; }
get_apk_vers() { req "$1" - | sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p'; }

get_patch_last_supported_ver() {
	declare -r supported_versions=$(unzip -p "$RV_PATCHES_JAR" | strings -s , | sed -rn "s/.*${1},versions,(([0-9.]*,*)*),Lk.*/\1/p")
	echo "${supported_versions##*,}"
}

dl_if_dne() {
	if [ ! -f "$1" ]; then
		echo -e "\nGetting '$1' from '$2'"
		req "$2" "$1"
	fi
}

dl_apk() {
	local url=$1 regexp=$2 output=$3
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n "s/href=\"/@/g; s;.*${regexp}.*;\1;p")"
	echo "$url"
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
	url="https://www.apkmirror.com$(req "$url" - | tr '\n' ' ' | sed -n 's;.*href="\(.*key=[^"]*\)">.*;\1;p')"
	req "$url" "$output"
}

xdelta_patch() {
	if [ -f "$3" ]; then return; fi
	echo "Binary diffing ${2} against ${1}"
	xdelta3 -f -e -s "$1" "$2" "$3"
}

patch_apk() {
	local stock_input=$1 patched_output=$2 patcher_args=$3
	if [ -f "$patched_output" ]; then return; fi
	# shellcheck disable=SC2086
	java -jar "$RV_CLI_JAR" -c -a "$stock_input" -o "$patched_output" -b "$RV_PATCHES_JAR" --keystore=ks.keystore $patcher_args
}

zip_module() {
	local xdelta_patch=$1 module_name=$2 stock_apk=$3
	cp -f "$xdelta_patch" "${MODULE_TEMPLATE_DIR}/rvc.xdelta"
	cp -f "$stock_apk" "${MODULE_TEMPLATE_DIR}/stock.apk"
	cd "$MODULE_TEMPLATE_DIR" || exit 1
	zip -FSr "../${BUILD_DIR}/${module_name}" .
	cd ..
}

build_reddit() {
	echo "Building Reddit"
	local last_ver
	last_ver=$(get_patch_last_supported_ver "frontpage")
	last_ver="${last_ver:-$(get_apk_vers "https://www.apkmirror.com/apk/redditinc/reddit/" | head -n 1)}"

	echo "Choosing version '${last_ver}'"
	local stock_apk="${TEMP_DIR}/reddit-stock-v${last_ver}.apk" patched_apk="${BUILD_DIR}/reddit-revanced-v${last_ver}.apk"
	if [ ! -f "$stock_apk" ]; then
		declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/redditinc/reddit/reddit-${last_ver//./-}-release/" \
			"APK</span>[^@]*@\([^#]*\)" \
			"$stock_apk")
		log "\nReddit version: ${last_ver}"
		log "downloaded from: [APKMirror - Reddit]($dl_url)"
	fi
	patch_apk "$stock_apk" "$patched_apk" "-r"
}

build_twitter() {
	echo "Building Twitter"
	local last_ver
	last_ver=$(get_patch_last_supported_ver "twitter")
	last_ver="${last_ver:-$(get_apk_vers "https://www.apkmirror.com/apk/twitter-inc/" | grep release | head -n 1)}"

	echo "Choosing version '${last_ver}'"
	local stock_apk="${TEMP_DIR}/twitter-stock-v${last_ver}.apk" patched_apk="${BUILD_DIR}/twitter-revanced-v${last_ver}.apk"
	if [ ! -f "$stock_apk" ]; then
		declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/twitter-inc/twitter/twitter-${last_ver//./-}-release/" \
			"APK</span>[^@]*@\([^#]*\)" \
			"$stock_apk")
		log "\nTwitter version: ${last_ver}"
		log "downloaded from: [APKMirror - Twitter]($dl_url)"
	fi
	patch_apk "$stock_apk" "$patched_apk" "-r"
}

build_warn_wetter() {
	echo "Building WarnWetter"
	local last_ver
	last_ver=$(get_patch_last_supported_ver "warnapp")
	last_ver="${last_ver:-$(get_apk_vers "https://www.apkmirror.com/apk/deutscher-wetterdienst/" | head -n 1)}"

	echo "Choosing version '${last_ver}'"
	local stock_apk="${TEMP_DIR}/warn_wetter-stock-v${last_ver}.apk" patched_apk="${BUILD_DIR}/warn_wetter-revanced-v${last_ver}.apk"
	if [ ! -f "$stock_apk" ]; then
		declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/deutscher-wetterdienst/warnwetter/warnwetter-${last_ver//./-}-release/" \
			"APK</span>[^@]*@\([^#]*\)" \
			"$stock_apk")
		log "\nWarnWetter version: ${last_ver}"
		log "downloaded from: [APKMirror - WarnWetter]($dl_url)"
	fi
	patch_apk "$stock_apk" "$patched_apk" "-r"
}

build_yt() {
	echo "Building YouTube"
	reset_template
	declare -r last_ver=$(get_patch_last_supported_ver "youtube")
	echo "Choosing version '${last_ver}'"

	local stock_apk="${TEMP_DIR}/youtube-stock-v${last_ver}.apk" patched_apk="${TEMP_DIR}/youtube-revanced-v${last_ver}.apk"
	if [ ! -f "$stock_apk" ]; then
		declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/google-inc/youtube/youtube-${last_ver//./-}-release/" \
			"APK</span>[^@]*@\([^#]*\)" \
			"$stock_apk")
		log "\nYouTube version: ${last_ver}"
		log "downloaded from: [APKMirror - YouTube]($dl_url)"
	fi
	patch_apk "$stock_apk" "$patched_apk" "${YT_PATCHER_ARGS} -m ${RV_INTEGRATIONS_APK}"

	if [[ "$YT_PATCHER_ARGS" != *"-e microg-support"* ]] && [[ "$YT_PATCHER_ARGS" != *"--exclusive"* ]] || [[ "$YT_PATCHER_ARGS" == *"-i microg-support"* ]]; then
		mv -f "$patched_apk" build
		echo "Built YouTube (no root) '${BUILD_DIR}/${patched_apk}'"
		return
	fi

	service_sh "com.google.android.youtube"
	postfsdata_sh "com.google.android.youtube"
	customize_sh "com.google.android.youtube" "$last_ver"
	module_prop "ytrv-magisk" \
		"YouTube ReVanced" \
		"$last_ver" \
		"mounts base.apk for YouTube ReVanced" \
		"https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/update/yt-update.json"

	local output="youtube-revanced-magisk-v${last_ver}-all.zip"
	local xdelta="${TEMP_DIR}/youtube-revanced-v${last_ver}.xdelta"
	xdelta_patch "$stock_apk" "$patched_apk" "$xdelta"
	zip_module "$xdelta" "$output" "$stock_apk"
	echo "Built YouTube: '${BUILD_DIR}/${output}'"
}

build_music() {
	local arch=$1
	echo "Building YouTube Music (${arch})"
	reset_template
	declare -r last_ver=$(get_patch_last_supported_ver "music")
	echo "Choosing version '${last_ver}'"

	local stock_apk="${TEMP_DIR}/music-stock-v${last_ver}-${arch}.apk" patched_apk="${TEMP_DIR}/music-revanced-v${last_ver}-${arch}.apk"
	if [ ! -f "$stock_apk" ]; then
		if [ "$arch" = "$ARM64_V8A" ]; then
			local regexp_arch='arm64-v8a</div>[^@]*@\([^"]*\)'
		elif [ "$arch" = "$ARM_V7A" ]; then
			local regexp_arch='armeabi-v7a</div>[^@]*@\([^"]*\)'
		fi
		declare -r dl_url=$(dl_apk "https://www.apkmirror.com/apk/google-inc/youtube-music/youtube-music-${last_ver//./-}-release/" \
			"$regexp_arch" \
			"$stock_apk")
		log "\nYouTube Music (${arch}) version: ${last_ver}"
		log "downloaded from: [APKMirror - YouTube Music ${arch}]($dl_url)"
	fi
	patch_apk "$stock_apk" "$patched_apk" "${MUSIC_PATCHER_ARGS} -m ${RV_INTEGRATIONS_APK}"

	if [[ "$MUSIC_PATCHER_ARGS" != *"-e music-microg-support"* ]] && [[ "$MUSIC_PATCHER_ARGS" != *"--exclusive"* ]] || [[ "$MUSIC_PATCHER_ARGS" == *"-i music-microg-support"* ]]; then
		mv -f "$patched_apk" build
		echo "Built Music (no root) '${BUILD_DIR}/${patched_apk}'"
		return
	fi

	service_sh "com.google.android.apps.youtube.music"
	postfsdata_sh "com.google.android.apps.youtube.music"
	customize_sh "com.google.android.apps.youtube.music" "$last_ver"

	local update_json="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/update/music-update-${arch}.json"
	if [ "$arch" = "$ARM64_V8A" ]; then
		local id="ytmusicrv-magisk"
	elif [ "$arch" = "$ARM_V7A" ]; then
		local id="ytmusicrv-arm-magisk"
	else
		echo "Wrong arch for prop: '$arch'"
		return
	fi
	module_prop "$id" \
		"YouTube Music ReVanced" \
		"$last_ver" \
		"mounts base.apk for YouTube Music ReVanced" \
		"$update_json"

	local output="music-revanced-magisk-v${last_ver}-${arch}.zip"
	local xdelta="${TEMP_DIR}/music-revanced-v${last_ver}.xdelta"
	xdelta_patch "$stock_apk" "$patched_apk" "$xdelta"
	zip_module "$xdelta" "$output" "$stock_apk"
	echo "Built Music (${arch}) '${BUILD_DIR}/${output}'"
}

service_sh() { echo "${SERVICE_SH//__PKGNAME/$1}" >"${MODULE_TEMPLATE_DIR}/service.sh"; }
postfsdata_sh() { echo "${POSTFSDATA_SH//__PKGNAME/$1}" >"${MODULE_TEMPLATE_DIR}/post-fs-data.sh"; }
customize_sh() {
	s="${CUSTOMIZE_SH//__PKGNAME/$1}"
	echo "${s//__MDVRSN/$2}" >"${MODULE_TEMPLATE_DIR}/customize.sh"
}

module_prop() {
	echo "id=${1}
name=${2}
version=v${3}
versionCode=${NEXT_VER_CODE}
author=j-hc
description=${4}" >"${MODULE_TEMPLATE_DIR}/module.prop"

	if [ "$ENABLE_MAGISK_UPDATE" = true ]; then
		echo "updateJson=${5}" >>"${MODULE_TEMPLATE_DIR}/module.prop"
	fi
}
