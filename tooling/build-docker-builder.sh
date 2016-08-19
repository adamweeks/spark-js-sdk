#!/bin/bash

cd "${SDK_ROOT_DIR}"

docker ps
docker ps -a

export WORKDIR="${SDK_ROOT_DIR}"

# Pass environment variables to container at runtime
DOCKER_RUN_ENV=""
if [ -n "${CONVERSATION_SERVICE}" ]; then
  DOCKER_RUN_ENV+=" -e CONVERSATION_SERVICE=${CONVERSATION_SERVICE} "
fi
if [ -n "${DEVICE_REGISTRATION_URL}" ]; then
  DOCKER_RUN_ENV+=" -e DEVICE_REGISTRATION_URL=${DEVICE_REGISTRATION_URL} "
fi
if [ -n "${ATLAS_SERVICE_URL}" ]; then
  DOCKER_RUN_ENV+=" -e ATLAS_SERVICE_URL=${ATLAS_SERVICE_URL} "
fi
if [ -n "${HYDRA_SERVICE_URL}" ]; then
  DOCKER_RUN_ENV+=" -e HYDRA_SERVICE_URL=${HYDRA_SERVICE_URL} "
fi
if [ -n "${WDM_SERVICE_URL}" ]; then
  DOCKER_RUN_ENV+=" -e WDM_SERVICE_URL=${WDM_SERVICE_URL} "
fi
if [ -n "${ENABLE_NETWORK_LOGGING}" ]; then
  DOCKER_RUN_ENV+=" -e ENABLE_NETWORK_LOGGING=${ENABLE_NETWORK_LOGGING} "
fi
if [ -n "${ENABLE_VERBOSE_NETWORK_LOGGING}" ]; then
  DOCKER_RUN_ENV+=" -e ENABLE_VERBOSE_NETWORK_LOGGING=${ENABLE_VERBOSE_NETWORK_LOGGING} "
fi
if [ -n "${BUILD_NUMBER}" ]; then
  DOCKER_RUN_ENV+=" -e BUILD_NUMBER=${BUILD_NUMBER} "
fi
if [ -n "${PIPELINE}" ]; then
  DOCKER_RUN_ENV+=" -e PIPELINE=${PIPELINE} "
fi

export DOCKER_CONTAINER_NAME="${JOB_NAME}-${BUILD_NUMBER}-builder"

# Push runtime config data into the container definition and build it
cat <<EOT >>./docker/builder/Dockerfile
RUN groupadd -g $(id -g) jenkins
RUN useradd -u $(id -u) -g $(id -g) -m jenkins
WORKDIR ${WORKDIR}
USER $(id -u)
EOT

# Reset the Dockerfile to make sure we don't accidentally commit it later
git checkout ./docker/builder/Dockerfile

export DOCKER_RUN_OPTS="${DOCKER_RUN_ENV}"
# Cleanup the container when done
export DOCKER_RUN_OPTS="${DOCKER_RUN_OPTS} --rm"
# Make sure the npm cache stays inside the workspace
export DOCKER_RUN_OPTS="${DOCKER_RUN_OPTS} -e NPM_CONFIG_CACHE=${WORKDIR}/.npm"
# Mount the workspace from the Jenkins slave volume
export DOCKER_RUN_OPTS="${DOCKER_RUN_OPTS} --volumes-from ${HOSTNAME}"
# Run commands as Jenkins user
export DOCKER_RUN_OPTS="${DOCKER_RUN_OPTS} --user=$(id -u):$(id -g)"
# Use the computed container name
export DOCKER_RUN_OPTS="${DOCKER_RUN_OPTS} ${DOCKER_CONTAINER_NAME}"


trap "docker rmi ${DOCKER_CONTAINER_NAME}" EXIT
set +e
docker build -t ${DOCKER_CONTAINER_NAME} ./docker/builder
EXIT_CODE=$?
if [ "${EXIT_CODE}" -ne "0" ]; then
  echo "Docker build failed, making attempt 2"
  docker build -t ${DOCKER_CONTAINER_NAME} ./docker/builder
  EXIT_CODE=$?
  if [ "${EXIT_CODE}" -ne "0" ]; then
    echo "Docker build failed, making attempt 3"
    docker build -t ${DOCKER_CONTAINER_NAME} ./docker/builder
    EXIT_CODE=$?
  fi
fi
set -e
