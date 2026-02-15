#!/bin/bash

#-----------------------------------------------------
# Install script for the EventServer and the 
# machine learning hooks
#
# /install.sh --help
#
# Note that this does not install all the event server
# dependencies. You still need to follow the README
#
# It does however try to install all the hook dependencies
#
#-----------------------------------------------------

# --- Change these if you want --

PYTHON=${PYTHON:-python3}
PIP=${PIP:-pip3}
PIP_COMPAT=${PIP_COMPAT:---break-system-packages}
INSTALLER=${INSTALLER:-$(which apt-get || which yum)}

# Models to install
# If you do not want them, pass them as variables to install.sh
# example: sudo INSTALL_YOLO4=no ./install.sh

INSTALL_YOLOV3=${INSTALL_YOLOV3:-no}
INSTALL_TINYYOLOV3=${INSTALL_TINYYOLOV3:-no}
INSTALL_YOLOV4=${INSTALL_YOLOV4:-yes}
INSTALL_TINYYOLOV4=${INSTALL_TINYYOLOV4:-yes}
INSTALL_CORAL_EDGETPU=${INSTALL_CORAL_EDGETPU:-no}
INSTALL_YOLOV11=${INSTALL_YOLOV11:-yes}
INSTALL_YOLOV26=${INSTALL_YOLOV26:-yes}


TARGET_CONFIG=${TARGET_CONFIG:-'/etc/zm'}
TARGET_DATA=${TARGET_DATA:-'/var/lib/zmeventnotification'}
TARGET_BIN_ES=${TARGET_BIN_ES:-'/usr/bin'}
TARGET_BIN_HOOK=${TARGET_BIN_HOOK:-'/var/lib/zmeventnotification/bin'}
TARGET_PERL_LIB=${TARGET_PERL_LIB:-'/usr/share/perl5'}

INSTALL_OPENCV=${INSTALL_OPENCV:-no}

WGET=${WGET:-$(which wget)}
_WEB_OWNER_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $1}')
#_WEB_OWNER='www-data' # uncomment this if the above mechanism fails

_WEB_GROUP_FROM_PS=$(ps xao user,group,comm | grep -E '(httpd|hiawatha|apache|apache2|nginx)' | grep -v whoami | grep -v root | head -n1 | awk '{print $2}')
#_WEB_GROUP='www-data' # uncomment if above line fails
# make this empty if you do not want backups
MAKE_CONFIG_BACKUP='--backup=numbered'

# --- end of change these ---

# set default values 
# if we have a value from ps use it, otherwise look in env

WEB_OWNER=${WEB_OWNER:-${_WEB_OWNER_FROM_PS}}
WEB_GROUP=${WEB_GROUP:-${_WEB_GROUP_FROM_PS}}

# if we do not have a value from ps or env, use default

WEB_OWNER=${WEB_OWNER:-'www-data'}
WEB_GROUP=${WEB_GROUP:-'www-data'}


# utility functions for color coded pretty printing
print_error() {
    COLOR="\033[1;31m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}ERROR:${NOCOLOR}$1"
}

print_important() {
    COLOR="\033[0;34m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}IMPORTANT:${NOCOLOR}$1"
}

print_warning() {
    COLOR="\033[0;33m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}WARNING:${NOCOLOR}$1"
}

print_success() {
    COLOR="\033[1;32m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}Success:${NOCOLOR}$1"
}

print_section() {
    COLOR="\033[1;36m"
    NOCOLOR="\033[0m"
    echo ""
    echo -e "${COLOR}──── $1 ────${NOCOLOR}"
}

print_skip() {
    COLOR="\033[0;33m"
    NOCOLOR="\033[0m"
    echo -e "${COLOR}Skipping: $1${NOCOLOR}"
}

# Run a command with its output dimmed (gray)
# Usage: run_dimmed <command> [args...]
run_dimmed() {
    local DIM="\033[0;90m"
    local NOCOLOR="\033[0m"
    echo -ne "${DIM}"
    "$@" 2>&1
    local rc=$?
    echo -ne "${NOCOLOR}"
    return $rc
}

get_distro() {
    local DISTRO=`(lsb_release -ds || cat /etc/*release || uname -om ) 2>/dev/null | head -n1`
    local DISTRO_NORM='ubuntu'
    if echo "${DISTRO}" | grep -iqF 'ubuntu'; then
        DISTRO_NORM='ubuntu'
    elif echo "${DISTRO}" | grep -iqF 'centos'; then
        DISTRO_NORM='centos'
    fi
    echo ${DISTRO_NORM}
}

get_installer() {
    local DISTRO=$(get_distro)
    local installer='apt-get'
    case $DISTRO in
        ubuntu)
            installer='apt-get'
            ;;
        centos)
            installer='yum'
            ;;
    esac
    echo ${installer}        
}

# generic confirm function that returns 0 for yes and 1 for no
confirm() {
    display_str=$1
    default_ans=$2
    if [[ $default_ans == 'y/N' ]]
    then
       must_match='[yY]'
    else
       must_match='[nN]'
    fi
    read -p "${display_str} [${default_ans}]:" ans
    [[ $ans == $must_match ]]   
}

# Are we running as root? If not, install may fail
check_root() {
    if [[ $EUID -ne 0 ]]
    then
        echo 
        echo "********************************************************************************"
        print_warning "Unless you have changed paths, this script requires to be run as sudo"
        echo "********************************************************************************"
        echo
        [[ ${INTERACTIVE} == 'yes' ]] && read -p "Press any key to continue or Ctrl+C to quit and run again with sudo..."

    fi
}

