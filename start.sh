#!/usr/bin/env bash

# This file inspired by tutorial at
# https://testdriven.io/blog/github-actions-docker/

# Requests a temporary token to register a GitHub runner.
# https://docs.github.com/en/rest/reference/actions#create-a-registration-token-for-an-organization

# For security, set these environment variables
# via Heroku configuration variables.
GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION}" # The GitHub organization to support, like 'trailhead-content-engineering'
GITHUB_ACCESS_TOKEN="${GITHUB_ACCESS_TOKEN}" # A personal access token with 'admin:org' and 'repo' scopes

# Holds short-lived registration token for attaching/detaching self-hosted runners with GitHub Actions framework.
# This variable is populated at runtime as needed because it does expire after an hour.
GITHUB_REG_TOKEN=""
GITHUB_REG_TOKEN_URL="https://api.github.com/orgs/${GITHUB_ORGANIZATION}/actions/runners/registration-token"

# -------------------------------------------------------------------

# Use access token to obtain a short-lived registration token for adding and removing runners.
# For example, when this container starts up then we need to attach this runner
# to our GitHub organization. Likewise, when this container shuts down then
# we need to remove this runner from our GitHub organization.
# Runners that are inactive for 30 days are automatically removed by GitHub.
getRegistrationToken() {
  GITHUB_REG_TOKEN=$(curl --silent -X POST -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" "${GITHUB_REG_TOKEN_URL}" | jq .token --raw-output)
}

attachRunner() {
  echo "Attaching runner..."
  getRegistrationToken
  ./config.sh \
    --unattended \
    --token "${GITHUB_REG_TOKEN}" \
    --url "https://github.com/${GITHUB_ORGANIZATION}" \
    --replace
}

detachRunner() {
  echo "Removing runner..."
  getRegistrationToken
  ./config.sh remove \
    --unattended \
    --token "${GITHUB_REG_TOKEN}"
}

# Recall that this script is running in our dockerized image on Heroku.
# Our Dockerfile created a user named 'docker' and the following directory is
# where it installed the GitHub Actions self-hosting runner package.
# We now navigate to that directory to start the runner.
cd ${HOME}/actions-runner

attachRunner

# In case of error or the dyno shutting down,
# detach this runner from the GitHub Actions framework.
#
# In bash, the way to "catch" an exception is with `trap` command.
# Syntax is `trap {command to run} {error code to handle}`
# https://sodocumentation.net/bash/topic/363/using--trap--to-react-to-signals-and-system-events
#
# `INT` refers to SIGINT status code, the process interrupted at the terminal (Ctrl+C)
# `TERM` refers to SIGTERM status code, the process was told to shutdown.
#
# POSIX systems return a status code as a number, which is 128 + N
# where N is the value of the actual error.
#
# SIGINT has a value of 2, so the exit code is 130 (128+2).
# SIGTERM has a value of 15, so the exit code is 143 (128+15).
# https://en.wikipedia.org/wiki/Signal_(IPC)#Default_action
trap 'detachRunner; exit 130' INT
trap 'detachRunner; exit 143' TERM

# Normally, bash will ignore any signals while a child process is executing.
# Starting the server with & (single ampersand) will background it into the
# shell's job control system, with `$!` holding the server's PID.
#
# Calling `wait` will then wait for the job with the specified PID (the server)
# to finish, or for any signals to be fired.
#
# For more on shell signal handling along with `wait`, review this Stack Exchange answer
# https://unix.stackexchange.com/questions/146756/forward-sigterm-to-child-in-bash/146770#146770
#
# Also note that we are invoking runsvc.sh and not run.sh because the runner
# program self-updates (no way to disable it) and according to online discussions
# the service script should handle the update and keep the processing running
# rather than shutting down and becoming a zombie runner that won't run jobs.
# https://github.com/actions/runner/issues/485
# https://github.com/actions/runner/issues/484
# https://github.com/actions/runner/issues/246
./bin/runsvc.sh &
wait $!
