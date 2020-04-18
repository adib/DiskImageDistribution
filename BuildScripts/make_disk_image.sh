#!/bin/bash
#
# Create a disk image "install" package from a macOS application bundle.
# The disk image would be signed and notarized as per macOS 10.15 "Catalina" requirements
#
# Copyright (c) 2019, Sasmito Adibowo
# https://cutecoder.org
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# -------- Check environment parameters

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY_NAME}" ]
then
	echo "Define environment variable `EXPANDED_CODE_SIGN_IDENTITY_NAME` to contain the code signing identity for the disk image."
	exit 64
elif [[ ! "${EXPANDED_CODE_SIGN_IDENTITY_NAME}" == 'Developer ID Application:'* ]]
then
	echo "EXPANDED_CODE_SIGN_IDENTITY_NAME should be a Developer ID identity"
	exit 64
fi

if [ ! -f "${APP_BUNDLE}/Contents/Info.plist" ]
then
	echo "Define environment variable APP_BUNDLE to point to the application bundle."
	exit 64
fi

if [ -z "${DISK_IMAGE_FULL_PATH}" ]
then
	echo "Define DISK_IMAGE_FULL_PATH to be the target disk image file name."
	exit 64
fi

if [ -z "${APPLE_ID_MAIL}" ]
then
	echo "Define APPLE_ID_MAIL to be the Apple ID to be used for notarization."
	exit 64
fi

if [ -z "${APPLE_ID_PASSWORD}" ]
then
	echo "Define APPLE_ID_PASSWORD to be the app-specific password to be used for notarization (don't use your primary password for this)."
	exit 64
fi

if [ -z "${APPLE_ID_PROVIDER_SHORT_NAME}" ]
then
	echo "APPLE_ID_PROVIDER_SHORT_NAME is empty — will not specify iTunes Provider."
fi

# -------- Define global constants

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

PLIST_BUDDY='/usr/libexec/PlistBuddy'

if [ ! -f "${DISK_IMAGE_BACKGROUND_FILE}" ]
then
	echo "Using default disk image background file."
	DISK_IMAGE_BACKGROUND_FILE="${SCRIPT_DIR}/../DiskImageBackground/window-background-800x378@2x.png"
fi

# -------- Check Tools Availability

if [ ! -x "${PLIST_BUDDY}" ]
then
	echo "Couldn't find PlistBuddy"
	exit 72
fi

if [ ! -x "$(which spctl)" ]
then
	echo "spctl not found"
	exit 72
fi

if [ ! -x "$(which hdiutil)" ]
then
	echo "hdiutil not found"
	exit 72
fi

if [ ! -x "$(which ditto)" ]
then
	echo "ditto not found"
	exit 72
fi

if [ ! -x "$(which create-dmg)" ]
then
	echo "create-dmg not found"
	exit 72
fi

if [ ! -d "$(xcrun --show-sdk-path)" ]
then
	echo "Xcode not configured"
	exit 72
fi


# -------- Verify App Bundle is signed correctly

spctl --assess --type execute --verbose  "${APP_BUNDLE}"
app_bundle_check_result=$?
if [ "${app_bundle_check_result}" != "0" ]
then
	echo "Failed to validate app bundle signature: ${app_bundle_check_result}"
	exit 1
fi

# -------- Prepare disk image "scratch" folder

primary_bundle_identifier=$( "${PLIST_BUDDY}" -c "Print CFBundleIdentifier" "${APP_BUNDLE}/Contents/Info.plist" )
echo "Primary bundle identifier: ${primary_bundle_identifier}"
bundle_name="$( "${PLIST_BUDDY}" -c "Print CFBundleName" "${APP_BUNDLE}/Contents/Info.plist" )"

app_wrapper_name="$(basename "${APP_BUNDLE}" )"

disk_image_work_dir="$(mktemp -d)"
tool_output_dir="$(mktemp -d)"

ditto  --hfsCompression "${APP_BUNDLE}" "${disk_image_work_dir}/${app_wrapper_name}"
ditto_result=$?
if [ "${ditto_result}" != "0" ]
then
	echo "Failed to copy app bundle: ${ditto_result}"
	exit 1
fi


# -------- Create disk image as application install package

create-dmg \
--background "${DISK_IMAGE_BACKGROUND_FILE}" \
--volname "${bundle_name}" \
--window-pos 200 120 \
--window-size 800 400 \
--icon-size 100 \
--icon "${app_wrapper_name}" 200 190 \
--hide-extension "${app_wrapper_name}" \
--app-drop-link 600 185 \
--no-internet-enable \
"${DISK_IMAGE_FULL_PATH}" \
"${disk_image_work_dir}"