# Some of these may be default values, so give user a change to change
verify_config() {

    if [[ ${INTERACTIVE} == 'no' && 
          ( ${INSTALL_ES} == 'prompt' || ${INSTALL_HOOK} == 'prompt' ||
            ${INSTALL_HOOK_CONFIG} == 'prompt' || ${INSTALL_ES_CONFIG} == 'prompt' ) 
       ]] 
    then
        print_error 'In non-interactive mode, you need to specify flags for all components'
        echo
        exit
    fi

    print_section 'Configured Values'
    echo "Your distro seems to be ${DISTRO}"
    echo "Your webserver user seems to be ${WEB_OWNER}"
    echo "Your webserver group seems to be ${WEB_GROUP}"
    echo "wget is ${WGET}"
    echo "installer software is ${INSTALLER}"

    echo "Install Event Server: ${INSTALL_ES}"
    echo "Install Event Server config: ${INSTALL_ES_CONFIG}"
    echo "Install Hooks: ${INSTALL_HOOK}"
    echo "Install Hooks config: ${INSTALL_HOOK_CONFIG}"
    echo "Upgrade Hooks config (if applicable): ${HOOK_CONFIG_UPGRADE}"
    echo "Download and install models (if needed): ${DOWNLOAD_MODELS}"
    echo "Install OpenCV: ${INSTALL_OPENCV}"
    echo "Perl module install path: ${TARGET_PERL_LIB}"
    echo

    [[ ${INSTALL_ES} != 'no' ]] && echo "The Event Server will be installed to ${TARGET_BIN_ES}"
    [[ ${INSTALL_ES_CONFIG} != 'no' ]] && echo "The Event Server config will be installed to ${TARGET_CONFIG}"

    [[ ${INSTALL_HOOK} != 'no' ]] && echo "Hooks will be installed to ${TARGET_DATA} sub-folders"
    [[ ${INSTALL_HOOK_CONFIG} != 'no' ]] && echo "Hook config files will be installed to ${TARGET_CONFIG}"

    echo
    if [[ ${DOWNLOAD_MODELS} == 'yes' ]]
    then
        echo "Models that will be checked/installed:"
        echo "(Note, if you have already downloaded a model, it will not be deleted)"
        echo "Yolo V3 (INSTALL_YOLOV3): ${INSTALL_YOLOV3}"
        echo "TinyYolo V3 (INSTALL_TINYYOLOV3): ${INSTALL_TINYYOLOV3}"
        echo "Yolo V4 (INSTALL_YOLOV4): ${INSTALL_YOLOV4}"
        echo "Tiny Yolo V4 (INSTALL_TINYYOLOV4)": ${INSTALL_TINYYOLOV4}
        echo "Google Coral Edge TPU (INSTALL_CORAL_EDGETPU)": ${INSTALL_CORAL_EDGETPU}
        echo "ONNX YOLOv11 (INSTALL_YOLOV11)": ${INSTALL_YOLOV11}
        echo "ONNX YOLOv26 (INSTALL_YOLOV26)": ${INSTALL_YOLOV26}

    fi
    echo
     [[ ${INTERACTIVE} == 'yes' ]] && read -p "If any of this looks wrong, please hit Ctrl+C and edit the variables in this script..."

}


