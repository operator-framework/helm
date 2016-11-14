#!/usr/bin/env bash

# Copyright 2016 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -euo pipefail

: ${GCLOUD_SERVICE_KEY:?"GCLOUD_SERVICE_KEY environment variable is not set"}
: ${PROJECT_NAME:?"PROJECT_NAME environment variable is not set"}

VERSION=
if [[ -n "${CIRCLE_TAG:-}" ]]; then
  VERSION="${CIRCLE_TAG}"
elif [[ "${CIRCLE_BRANCH:-}" == "master" ]]; then
  VERSION="canary"
else
  exit 1
fi

echo "Updating gcloud components"
sudo /opt/google-cloud-sdk/bin/gcloud --quiet components update

echo "Configuring gcloud authentication"
echo "${GCLOUD_SERVICE_KEY}" | base64 --decode > "${HOME}/gcloud-service-key.json"
sudo /opt/google-cloud-sdk/bin/gcloud auth activate-service-account --key-file "${HOME}/gcloud-service-key.json"
sudo /opt/google-cloud-sdk/bin/gcloud config set project "${PROJECT_NAME}"
docker login -e 1234@5678.com -u _json_key -p "$(cat ${HOME}/gcloud-service-key.json)" https://gcr.io

echo "Building the tiller image"
make docker-build VERSION="${VERSION}"

echo "Pushing image to gcr.io"
if [[ "${VERSION}" != "canary" ]]; then
  docker push "gcr.io/kubernetes-helm/tiller:${VERSION}"
fi
docker push gcr.io/kubernetes-helm/tiller:canary

echo "Building helm binaries"
make build-cross
make dist checksum VERSION="${VERSION}"

echo "Pushing binaries to gs bucket"
sudo /opt/google-cloud-sdk/bin/gsutil cp ./_dist/* "gs://${PROJECT_NAME}"