# Use the same image that Heroku apps use.
# https://devcenter.heroku.com/articles/heroku-22-stack#heroku-22-docker-image
FROM heroku/heroku:22

# ------------------------------------------------------------------------------

# Inform utilities that we are in non-interactive mode.
ARG TERM=linux
ARG DEBIAN_FRONTEND=noninteractive

# Switch to bash shell.
#
# This resolves an error when the ENTRYPOINT script is started:
#   "OCI runtime create failed: container_linux.go:380:
#    starting container process caused: exec: "/bin/sh":
#    stat /bin/sh: no such file or directory: unknown"
#
# Note, even though Docker supports a 'SHELL' setting, Heroku doesn't support it.
# https://devcenter.heroku.com/articles/container-registry-and-runtime#unsupported-dockerfile-commands
#
# Remove /bin/sh and link to bash shell.
# https://stackoverflow.com/a/46670119/470818
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Creating Heroku Dyno-like Environment with Docker
# This makes it more consistent with how Heroku dynos run,
# which set $HOME to '/app' and run as a non-root user.
# https://github.com/heroku/stack-images/issues/56#issuecomment-323378577
# https://github.com/heroku/stack-images/issues/56#issuecomment-348246257
ARG HOME="/app"
ENV HOME ${HOME}
WORKDIR ${HOME}

# Paths where we'll install various tools.
ARG GH_DIR="${HOME}/gh"
ARG SFDX_DIR="${HOME}/sfdx"
ARG NODE_DIR="${HOME}/nodejs"
ARG ACTIONS_DIR="${HOME}/actions-runner"

# Create a non-root user. Heroku will not run as root.
# This step creates a user named 'docker' and creates its home directory.
# The user could be named anything, 'docker' just seemed fitting.
# https://ss64.com/bash/useradd.html
RUN useradd -m -d ${HOME} docker \
 && mkdir -p ${GH_DIR} \
 && mkdir -p ${SFDX_DIR} \
 && mkdir -p ${NODE_DIR} \
 && mkdir -p ${ACTIONS_DIR}

# ------------------------------------------------------------------------------
# Install build packages
#    jq - https://stedolan.github.io/jq/
#   jdk - https://packages.ubuntu.com/search?suite=default&arch=amd64&searchon=names&keywords=openjdk
# ------------------------------------------------------------------------------
RUN apt-get update --yes && apt-get upgrade --yes && apt-get install --yes --no-install-recommends \
    jq \
    openjdk-17-jdk-headless \
    openjdk-17-jre-headless

# ------------------------------------------------------------------------------
# Install Heroku CLI
# https://devcenter.heroku.com/articles/heroku-cli
# ------------------------------------------------------------------------------

RUN curl --silent --show-error --location https://cli-assets.heroku.com/install.sh | sh \
 && heroku update

# ------------------------------------------------------------------------------
# Install GitHub CLI
# https://github.com/cli/cli#installation
# ------------------------------------------------------------------------------

WORKDIR ${GH_DIR}

RUN GH_OS="linux" \
    GH_ARCH="amd64" \
 && GH_RELEASE=$(curl --silent --show-error --location "https://api.github.com/repos/cli/cli/releases/latest") \
 && GH_VERSION=$(echo -E ${GH_RELEASE} | jq -r '.tag_name' | cut -c2-) \
 && curl --silent --show-error --location "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_OS}_${GH_ARCH}.tar.gz" | tar -xz --strip-components 1 \
 && ln -s ${GH_DIR}/bin/gh /usr/local/bin

# ------------------------------------------------------------------------------
# Install Salesforce CLI
# https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm
# ------------------------------------------------------------------------------

WORKDIR ${SFDX_DIR}

RUN SFDX_CHANNEL="stable" \
    SFDX_OS="linux" \
    SFDX_ARCH="x64" \
 && SFDX_MANIFEST=$(curl --silent --show-error --location "https://developer.salesforce.com/media/salesforce-cli/sfdx/channels/${SFDX_CHANNEL}/sfdx-${SFDX_OS}-${SFDX_ARCH}-buildmanifest") \
 && SFDX_DOWNLOAD_URL=$(echo -E ${SFDX_MANIFEST} | jq -r '.xz') \
 && curl --silent --show-error --location "${SFDX_DOWNLOAD_URL}" | tar -xJ --strip-components 1 \
 && ln -s ${SFDX_DIR}/bin/sfdx /usr/local/bin

