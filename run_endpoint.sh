#!/bin/bash

set -eu

# set up the routing needed for the simulation
/setup.sh

# The following variables are available for use:
# - ROLE contains the role of this execution context, client or server
# - SERVER_PARAMS contains user-supplied command line parameters
# - CLIENT_PARAMS contains user-supplied command line parameters

case $TESTCASE in
versionnegotiation|handshake|transfer|retry|resumption|http3|multiconnect|zerortt|chacha20|keyupdate|v2)
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
	echo "starting lighttpd server"
	lighttpd -f /lighttpd.cfg

	cp /certs/cert.pem /tmp/
	cp /certs/priv.key /tmp/cert.pem.key

	export LD_LIBRARY_PATH=/usr/local/lib
	echo "haproxy version $(haproxy -v)"
	echo "starting haproxy..."

	case $TESTCASE in
		retry)
			HAP_EXTRA_ARGS="quic-force-retry" /usr/local/sbin/haproxy -d -dM -f /quic.cfg &> $LOG
		;;
		*)
			HAP_EXTRA_ARGS="" /usr/local/sbin/haproxy -d -dM -f /quic.cfg &> $LOG
		;;
	esac
fi
