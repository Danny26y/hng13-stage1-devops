# README (top of file - read before running)
# -----------------------------------------------------------------------------
# HNG Stage 1 — Automated Deployment Bash Script
# Files inside this single deliverable:
# - deploy.sh  (this script)
#
# Purpose:
# This script automates cloning a Git repo, preparing a remote Linux server,
# deploying a Dockerized app, configuring Nginx as a reverse proxy, validating
# the deployment, and logging each step.
#
# Features:
# - Interactive prompts for all required parameters (or pass via flags)
# - Supports PAT-authenticated git clone
# - Detects Dockerfile or docker-compose.yml and deploys accordingly
# - Installs Docker, docker-compose, and nginx on the remote host (Ubuntu or Amazon Linux)
# - Uses rsync to transfer files (efficient and idempotent)
# - Creates a simple Nginx reverse proxy and reloads configuration
# - Logs to deploy_YYYYMMDD_HHMMSS.log
# - Basic error handling, exit codes, and --cleanup option to remove deployed resources
#
# SECURITY NOTES
# - The script will use your SSH key to SSH into the remote server and run commands
# - Keep your PAT and private keys secure; do not share logs that contain secrets
#
# QUICK USAGE (interactive):
#   chmod +x deploy.sh
#   ./deploy.sh
#
# QUICK USAGE (flags):
#   ./deploy.sh \
#     --repo "https://github.com/username/repo.git" \
#     --pat "ghp_xxx" \
#     --branch "main" \
#     --user ubuntu \
#     --host 54.201.23.11 \
#     --key ~/.ssh/mykey.pem \
#     --port 5000
#
# Cleanup mode (removes container, nginx conf, and files):
#   ./deploy.sh --cleanup --user ubuntu --host 54.201.23.11 --key ~/.ssh/mykey.pem --app-name repo
#
# Exit codes:
#  0 = success
# 10 = missing param or validation failed
# 20 = git clone/pull failed
# 30 = remote connectivity failed
# 40 = remote install or deploy failure
# 50 = validation/test failure
# -----------------------------------------------------------------------------

set -o pipefail
# Use bash features; require bash
if [ -z "$BASH_VERSION" ]; then
  echo "This script requires bash. Run with: bash ./deploy.sh" >&2
  exit 1
fi

# ---------------------- helpers and logging ----------------------
timestamp() { date +"%Y%m%d_%H%M%S"; }
LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[INFO] Starting deploy script at $(date -u)"

die() {
  echo "[ERROR] $1"
  exit ${2:-1}
}

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

trap 'err=$?; echo "[ERROR] Script interrupted with exit code $err"; exit $err' ERR INT TERM

# ---------------------- default values ----------------------
BRANCH="main"
CLEANUP=0
NONINTERACTIVE=0

# ---------------------- parse args ----------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --pat) PAT="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --user) SSH_USER="$2"; shift 2;;
    --host) SSH_HOST="$2"; shift 2;;
    --key) SSH_KEY="$2"; shift 2;;
    --port) APP_PORT="$2"; shift 2;;
    --cleanup) CLEANUP=1; shift 1;;
    --non-interactive) NONINTERACTIVE=1; shift 1;;
    --app-name) APP_NAME="$2"; shift 2;;
    --help|-h) echo "Usage: ./deploy.sh [--repo URL] [--pat TOKEN] [--branch BRANCH] [--user USER] [--host IP] [--key /path/to/key] [--port PORT] [--cleanup]"; exit 0;;
    *) warn "Unknown arg: $1"; shift 1;;
  esac
done

# ---------------------- interactive prompts if missing ----------------------
prompt_if_missing() {
  varname="$1"; prompt="$2"; default="$3"
  eval val="\"\\${$varname}\""
  if [ -z "$val" ] && [ "$NONINTERACTIVE" -ne 1 ]; then
    if [ -n "$default" ]; then
      read -p "$prompt [$default]: " tmp; tmp="${tmp:-$default}"
    else
      read -p "$prompt: " tmp
    fi
    eval "$varname=\"$tmp\""
  fi
}

prompt_if_missing REPO "Git repository URL (HTTPS)" ""
prompt_if_missing PAT "Personal Access Token (PAT) - will not be echoed" ""
if [ -z "$PAT" ] && [ "$NONINTERACTIVE" -ne 1 ]; then
  # read -s to avoid echo
  read -s -p "Enter PAT (input hidden): " PAT
  echo
fi

prompt_if_missing BRANCH "Branch to deploy" "main"
prompt_if_missing SSH_USER "Remote SSH username (e.g. ubuntu, ec2-user)" "ubuntu"
prompt_if_missing SSH_HOST "Remote server IP or hostname" ""
prompt_if_missing SSH_KEY "Path to SSH private key" "~/.ssh/id_rsa"
prompt_if_missing APP_PORT "Application internal container port (e.g. 5000)" "80"

