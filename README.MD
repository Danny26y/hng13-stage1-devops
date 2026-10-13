# HNG Stage 1 — Automated Deployment with Bash, Docker and Nginx

## Overview

This project contains a Bash script designed to automate the deployment of a Dockerized application to a remote Linux server over SSH.

The script brings together several common DevOps tasks: repository cloning, remote server preparation, application file transfer, container deployment, Nginx reverse-proxy configuration, and basic deployment validation.

The goal of the project is to reduce repetitive deployment work through scripting and to practise Linux administration, networking, containerization, and deployment automation.

**Project status:** Learning project. The script has not been verified as production-ready. Test it in a disposable environment before using it on a real server.

## Repository Contents

- `deploy.sh` — Bash script for automating the intended deployment workflow.
- `README.MD` — Project documentation, setup requirements, limitations, and testing checklist.

## Key Features

The script is designed to support the following workflow:

- Collect deployment configuration through prompts or command-line options.
- Validate required inputs and the SSH private-key path.
- Clone an application repository and select a branch.
- Detect a `Dockerfile` or Docker Compose configuration.
- Connect to a remote Linux server over SSH.
- Prepare the server with Docker, Docker Compose, and Nginx where supported.
- Transfer application files using `rsync`.
- Build or start the application using Docker.
- Configure Nginx as a reverse proxy.
- Perform basic deployment checks and record log output.
- Provide a cleanup option for deployment resources.

These are intended capabilities. The checklist below should be used to establish which paths have actually been tested.

## Technologies

- **Bash** — Deployment automation and shell scripting.
- **Linux** — Remote server administration.
- **SSH** — Remote access.
- **Git** — Source-code retrieval.
- **Docker** — Application containerization.
- **Docker Compose** — Multi-container application orchestration.
- **Nginx** — Reverse proxy and HTTP traffic routing.
- **rsync** — File transfer to the remote server.
- **Cloud VM networking** — Server reachability and firewall configuration.

## Architecture

The intended deployment flow is:

1. The operator supplies application and server configuration.
2. The script validates the required inputs.
3. The application repository is retrieved.
4. The script connects to the remote server over SSH.
5. Required server software is prepared.
6. Application files are transferred to the server.
7. Docker builds or starts the application.
8. Nginx forwards incoming HTTP requests to the application.
9. Basic checks are performed and diagnostic logs are recorded.

## Prerequisites

### Local environment

The machine running the script needs:

- Bash, such as through Linux or WSL.
- Git.
- An SSH client.
- `rsync`.
- Network access to the remote server.
- An SSH key with appropriate access to that server.

### Remote server

The target server needs:

- A Linux distribution supported by the relevant script paths.
- SSH access.
- Sufficient privileges to install software and configure services.
- Network access to retrieve required packages and application dependencies.
- A cloud firewall or security-group configuration that permits the intended traffic.

For a public HTTP deployment, port 80 must be reachable. Do not expose application or administration ports publicly unless there is a specific need.

### Application repository

The application repository should contain either:

- A `Dockerfile`, or
- A Docker Compose configuration.

The application port and container configuration must agree with the deployment settings.

## Running the Script

Review the script before executing it. Use a disposable test environment rather than a production server.

From a Bash terminal in the repository directory:

```bash
chmod +x deploy.sh
./deploy.sh --help
```

The help command should be used to inspect the available options before starting a deployment.

If the options and environment are understood, the script can be started with:

```bash
./deploy.sh
```

The script prompts for missing configuration values. Follow its actual prompts and options rather than assuming that a particular deployment configuration is supported.

## Security Considerations

This project is intended for learning and should not be treated as production-ready.

### SSH host verification

The current script disables strict SSH host-key checking. This weakens protection against connecting to an impersonated server.

**Recommended improvement:** Enable host-key verification and verify the remote server's host key before connecting.

### Personal access tokens

