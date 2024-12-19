#!/bin/bash

set -o errexit
set -o pipefail
set -vx

: ${SEOD_GIT_REPO:=https://github.com/DigitalCommons/open-data/}
: ${SEOD_GIT_BRANCH:=userland-deploy} # may need to be overriddeb

DEPLOY_DIR=$HOME/$SEOD_WORKING_DIR # scripts assume this working dir
rm -rf $DEPLOY_DIR

mkdir -p $DEPLOY_DIR
# GitHub doesn't support git-archive so we use the init-and-remote-add method
(
  cd $DEPLOY_DIR
  git init
  git remote add origin $SEOD_GIT_REPO
  git pull --depth=1 origin $SEOD_GIT_BRANCH
  ./tools/deploy/post-pull.rb
)
