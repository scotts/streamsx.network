#!/bin/bash

## Copyright (C) 2016  International Business Machines Corporation
## All Rights Reserved

################### parameters used in this script ##############################

#set -o xtrace
#set -o pipefail

here=$( cd ${0%/*} ; pwd )

STREAMS_ZKCONNECT=localhost:21810
STREAMS_DOMAIN_ID=CapabilitiesDomain
STREAMS_INSTANCE_ID=CapabilitiesInstance

domainPropertyList=(
--property jmx.port=0
--property sws.port=0
--property jmx.startTimeout=60
--property sws.startTimeout=60
)

instancePropertyList=(
--hosts $( hostname )
--property instanceTrace.defaultLevel=info
--property instanceTrace.maximumFileCount=10
--property instanceTrace.maximumFileSize=1000000
--property instance.canSetPeOSCapabilities=true
--property instance.runAsUser=$USER
--property instance.applicationBundlesPath=/tmp/Streams-$STREAMS_INSTANCE_ID\@$USER
)

################### functions used in this script #############################

die() { echo ; echo -e "\e[1;31m$*\e[0m" >&2 ; exit 1 ; }
step() { echo ; echo -e "\e[1;34m$*\e[0m" ; }

################################################################################

capabilities=$( /usr/sbin/getcap $STREAMS_INSTALL/system/impl/bin/streams-hc )
if [[ -z $capabilities ]] ; then
    step "granting Linux capabilities to Streams host controller ..."
    sudo /usr/sbin/setcap 'CAP_SETFCAP+eip CAP_FOWNER+eip' $STREAMS_INSTALL/system/impl/bin/streams-hc
    /usr/sbin/getcap $STREAMS_INSTALL/system/impl/bin/streams-hc
fi

step "using zookeeper at $STREAMS_ZKCONNECT ..."
zookeeper="--zkconnect $STREAMS_ZKCONNECT"

$STREAMS_INSTALL/system/impl/bin/streams-zk.sh status 1>/dev/null 2>/dev/null
if [[ $? != 0 ]] ; then
    step "starting zookeeper ..."
    $STREAMS_INSTALL/system/impl/bin/streams-zk.sh start || die "sorry, could not start zookeeper, $?"
fi

streamtool lsdomain $zookeeper $STREAMS_DOMAIN_ID 1>/dev/null 2>/dev/null
if [[ $? == 0 ]] ; then 
    step "Streams domain '$STREAMS_DOMAIN_ID' already created ..."
else
    step "creating Streams domain '$STREAMS_DOMAIN_ID' ..."
    ( IFS=$'\n' ; echo -e "domain properties:\n${domainPropertyList[*]}" )
    streamtool mkdomain -d $STREAMS_DOMAIN_ID ${domainPropertyList[*]} $zookeeper || die "sorry, could not make Streams domain '$STREAMS_DOMAIN_ID', $?"
    step "creating keys for Streams domain '$STREAMS_DOMAIN_ID' ..."
    streamtool genkey -d $STREAMS_DOMAIN_ID $zookeeper || die "sorry, could not generate keys for Streams domain '$STREAMS_DOMAIN_ID', $?"
    step "registering Streams domain '$STREAMS_DOMAIN_ID' as a Linux system service ..."
    sudo STREAMS_INSTALL=$STREAMS_INSTALL $STREAMS_INSTALL/bin/streamtool registerdomainhost -d $STREAMS_DOMAIN_ID --application --management $zookeeper || die "sorry, could not register Streams domain '$domain', $?"
fi

streamtool lsdomain --started $zookeeper $STREAMS_DOMAIN_ID 1>/dev/null 2>/dev/null
if [[ $? == 0 ]] ; then 
    step "Streams domain '$STREAMS_DOMAIN_ID' already started ..."
else
    step "starting Streams domain '$STREAMS_DOMAIN_ID' ..."
    streamtool startdomain -d $STREAMS_DOMAIN_ID $zookeeper || die "sorry, could not start Streams domain '$STREAMS_DOMAIN_ID', $?"
fi

streamtool lsinstance $zookeeper $STREAMS_INSTANCE_ID 1>/dev/null 2>/dev/null
if [[ $? == 0 ]] ; then 
    step "Streams instance '$STREAMS_INSTANCE_ID' already created ..."
else
    step "creating Streams instance '$STREAMS_INSTANCE_ID' ..."
    ( IFS=$'\n' ; echo -e "instance properties:\n${instancePropertyList[*]}" )
    streamtool mkinstance -i $STREAMS_INSTANCE_ID -d $STREAMS_DOMAIN_ID ${instancePropertyList[*]} $zookeeper || die "Sorry, could not create Streams instance '$STREAMS_INSTANCE_ID', $?"
fi 

streamtool lsinstance --started -embeddedzk $STREAMS_INSTANCE_ID 1>/dev/null 2>/dev/null
if [[ $? == 0 ]] ; then 
    step "Streams instance '$STREAMS_INSTANCE_ID' already started ..."
else
    step "starting Streams instance '$STREAMS_INSTANCE_ID' ..."
    streamtool startinstance -i $STREAMS_INSTANCE_ID -d $STREAMS_DOMAIN_ID $zookeeper || die "Sorry, could not start Streams instance '$STREAMS_INSTANCE_ID', $?" 
fi

step "getting service URLs for Streams domain '$STREAMS_DOMAIN_ID' ..."
streamtool getjmxconnect -d $STREAMS_DOMAIN_ID $zookeeper || die "sorry, could not domain service URL for Streams domain '$STREAMS_DOMAIN_ID', $?"
streamtool geturl -d $STREAMS_DOMAIN_ID $zookeeper || die "sorry, could not get Streams console URL for Streams domain '$STREAMS_DOMAIN_ID', $?"

exit 0

