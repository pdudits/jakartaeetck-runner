#!/bin/bash
# Payara Jakarta EE TCK Runner.
# Any environment customization is marked in commend with prefix (ENV) below
# Usage:
# 1. copy or link tck binary, glassfish binary and payara binary to bundles/ (see BUNDLES below)
# 2. run bundles/run_server.sh
#      This starts download server at port 8000
# 3. run ./run.sh <test_bundle>
# 4. swear appropriately to number of failing test cases
# 5. collect failure logs
# 6. adjust test properties in ./ts.override.properties


SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

# BUNDLES 
# 
# URLs to respective binaries that get downloaded thoughout the process. By default it assumes server
# running off bundles directory that serves on port 80. Any of these variables are overridable
# (ENV) BASE_URL - parent url, assuming binaries called jakartaeetck.zip, latest-glassfish.zip and payara-prerelease.zip
# (ENV) TCK_URL - full url to TCK
# (ENV) GLASSFISH_URL - full url to glassfish
# (ENV) PAYARA_URL - full url to payara
if [ -z "$BASE_URL"]; then
  BASE_URL=http://localhost:8000
fi
if [ -z "$TCK_URL"]; then
  TCK_URL=$BASE_URL/jakartaeetck.zip
fi
if [ -z "$GLASSFISH_URL" ]; then
  GLASSFISH_URL=$BASE_URL/latest-glassfish.zip
fi
if [ -z "$PAYARA_URL" ]; then
  PAYARA_URL=$BASE_URL/payara-prerelease.zip
fi

# Since this is multi-step process, there are some environment variables that help when troubleshooting
# (ENV) SKIP_TCK - skips cleaning CTS home and downloading TCK again

export CTS_HOME=$SCRIPTPATH/cts_home
export WORKSPACE=$CTS_HOME/jakartaeetck

echo "Cleaning and installing TCK"
if [ -z "$SKIP_TCK" ]; then
    # clean cts directory
    rm -rf $CTS_HOME/*
    # download and unzip TCK
    TCK_TEMP=`tempfile -s .zip`
    curl $TCK_URL -o $TCK_TEMP
    echo -n "Unzipping TCK... "
    unzip -q -d $CTS_HOME $TCK_TEMP
    rm $TCK_TEMP
    cp $WORKSPACE/bin/ts.jte $CTS_HOME/ts.jte.dist
    echo "Done"
fi

# link VI impl
rm -rf $WORKSPACE/bin/xml/impl/payara
ln -s $SCRIPTPATH/cts-impl $WORKSPACE/bin/xml/impl/payara

# patch ts.jte
echo "Patching ts.jte"

OVERRIDE_TEMP=`tempfile`
## We create a sed program, that we'll execute against ts.jte.
sed -n "s/^\([a-z.]\+\)=\(.\+\)/s#^\1=.\\\+#\1=\2#/p " ts.override.properties > $OVERRIDE_TEMP
sed -f $OVERRIDE_TEMP -i $WORKSPACE/bin/ts.jte
rm $OVERRIDE_TEMP

echo "Comparison with distributed ts.jte"
diff $WORKSPACE/bin/ts.jte $CTS_HOME/ts.jte.dist

# run mailserver container
JAMES_CONTAINER=`docker ps -f name='james-mail' -q`
if [ -z "$JAMES_CONTAINER"]; then
    echo "Starting email server Docker container"
    docker run --name james-mail --rm -d -p 1025:1025 -p 1143:1143 --entrypoint=/bin/bash jakartaee/cts-mailserver:0.1 -c /root/startup.sh
    sleep 10
    echo "Initializing container"
    docker exec -it james-mail /bin/bash -c /root/create_users.sh
fi
# run testcase

echo "Starting test!"

export PROFILE=full
export LANG="en_US.UTF-8"
export GF_BUNDLE_URL=$GLASSFISH_URL
export DATABASE=JavaDB
export GF_VI_BUNDLE_URL=$PAYARA_URL
export GF_VI_TOPLEVEL_DIR=payara5

time $WORKSPACE/docker/run_jakartaeetck.sh "$@" | tee $CTS_HOME/$1.log
# collect results