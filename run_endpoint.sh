#!/bin/bash

set -eu

# set up the routing needed for the simulation
/setup.sh

# The following variables are available for use:
# - ROLE contains the role of this execution context, client or server
# - SERVER_PARAMS contains user-supplied command line parameters
# - CLIENT_PARAMS contains user-supplied command line parameters

# TODO fix the TESTCASE multiconnect
case $TESTCASE in
    versionnegotiation|handshake|transfer|retry|resumption|http3|multiconnect|zerortt|chacha20|keyupdate|ecn)
	:
	;;
    *)
	exit 127
	;;
esac

LOG=/logs/log.txt

if [ "$ROLE" == "client" ]; then
	exit 127
elif [ "$ROLE" == "server" ]; then
	echo "starting python http server"
	python3 -m http.server 10080 -d /www & sleep 1

	cp /certs/cert.pem /tmp/
	cp /certs/priv.key /tmp/cert.pem.key

	echo "starting haproxy..."
	LD_LIBRARY_PATH=/usr/local/lib /haproxy/haproxy -d -dM -f /quic.cfg > $LOG
fi
