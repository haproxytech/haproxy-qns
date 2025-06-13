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
	# Wait for the simulator to start up.
	/wait-for-it.sh sim:57832 -s -t 30
	if [ ! -z "$REQUESTS" ]; then
		echo "requests $REQUESTS"
		SERVER_ADDR=$(echo $REQUESTS | sed -e 's_^https://\([^:]*\):443/.*$_\1_')
		CURL_REQUEST=$(echo $REQUESTS | sed -e 's_^https://[^:]*:443/\(.*\)$_http://127.0.0.1:20080/\1_')

		cp /certs/cert.pem /tmp/
		cp /certs/priv.key /tmp/cert.pem.key

		export LD_LIBRARY_PATH=/usr/local/lib
		echo "haproxy client version $(haproxy -vv)"
		echo "starting haproxy..."
		SERVER_ADDR=$SERVER_ADDR HAP_EXTRA_ARGS="" /usr/local/sbin/haproxy -d -dM -f /quic-be.cfg &> $LOG &

		sleep 2 # add some delay for haproxy startup
		cd /downloads
		echo "curl $CURL_REQUEST"
		curl -O $CURL_REQUEST
	fi

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
