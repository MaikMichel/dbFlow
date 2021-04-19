#!/bin/bash
# echo "Your script args ($#) are: $@"


SOURCE_BRANCH=$1 # schema_aufteilung
INSTANCE_BRANCH=$2 #instance/test
NEW_VERSION=$3 # 0.0.3

echo "SOURCE_BRANCH: ${SOURCE_BRANCH}"
echo "INSTANCE_BRANCH: ${INSTANCE_BRANCH}"
echo "NEW_VERSION: ${NEW_VERSION}"
echo " let's do this ..."


# refresh source branche
git checkout ${SOURCE_BRANCH}
git pull

# switch to target
git checkout ${INSTANCE_BRANCH}
git pull

# now merge
git merge ${SOURCE_BRANCH} -m "merge from branch ${SOURCE_BRANCH} to branch ${INSTANCE_BRANCH}"

# build the patch
./build.sh patch ORIG_HEAD ${NEW_VERSION}

# apply then patch
./apply.sh patch ${NEW_VERSION}
