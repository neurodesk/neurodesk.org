#!/bin/bash

random_tunnel_port() {
    # macOS does not ship `shuf` by default.
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 10000-65000 -n 1
        return
    fi

    echo $((10000 + RANDOM % 55001))
}

port_is_free_local() {
    local PORT="$1"

    if [ -z "$PORT" ]; then
        return 1
    fi

    if command -v lsof >/dev/null 2>&1; then
        if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi

    if command -v ss >/dev/null 2>&1; then
        if ss -ltn "( sport = :$PORT )" 2>/dev/null | awk 'NR>1 {found=1} END {exit(found ? 0 : 1)}'; then
            return 1
        fi
        return 0
    fi

    if command -v netstat >/dev/null 2>&1; then
        if netstat -an 2>/dev/null | grep -Eq "[\\.:]${PORT}[[:space:]].*LISTEN"; then
            return 1
        fi
        return 0
    fi

    return 0
}

port_is_free_remote() {
    local SSH_SOCKET="$1"
    local SSH_TARGET="$2"
    local PORT="$3"

    ssh -S "$SSH_SOCKET" -q "$SSH_TARGET" "bash -s -- \"$PORT\"" <<'EOF'
port="$1"

if [ -z "$port" ]; then
    exit 1
fi

if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
        exit 1
    fi
    exit 0
fi

if command -v ss >/dev/null 2>&1; then
    if ss -ltn "( sport = :${port} )" 2>/dev/null | awk 'NR>1 {found=1} END {exit(found ? 0 : 1)}'; then
        exit 1
    fi
    exit 0
fi

if command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -Eq "[\\.:]${port}[[:space:]].*LISTEN"; then
        exit 1
    fi
    exit 0
fi

exit 0
EOF
}

choose_shared_tunnel_port() {
    local SSH_SOCKET="$1"
    local SSH_TARGET="$2"
    local MAX_ATTEMPTS="${3:-80}"
    local ATTEMPT=1
    local CANDIDATE_PORT

    while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
        CANDIDATE_PORT=$(random_tunnel_port)
        if [[ ! "$CANDIDATE_PORT" =~ ^[0-9]+$ ]]; then
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi

        if ! port_is_free_local "$CANDIDATE_PORT"; then
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi

        if ! port_is_free_remote "$SSH_SOCKET" "$SSH_TARGET" "$CANDIDATE_PORT"; then
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi

        echo "$CANDIDATE_PORT"
        return 0
    done

    return 1
}

ssh_config_has_host_alias() {
    local SSH_CONFIG_FILE="$1"
    local TARGET_ALIAS="$2"

    if [ ! -f "$SSH_CONFIG_FILE" ]; then
        return 1
    fi

    awk -v target="$TARGET_ALIAS" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]+/, "", line)
            split(line, host_patterns, /[[:space:]]+/)
            for (i in host_patterns) {
                if (tolower(host_patterns[i]) == tolower(target)) {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$SSH_CONFIG_FILE"
}

ensure_sherlock_ssh_config() {
    local LOGIN_ALIAS="$1"
    local SSH_DIR="${HOME}/.ssh"
    local SSH_CONFIG_FILE="${SSH_DIR}/config"
    local USER_CHOICE
    local SHERLOCK_USER

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR" 2>/dev/null || true

    if ssh_config_has_host_alias "$SSH_CONFIG_FILE" "$LOGIN_ALIAS"; then
        return 0
    fi

    echo "No SSH config entry found for '${LOGIN_ALIAS}' in ${SSH_CONFIG_FILE}."
    echo "This script connects using the '${LOGIN_ALIAS}' SSH alias."
    echo -n "Add a Sherlock SSH config entry now? [Y/n] "
    read -r USER_CHOICE

    if [[ "$USER_CHOICE" =~ ^([nN][oO]|[nN])$ ]]; then
        echo "Skipping SSH config update."
        return 1
    fi

    echo -n "Sherlock username (SUNet ID) [${USER}]: "
    read -r SHERLOCK_USER
    SHERLOCK_USER=${SHERLOCK_USER:-$USER}

    if [ -f "$SSH_CONFIG_FILE" ] && [ -s "$SSH_CONFIG_FILE" ]; then
        printf "\n" >> "$SSH_CONFIG_FILE"
    fi

    cat >> "$SSH_CONFIG_FILE" <<EOF
Host ${LOGIN_ALIAS}
    ControlMaster auto
    ControlPath ~/.ssh/%l%r@%h:%p
    HostName login.sherlock.stanford.edu
    User ${SHERLOCK_USER}
    ControlPersist 1h
EOF
    chmod 600 "$SSH_CONFIG_FILE" 2>/dev/null || true
    echo "Added SSH config entry for '${LOGIN_ALIAS}' to ${SSH_CONFIG_FILE}."
    return 0
}

resolve_ssh_user_for_alias() {
    local LOGIN_ALIAS="$1"
    local RESOLVED_USER

    RESOLVED_USER=$(ssh -G "$LOGIN_ALIAS" 2>/dev/null | awk 'tolower($1)=="user" {print $2; exit}')
    if [ -z "$RESOLVED_USER" ]; then
        RESOLVED_USER="$USER"
    fi

    echo "$RESOLVED_USER"
}

read_secret_value() {
    local PROMPT_TEXT="$1"
    local RESULT_VAR_NAME="$2"
    local SECRET_VALUE

    IFS= read -r -s -p "$PROMPT_TEXT" SECRET_VALUE
    echo
    printf -v "$RESULT_VAR_NAME" '%s' "$SECRET_VALUE"
}

ensure_sherlock_password_in_keychain() {
    local SHERLOCK_USER="$1"
    local KEYCHAIN_SERVICE="neurodesk.connectSherlock.ssh"
    local USER_CHOICE
    local SHERLOCK_PASSWORD

    if ! command -v security >/dev/null 2>&1; then
        return 1
    fi

    if security find-generic-password -a "$SHERLOCK_USER" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
        return 0
    fi

    echo "No saved Sherlock password found in macOS Keychain for '${SHERLOCK_USER}'."
    echo -n "Save Sherlock password in Keychain for future logins? [Y/n] "
    read -r USER_CHOICE

    if [[ "$USER_CHOICE" =~ ^([nN][oO]|[nN])$ ]]; then
        return 1
    fi

    read_secret_value "Sherlock password for ${SHERLOCK_USER}: " SHERLOCK_PASSWORD
    if [ -z "$SHERLOCK_PASSWORD" ]; then
        echo "Empty password was not saved."
        return 1
    fi

    if ! security add-generic-password -U -a "$SHERLOCK_USER" -s "$KEYCHAIN_SERVICE" -w "$SHERLOCK_PASSWORD" >/dev/null 2>&1; then
        unset SHERLOCK_PASSWORD
        echo "Failed to save Sherlock password in Keychain."
        return 1
    fi

    unset SHERLOCK_PASSWORD
    echo "Saved Sherlock password in macOS Keychain service '${KEYCHAIN_SERVICE}'."
    return 0
}

start_master_connection_with_password_autofill() {
    local LOGIN_ALIAS="$1"
    local CTRL_SOCKET="$2"
    local SHERLOCK_USER
    local ASKPASS_SCRIPT
    local KEYCHAIN_SERVICE="neurodesk.connectSherlock.ssh"
    local DUO_OPTION="${NEURODESKTOP_DUO_OPTION:-1}"

    if [ "$(uname -s)" != "Darwin" ]; then
        return 1
    fi

    if ! command -v security >/dev/null 2>&1; then
        return 1
    fi

    SHERLOCK_USER=$(resolve_ssh_user_for_alias "$LOGIN_ALIAS")
    if ! ensure_sherlock_password_in_keychain "$SHERLOCK_USER"; then
        return 1
    fi
    echo "Auto-selecting Duo prompt option: ${DUO_OPTION} (override with NEURODESKTOP_DUO_OPTION=<option-number>)."

    ASKPASS_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/neurodesk_askpass_XXXXXX")
    if [ -z "$ASKPASS_SCRIPT" ]; then
        return 1
    fi

    cat > "$ASKPASS_SCRIPT" <<'EOF'
#!/bin/sh
PROMPT_TEXT="$1"

case "$PROMPT_TEXT" in
    *assword*|*ASSWORD*)
        security find-generic-password -a "$NEURODESKTOP_SSH_ACCOUNT" -s "$NEURODESKTOP_SSH_SERVICE" -w 2>/dev/null
        ;;
    *Passcode*|*passcode*|*Verification*|*verification*|*option*|*Option*)
        printf '%s\n' "${NEURODESKTOP_DUO_OPTION:-1}"
        ;;
    *)
        printf '\n'
        ;;