The script accepts a personal access token and can embed it in an authenticated repository URL. Credentials in command arguments or URLs can be exposed through process information, logs, or other diagnostic output.

**Recommended improvement:** Prefer a secure authentication method, such as a properly configured SSH deploy key or an approved credential helper. Never commit tokens or private keys to the repository.

If a real token has been exposed, revoke it and create a replacement.

### Administrative permissions

Automated installation and service configuration may require elevated privileges. Review every privileged command and restrict the deployment account to the permissions it actually needs.

### Cleanup behaviour

The cleanup option should be tested carefully to ensure that it removes only resources belonging to this deployment.

## Validation and Testing Checklist

Use this checklist during testing. Mark an item complete only after observing the result.

- [ ] `bash -n deploy.sh` passes syntax validation.
- [ ] `./deploy.sh --help` displays the available options.
- [ ] Missing configuration produces a useful error.
- [ ] An invalid SSH-key path is handled correctly.
- [ ] SSH connects to the intended server with host-key verification enabled.
- [ ] A repository containing a `Dockerfile` is handled correctly.
- [ ] A repository containing a Docker Compose file is handled correctly.
- [ ] Docker containers or Compose services start successfully.
- [ ] Nginx configuration passes `nginx -t` before reload.
- [ ] The application responds successfully through the reverse proxy.
- [ ] Failure cases produce useful logs and a non-zero exit status where appropriate.
- [ ] Cleanup affects only the resources created for this deployment.
- [ ] Logs do not contain tokens, passwords, or private-key contents.

## Known Limitations and Improvement Areas

The following are code-review findings to investigate. They are not all confirmed runtime failures.

1. **SSH security:** Strict host-key checking is disabled and should be corrected.
2. **Credential handling:** Personal access tokens may be exposed through authenticated clone URLs or command arguments.
3. **Distribution-specific Nginx paths:** The `sites-available` and `sites-enabled` layout is typical of Debian/Ubuntu systems and may not work unchanged on Amazon Linux.
4. **Docker Compose filename handling:** The script detects both `docker-compose.yml` and `docker-compose.yaml`, but a later validation path assumes `docker-compose.yml`.
5. **Compose version:** The script uses an older Compose v1 installation path. Review compatibility and consider the currently supported Docker Compose plugin.
6. **Health checks:** A successful command or running container does not necessarily mean the application is healthy. Add an application-specific health check.
7. **Rollback:** A failed deployment should not leave the application in an unknown or unusable state. Add and test rollback behaviour.
8. **Dry-run support:** A dry-run mode would make it easier to inspect planned actions before modifying a server.
9. **Idempotency:** Repeated deployments should be tested to confirm that they do not create duplicate or conflicting configuration.

## Troubleshooting Notes

Record actual observations while testing the script.

| Date | Observed issue | Confirmed cause | Fix | Verification |
|---|---|---|---|---|
| YYYY-MM-DD | Describe the error | Record the confirmed cause, or leave unresolved | Describe the change | Record the command or result |

Do not present a suspected cause as a confirmed finding. Include relevant error messages without exposing secrets.

## Future Improvements

- Add a dry-run mode.
- Replace insecure SSH host-key handling.
- Improve credential management.
- Support distribution-aware Nginx configuration.
- Handle both Docker Compose filename variants consistently.
- Add application health checks.
- Implement deployment rollback.
- Test repeated deployments for idempotency.
- Add automated shell linting and tests through a CI workflow.
- Document reproducible test results for a disposable Linux server.

## Learning Outcomes

This project provides a practical setting for learning and demonstrating:

- Bash scripting and error handling.
- Linux server administration.
- SSH and remote execution.
- Git-based deployment workflows.
- Docker and Docker Compose.
- Nginx reverse-proxy configuration.
- Cloud networking and firewall basics.
- Deployment validation and troubleshooting.
- Secure handling of deployment credentials.

## Project Links

- **Repository:** https://github.com/Danny26y/hng13-stage1-devops
- **Main script:** `deploy.sh`

