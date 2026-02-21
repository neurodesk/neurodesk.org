#!/bin/bash

random_tunnel_port() {
    # macOS does not ship `shuf` by default.
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 10000-65000 -n 1
        return
    fi

    echo $((10000 + RANDOM % 55001))
}

function connectSherlock() {
    local LOGIN_NODE="sherlock"
    local JOB_NAME="neurodesktop"
    local CTRL_SOCKET="${HOME}/.ssh/sherlock_ctrl_$(date +%s)_${RANDOM}"

    # Start master connection
    # -M: master mode, -f: background, -N: no command, -S: socket path
    ssh -M -f -N -S "$CTRL_SOCKET" "$LOGIN_NODE"
    if [ $? -ne 0 ]; then
        echo "Authentication failed."
        return 1
    fi
    # Close master connection and free up port 8888 on return
    trap 'ssh -S "'"$CTRL_SOCKET"'" -O exit "'"$LOGIN_NODE"'" 2>/dev/null; \
          if lsof -Pi :8888 -sTCP:LISTEN -t >/dev/null 2>&1; then \
              echo "Cleaning up port 8888..."; \
              lsof -Pi :8888 -sTCP:LISTEN -t | xargs kill -9 2>/dev/null; \
          fi' RETURN
    
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
            echo "ℹ️  Using existing tunnel on port 8888 (maintained by your original terminal)."
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

    local MIDDLE_PORT
    MIDDLE_PORT=$(random_tunnel_port)
    if [[ ! "$MIDDLE_PORT" =~ ^[0-9]+$ ]]; then
        echo "Failed to select a valid tunnel port."
        return 1
    fi
    echo "Establishing tunnel via Login Node port: $MIDDLE_PORT"

    # --- 3. CHECK LOCAL PORT 8888 ---
    # Check if port 8888 is occupied and kill the process(es) if so
    if lsof -Pi :8888 -sTCP:LISTEN -t >/dev/null ; then
        echo "Port 8888 is already in use."
        local PIDS
        PIDS=$(lsof -Pi :8888 -sTCP:LISTEN -t)
        echo "Killing process(es) $PIDS to free up port 8888..."
        echo "$PIDS" | xargs kill -9 2>/dev/null
    fi

    echo "Preparing setup script..."
    ssh -S "$CTRL_SOCKET" "$LOGIN_NODE" "cat > ~/.neurodesk_setup.sh << 'EOF'
#!/bin/bash
cd \$SCRATCH
export PATH=\$PATH:/sbin:/usr/sbin
if [ ! -f neurodesktop-overlay.img ]; then
    echo \"Creating neurodesktop-overlay.img (2GB)...\"
    dd if=/dev/zero of=neurodesktop-overlay.img bs=1M count=2048
    mkfs.ext3 -F neurodesktop-overlay.img
    debugfs -w -R \"mkdir upper\" neurodesktop-overlay.img
    debugfs -w -R \"mkdir work\" neurodesktop-overlay.img
else
    echo \"neurodesktop-overlay.img found.\"
fi

if [ ! -d ~/neurodesktop-home ]; then
    echo \"Creating ~/neurodesktop-home...\"
    mkdir -p ~/neurodesktop-home
else
    echo \"~/neurodesktop-home found.\"
fi

if [ ! -d ~/neurodesktop-home/workdir ]; then
    echo \"Creating ~/neurodesktop-home/workdir...\"
    mkdir -p ~/neurodesktop-home/workdir
else
    echo \"~/neurodesktop-home/workdir found.\"
fi


#    --home \$HOME/neurodesktop-home:/home/jovyan \\

echo \"Starting Neurodesktop container...\"
# Using backslashes for line continuation in the remote file requires double backslash here
apptainer run \\
   --nv \\
   --fakeroot \\
   --overlay \$SCRATCH/neurodesktop-overlay.img \\
   --bind \$GROUP_HOME/neurodesk/local/containers/:/neurodesktop-storage/containers \\
   --bind \$GROUP_HOME/neurodesk/local/containers/:/neurocommand/local/containers \\
   --no-home \\
   --env CVMFS_DISABLE=true \\
   --env NB_UID=\$(id -u) \\
   --env NB_GID=\$(id -g) \\
   --env NEURODESKTOP_VERSION=latest \\
   \$GROUP_HOME/neurodesk/neurodesktop_latest.sif \\
   start-notebook.py --allow-root
EOF
chmod +x ~/.neurodesk_setup.sh"

    # --- 4. LAUNCH ALLOCATION ---
    local GPU_FLAG=""
    if [[ "$GPU" != "none" && ! -z "$GPU" ]]; then
        GPU_FLAG="--gres=gpu:$GPU"
    fi
    
    ssh -S "$CTRL_SOCKET" -t -L 8888:localhost:${MIDDLE_PORT} "$LOGIN_NODE" \
        "salloc --job-name=$JOB_NAME -p $PARTITION --nodes=1 --time=$WALLTIME --ntasks=1 --cpus-per-task=$CPUS --mem=$MEM $GPU_FLAG \
        bash -c 'echo \"Allocated: \${SLURM_NODELIST}\"; \
                 ssh -t -L ${MIDDLE_PORT}:localhost:8888 \${SLURM_NODELIST} \"~/.neurodesk_setup.sh\"'"
}

# Check if the script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    connectSherlock "$@"
fi
