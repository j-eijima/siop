#!/bin/sh
# Regenerates the Swift-issued token fixture. Requires a Swift toolchain.
# The fixture lets the RP test suite verify a genuine, Swift-signed token
# without needing Swift installed.
set -eu
cd "$(dirname "$0")"

QUERY='response_type=id_token&client_id=http%3A%2F%2Flocalhost%3A8080%2Fcallback.html&scope=openid&nonce=n-0S6_WzA2Mj&state=st1'
swift run --package-path ../../../ios/SIOPKit siop-issue "openid://?${QUERY}" > swift-issued.json
echo "wrote $(pwd)/swift-issued.json"