# move proc for zmeventnotification.pl
install_es() {
    print_section 'Installing ES Dependencies'
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
      run_dimmed $INSTALLER install -y libyaml-libyaml-perl libcrypt-eksblowfish-perl \
          libcrypt-openssl-rsa-perl libmodule-build-perl libyaml-perl libjson-perl \
          liblwp-protocol-https-perl libio-socket-ssl-perl liburi-perl libdbi-perl \
          libtest-warn-perl
      echo "Note: Net::WebSocket::Server is also required but not available via apt."
      echo "Install it via CPAN if not already present: sudo cpanm Net::WebSocket::Server"
    else
      echo "Not ubuntu or debian - please install Perl dependencies manually"
    fi

    print_section 'Installing Event Server'
    mkdir -p "${TARGET_DATA}/push" 2>/dev/null
    local es_target="${TARGET_BIN_ES}/zmeventnotification.pl"
    if install -m 755 -o "${WEB_OWNER}" -g "${WEB_GROUP}" zmeventnotification.pl "${TARGET_BIN_ES}"; then
        print_success "Completed, but you will still have to install ES dependencies as per https://zmeventnotificationv7.readthedocs.io/en/latest/guides/install.html#install-dependencies"
    elif [ -f "$es_target" ]; then
        # install(1) unlinks the target first, which fails on bind mounts.
        # Fall back to in-place copy which overwrites contents without unlinking.
        print_warning "'install' failed (target may be a bind mount). Trying in-place copy..."
        if cp zmeventnotification.pl "$es_target" && chmod 755 "$es_target"; then
            chown "${WEB_OWNER}:${WEB_GROUP}" "$es_target" 2>/dev/null
            print_success "Copied in-place"
        else
            print_error "In-place copy also failed. Check permissions on ${es_target}"
        fi
    else
        print_error "failed to install to ${es_target}"
    fi

    print_section 'Installing Perl modules'
    mkdir -p "${TARGET_PERL_LIB}/ZmEventNotification/"
    for pm_file in ZmEventNotification/*.pm; do
        local pm_target="${TARGET_PERL_LIB}/ZmEventNotification/$(basename "$pm_file")"
        if install -m 644 "$pm_file" "${TARGET_PERL_LIB}/ZmEventNotification/"; then
            echo "Installed $(basename $pm_file)"
        elif cp "$pm_file" "$pm_target" && chmod 644 "$pm_target"; then
            echo "Installed $(basename $pm_file) (in-place copy)"
        else
            print_error "Failed to install $(basename $pm_file)"
        fi
    done

    # Update Version.pm with the version from VERSION file
    if [ -f "VERSION" ]; then
        ES_VERSION=$(cat VERSION | tr -d '[:space:]')
        sed -i "s/^\(.*\)\$FALLBACK_VERSION = '.*';$/\1\$FALLBACK_VERSION = '${ES_VERSION}';/" \
            "${TARGET_PERL_LIB}/ZmEventNotification/Version.pm" &&
            echo "Set version to ${ES_VERSION} in Version.pm" || print_error "Failed to set version"
    fi

    # No need to patch use lib - FindBin resolves the script's directory at runtime,
    # and installed modules in ${TARGET_PERL_LIB} are already in @INC.
}

# Download model files if they don't already exist
# Usage: download_if_needed <model_dir> <target1> <source1> [<target2> <source2> ...]
download_if_needed() {
    local model_dir="$1"; shift
    mkdir -p "${TARGET_DATA}/models/${model_dir}"
    while [ $# -ge 2 ]; do
        local target="$1" source="$2"; shift 2
        if [ ! -f "${TARGET_DATA}/models/${model_dir}/${target}" ]; then
            run_dimmed ${WGET} "${source}" -O"${TARGET_DATA}/models/${model_dir}/${target}"
        else
            print_success " ${target} already exists"
        fi
    done
}

# install proc for ML hooks
download_models() {
    # Create model directories
    mkdir -p "${TARGET_DATA}/models/yolov3" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/tinyyolov3" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/tinyyolov4" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/yolov4" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/coral_edgetpu" 2>/dev/null
    mkdir -p "${TARGET_DATA}/models/ultralytics" 2>/dev/null

    if [ "${DOWNLOAD_MODELS}" == "yes" ]
    then

        if [ "${INSTALL_CORAL_EDGETPU}" == "yes" ]
        then
            print_important ' Checking for Google Coral Edge TPU data files...'
            download_if_needed coral_edgetpu \
                'coco_indexed.names' 'https://dl.google.com/coral/canned_models/coco_labels.txt' \
                'ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite' 'https://github.com/google-coral/edgetpu/raw/master/test_data/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite' \
                'ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite' 'https://github.com/google-coral/test_data/raw/master/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite' \
                'ssd_mobilenet_v2_face_quant_postprocess_edgetpu.tflite' 'https://github.com/google-coral/test_data/raw/master/ssd_mobilenet_v2_face_quant_postprocess_edgetpu.tflite'
        fi

        if [ "${INSTALL_YOLOV3}" == "yes" ]
        then
            print_important ' Checking for YOLOv3 data files...'
            [ -f "${TARGET_DATA}/models/yolov3/yolov3_classes.txt" ] && rm "${TARGET_DATA}/models/yolov3/yolov3_classes.txt"
            download_if_needed yolov3 \
                'yolov3.cfg' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov3/yolov3.cfg' \
                'coco.names' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov3/coco.names' \
                'yolov3.weights' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov3/yolov3.weights'
        fi

        if [ "${INSTALL_TINYYOLOV3}" == "yes" ]
        then
            [ -d "${TARGET_DATA}/models/tinyyolo" ] && mv "${TARGET_DATA}/models/tinyyolo" "${TARGET_DATA}/models/tinyyolov3"
            print_important ' Checking for TinyYOLOv3 data files...'
            [ -f "${TARGET_DATA}/models/tinyyolov3/yolov3-tiny.txt" ] && rm "${TARGET_DATA}/models/yolov3/yolov3-tiny.txt"
            download_if_needed tinyyolov3 \
                'yolov3-tiny.cfg' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov3/yolov3-tiny.cfg' \
                'coco.names' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov3/coco.names' \
                'yolov3-tiny.weights' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov3/yolov3-tiny.weights'
        fi

        if [ "${INSTALL_TINYYOLOV4}" == "yes" ]
        then
            print_important ' Checking for TinyYOLOv4 data files...'
            download_if_needed tinyyolov4 \
                'yolov4-tiny.cfg' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov4/yolov4-tiny.cfg' \
                'coco.names' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov4/coco.names' \
                'yolov4-tiny.weights' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/tinyyolov4/yolov4-tiny.weights'
        fi

        if [ "${INSTALL_YOLOV4}" == "yes" ]
        then
            if [ -d "${TARGET_DATA}/models/cspn" ]
            then
                echo "Removing old CSPN files, it is YoloV4 now"
                rm -rf "${TARGET_DATA}/models/cspn" 2>/dev/null
            fi

            print_important ' Checking for YOLOv4 data files...'
            print_warning ' Note, you need OpenCV 4.4+ for Yolov4 to work'
            download_if_needed yolov4 \
                'yolov4.cfg' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov4/yolov4.cfg' \
                'coco.names' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov4/coco.names' \
                'yolov4.weights' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/yolov4/yolov4.weights'
        fi

        if [ "${INSTALL_YOLOV11}" == "yes" ]
        then
            print_important ' Checking for ONNX YOLOv11 model files...'
            print_warning 'Note, you need OpenCV 4.10+ for ONNX YOLOv11 to work'
            download_if_needed ultralytics \
                'yolo11n.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo11n.onnx' \
                'yolo11s.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo11s.onnx' \
                'yolo11m.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo11m.onnx' \
                'yolo11l.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo11l.onnx'
        fi

        if [ "${INSTALL_YOLOV26}" == "yes" ]
        then
            print_important ' Checking for ONNX YOLOv26 model files...'
            print_warning 'Note, you need OpenCV 4.13+ for ONNX YOLOv26 to work (TopK layer support required)'
            download_if_needed ultralytics \
                'yolo26n.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo26n.onnx' \
                'yolo26s.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo26s.onnx' \
                'yolo26m.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo26m.onnx' \
                'yolo26l.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo26l.onnx' \
                'yolo26x.onnx' 'https://github.com/pliablepixels/zmes_ai_assets/raw/master/models/ultralytics/yolo26x.onnx'
        fi
    else
        print_skip 'Model downloads'
    fi
}

install_hook() {

    if [ "${INSTALL_OPENCV}" == "yes" ]; then
        echo "Installing python3-opencv..."
        run_dimmed ${PY_SUDO} ${INSTALLER} install python3-opencv
    else
        print_skip "python3-opencv installation"
    fi

    print_section 'Installing Hooks'
    mkdir -p "${TARGET_DATA}/bin" 2>/dev/null
    rm -fr  "${TARGET_DATA}/bin/*" 2>/dev/null

    #don't delete contrib so custom user files remain
    mkdir -p "${TARGET_DATA}/contrib" 2>/dev/null

    mkdir -p "${TARGET_DATA}/images" 2>/dev/null
    mkdir -p "${TARGET_DATA}/mlapi" 2>/dev/null
    mkdir -p "${TARGET_DATA}/known_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/unknown_faces" 2>/dev/null
    mkdir -p "${TARGET_DATA}/misc" 2>/dev/null
    echo "everything that does not fit anywhere else :-)" > "${TARGET_DATA}/misc/README.txt" 2>/dev/null
    
    download_models

    # Now install the ML hooks

    print_section 'Installing push API plugins'
     install -m 755 -o "${WEB_OWNER}" pushapi_plugins/pushapi_pushover.py "${TARGET_BIN_HOOK}"

    print_section 'Installing detection scripts'
    install -m 755 -o "${WEB_OWNER}" hook/zm_event_start.sh "${TARGET_BIN_HOOK}"
    install -m 755 -o "${WEB_OWNER}" hook/zm_event_end.sh "${TARGET_BIN_HOOK}"

    install -m 755 -o "${WEB_OWNER}" hook/zm_detect.py "${TARGET_BIN_HOOK}"
    install -m 755 -o "${WEB_OWNER}" hook/zm_train_faces.py "${TARGET_BIN_HOOK}"

    # Fix hardcoded paths in installed scripts to match TARGET_CONFIG / TARGET_BIN_HOOK
    sed -i "s|CONFIG_FILE=\"/etc/zm/objectconfig.yml\"|CONFIG_FILE=\"${TARGET_CONFIG}/objectconfig.yml\"|" \
        "${TARGET_BIN_HOOK}/zm_event_start.sh"
    sed -i "s|/var/lib/zmeventnotification/bin/zm_detect.py|${TARGET_BIN_HOOK}/zm_detect.py|g" \
        "${TARGET_BIN_HOOK}/zm_event_start.sh"
    sed -i "s|default='/etc/zm/objectconfig.yml'|default='${TARGET_CONFIG}/objectconfig.yml'|" \
        "${TARGET_BIN_HOOK}/zm_train_faces.py"
    #python setup.py install && print_success "Done" || print_error "python setup failed"

    print_section 'Installing user contributions'
    cp docs/guides/contrib_guidelines.rst "${TARGET_DATA}/contrib"
    for file in contrib/*; do
    echo "Copying over ${file}..."
      install -m 755 -o "${WEB_OWNER}" "$file" "${TARGET_DATA}/contrib"
    done
    echo
    

    print_section 'Installing Python hook package'
    ${PY_SUDO} ${PIP} uninstall -y zmes-hooks ${PIP_COMPAT}   >/dev/null 2>&1
    ${PY_SUDO} ${PIP} uninstall -y zmes_hook_helpers ${PIP_COMPAT}   >/dev/null 2>&1
 

    ZM_DETECT_VERSION=`./hook/zm_detect.py --bareversion`
    if [ "$ZM_DETECT_VERSION" == "" ]; then
      echo "Failed to detect hooks version."
    else
      echo "__version__ = \"${ZM_DETECT_VERSION}\"" > hook/zmes_hook_helpers/__init__.py
      echo "VERSION=__version__" >> hook/zmes_hook_helpers/__init__.py
    fi

    echo "Running: ${PY_SUDO} ${PIP} -v install hook/ ${PIP_COMPAT}"
    run_dimmed ${PY_SUDO} ${PIP} -v install hook/ ${PIP_COMPAT} && print_opencv_message || print_error "python hooks setup failed"

    print_section 'Installing package dependencies'
    run_dimmed ${PY_SUDO} ${INSTALLER} install gifsicle -qq

}


# move ES config files
install_es_config() {
    # Ensure pyyaml is installed for config migration/upgrade scripts
    run_dimmed ${PY_SUDO} ${PIP} install pyyaml ${PIP_COMPAT}

    # Auto-migrate from INI to YAML if needed
    if [ -f "${TARGET_CONFIG}/zmeventnotification.ini" ] && [ ! -f "${TARGET_CONFIG}/zmeventnotification.yml" ]; then
        echo "Found existing zmeventnotification.ini but no zmeventnotification.yml - running migration..."
        if ${PYTHON} tools/es_config_migrate_yaml.py -c "${TARGET_CONFIG}/zmeventnotification.ini" -o "${TARGET_CONFIG}/zmeventnotification.yml"; then
            print_success "ES config migration complete"
            mv "${TARGET_CONFIG}/zmeventnotification.ini" "${TARGET_CONFIG}/zmeventnotification.ini.migrated"
            print_important "Renamed old zmeventnotification.ini to zmeventnotification.ini.migrated"
        else
            print_warning "ES config migration failed"
        fi
    fi
    if [ -f "${TARGET_CONFIG}/secrets.ini" ] && [ ! -f "${TARGET_CONFIG}/secrets.yml" ]; then
        echo "Found existing secrets.ini but no secrets.yml - running migration..."
        if ${PYTHON} tools/es_config_migrate_yaml.py --secrets -c "${TARGET_CONFIG}/secrets.ini" -o "${TARGET_CONFIG}/secrets.yml"; then
            print_success "secrets migration complete"
            mv "${TARGET_CONFIG}/secrets.ini" "${TARGET_CONFIG}/secrets.ini.migrated"
            print_important "Renamed old secrets.ini to secrets.ini.migrated"
        else
            print_warning "secrets migration failed"
        fi
    fi

    if [ ! -f "${TARGET_CONFIG}/zmeventnotification.yml" ]; then
        echo 'No existing ES config found, installing example as active config'
        install -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 zmeventnotification.example.yml "${TARGET_CONFIG}/zmeventnotification.yml" &&
            print_success "config copied" || print_error "could not copy config"
    else
        echo "Upgrading existing ES config with any new keys..."
        ${PYTHON} tools/config_upgrade_yaml.py -c "${TARGET_CONFIG}/zmeventnotification.yml" -e zmeventnotification.example.yml &&
            print_success "ES config upgraded" || print_warning "ES config upgrade failed"
    fi
    if [ ! -f "${TARGET_CONFIG}/secrets.yml" ]; then
        echo 'No existing secrets found, installing example as active config'
        install -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 secrets.example.yml "${TARGET_CONFIG}/secrets.yml" &&
            print_success "secrets copied" || print_error "could not copy secrets"
    else
        echo "Upgrading existing secrets with any new keys..."
        ${PYTHON} tools/config_upgrade_yaml.py -c "${TARGET_CONFIG}/secrets.yml" -e secrets.example.yml &&
            print_success "secrets upgraded" || print_warning "secrets upgrade failed"
    fi

    # Fix stale secrets.ini reference in config if secrets.yml exists
    if [ -f "${TARGET_CONFIG}/zmeventnotification.yml" ] && [ -f "${TARGET_CONFIG}/secrets.yml" ]; then
        if grep -q 'secrets\.ini' "${TARGET_CONFIG}/zmeventnotification.yml"; then
            sed -i 's|secrets\.ini|secrets.yml|g' "${TARGET_CONFIG}/zmeventnotification.yml"
            print_success "Updated secrets path from .ini to .yml in zmeventnotification.yml"
        fi
    fi

    # Fix hardcoded /etc/zm paths in ES config when TARGET_CONFIG differs
    if [ "${TARGET_CONFIG}" != "/etc/zm" ] && [ -f "${TARGET_CONFIG}/zmeventnotification.yml" ]; then
        sed -i "s|/etc/zm/|${TARGET_CONFIG}/|g" "${TARGET_CONFIG}/zmeventnotification.yml"
        print_success "Updated /etc/zm paths to ${TARGET_CONFIG} in zmeventnotification.yml"
    fi

    # Migrate es_rules.json to YAML if needed
    if [ -f "${TARGET_CONFIG}/es_rules.json" ] && [ ! -f "${TARGET_CONFIG}/es_rules.yml" ]; then
        echo "Found existing es_rules.json but no es_rules.yml - converting..."
        if ${PYTHON} -c "
import json, yaml, sys
with open('${TARGET_CONFIG}/es_rules.json') as f:
    data = json.load(f)
with open('${TARGET_CONFIG}/es_rules.yml', 'w') as f:
    f.write('# Migrated from es_rules.json\n')
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
"; then
            print_success "es_rules migration complete"
            mv "${TARGET_CONFIG}/es_rules.json" "${TARGET_CONFIG}/es_rules.json.migrated"
            print_important "Renamed old es_rules.json to es_rules.json.migrated"
        else
            print_warning "es_rules migration failed"
        fi
    fi

    if [ ! -f "${TARGET_CONFIG}/es_rules.yml" ]; then
        echo 'No existing rules file found, installing example'
        install -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 es_rules.example.yml "${TARGET_CONFIG}/es_rules.yml" &&
            print_success "rules copied" || print_error "could not copy rules"
    else
        echo "Upgrading existing rules with any new keys..."
        ${PYTHON} tools/config_upgrade_yaml.py -c "${TARGET_CONFIG}/es_rules.yml" -e es_rules.example.yml &&
            print_success "rules upgraded" || print_warning "rules upgrade failed"
    fi


    print_warning " Remember to fill in the right values in the config files, or your system won't work!"
    echo
}

# move Hook config files
install_hook_config() {
    # Download models if needed (uses download_if_needed, so existing files are skipped)
    download_models

    # Auto-migrate from INI to YAML if needed
    if [ -f "${TARGET_CONFIG}/objectconfig.ini" ] && [ ! -f "${TARGET_CONFIG}/objectconfig.yml" ]; then
        echo "Found existing objectconfig.ini but no objectconfig.yml - running migration..."
        if ${PYTHON} tools/config_migrate_yaml.py -c "${TARGET_CONFIG}/objectconfig.ini" -o "${TARGET_CONFIG}/objectconfig.yml"; then
            print_success "migration complete"
            mv "${TARGET_CONFIG}/objectconfig.ini" "${TARGET_CONFIG}/objectconfig.ini.migrated"
            print_important "Renamed old objectconfig.ini to objectconfig.ini.migrated"
        else
            print_warning "migration failed"
        fi
    fi

    if [ ! -f "${TARGET_CONFIG}/objectconfig.yml" ]; then
        echo 'No existing hook config found, installing example as active config'
        install -o "${WEB_OWNER}" -g "${WEB_GROUP}" -m 644 hook/objectconfig.yml "${TARGET_CONFIG}" &&
            print_success "config copied" || print_error "could not copy config"
    else
        echo "Upgrading existing hook config with any new keys..."
        ${PYTHON} tools/config_upgrade_yaml.py -c "${TARGET_CONFIG}/objectconfig.yml" -e hook/objectconfig.yml &&
            print_success "hook config upgraded" || print_warning "hook config upgrade failed"
    fi

    # Fix stale secrets.ini reference in objectconfig if secrets.yml exists
    if [ -f "${TARGET_CONFIG}/objectconfig.yml" ] && [ -f "${TARGET_CONFIG}/secrets.yml" ]; then
        if grep -q 'secrets\.ini' "${TARGET_CONFIG}/objectconfig.yml"; then
            sed -i 's|secrets\.ini|secrets.yml|g' "${TARGET_CONFIG}/objectconfig.yml"
            print_success "Updated secrets path from .ini to .yml in objectconfig.yml"
        fi
    fi

    # Fix hardcoded /etc/zm paths in hook config when TARGET_CONFIG differs
    if [ "${TARGET_CONFIG}" != "/etc/zm" ] && [ -f "${TARGET_CONFIG}/objectconfig.yml" ]; then
        sed -i "s|/etc/zm/|${TARGET_CONFIG}/|g" "${TARGET_CONFIG}/objectconfig.yml"
        print_success "Updated /etc/zm paths to ${TARGET_CONFIG} in objectconfig.yml"
    fi

    print_warning " Remember to fill in the right values in the config files, or your system won't work!"
    echo
}

# returns 'ok' if openCV version >= version passed
check_opencv_version() {
    MAJOR=$1
    MINOR=$2
    CVVERS=`${PYTHON} -c "import cv2; print (cv2.__version__)" 2>/dev/null`
    if [ -z "${CVVERS}" ]; then
            echo "fail"
            return 1
    fi
    IFS='.'
    list=($CVVERS)
    if [ ${list[0]} -ge ${MAJOR} ] && [ ${list[1]} -ge ${MINOR} ]; then
            echo "ok"
            return 0
    else
            echo "fail"
            return 1
    fi
}

print_opencv_message() {

    print_success "Done"

    cat << EOF

    |-------------------------- NOTE -------------------------------------|

     Hooks are installed, but please make sure you have the right version
     of OpenCV installed. ONNX YOLOv26 models require OpenCV 4.13+.
     See https://zmeventnotificationv7.readthedocs.io/en/latest/guides/hooks.html#opencv-install

    |----------------------------------------------------------------------|

EOF
}

# Post-install diagnostic checks
run_doctor_checks() {
    local hook_config="${TARGET_CONFIG}/objectconfig.yml"
    local es_config="${TARGET_CONFIG}/zmeventnotification.yml"
    [ ! -f "$hook_config" ] && [ ! -f "$es_config" ] && return

    print_section 'Post-install diagnostic checks'

    ${PYTHON} tools/install_doctor.py \
        --hook-config "$hook_config" \
        --es-config "$es_config" \
        --web-owner "${WEB_OWNER}" \
        --web-group "${WEB_GROUP}" \
        --base-data "${TARGET_DATA}" \
        || true
}

# wuh
display_help() {
    cat << EOF
    
    sudo -H [VAR1=value|VAR2=value...] $0 [-h|--help] [--install-es|--no-install-es] [--install-hook|--no-install-hook] [--install-config|--no-install-config] [--install-es-config|--no-install-es-config] [--install-hook-config|--no-install-hook-config] [--hook-config-upgrade|--no-hook-config-upgrade] [--no-pysudo] [--no-download-models] [--install-opencv|--no-install-opencv]

        When used without any parameters executes in interactive mode

        -h: This help

        --install-es: installs Event Server without prompting
        --no-install-es: skips Event Server install without prompting

        --install-hook: installs hooks without prompting
        --no-install-hook: skips hooks install without prompting

        --install-config: installs/overwrites both ES and hook config files without prompting
        --no-install-config: skips both ES and hook config install without prompting

        --install-es-config: installs/overwrites ES config without prompting
        --no-install-es-config: skips ES config install without prompting

        --install-hook-config: installs/overwrites hook config without prompting
        --no-install-hook-config: skips hook config install without prompting

        --no-interactive: run automatically, but you need to specify flags for all components

        --no-pysudo: If specified will install python packages 
        without sudo (some users don't install packages globally)

        --no-download-models: If specified will not download any models.
        You may want to do this if using mlapi

        --install-opencv: Install python3-opencv (default)
        --no-install-opencv: Skip python3-opencv installation

        --hook-config-upgrade: Upgrades legacy objectconfig.ini and migrates to objectconfig.yml
        You will need to manually review the migrated config
        --no-hook-config-upgrade: skips above process

        In addition to the above, you can also override all variables used for your own needs 
        Overridable variables are: 

        PYTHON: python interpreter (default: python3)
        PIP: pip package installer (default: pip3)
        WGET: path to wget (default `which wget`)

        INSTALLER: Your OS equivalent of apt-get or yum (default: apt-get or yum)
        INSTALL_YOLOV3: Download and install yolov3 model (default:no)
        INSTALL_TINYYOLOV3: Download and install tiny yolov3 model (default:no)
        INSTALL_YOLOV4: Download and install yolov4 model (default:yes)
        INSTALL_TINY_YOLOV4: Download and install tiny yolov4 model (default:yes)
        INSTALL_CORAL_EDGETPU: Download and install coral models (default:no)
        INSTALL_YOLOV26: Download and install ONNX YOLOv26 models (default:yes). Needs OpenCV 4.13+

        TARGET_CONFIG: Path to ES config dir (default: /etc/zm)
        TARGET_DATA: Path to ES data dir (default: /var/lib/zmeventnotification)
        TARGET_BIN_ES: Path to ES binary (default:/usr/bin)
        TARGET_BIN_HOOK: Path to hook script files (default: /var/lib/zmeventnotification/bin)
        TARGET_PERL_LIB: Path to install Perl modules (default: /usr/share/perl5)

        INSTALL_OPENCV: Install python3-opencv (default: no)

        WEB_OWNER: Your webserver user (default: www-data)
        WEB_GROUP: Your webserver group (default: www-data)


EOF
}

# parses arguments and does a bit of conflict sanitization
check_args() {
    # credit: https://stackoverflow.com/a/14203146/1361529
    INSTALL_ES='prompt'
    INSTALL_HOOK='prompt'
    INSTALL_ES_CONFIG='prompt'
    INSTALL_HOOK_CONFIG='prompt'
    INSTALL_ES_CONFIG_EXPLICIT='no'
    INSTALL_HOOK_CONFIG_EXPLICIT='no'
    INTERACTIVE='yes'
    PY_SUDO='sudo -H'
    DOWNLOAD_MODELS='yes'
    HOOK_CONFIG_UPGRADE='yes'

    for key in "${cmd_args[@]}"
    do
    case $key in
        -h|--help)
            display_help && exit
            shift
            ;;

        --no-download-models)
            DOWNLOAD_MODELS='no'
            shift
            ;;
        --no-pysudo)
            PY_SUDO=''
            shift
            ;;
        --no-interactive)
            INTERACTIVE='no'
            shift
            ;;
        --install-es)
            INSTALL_ES='yes'
            shift 
            ;;
        --no-install-es)
            INSTALL_ES='no'
            shift
            ;;
        --install-hook)
            INSTALL_HOOK='yes'
            shift 
            ;;
        --no-install-hook)
            INSTALL_HOOK='no'
            shift
            ;;
        --no-hook-config-upgrade)
            HOOK_CONFIG_UPGRADE='no'
            shift
            ;;
        --hook-config-upgrade)
            HOOK_CONFIG_UPGRADE='yes'
            shift
            ;;
        --install-config)
            INSTALL_HOOK_CONFIG='yes'
            INSTALL_ES_CONFIG='yes'
            shift
            ;;
        --no-install-config)
            INSTALL_ES_CONFIG='no'
            INSTALL_HOOK_CONFIG='no'
            shift
            ;;
        --install-es-config)
            INSTALL_ES_CONFIG='yes'
            INSTALL_ES_CONFIG_EXPLICIT='yes'
            shift
            ;;
        --no-install-es-config)
            INSTALL_ES_CONFIG='no'
            INSTALL_ES_CONFIG_EXPLICIT='yes'
            shift
            ;;
        --install-hook-config)
            INSTALL_HOOK_CONFIG='yes'
            INSTALL_HOOK_CONFIG_EXPLICIT='yes'
            shift
            ;;
        --no-install-hook-config)
            INSTALL_HOOK_CONFIG='no'
            INSTALL_HOOK_CONFIG_EXPLICIT='yes'
            shift
            ;;
        --install-opencv)
            INSTALL_OPENCV='yes'
            shift
            ;;
        --no-install-opencv)
            INSTALL_OPENCV='no'
            shift
            ;;
        *)  # unknown option
            shift 
            ;;
    esac
    done  

    # If ES/hook won't be installed and config wasn't explicitly requested, skip config too
    if [[ ${INSTALL_ES_CONFIG_EXPLICIT} == 'no' ]]; then
        [[ ${INSTALL_ES} == 'no' ]] && INSTALL_ES_CONFIG='no'
        [[ ${INSTALL_ES} == 'prompt' && ${INSTALL_ES_CONFIG} == 'yes' ]] && INSTALL_ES_CONFIG='prompt'
    fi

    if [[ ${INSTALL_HOOK_CONFIG_EXPLICIT} == 'no' ]]; then
        [[ ${INSTALL_HOOK} == 'no' ]] && INSTALL_HOOK_CONFIG='no'
        [[ ${INSTALL_HOOK} == 'prompt' && ${INSTALL_HOOK_CONFIG} == 'yes' ]] && INSTALL_HOOK_CONFIG='prompt'
    fi
}

check_deps() {
    local missing=0

    if [[ ${INSTALL_ES} != 'no' ]]; then
        if ! perl -MNet::WebSocket::Server -e1 2>/dev/null; then
            print_error "Net::WebSocket::Server Perl module is not installed."
            echo "       Install it with: sudo cpanm Net::WebSocket::Server"
            missing=1
        fi
        if ! perl -MIO::Socket::SSL -e1 2>/dev/null; then
            print_error "IO::Socket::SSL Perl module is not installed."
            echo "       Install it with: sudo ${INSTALLER} install libio-socket-ssl-perl"
            missing=1
        fi
        if ! perl -MURI::Escape -e1 2>/dev/null; then
            print_error "URI::Escape Perl module is not installed."
            echo "       Install it with: sudo ${INSTALLER} install liburi-perl"
            missing=1
        fi
        if ! perl -MDBI -e1 2>/dev/null; then
            print_error "DBI Perl module is not installed."
            echo "       Install it with: sudo ${INSTALLER} install libdbi-perl"
            missing=1
        fi
    fi

    if [[ ${INSTALL_HOOK} != 'no' ]]; then
        if ! command -v ${PIP} >/dev/null 2>&1; then
            print_error "${PIP} is not installed."
            echo "       Install it with: sudo ${INSTALLER} install python3-pip"
            missing=1
        fi
    fi

    if [[ ${missing} -eq 1 ]]; then
        print_error "Please install missing dependencies and re-run."
        exit 1
    fi
}

###################################################
# script main
###################################################
cmd_args=("$@") # because we need a function to access them
check_args
DISTRO=$(get_distro)
check_root
verify_config
check_deps
echo
echo

ES_INSTALLED='no'
[[ ${INSTALL_ES} == 'yes' ]] && { install_es; ES_INSTALLED='yes'; }
[[ ${INSTALL_ES} == 'no' ]] && print_skip 'Event Server install'
if [[ ${INSTALL_ES} == 'prompt' ]]
then
    confirm 'Install Event Server' 'y/N' && { install_es; ES_INSTALLED='yes'; } || print_skip 'Event Server install'
fi

echo
echo

if [[ ${ES_INSTALLED} == 'no' ]]; then
    print_skip 'Event Server config (ES was not installed)'
else
    [[ ${INSTALL_ES_CONFIG} == 'yes' ]] && install_es_config
    [[ ${INSTALL_ES_CONFIG} == 'no' ]] && print_skip 'Event Server config install'
    if [[ ${INSTALL_ES_CONFIG} == 'prompt' ]]
    then
        confirm 'Install Event Server Config' 'y/N' && install_es_config || print_skip 'Event Server config install'
    fi
fi

echo
echo

[[ ${INSTALL_HOOK} == 'yes' ]] && install_hook 
[[ ${INSTALL_HOOK} == 'no' ]] && print_skip 'Hook install'
if [[ ${INSTALL_HOOK} == 'prompt' ]] 
then
    confirm 'Install Hook' 'y/N' && install_hook || print_skip 'Hook install'
fi

echo
echo

[[ ${INSTALL_HOOK_CONFIG} == 'yes' ]] && install_hook_config
[[ ${INSTALL_HOOK_CONFIG} == 'no' ]] && print_skip 'Hook config install'
if [[ ${INSTALL_HOOK_CONFIG} == 'prompt' ]] 
then
    confirm 'Install Hook Config' 'y/N' && install_hook_config || print_skip 'Hook config install'
fi

# Make sure webserver can access them
chown -R ${WEB_OWNER}:${WEB_GROUP} "${TARGET_DATA}"


if [ "${INSTALL_CORAL_EDGETPU}" == "yes" ]
then
    echo
    echo "========================================================================"
    print_important " Google Coral Edge TPU — MANUAL STEPS REQUIRED"
    echo "========================================================================"
    print_warning " This installer downloads TPU model files but does NOT install"
    print_warning " the TPU runtime libraries. You MUST install them yourself or"
    print_warning " you will get: ModuleNotFoundError: No module named 'pycoral'"
    echo
    echo "    Follow the instructions at:"
    echo "      https://coral.ai/docs/accelerator/get-started/"
    echo
    echo "    Specifically, you need to:"
    echo "      1. Install the right libedgetpu library (max or std)"
    echo "      2. Install the pycoral API:"
    echo "           pip3 install pycoral"
    echo "         or follow https://coral.ai/software/#pycoral-api"
    print_warning " pycoral official packages only support Python <=3.9."
    print_warning " For Python 3.10+ see: https://github.com/google-coral/pycoral/issues/149"
    echo
    echo "    You also need to make sure your web user (${WEB_OWNER}) has"
    echo "    access to the Coral USB device:"
    echo "      sudo usermod -a -G plugdev ${WEB_OWNER}"
    echo "========================================================================"
    echo
fi

if [ "${HOOK_CONFIG_UPGRADE}" == "yes" ]
then
    echo
    # If old INI exists, migrate to YAML
    if [ -f "${TARGET_CONFIG}/objectconfig.ini" ] && [ ! -f "${TARGET_CONFIG}/objectconfig.yml" ]; then
        echo "Migrating objectconfig.ini to objectconfig.yml..."
        if ${PYTHON} tools/config_migrate_yaml.py -c "${TARGET_CONFIG}/objectconfig.ini" -o "${TARGET_CONFIG}/objectconfig.yml"; then
            print_success "YAML migration complete"
            mv "${TARGET_CONFIG}/objectconfig.ini" "${TARGET_CONFIG}/objectconfig.ini.migrated"
            print_important "Renamed old objectconfig.ini to objectconfig.ini.migrated"
        else
            print_warning "YAML migration failed"
        fi
    else
        echo "No legacy objectconfig.ini found (or objectconfig.yml already exists), skipping upgrade"
    fi
else
    print_skip 'Hook config upgrade process'
fi


run_doctor_checks

echo
if [[ ${ES_INSTALLED} == 'yes' ]]; then
    print_success " Installation complete. Please remember to start the Event Server."
else
    print_success " Hook installation complete. Configure objectconfig.yml and set up EventStartCommand in ZM."
fi