# ------------------------------------------------------------------------------
# Install Nodejs
# https://nodejs.org/en/download/
# ------------------------------------------------------------------------------

WORKDIR ${NODE_DIR}

RUN NODE_VERSION="v16.13.1" \
    NODE_OS="linux" \
    NODE_ARCH="x64" \
 && curl --silent --show-error --location "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${NODE_OS}-${NODE_ARCH}.tar.xz" | tar -xJ --strip-components 1 \
 && ln -s ${NODE_DIR}/bin/node /usr/local/bin \
 && ln -s ${NODE_DIR}/bin/npm /usr/local/bin

# ------------------------------------------------------------------------------
# Install GitHub Actions Runner
#
# The following commands come from GitHub's instructions
# at the time you choose which kind of self-hosted runner to create.
# https://github.com/organizations/{org}/settings/actions/runners/new
#
# Some of the instructions are inspired by the tutorial at
# https://testdriven.io/blog/github-actions-docker
#
# Learn more about self-hosted runners at
# https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners
# ------------------------------------------------------------------------------

# Switch to the actions directory to download and install the package.
# Note, doing a `cd` command in a `RUN` operation won't work like in a terminal,
# you must use `WORKDIR` to change your working directory.
WORKDIR ${ACTIONS_DIR}

# Download the latest GitHub Actions runner package.
# https://github.com/actions/runner/releases
RUN RUNNER_VERSION=$(curl --silent --show-error --location -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/actions/runner/releases/latest" | jq -r '.name') \
    RUNNER_VERSION=$(if [[ "v" == "${RUNNER_VERSION:0:1}" ]]; then echo "${RUNNER_VERSION:1}"; else echo "${RUNNER_VERSION}"; fi) \
    RUNNER_OS="linux" \
    RUNNER_ARCH="x64" \
 && curl --silent --show-error --location "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_OS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" | tar -xz \
    # Install some additional dependencies for the runner.
    # https://github.com/actions/runner/blob/main/docs/start/envlinux.md#install-net-core-3x-linux-dependencies
 && ./bin/installdependencies.sh

# ------------------------------------------------------------------------------
# Copy files and set permissions
# ------------------------------------------------------------------------------

# Copy over our start.sh script that's in our repository
# and store it in the docker user's home directory.
COPY start.sh ${HOME}/start.sh

# Make the script executable and
# Make our docker user owner of the files we've added to the image.
RUN chmod ug+x ${HOME}/start.sh \
 && chown -R docker:docker ${HOME}

# Clean up the apt cache to reduce image size for faster starts.
RUN apt-get autoremove --yes \
 && apt-get clean --yes \
 && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# Create User
# ------------------------------------------------------------------------------

# Since the config and run scripts for actions are not allowed to be run by root,
# switch to a different user so all subsequent commands are run as that user.
USER docker

# Inform Salesforce CLI it's running in a headless container.
# It will warn/prevent actions that can't be done, like auth:web:login.
ENV SFDX_CONTAINER_MODE=true
ENV SFDX_AUTOUPDATE_DISABLE=true

# Confirm apps are where they should be.
RUN echo -e "\nListing installed program versions:\n" \
 && which jq     && jq     --version && echo \
 && which java   && java   --version && echo \
 && which heroku && heroku --version && echo \
 && which gh     && gh     --version && echo \
 && which sfdx   && sfdx   --version && echo \
 && which node   && node   --version && echo \
 && which npm    && npm    --version && echo

# Confirm actions is where it should be.
RUN ${ACTIONS_DIR}/config.sh --version \
 && ${ACTIONS_DIR}/config.sh --commit

# Set the script to execute when the image starts.
# Note, even though Docker supports a 'SHELL' setting, Heroku doesn't support it.
# https://devcenter.heroku.com/articles/container-registry-and-runtime#unsupported-dockerfile-commands
ENTRYPOINT ["/bin/bash", "-c", "/app/start.sh"]
