#!/bin/bash

set -o errexit
set -o pipefail
set -vx

: ${GIT_REPO:=https://github.com/DigitalCommons/open-data/}
: ${GIT_BRANCH:=userland-deploy} # may need to be overriddeb

DEPLOY_DIR=$HOME/working # scripts assume this working dir
rm -rf $DEPLOY_DIR

mkdir -p $DEPLOY_DIR
# GitHub doesn't support git-archive so we use the init-and-remote-add method
(
  cd $DEPLOY_DIR
  git init
  git remote add origin $GIT_REPO
  git pull --depth=1 origin $GIT_BRANCH
  ./tools/deploy/post-pull.rb
)
