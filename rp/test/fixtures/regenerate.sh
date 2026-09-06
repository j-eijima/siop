#!/bin/sh
# Regenerates the issued-token fixtures. Requires a Swift toolchain and a JDK.
#
# The fixtures let each implementation's verifier be exercised against tokens
# another implementation signed, without every test needing every toolchain.
set -eu
cd "$(dirname "$0")"

QUERY='response_type=id_token&client_id=http%3A%2F%2Flocalhost%3A8080%2Fcallback.html&scope=openid&nonce=n-0S6_WzA2Mj&state=st1'

swift run --package-path ../../../ios/SIOPKit siop-issue "openid://?${QUERY}" > swift-issued.json
echo "wrote $(pwd)/swift-issued.json"

# The wrapper, not whatever gradle is on PATH: the Android plugin does not
# work on every Gradle version.
(cd ../../../android && ./gradlew --quiet --console=plain :siop-issue:run \
  --args="openid://?${QUERY}") > kotlin-issued.json
echo "wrote $(pwd)/kotlin-issued.json"

cp swift-issued.json ../../../android/siopkit/src/test/resources/swift-issued.json
echo "copied swift-issued.json into the Kotlin test resources"
