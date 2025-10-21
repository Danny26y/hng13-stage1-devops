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
# ---------------------------------