dmg_result=$?
if [ "${dmg_result}" != "0" ]
then
	echo "Failed to create disk image: ${dmg_result}"
	exit 1
elif [ ! -f "${DISK_IMAGE_FULL_PATH}" ]
then
	echo "Disk image result not found"
	exit 1
fi


# -------- Sign the disk image

xcrun codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY_NAME}" "${DISK_IMAGE_FULL_PATH}"
codesign_result=$?
if [ "${codesign_result}" != "0" ]
then
	echo "Failed to sign disk image: ${codesign_result}"
	exit 1
fi

hdiutil verify "${DISK_IMAGE_FULL_PATH}"
hdiutil_result=$?
if [ "${hdiutil_result}" != "0" ]
then
	echo "Disk image failed verification: ${hdiutil_result}"
	exit 1
fi


# -------- Upload the disk image for notarization

echo "Uploading for notarization..."

if [ -z "${APPLE_ID_PROVIDER_SHORT_NAME}" ]
then
	xcrun altool --notarize-app \
	--primary-bundle-id "${primary_bundle_identifier}" \
	-u "${APPLE_ID_MAIL}" \
	-p "${APPLE_ID_PASSWORD}" \
	--output-format xml \
	--file "${DISK_IMAGE_FULL_PATH}" \
	> "${tool_output_dir}/notarize_result.plist"
else
	xcrun altool --notarize-app \
	--primary-bundle-id "${primary_bundle_identifier}" \
	-u "${APPLE_ID_MAIL}" \
	-p "${APPLE_ID_PASSWORD}" \
	--output-format xml \
	--asc-provider "${APPLE_ID_PROVIDER_SHORT_NAME}" \
	--file "${DISK_IMAGE_FULL_PATH}" \
	> "${tool_output_dir}/notarize_result.plist"
fi

notarize_exit=$?
if [ "${notarize_exit}" != "0" ]
then
	echo "Notarization failed: ${notarize_exit}"
	cat "${tool_output_dir}/notarize_result.plist"
	exit 1
fi

request_uuid="$("${PLIST_BUDDY}" -c "Print notarization-upload:RequestUUID"  "${tool_output_dir}/notarize_result.plist")"
echo "Notarization UUID: ${request_uuid} result: $("${PLIST_BUDDY}" -c "Print success-message"  "${tool_output_dir}/notarize_result.plist")"


# -------- Wait for notarization result

for (( ; ; ))
do
	xcrun altool --notarization-info "${request_uuid}" \
	-u "${APPLE_ID_MAIL}" \
	-p "${APPLE_ID_PASSWORD}" \
	--output-format xml \
	> "${tool_output_dir}/notarize_status.plist"

	notarize_exit=$?
	if [ "${notarize_exit}" != "0" ]
	then
		echo "Notarization failed: ${notarize_exit}"
		cat "${tool_output_dir}/notarize_status.plist"
		exit 1
	fi
	notarize_status="$("${PLIST_BUDDY}" -c "Print notarization-info:Status"  "${tool_output_dir}/notarize_status.plist")"
	if [ "${notarize_status}" == "in progress" ]
	then
        echo "Waiting for notarization to complete"
        sleep 10
    else
    	echo "Notarization status: ${notarize_status}"
    	break
	fi
done


notarization_log_url="$("${PLIST_BUDDY}" -c "Print notarization-info:LogFileURL"  "${tool_output_dir}/notarize_status.plist")"
echo "Notarization log URL: ${notarization_log_url}"

if [ "${notarize_status}" != "success" ]
then
	echo "Notarization failed."
	if [ ! -z "${notarization_log_url}" ]
	then
		curl "${notarization_log_url}"
	fi
	exit 1
fi


# -------- Staple notarization result on to disk image

echo "Stapling notarization result..."
for (( ; ; ))
do
    xcrun stapler staple -q "${DISK_IMAGE_FULL_PATH}"
    stapler_status=$?
    if [ "${stapler_status}" = "65" ]
    then
        echo "Waiting for stapling to find record"
        sleep 10
    else
        echo "Stapler status: ${stapler_status}"
        break
    fi
done


# -------- Validate the resulting disk image

spctl --assess --type open --context context:primary-signature -v "${DISK_IMAGE_FULL_PATH}"
disk_image_validation_result=$?

if [ "${disk_image_validation_result}" != 0 ]
then
	echo "Failed to validate disk image: ${disk_image_validation_result}"
	curl "${notarization_log_url}"
	exit 1
fi

# -------- Clean up work directory
rm -rf "${disk_image_work_dir}"
rm -rf "${tool_output_dir}"

echo "All done"
exit 0