esac
EOF
    chmod 700 "$ASKPASS_SCRIPT" 2>/dev/null || true

    NEURODESKTOP_SSH_ACCOUNT="$SHERLOCK_USER" \
    NEURODESKTOP_SSH_SERVICE="$KEYCHAIN_SERVICE" \
    NEURODESKTOP_DUO_OPTION="$DUO_OPTION" \
    DISPLAY="${DISPLAY:-neurodesk-askpass}" \
    SSH_ASKPASS="$ASKPASS_SCRIPT" \
    SSH_ASKPASS_REQUIRE=force \
    ssh -M -f -N -S "$CTRL_SOCKET" "$LOGIN_ALIAS"
    local AUTH_STATUS=$?

    rm -f "$ASKPASS_SCRIPT"
    return "$AUTH_STATUS"
}

function connectSherlock() {
    local LOGIN_NODE="sherlock"
    local JOB_NAME="neurodesktop"
    local CTRL_SOCKET="${HOME}/.ssh/sherlock_ctrl_$(date +%s)_${RANDOM}"
    local TUNNEL_PORT

    if ! ensure_sherlock_ssh_config "$LOGIN_NODE"; then
        echo "Please add a valid SSH entry for '${LOGIN_NODE}' and run the script again."
        return 1
    fi

    # Start master connection
    # -M: master mode, -f: background, -N: no command, -S: socket path
    if ! start_master_connection_with_password_autofill "$LOGIN_NODE" "$CTRL_SOCKET"; then
        ssh -M -f -N -S "$CTRL_SOCKET" "$LOGIN_NODE"
        if [ $? -ne 0 ]; then
            echo "Authentication failed."
            return 1
        fi
    fi
    # Close master connection on return.
    trap 'ssh -S "'"$CTRL_SOCKET"'" -O exit "'"$LOGIN_NODE"'" 2>/dev/null' RETURN
    
    # --- 1. CHECK FOR EXISTING "NEURODESKTOP" JOBS ---
    # We add --name="neurodesktop" to squeue so we don't accidentally 
    # grab background compute jobs.
    local EXISTING_JOB=$(ssh -S "$CTRL_SOCKET" -q "$LOGIN_NODE" "squeue -u \$USER --name=$JOB_NAME -h -t R -o '%i %N' | head -n 1")
    
    if [ ! -z "$EXISTING_JOB" ]; then
        read -r JOB_ID NODE_NAME <<< "$EXISTING_JOB"
        echo "Found active $JOB_NAME session (Job $JOB_ID) on Node: $NODE_NAME"
        echo -n "Reuse this connection? [Y/n] "
        read -r reuse
        
        # Default to Yes
        if [[ ! "$reuse" =~ ^([nN][oO]|[nN])$ ]]; then
            echo "Reconnecting to $NODE_NAME..."
            echo "ℹ️  Using existing tunnel from your original terminal."
            ssh -S "$CTRL_SOCKET" -t "$LOGIN_NODE" "ssh $NODE_NAME"
            return
        fi
    fi

    # --- 2. CONFIGURATION FOR NEW CONNECTION ---
    echo "================================================================================"
    echo " partition   || job runtime       | mem/core | per-node cores"
    echo " name        ||     maximum       |  maximum | (range)"
    echo "--------------------------------------------------------------------------------"
    echo " normal      || 2d or 7d (owner) |      8GB  | 20-64"
    echo " bigmem      ||               1d |     64GB  | 24-256"
    echo " dev         ||               2h |      8GB  | 20-32"
    echo "--------------------------------------------------------------------------------"
    echo "================================================================================"
    
    echo -n "Which partition do you want to submit to? [normal] "
    read -r PARTITION
    PARTITION=${PARTITION:-normal}

    echo -n "How much Memory needed? [8G] "
    read -r MEM
    MEM=${MEM:-8G}

    echo -n "How many CPUs needed? [1] "
    read -r CPUS
    CPUS=${CPUS:-1}

    echo -n "How much Time needed? [02:00:00] "
    read -r WALLTIME
    WALLTIME=${WALLTIME:-02:00:00}

    echo -n "How many GPUs needed? [none] "
    read -r GPU
    GPU=${GPU:-none}

    TUNNEL_PORT=$(choose_shared_tunnel_port "$CTRL_SOCKET" "$LOGIN_NODE")
    if [[ ! "$TUNNEL_PORT" =~ ^[0-9]+$ ]]; then
        echo "Failed to find a shared free tunnel port after multiple attempts."
        echo "Please close old SSH tunnels/services and run the script again."
        return 1
    fi

    echo "Using shared random tunnel/notebook port: ${TUNNEL_PORT}"

    echo "Preparing setup script..."
    ssh -S "$CTRL_SOCKET" "$LOGIN_NODE" "cat > ~/.neurodesk_setup.sh && chmod +x ~/.neurodesk_setup.sh" <<'EOF'
#!/bin/bash
export PATH=$PATH:/sbin:/usr/sbin
NEURODESKTOP_ASSET_BASE="${HOME%/}/neurodesk"
NEURODESKTOP_HOME_DIR="${NEURODESKTOP_ASSET_BASE}/home"
NEURODESKTOP_WORKDIR="${NEURODESKTOP_HOME_DIR}/workdir"
NEURODESKTOP_CONTAINER_USER="${NEURODESKTOP_CONTAINER_USER:-jovyan}"
NEURODESKTOP_CONTAINER_HOME="${NEURODESKTOP_CONTAINER_HOME:-/home/${NEURODESKTOP_CONTAINER_USER}}"
NEURODESKTOP_SCRATCH_DIR="${SCRATCH:-/scratch/users/${USER:-neurodesk}}"

if [ -d "${NEURODESKTOP_ASSET_BASE}/slurm" ]; then
    echo "Removing cached Slurm compatibility assets at ${NEURODESKTOP_ASSET_BASE}/slurm..."
    rm -rf "${NEURODESKTOP_ASSET_BASE}/slurm"
fi

if [ ! -d "${NEURODESKTOP_HOME_DIR}" ]; then
    echo "Creating ${NEURODESKTOP_HOME_DIR}..."
    mkdir -p "${NEURODESKTOP_HOME_DIR}"
else
    echo "${NEURODESKTOP_HOME_DIR} found."
fi

if [ ! -d "${NEURODESKTOP_WORKDIR}" ]; then
    echo "Creating ${NEURODESKTOP_WORKDIR}..."
    mkdir -p "${NEURODESKTOP_WORKDIR}"
else
    echo "${NEURODESKTOP_WORKDIR} found."
fi

NEURODESKTOP_START_DIR="${NEURODESKTOP_START_DIR:-${NEURODESKTOP_SCRATCH_DIR}}"
if [ ! -d "${NEURODESKTOP_START_DIR}" ]; then
    echo "Requested start dir ${NEURODESKTOP_START_DIR} not found; falling back to ${NEURODESKTOP_WORKDIR}."
    NEURODESKTOP_START_DIR="${NEURODESKTOP_WORKDIR}"
fi
NEURODESKTOP_CONTAINER_WORKDIR="${NEURODESKTOP_CONTAINER_WORKDIR:-${NEURODESKTOP_START_DIR}}"
if ! cd "${NEURODESKTOP_START_DIR}"; then
    echo "ERROR: failed to cd into ${NEURODESKTOP_START_DIR}"
    exit 1
fi
echo "Container start directory target: ${NEURODESKTOP_START_DIR}"
echo "Container working directory path: ${NEURODESKTOP_CONTAINER_WORKDIR}"
echo "Container home mapping: ${NEURODESKTOP_HOME_DIR} -> ${NEURODESKTOP_CONTAINER_HOME}"
echo "Using --writable-tmpfs (ephemeral writable container layer)."

SLURM_BINDS=()
add_slurm_bind() {
    local bind_spec="$1"
    local idx
    for ((idx=1; idx<${#SLURM_BINDS[@]}; idx+=2)); do
        if [ "${SLURM_BINDS[$idx]}" = "${bind_spec}" ]; then
            return
        fi
    done
    SLURM_BINDS+=(--bind "${bind_spec}")
}
# Ensure the notebook start/work directory is available at the same path in the container.
if [ -d "${NEURODESKTOP_START_DIR}" ]; then
    add_slurm_bind "${NEURODESKTOP_START_DIR}:${NEURODESKTOP_START_DIR}"
fi
HOST_SLURM_CONF="${SLURM_CONF:-/etc/slurm/slurm.conf}"
HOST_SLURM_CONF_DIR=/etc/slurm
if [ -n "${HOST_SLURM_CONF}" ]; then
    HOST_SLURM_CONF_DIR=$(dirname -- "${HOST_SLURM_CONF}")
fi
HOST_SLURM_CONF_REAL=$(readlink -f "${HOST_SLURM_CONF}" 2>/dev/null || echo "${HOST_SLURM_CONF}")
if [ -z "${HOST_SLURM_CONF_REAL}" ]; then
    HOST_SLURM_CONF_REAL="${HOST_SLURM_CONF}"
fi
HOST_SLURM_CONF_REAL_DIR="${HOST_SLURM_CONF_DIR}"
if [ -n "${HOST_SLURM_CONF_REAL}" ]; then
    HOST_SLURM_CONF_REAL_DIR=$(dirname -- "${HOST_SLURM_CONF_REAL}")
fi
CONTAINER_SLURM_CONF_DIR=/etc/slurm
CONTAINER_SLURM_CONF_PATH="${CONTAINER_SLURM_CONF_DIR}/${HOST_SLURM_CONF_REAL##*/}"
if [ -d "${HOST_SLURM_CONF_REAL_DIR}" ]; then
    add_slurm_bind "${HOST_SLURM_CONF_REAL_DIR}:${CONTAINER_SLURM_CONF_DIR}"
elif [ -d "${HOST_SLURM_CONF_DIR}" ]; then
    add_slurm_bind "${HOST_SLURM_CONF_DIR}:${CONTAINER_SLURM_CONF_DIR}"
fi

SLURM_PLUGIN_DIRS_RAW=""
if [ -r "${HOST_SLURM_CONF_REAL}" ]; then
    SLURM_PLUGIN_DIRS_RAW=$(awk -F= '/^[[:space:]]*PluginDir[[:space:]]*=/{print $2}' "${HOST_SLURM_CONF_REAL}" | tail -n 1 | tr -d '[:space:]')
fi
if [ -z "${SLURM_PLUGIN_DIRS_RAW}" ] && [ -n "${SLURM_PLUGIN_DIR:-}" ]; then
    SLURM_PLUGIN_DIRS_RAW="${SLURM_PLUGIN_DIR}"
fi
if [ -n "${SLURM_PLUGIN_DIRS_RAW}" ]; then
    OLD_IFS="${IFS}"
    IFS=':'
    read -r -a SLURM_PLUGIN_DIRS <<< "${SLURM_PLUGIN_DIRS_RAW}"
    IFS="${OLD_IFS}"
    for plugin_dir in "${SLURM_PLUGIN_DIRS[@]}"; do
        if [ -n "${plugin_dir}" ] && [ -d "${plugin_dir}" ]; then
            add_slurm_bind "${plugin_dir}:${plugin_dir}"
        fi
    done
fi

SLURM_LD_LIBRARY_PATH=""
if [ -z "${NEURODESKTOP_ASSET_BASE:-}" ]; then
    NEURODESKTOP_ASSET_BASE="${HOME%/}/neurodesk"
fi
SLURM_ASSET_ROOT="${NEURODESKTOP_ASSET_BASE}/slurm"
SLURM_HOST_BIN_REAL_STAGING="${SLURM_ASSET_ROOT}/bin-real"
SLURM_HOST_BIN_STAGING="${SLURM_ASSET_ROOT}/bin"
SLURM_HOST_LIB_STAGING="${SLURM_ASSET_ROOT}/libs"
SLURM_WRAPPER_LIB_PATH="/opt/slurm-host-libs"
SLURM_WRAPPER_BIN_PATH="/opt/slurm-host-bin"
unset APPTAINERENV_PREPEND_PATH
unset APPTAINERENV_PATH
resolve_slurm_cmd_path() {
    local slurm_cmd_name="$1"
    local slurm_cmd_path=""
    slurm_cmd_path=$(type -P "${slurm_cmd_name}" 2>/dev/null || true)
    if [ -z "${slurm_cmd_path}" ]; then
        for candidate in /usr/bin /usr/local/bin /bin /usr/sbin /sbin; do
            if [ -x "${candidate}/${slurm_cmd_name}" ]; then
                slurm_cmd_path="${candidate}/${slurm_cmd_name}"
                break
            fi
        done
    fi
    echo "${slurm_cmd_path}"
}
resolve_host_cmd_path() {
    local cmd_name="$1"
    local cmd_path=""
    local login_path=""
    local OLD_IFS

    cmd_path=$(resolve_slurm_cmd_path "${cmd_name}")
    if [ -n "${cmd_path}" ] && [ -x "${cmd_path}" ]; then
        echo "${cmd_path}"
        return
    fi

    # In non-login shells on Sherlock, PATH can miss helper locations.
    login_path=$(bash -lc 'printf "%s" "$PATH"' 2>/dev/null || true)
    if [ -n "${login_path}" ]; then
        OLD_IFS="${IFS}"
        IFS=':'
        read -r -a login_dirs <<< "${login_path}"
        IFS="${OLD_IFS}"
        for login_dir in "${login_dirs[@]}"; do
            [ -z "${login_dir}" ] && continue
            if [ -x "${login_dir}/${cmd_name}" ]; then
                echo "${login_dir}/${cmd_name}"
                return
            fi
        done
    fi

    for candidate in \
        /share/software/user/open/bin \
        /share/software/user/bin \
        /usr/local/bin \
        /usr/bin \
        /bin \
        /usr/sbin \
        /sbin
    do
        if [ -x "${candidate}/${cmd_name}" ]; then
            echo "${candidate}/${cmd_name}"
            return
        fi
    done

    echo ""
}
copy_host_library_dep() {
    local dep_path="$1"
    local dep_base
    [ -z "${dep_path}" ] && return
    [ -r "${dep_path}" ] || return
    dep_base=$(basename "${dep_path}")
    case "${dep_base}" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|ld-linux*.so.*)
            return
            ;;
    esac
    cp -Lf "${dep_path}" "${SLURM_HOST_LIB_STAGING}/${dep_base}" 2>/dev/null || true
}
resolve_missing_library_dep() {
    local dep_name="$1"
    local dep_path=""
    local dep_dir
    if command -v ldconfig >/dev/null 2>&1; then
        dep_path=$(ldconfig -p 2>/dev/null | awk -v lib="${dep_name}" '$1 == lib {print $NF; exit}')
    fi
    if [ -n "${dep_path}" ] && [ -r "${dep_path}" ]; then
        echo "${dep_path}"
        return
    fi
    for dep_dir in /usr/lib64 /lib64 /usr/lib /lib /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
        if [ -r "${dep_dir}/${dep_name}" ]; then
            echo "${dep_dir}/${dep_name}"
            return
        fi
    done
    echo ""
}
copy_binary_dependencies() {
    local bin_path="$1"
    local dep_path
    local dep_name
    local resolved_path
    while read -r dep_path; do
        [ -z "${dep_path}" ] && continue
        copy_host_library_dep "${dep_path}"
    done < <(ldd "${bin_path}" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}')
    while read -r dep_name; do
        [ -z "${dep_name}" ] && continue
        resolved_path=$(resolve_missing_library_dep "${dep_name}")
        if [ -n "${resolved_path}" ]; then
            copy_host_library_dep "${resolved_path}"
        fi
    done < <(ldd "${bin_path}" 2>/dev/null | awk '$2 == "=>" && $3 == "not" && $4 == "found" {print $1}')
}
copy_library_family_dependencies() {
    local lib_prefix="$1"
    local dep_dir
    local dep_path
    for dep_dir in /usr/lib64 /lib64 /usr/lib /lib /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
        [ -d "${dep_dir}" ] || continue
        while read -r dep_path; do
            [ -z "${dep_path}" ] && continue
            copy_host_library_dep "${dep_path}"
        done < <(find "${dep_dir}" -maxdepth 1 -type f -name "${lib_prefix}*.so*" 2>/dev/null)
    done
}
file_mtime_epoch() {
    local path="$1"
    if [ ! -e "${path}" ]; then
        echo 0
        return
    fi
    stat -c %Y "${path}" 2>/dev/null || stat -f %m "${path}" 2>/dev/null || echo 0
}
hash_text_value() {
    local value="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "${value}" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "${value}" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "${value}" | cksum | awk '{print $1}'
    fi
}
if command -v ldd >/dev/null 2>&1; then
    SLURM_HOST_CMDS=(sinfo squeue scontrol sacct srun sbatch scancel salloc sstat sprio quota lfs)
    SLURM_CACHE_DIR="${SLURM_ASSET_ROOT}/cache"
    SLURM_CACHE_SIG_FILE="${SLURM_CACHE_DIR}/signature.txt"
    SLURM_CACHE_TTL_SECONDS="${NEURODESKTOP_SLURM_CACHE_TTL_SECONDS:-86400}"
    if [[ ! "${SLURM_CACHE_TTL_SECONDS}" =~ ^[0-9]+$ ]]; then
        SLURM_CACHE_TTL_SECONDS=86400
    fi
    mkdir -p "${SLURM_CACHE_DIR}"
    mkdir -p "${SLURM_HOST_BIN_REAL_STAGING}"
    mkdir -p "${SLURM_HOST_BIN_STAGING}"
    mkdir -p "${SLURM_HOST_LIB_STAGING}"
    SLURM_CACHE_INPUT="host=$(hostname 2>/dev/null || echo unknown)
slurm_conf=${HOST_SLURM_CONF_REAL}
slurm_conf_mtime=$(file_mtime_epoch "${HOST_SLURM_CONF_REAL}")
plugin_dirs=${SLURM_PLUGIN_DIRS_RAW:-unset}"
    for plugin_dir in "${SLURM_PLUGIN_DIRS[@]}"; do
        [ -z "${plugin_dir}" ] && continue
        SLURM_CACHE_INPUT="${SLURM_CACHE_INPUT}
plugin_dir=${plugin_dir}|mtime=$(file_mtime_epoch "${plugin_dir}")"
    done
    for slurm_cmd in "${SLURM_HOST_CMDS[@]}"; do
        cmd_path=$(resolve_slurm_cmd_path "${slurm_cmd}")
        SLURM_CACHE_INPUT="${SLURM_CACHE_INPUT}
cmd=${slurm_cmd}|path=${cmd_path:-missing}|mtime=$(file_mtime_epoch "${cmd_path}")"
    done
    SLURM_CACHE_SIGNATURE=$(hash_text_value "${SLURM_CACHE_INPUT}")

    NEED_CACHE_REBUILD=1
    CACHE_COMMAND_WRAPPERS_OK=1
    for slurm_cmd in "${SLURM_HOST_CMDS[@]}"; do
        cmd_path=$(resolve_slurm_cmd_path "${slurm_cmd}")
        if [ -n "${cmd_path}" ] && [ -x "${cmd_path}" ]; then
            if [ ! -x "${SLURM_HOST_BIN_STAGING}/${slurm_cmd}" ] || \
               [ ! -e "${SLURM_HOST_BIN_REAL_STAGING}/${slurm_cmd}" ]; then
                CACHE_COMMAND_WRAPPERS_OK=0
                break
            fi
        fi
    done
    if [ -f "${SLURM_CACHE_SIG_FILE}" ] && [ -s "${SLURM_CACHE_SIG_FILE}" ]; then
        CACHED_SIGNATURE=$(head -n 1 "${SLURM_CACHE_SIG_FILE}" 2>/dev/null || echo "")
        CACHE_SIG_MTIME=$(file_mtime_epoch "${SLURM_CACHE_SIG_FILE}")
        CACHE_NOW_EPOCH=$(date +%s)
        CACHE_AGE=$((CACHE_NOW_EPOCH - CACHE_SIG_MTIME))
        if [ "${CACHED_SIGNATURE}" = "${SLURM_CACHE_SIGNATURE}" ] && \
           [ "${CACHE_AGE}" -ge 0 ] && [ "${CACHE_AGE}" -le "${SLURM_CACHE_TTL_SECONDS}" ] && \
           ls "${SLURM_HOST_BIN_REAL_STAGING}"/* >/dev/null 2>&1 && \
           ls "${SLURM_HOST_BIN_STAGING}"/* >/dev/null 2>&1 && \
           [ "${CACHE_COMMAND_WRAPPERS_OK}" -eq 1 ]; then
            NEED_CACHE_REBUILD=0
        fi
    fi

    if [ "${NEED_CACHE_REBUILD}" -eq 1 ]; then
        echo "Preparing host Slurm compatibility assets (initial run or cache refresh)..."
        rm -f "${SLURM_HOST_BIN_REAL_STAGING}"/* 2>/dev/null || true
        rm -f "${SLURM_HOST_BIN_STAGING}"/* 2>/dev/null || true
        rm -f "${SLURM_HOST_LIB_STAGING}"/*.so* 2>/dev/null || true

        echo "Scanning host Slurm command dependencies..."
        for slurm_cmd in "${SLURM_HOST_CMDS[@]}"; do
            cmd_path=$(resolve_slurm_cmd_path "${slurm_cmd}")
            if [ -n "${cmd_path}" ] && [ -x "${cmd_path}" ]; then
                cp -Lf "${cmd_path}" "${SLURM_HOST_BIN_REAL_STAGING}/${slurm_cmd}" 2>/dev/null || true
                printf '%s\n' \
                    '#!/bin/bash' \
                    "export LD_LIBRARY_PATH=${SLURM_WRAPPER_LIB_PATH}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}" \
                    "exec /opt/slurm-host-bin-real/${slurm_cmd} \"\$@\"" \
                    > "${SLURM_HOST_BIN_STAGING}/${slurm_cmd}"
                chmod +x "${SLURM_HOST_BIN_STAGING}/${slurm_cmd}" 2>/dev/null || true
                copy_binary_dependencies "${cmd_path}"
            fi
        done

        if [ -n "${SLURM_PLUGIN_DIRS_RAW}" ]; then
            echo "Scanning Slurm plugin dependencies..."
        fi
        for plugin_dir in "${SLURM_PLUGIN_DIRS[@]}"; do
            [ -d "${plugin_dir}" ] || continue
            while read -r plugin_file; do
                [ -r "${plugin_file}" ] || continue
                copy_binary_dependencies "${plugin_file}"
            done < <(find "${plugin_dir}" -maxdepth 4 -type f -name '*.so*' 2>/dev/null)
        done

        # lfs can dlopen Lustre libraries that may not appear in ldd output.
        copy_library_family_dependencies liblustre
        copy_library_family_dependencies liblnet

        printf '%s\n' "${SLURM_CACHE_SIGNATURE}" > "${SLURM_CACHE_SIG_FILE}"
    else
        echo "Using cached host Slurm compatibility assets."
    fi

    if ls "${SLURM_HOST_BIN_REAL_STAGING}"/* >/dev/null 2>&1; then
        add_slurm_bind "${SLURM_HOST_BIN_REAL_STAGING}:/opt/slurm-host-bin-real"
    fi
    if ls "${SLURM_HOST_BIN_STAGING}"/* >/dev/null 2>&1; then
        add_slurm_bind "${SLURM_HOST_BIN_STAGING}:${SLURM_WRAPPER_BIN_PATH}"
        export APPTAINERENV_PREPEND_PATH="${SLURM_WRAPPER_BIN_PATH}"
        # Explicitly set PATH to keep wrapper precedence even if startup scripts reset PATH.
        export APPTAINERENV_PATH="${SLURM_WRAPPER_BIN_PATH}:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    fi
    for slurm_cmd in "${SLURM_HOST_CMDS[@]}"; do
        cmd_path=$(resolve_slurm_cmd_path "${slurm_cmd}")
        if [ -n "${cmd_path}" ] && [ -x "${cmd_path}" ] && [ -x "${SLURM_HOST_BIN_STAGING}/${slurm_cmd}" ]; then
            # Force replacement of container slurm client command paths so PATH changes cannot bypass wrappers.
            add_slurm_bind "${SLURM_HOST_BIN_STAGING}/${slurm_cmd}:${cmd_path}"
        fi
    done
    if ls "${SLURM_HOST_LIB_STAGING}"/*.so* >/dev/null 2>&1; then
        add_slurm_bind "${SLURM_HOST_LIB_STAGING}:${SLURM_WRAPPER_LIB_PATH}"
        SLURM_LD_LIBRARY_PATH="${SLURM_WRAPPER_LIB_PATH} (wrapper scoped)"
    fi

    # Ensure legacy cached sh_quota wrappers do not survive cache reuse.
    rm -f "${SLURM_HOST_BIN_REAL_STAGING}/sh_quota" 2>/dev/null || true

    # Install a clean sh_quota shim into wrapper PATH that explicitly unsets
    # LD_LIBRARY_PATH before executing the host helper.
    HOST_SH_QUOTA_PATH=$(resolve_host_cmd_path sh_quota)
    if [ -n "${HOST_SH_QUOTA_PATH}" ] && [ -x "${HOST_SH_QUOTA_PATH}" ]; then
        cat > "${SLURM_HOST_BIN_STAGING}/sh_quota" <<__NEURODESK_SH_QUOTA_WRAPPER__
#!/bin/bash
unset LD_LIBRARY_PATH
HOST_SH_QUOTA_PATH="${HOST_SH_QUOTA_PATH}"
HOST_HOME_PATH="${HOME}"
lfs_cmd=/opt/slurm-host-bin/lfs
if [ ! -x "\${lfs_cmd}" ]; then
    lfs_cmd=/bin/lfs
fi
srun_cmd=/opt/slurm-host-bin/srun
if [ ! -x "\${srun_cmd}" ]; then
    srun_cmd=/usr/bin/srun
fi

run_host_quota_via_srun() {
    local out status
    [ -n "\${SLURM_JOB_ID:-}" ] || return 1
    [ -x "\${srun_cmd}" ] || return 1
    out=\$(HOME="\${HOST_HOME_PATH}" SLURM_MPI_TYPE=none "\${srun_cmd}" \
        --jobid "\${SLURM_JOB_ID}" \
        --overlap \
        --nodes=1 \
        --ntasks=1 \
        --mpi=none \
        --export=ALL,HOME="\${HOST_HOME_PATH}" \
        --quiet \
        --chdir "\${PWD}" \
        "\${HOST_SH_QUOTA_PATH}" "\$@" 2>&1)
    status=\$?
    if [ "\${status}" -eq 0 ]; then
        printf '%s\n' "\${out}"
        return 0
    fi
    return "\${status}"
}

print_filtered_host_quota() {
    local out status
    out=\$(HOME="\${HOST_HOME_PATH}" "\${HOST_SH_QUOTA_PATH}" "\$@" 2>&1)
    status=\$?
    printf '%s\n' "\${out}" | awk '
        \$0 == "error: unsupported filesystem lustre" { next }
        \$0 == "error: unsupported filesystem nfs4" { next }
        \$0 == "lustre" { next }
        \$0 == "nfs4" { next }
        { print }
    '
    return "\${status}"
}

print_lustre_fallback() {
    local label="\$1"
    local path="\$2"
    local out
    [ -n "\${path}" ] || return 1
    [ -x "\${lfs_cmd}" ] || return 1
    out=\$("\${lfs_cmd}" quota -u "\${USER}" "\${path}" 2>&1) || return 1
    printf '%s\n' "+---------------------------------------------------------------------------+"
    printf '| %-73s |\n' "\${label} quota fallback via lfs (\${path})"
    printf '%s\n' "+---------------------------------------------------------------------------+"
    printf '%s\n' "\${out}"
    return 0
}

if run_host_quota_via_srun "\$@"; then
    exit 0
fi

if [ "\$1" = "-f" ] && [ -n "\$2" ]; then
    fs_name=\$(printf '%s' "\$2" | tr '[:lower:]' '[:upper:]')
    case "\${fs_name}" in
        SCRATCH)
            if print_lustre_fallback SCRATCH "\${SCRATCH:-/scratch/users/\${USER}}"; then
                exit 0
            fi
            ;;
        GROUP_SCRATCH)
            if print_lustre_fallback GROUP_SCRATCH "\${GROUP_SCRATCH:-}"; then
                exit 0
            fi
            ;;
    esac
    print_filtered_host_quota "\$@"
    exit \$?
fi

if [ "\$#" -gt 0 ]; then
    print_filtered_host_quota "\$@"
    exit \$?
fi

host_output=\$(print_filtered_host_quota)
host_status=\$?
printf '%s\n' "\${host_output}"

fallback_printed=0
if ! printf '%s\n' "\${host_output}" | grep -Eq '^[[:space:]]*SCRATCH[[:space:]]*\\|'; then
    if print_lustre_fallback SCRATCH "\${SCRATCH:-/scratch/users/\${USER}}"; then
        fallback_printed=1
    fi
fi
if ! printf '%s\n' "\${host_output}" | grep -Eq '^[[:space:]]*GROUP_SCRATCH[[:space:]]*\\|'; then
    if print_lustre_fallback GROUP_SCRATCH "\${GROUP_SCRATCH:-}"; then
        fallback_printed=1
    fi
fi

if [ "\${fallback_printed}" -eq 1 ]; then
    exit 0
fi
exit "\${host_status}"
__NEURODESK_SH_QUOTA_WRAPPER__
        chmod +x "${SLURM_HOST_BIN_STAGING}/sh_quota" 2>/dev/null || true
        add_slurm_bind "${HOST_SH_QUOTA_PATH}:${HOST_SH_QUOTA_PATH}"
        # Keep sh_quota available even if PATH inside the container is reset.
        add_slurm_bind "${SLURM_HOST_BIN_STAGING}/sh_quota:/usr/local/bin/sh_quota"
    else
        rm -f "${SLURM_HOST_BIN_STAGING}/sh_quota" 2>/dev/null || true
        echo "WARNING: host sh_quota command not found in current/login PATH."
    fi
    if [ -x "${SLURM_HOST_BIN_STAGING}/quota" ]; then
        # sh_quota may call quota via different absolute paths on Sherlock.
        for quota_path in /usr/bin/quota /usr/sbin/quota /bin/quota /sbin/quota; do
            if [ -x "${quota_path}" ]; then
                add_slurm_bind "${SLURM_HOST_BIN_STAGING}/quota:${quota_path}"
            fi
        done
    fi
    if [ -x "${SLURM_HOST_BIN_STAGING}/lfs" ]; then
        # sh_quota can call /bin/lfs or /usr/bin/lfs on Sherlock.
        add_slurm_bind "${SLURM_HOST_BIN_STAGING}/lfs:/bin/lfs"
        add_slurm_bind "${SLURM_HOST_BIN_STAGING}/lfs:/usr/bin/lfs"
    else
        HOST_LFS_PATH=$(resolve_host_cmd_path lfs)
        if [ -n "${HOST_LFS_PATH}" ] && [ -x "${HOST_LFS_PATH}" ]; then
            echo "WARNING: using unwrapped host lfs at ${HOST_LFS_PATH}; Lustre libs may be missing in container."
            add_slurm_bind "${HOST_LFS_PATH}:/bin/lfs"
            add_slurm_bind "${HOST_LFS_PATH}:/usr/bin/lfs"
        else
            echo "WARNING: host lfs command not found; sh_quota may not report Lustre quotas."
        fi
    fi
fi
if [ -e /run/slurm ]; then
    add_slurm_bind /run/slurm:/run/slurm
fi
if [ -e /run/slurmctld ]; then
    add_slurm_bind /run/slurmctld:/run/slurmctld
fi
if [ -e /run/slurmdbd ]; then
    add_slurm_bind /run/slurmdbd:/run/slurmdbd
fi

CLUSTER_NAME=""
if [ -r "${HOST_SLURM_CONF_REAL}" ]; then
    CLUSTER_NAME=$(awk -F= '/^[[:space:]]*ClusterName[[:space:]]*=/{print $2}' "${HOST_SLURM_CONF_REAL}" | tail -n 1 | tr -d '[:space:]')
fi
if [ -n "${CLUSTER_NAME}" ] && [ -e "/run/slurm-${CLUSTER_NAME}" ]; then
    add_slurm_bind "/run/slurm-${CLUSTER_NAME}:/run/slurm-${CLUSTER_NAME}"
fi

SACK_SOCKET_CANDIDATE="${SLURM_SACK_SOCKET:-}"
if [ -z "${SACK_SOCKET_CANDIDATE}" ]; then
    if [ -n "${CLUSTER_NAME}" ] && [ -S "/run/slurm-${CLUSTER_NAME}/sack.socket" ]; then
        SACK_SOCKET_CANDIDATE="/run/slurm-${CLUSTER_NAME}/sack.socket"
    elif [ -S /run/slurm/sack.socket ]; then
        SACK_SOCKET_CANDIDATE=/run/slurm/sack.socket
    elif [ -S /run/slurmctld/sack.socket ]; then
        SACK_SOCKET_CANDIDATE=/run/slurmctld/sack.socket
    elif [ -S /run/slurmdbd/sack.socket ]; then
        SACK_SOCKET_CANDIDATE=/run/slurmdbd/sack.socket
    else
        SACK_SOCKET_CANDIDATE=$(find /run -maxdepth 4 -type s -name 'sack.socket' 2>/dev/null | head -n 1)
    fi
fi
if [ -n "${SACK_SOCKET_CANDIDATE}" ] && [ -S "${SACK_SOCKET_CANDIDATE}" ]; then
    SACK_SOCKET_DIR=$(dirname "${SACK_SOCKET_CANDIDATE}")
    if [ -d "${SACK_SOCKET_DIR}" ]; then
        add_slurm_bind "${SACK_SOCKET_DIR}:${SACK_SOCKET_DIR}"
    fi
fi
if [ -e /run/munge ]; then
    add_slurm_bind /run/munge:/run/munge
fi
if [ -e /var/run/munge ]; then
    add_slurm_bind /var/run/munge:/var/run/munge
fi

MUNGE_SOCKET_CANDIDATE="${MUNGE_SOCKET:-}"
if [ -z "${MUNGE_SOCKET_CANDIDATE}" ]; then
    for sock in \
        /run/munge/munge.socket.2 \
        /var/run/munge/munge.socket.2 \
        /run/munge/munge.socket \
        /var/run/munge/munge.socket \
        /var/spool/slurmd/munge.socket.2 \
        /var/spool/slurm/munge.socket.2
    do
        if [ -S "${sock}" ]; then
            MUNGE_SOCKET_CANDIDATE="${sock}"
            break
        fi
    done
fi
if [ -n "${MUNGE_SOCKET_CANDIDATE}" ] && [ -S "${MUNGE_SOCKET_CANDIDATE}" ]; then
    MUNGE_SOCKET_DIR=$(dirname "${MUNGE_SOCKET_CANDIDATE}")
    if [ -d "${MUNGE_SOCKET_DIR}" ]; then
        add_slurm_bind "${MUNGE_SOCKET_DIR}:${MUNGE_SOCKET_DIR}"
    fi
fi

export APPTAINERENV_NEURODESKTOP_SLURM_MODE=host
export APPTAINERENV_SLURM_CONF="${CONTAINER_SLURM_CONF_PATH}"
unset APPTAINERENV_LD_LIBRARY_PATH
if [ -n "${SACK_SOCKET_CANDIDATE}" ] && [ -S "${SACK_SOCKET_CANDIDATE}" ]; then
    export APPTAINERENV_SLURM_SACK_SOCKET="${SACK_SOCKET_CANDIDATE}"
else
    unset APPTAINERENV_SLURM_SACK_SOCKET
fi

if [ -n "${MUNGE_SOCKET_CANDIDATE}" ] && [ -S "${MUNGE_SOCKET_CANDIDATE}" ]; then
    export APPTAINERENV_MUNGE_SOCKET="${MUNGE_SOCKET_CANDIDATE}"
else
    unset APPTAINERENV_MUNGE_SOCKET
fi

echo "Host Slurm integration: mode=${APPTAINERENV_NEURODESKTOP_SLURM_MODE:-unset} conf=${APPTAINERENV_SLURM_CONF:-unset} (from ${HOST_SLURM_CONF}) sack=${APPTAINERENV_SLURM_SACK_SOCKET:-unset} munge=${APPTAINERENV_MUNGE_SOCKET:-unset}"
echo "Host Slurm plugin dirs: ${SLURM_PLUGIN_DIRS_RAW:-unset}"
echo "Host Slurm bin dir: ${APPTAINERENV_PREPEND_PATH:-unset}"
echo "Host Slurm PATH: ${APPTAINERENV_PATH:-unset}"
echo "Host Slurm loader dirs: ${SLURM_LD_LIBRARY_PATH:-unset}"
echo "Host Slurm wrapper count: $(ls "$SLURM_HOST_BIN_STAGING" 2>/dev/null | wc -l | tr -d ' ')"
if [ -e "${HOST_SLURM_CONF_REAL}" ]; then
    ls -l "${HOST_SLURM_CONF_REAL}"
else
    echo "WARNING: host slurm.conf not found at ${HOST_SLURM_CONF_REAL}"
fi

echo "Starting Neurodesktop container..."
NEURODESKTOP_NOTEBOOK_PORT="${NEURODESKTOP_NOTEBOOK_PORT:-8888}"
NEURODESKTOP_DISPLAY_URL="${NEURODESKTOP_DISPLAY_URL:-http://127.0.0.1:8888}"
NEURODESKTOP_DISABLE_JPSERVER_EXTENSIONS="${NEURODESKTOP_DISABLE_JPSERVER_EXTENSIONS:-{'jupyter_server_fileid': False, 'jupyter_server_ydoc': False}}"
NEURODESKTOP_SHELL_PROMPT="${NEURODESKTOP_SHELL_PROMPT:-neurodesk@sherlock:\\w\\$ }"

port_in_use_on_host() {
    local port="$1"

    if [ -z "${port}" ]; then
        return 1
    fi

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t >/dev/null 2>&1
        return $?
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -ltn "( sport = :${port} )" 2>/dev/null | awk 'NR>1 {found=1} END {exit(found ? 0 : 1)}'
        return $?
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -an 2>/dev/null | grep -Eq "[\\.:]${port}[[:space:]].*LISTEN"
        return $?
    fi

    return 1
}

if port_in_use_on_host "${NEURODESKTOP_NOTEBOOK_PORT}"; then
    echo "ERROR: notebook port ${NEURODESKTOP_NOTEBOOK_PORT} is already in use on $(hostname)."
    echo "Please rerun connectSherlock.sh to pick a different tunnel port."
    exit 1
fi

NEURODESKTOP_UID=$(id -u)
NEURODESKTOP_GID=$(id -g)
NEURODESKTOP_ENABLE_GPU="${NEURODESKTOP_ENABLE_GPU:-0}"
APPTAINER_GPU_ARGS=()
if [ "${NEURODESKTOP_ENABLE_GPU}" = "1" ]; then
    APPTAINER_GPU_ARGS+=(--nv)
    if [ -d /dev/dri ]; then
        APPTAINER_GPU_ARGS+=(--bind /dev/dri:/dev/dri)
    fi
    export APPTAINERENV_NVIDIA_DRIVER_CAPABILITIES=all
    if [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
        export APPTAINERENV_CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}"
    fi
    if [ -n "${NVIDIA_VISIBLE_DEVICES:-}" ]; then
        export APPTAINERENV_NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES}"
    elif [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
        export APPTAINERENV_NVIDIA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}"
    fi
    echo "GPU passthrough enabled for container (--nv)."
else
    unset APPTAINERENV_CUDA_VISIBLE_DEVICES
    unset APPTAINERENV_NVIDIA_VISIBLE_DEVICES
    echo "GPU passthrough disabled for container."
fi

REQUIRED_APPTAINER_BINDPATH="/scratch,/tmp,/oak"
APPTAINER_BINDPATH_OK=1
if [ -z "${APPTAINER_BINDPATH:-}" ]; then
    APPTAINER_BINDPATH_OK=0
else
    for required_bind in /scratch /tmp /oak; do
        case ",${APPTAINER_BINDPATH}," in
            *",${required_bind},"*|*",${required_bind}:"*|*",${required_bind}/,"*|*",${required_bind}/:"*)
                ;;
            *)
                APPTAINER_BINDPATH_OK=0
                break
                ;;
        esac
    done
fi
if [ "${APPTAINER_BINDPATH_OK}" -eq 1 ]; then
    echo "APPTAINER_BINDPATH includes required paths: ${APPTAINER_BINDPATH}"
else
    export APPTAINER_BINDPATH="${REQUIRED_APPTAINER_BINDPATH}"
    echo "Set APPTAINER_BINDPATH=${APPTAINER_BINDPATH}"
fi

NEURODESKTOP_SHARED_CONTAINER_STORE="${GROUP_HOME}/neurodesk/local/containers"
mkdir -p "${NEURODESKTOP_SHARED_CONTAINER_STORE}"
CONTAINER_STORE_BIND_SPEC="${NEURODESKTOP_SHARED_CONTAINER_STORE}:${NEURODESKTOP_SHARED_CONTAINER_STORE}"
CONTAINER_STORE_NEURODESKTOP_BIND_SPEC="${NEURODESKTOP_SHARED_CONTAINER_STORE}:/neurodesktop-storage/containers"
echo "Shared container store mapping: ${CONTAINER_STORE_BIND_SPEC}"
echo "Neurodesktop container store mapping: ${CONTAINER_STORE_NEURODESKTOP_BIND_SPEC}"

unset APPTAINERENV_HOME
echo "Jupyter trash is disabled on Sherlock scratch mounts; deletes are permanent."
apptainer run \
   "${APPTAINER_GPU_ARGS[@]}" \
   --writable-tmpfs \
   --bind "${CONTAINER_STORE_BIND_SPEC}" \
   --bind "${CONTAINER_STORE_NEURODESKTOP_BIND_SPEC}" \
   "${SLURM_BINDS[@]}" \
   --home "${NEURODESKTOP_HOME_DIR}:${NEURODESKTOP_CONTAINER_HOME}" \
   --pwd "${NEURODESKTOP_CONTAINER_WORKDIR}" \
   --env CVMFS_DISABLE=true \
   --env TINI_SUBREAPER=1 \
   --env NB_UID="${NEURODESKTOP_UID}" \
   --env NB_GID="${NEURODESKTOP_GID}" \
   --env PS1="${NEURODESKTOP_SHELL_PROMPT}" \
   --env NEURODESKTOP_LOCAL_CONTAINERS="${GROUP_HOME}/neurodesk/local/containers" \
   --env NEURODESKTOP_VERSION=latest \
   $GROUP_HOME/neurodesk/neurodesktop_latest.sif \
   start-notebook.py \
      --ServerApp.port="${NEURODESKTOP_NOTEBOOK_PORT}" \
      --ServerApp.port_retries=0 \
      --ServerApp.custom_display_url="${NEURODESKTOP_DISPLAY_URL}" \
      --FileContentsManager.delete_to_trash=False \
      --ServerApp.jpserver_extensions="${NEURODESKTOP_DISABLE_JPSERVER_EXTENSIONS}"
EOF

    # --- 4. LAUNCH ALLOCATION ---
    local GPU_FLAG=""
    local ENABLE_GPU_CONTAINER=0
    if [[ -n "$GPU" && ! "$GPU" =~ ^([nN][oO][nN][eE]|0)$ ]]; then
        GPU_FLAG="--gres=gpu:$GPU"
        ENABLE_GPU_CONTAINER=1
    fi
    
    ssh -S "$CTRL_SOCKET" -o ExitOnForwardFailure=yes -t -L ${TUNNEL_PORT}:localhost:${TUNNEL_PORT} "$LOGIN_NODE" \
        "salloc --job-name=$JOB_NAME -p $PARTITION --nodes=1 --time=$WALLTIME --ntasks=1 --cpus-per-task=$CPUS --mem=$MEM $GPU_FLAG \
        bash -c 'echo \"Allocated: \${SLURM_NODELIST}\"; \
                 ssh -o ExitOnForwardFailure=yes -t -L ${TUNNEL_PORT}:localhost:${TUNNEL_PORT} \${SLURM_NODELIST} \"SLURM_CONF=\${SLURM_CONF:-} SLURM_SACK_SOCKET=\${SLURM_SACK_SOCKET:-} MUNGE_SOCKET=\${MUNGE_SOCKET:-} NEURODESKTOP_ENABLE_GPU=${ENABLE_GPU_CONTAINER} NEURODESKTOP_NOTEBOOK_PORT=${TUNNEL_PORT} NEURODESKTOP_DISPLAY_URL=http://127.0.0.1:${TUNNEL_PORT} ~/.neurodesk_setup.sh\"'"
}

# Check if the script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    connectSherlock "$@"
fi