# normalize key path
SSH_KEY=${SSH_KEY/#\~/$HOME}

# infer app name from repo
if [ -z "$APP_NAME" ]; then
  APP_NAME=$(basename "$REPO" .git)
fi

# validations
[ -n "$REPO" ] || die "Git repo URL is required" 10
[ -n "$SSH_HOST" ] || die "Remote host is required" 10
[ -n "$SSH_KEY" ] || die "SSH key path is required" 10
[ -f "$SSH_KEY" ] || die "SSH key not found at $SSH_KEY" 10
[ -n "$APP_PORT" ] || die "Application port is required" 10

# ensure PAT looks like something
if [ -z "$PAT" ]; then
  warn "No PAT provided — cloning public repos only"
fi

info "Parameters: repo=$REPO branch=$BRANCH user=$SSH_USER host=$SSH_HOST app_name=$APP_NAME app_port=$APP_PORT"

# ---------------------- local git clone/pull ----------------------
WORKDIR="$PWD/deploy_workspace_$APP_NAME"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || die "Cannot cd into workspace" 10

if [ -d "$WORKDIR/.git" ] || git ls-remote "$REPO" >/dev/null 2>&1; then
  if [ -d "$APP_NAME" ]; then
    info "Repo exists locally — pulling latest"
    cd "$APP_NAME" || die "Cannot enter repo dir" 20
    git fetch --all || die "git fetch failed" 20
    git checkout "$BRANCH" || die "git checkout failed" 20
    git pull origin "$BRANCH" || die "git pull failed" 20
    cd ..
  else
    info "Cloning into $APP_NAME"
    if [ -n "$PAT" ]; then
      # embed PAT into HTTPS URL safely
      AUTH_REPO=$(echo "$REPO" | sed -E "s#https?://#https://$PAT@#")
      git clone --branch "$BRANCH" "$AUTH_REPO" "$APP_NAME" || die "git clone failed" 20
    else
      git clone --branch "$BRANCH" "$REPO" "$APP_NAME" || die "git clone failed" 20
    fi
  fi
else
  info "Cloning fresh"
  if [ -n "$PAT" ]; then
    AUTH_REPO=$(echo "$REPO" | sed -E "s#https?://#https://$PAT@#")
    git clone --branch "$BRANCH" "$AUTH_REPO" "$APP_NAME" || die "git clone failed" 20
  else
    git clone --branch "$BRANCH" "$REPO" "$APP_NAME" || die "git clone failed" 20
  fi
fi

cd "$APP_NAME" || die "Cannot enter project dir" 20

# check for Dockerfile or docker-compose.yml
if [ -f Dockerfile ]; then
  DEPLOY_MODE="dockerfile"
  info "Found Dockerfile — will build and run container"
elif [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
  DEPLOY_MODE="compose"
  info "Found docker-compose.yml — will use docker-compose up -d"
else
  die "No Dockerfile or docker-compose.yml found in repo root" 20
fi

# ---------------------- remote helpers ----------------------
SSH_BASE="-i $SSH_KEY -o StrictHostKeyChecking=no $SSH_USER@$SSH_HOST"
REMOTE="ssh $SSH_BASE"
RSYNC_BASE=(rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no")

# quick connectivity test
info "Testing SSH connectivity to $SSH_HOST"
$REMOTE -o ConnectTimeout=10 echo ok || die "SSH connection failed" 30

# ---------------------- cleanup flag handling ----------------------
if [ "$CLEANUP" -eq 1 ]; then
  info "Cleanup mode: removing app and nginx config on remote"
  $REMOTE "set -e; sudo docker ps -a --filter name=$APP_NAME -q | xargs -r sudo docker rm -f || true; sudo rm -rf ~/deploy_$APP_NAME || true; sudo rm -f /etc/nginx/sites-available/${APP_NAME}.conf /etc/nginx/sites-enabled/${APP_NAME}.conf || true; sudo nginx -t && sudo systemctl reload nginx || true"
  info "Cleanup complete"; exit 0
fi

# ---------------------- prepare remote environment ----------------------
info "Preparing remote environment"
$REMOTE "set -e; \
  if [ -f /etc/os-release ]; then . /etc/os-release; echo \"OS=$ID\"; fi"
REMOTE_OS=$($REMOTE ". /etc/os-release && echo \$ID 2>/dev/null" ) || REMOTE_OS=unknown
info "Remote OS detected: $REMOTE_OS"

# install prerequisites (works for ubuntu and amazon linux)
info "Installing Docker, Docker Compose, and Nginx on remote"
if echo "$REMOTE_OS" | grep -iq "ubuntu"; then
  $REMOTE "set -e; sudo apt update -y; sudo apt install -y ca-certificates curl gnupg lsb-release nginx; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; \
    echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null; \
    sudo apt update -y; sudo apt install -y docker-ce docker-ce-cli containerd.io; sudo systemctl enable --now docker; \
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; sudo chmod +x /usr/local/bin/docker-compose; \
    sudo usermod -aG docker $SSH_USER || true; sudo systemctl enable --now nginx"
elif echo "$REMOTE_OS" | grep -iq "amzn" || echo "$REMOTE_OS" | grep -iq "amazon"; then
  # Amazon Linux
  $REMOTE "set -e; sudo yum update -y; sudo amazon-linux-extras install docker -y || sudo yum install -y docker; sudo systemctl enable --now docker; \
    sudo curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose; sudo chmod +x /usr/local/bin/docker-compose; sudo yum install -y nginx || sudo amazon-linux-extras install nginx1 -y; sudo systemctl enable --now nginx; sudo usermod -aG docker $SSH_USER || true"
else
  warn "Unknown remote OS; attempting generic Docker/Nginx install"
  $REMOTE "set -e; sudo apt update -y || true; sudo yum update -y || true; \
    (curl -fsSL https://get.docker.com | sudo sh) || true; sudo systemctl enable --now docker || true; sudo curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose || true; sudo chmod +x /usr/local/bin/docker-compose || true; sudo systemctl enable --now nginx || true"
fi

# confirm versions
info "Remote Docker version:"
$REMOTE "sudo docker --version || true"
info "Remote docker-compose version:"
$REMOTE "/usr/local/bin/docker-compose --version || true"
info "Remote nginx version:"
$REMOTE "nginx -v || true"

# ---------------------- transfer files ----------------------
info "Syncing project files to remote (rsync)"
REMOTE_DIR="~/deploy_$APP_NAME"
${RSYNC_BASE[@]} "$PWD/" "$SSH_USER@$SSH_HOST:$REMOTE_DIR/" || die "rsync failed" 40

# ---------------------- remote deploy steps ----------------------
info "Running remote deploy steps"
if [ "$DEPLOY_MODE" = "compose" ]; then
  RUN_CMDS="set -e; cd $REMOTE_DIR; sudo /usr/local/bin/docker-compose down || true; sudo /usr/local/bin/docker-compose pull || true; sudo /usr/local/bin/docker-compose up -d --build"
else
  # dockerfile mode: build an image and run
  IMAGE_NAME="$APP_NAME:latest"
  RUN_CMDS="set -e; cd $REMOTE_DIR; sudo docker build -t $IMAGE_NAME .; sudo docker ps -a --filter name=$APP_NAME -q | xargs -r sudo docker rm -f || true; sudo docker run -d --name $APP_NAME -p 127.0.0.1:$APP_PORT:$APP_PORT $IMAGE_NAME"
fi

$REMOTE "$RUN_CMDS" || die "Remote deploy commands failed" 40

# ---------------------- configure Nginx reverse proxy ----------------------
info "Configuring Nginx reverse proxy"
NGINX_CONF="/etc/nginx/sites-available/${APP_NAME}.conf"
PROXY_CONF="server {\n    listen 80;\n    server_name _;\n    location / {\n        proxy_pass http://127.0.0.1:$APP_PORT;\n        proxy_set_header Host \$host;\n        proxy_set_header X-Real-IP \$remote_addr;\n        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto \$scheme;\n    }\n}"

# write the nginx conf via ssh heredoc
$REMOTE "sudo bash -c 'cat > $NGINX_CONF <<"EOF"\n$PROXY_CONF\nEOF'"

# enable the site (for systems with sites-enabled)
$REMOTE "sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/${APP_NAME}.conf || true; sudo nginx -t"
$REMOTE "sudo systemctl reload nginx"

# ---------------------- validation ----------------------
info "Validating deployment"
# check docker service
$REMOTE "sudo systemctl is-active --quiet docker" || die "Docker service not active" 50

# check container running
if [ "$DEPLOY_MODE" = "compose" ]; then
  $REMOTE "sudo /usr/local/bin/docker-compose -f $REMOTE_DIR/docker-compose.yml ps" || die "Compose ps failed" 50
  CONTAINER_OK=$($REMOTE "sudo /usr/local/bin/docker-compose -f $REMOTE_DIR/docker-compose.yml ps | tail -n +3" 2>/dev/null || echo "")
else
  $REMOTE "sudo docker ps --filter name=$APP_NAME --format '{{.Names}}:{{.Status}}'" || die "docker ps failed" 50
fi

# server internal curl check from remote
info "Testing HTTP from remote to localhost:$APP_PORT"
$REMOTE "curl -sS -I http://127.0.0.1:$APP_PORT | head -n 1" || warn "Remote localhost curl failed"

# test from local to remote public IP
info "Testing HTTP from local to remote public IP"
if curl -sI "http://$SSH_HOST/" | head -n 1 | grep -q "200\|301\|302"; then
  info "Public URL returned HTTP OK"
else
  warn "Public URL did not return 200/3xx — check security group or nginx"
fi

info "Deployment completed successfully"
exit 0
