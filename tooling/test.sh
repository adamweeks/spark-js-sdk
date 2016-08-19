#!/bin/bash

set -e

cd "${SDK_ROOT_DIR}"

# Kill background tasks if the script exits early
# single quotes are intentional
# see http://stackoverflow.com/questions/360201/how-do-i-kill-background-processes-jobs-when-my-shell-script-exits
# and https://wiki.jenkins-ci.org/display/JENKINS/Aborting+a+build
trap 'JOBS=$(jobs -p); if [ -n "${JOBS}" ]; then kill "${JOBS}"; fi' SIGINT SIGTERM EXIT

#
# REMOVE REMNANT SAUCE FILES FROM PREVIOUS BUILD
#

rm -rf .sauce/*/sc.pid
rm -rf .sauce/*/sc.tid
rm -rf .sauce/*/sc.ready
rm -rf .sauce/*/sauce_connect.log

#
# BUILD BUILDER
#

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

#
# MAKE SECRETS AVAILABLE TO AUX CONTAINERS
#

# Remove secrets on exit
trap "rm -f .env" EXIT

cat <<EOF >.env
COMMON_IDENTITY_CLIENT_SECRET=${CISCOSPARK_CLIENT_SECRET}
CISCOSPARK_CLIENT_SECRET=${CISCOSPARK_CLIENT_SECRET}
SAUCE_USERNAME=${SAUCE_USERNAME}
SAUCE_ACCESS_KEY=${SAUCE_ACCESS_KEY}
EOF

#
# BUILD AND TEST
#

echo "################################################################################"
echo "# INSTALLING LEGACY DEPENDENCIES"
echo "################################################################################"
docker run ${DOCKER_RUN_OPTS} npm install

echo "################################################################################"
echo "# CLEANING"
echo "################################################################################"
docker run ${DOCKER_RUN_OPTS} npm run grunt -- clean
docker run ${DOCKER_RUN_OPTS} npm run grunt:concurrent -- clean

rm -rf ${SDK_ROOT_DIR}/reports
mkdir -p ${SDK_ROOT_DIR}/reports/logs

echo "################################################################################"
echo "# BOOTSTRAPPING MODULES"
echo "################################################################################"
docker run ${DOCKER_RUN_OPTS} npm run bootstrap

echo "################################################################################"
echo "# BUILDING MODULES"
echo "################################################################################"
docker run ${DOCKER_RUN_OPTS} npm run build

PIDS=""

echo "################################################################################"
echo "# RUNNING LEGACY NODE TESTS"
echo "################################################################################"
docker run ${DOCKER_RUN_OPTS} bash -c "npm run test:legacy:node > ${SDK_ROOT_DIR}/reports/logs/legacy.node.log 2>&1" &
PIDS+=" $!"

echo "################################################################################"
echo "# RUNNING LEGACY BROWSER TESTS"
echo "################################################################################"
docker run -e PACKAGE=${legacy} ${DOCKER_RUN_OPTS} bash -c "npm run test:legacy:browser > ${SDK_ROOT_DIR}/reports/logs/legacy.browser.log 2>&1" &
PIDS+=" $!"

echo "################################################################################"
echo "# RUNNING MODULE TESTS"
echo "################################################################################"

CONCURRENCY=4
# Ideally, the following would be done with lerna but there seem to be some bugs
# in --scope and --ignore
for i in ${SDK_ROOT_DIR}/packages/*; do
  if ! echo $i | grep -qc -v test-helper ; then
    continue
  fi

  if ! echo $i | grep -qc -v bin- ; then
    continue
  fi

  if ! echo $i | grep -qc -v xunit-with-logs ; then
    continue
  fi

  echo "################################################################################"
  echo "# Docker Stats"
  echo "################################################################################"
  docker stats --no-stream

  echo "Keeping concurrent job count below ${CONCURRENCY}"
  while [ $(jobs -p | wc -l) -gt ${CONCURRENCY} ]; do
    echo "."
    sleep 5
  done

  PACKAGE=$(echo $i | sed -e 's/.*packages\///g')
  echo "################################################################################"
  echo "# RUNNING ${PACKAGE} TESTS"
  echo "################################################################################"
  # Note: using & instead of -d so that wait works
  # Note: the Dockerfile's default CMD will run package tests automatically
  docker run -e PACKAGE=${PACKAGE} ${DOCKER_RUN_OPTS} &
  PIDS+=" $!"
done

FINAL_EXIT_CODE=0
for P in $PIDS; do
  echo "################################################################################"
  echo "# Docker Stats"
  echo "################################################################################"
  docker stats --no-stream

  echo "################################################################################"
  echo "# Waiting for $(jobs -p | wc -l) jobs to complete"
  echo "################################################################################"

  set +e
  wait $P
  EXIT_CODE=$?
  set -e

  if [ "${EXIT_CODE}" -ne "0" ]; then
    FINAL_EXIT_CODE=1
  fi
  # TODO cleanup sauce files for package
done

if [ "${FINAL_EXIT_CODE}" -ne "0" ]; then
  echo "################################################################################"
  echo "# One or more test suites failed to execute"
  echo "################################################################################"
  exit ${FINAL_EXIT_CODE}
fi
