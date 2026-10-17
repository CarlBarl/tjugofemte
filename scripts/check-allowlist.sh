#!/bin/sh
# Fails if anything outside EnableBankingKit looks like it could talk to the network or leave the device.
# Regression guard, not proof: App Privacy Report and a device-wide proxy are the real checks (see README).
cd "$(dirname "$0")/.."
pattern='URLSession|URLRequest|import Network|import WebKit|contentsOf:|AsyncImage|NSUserActivity|kSecAttrSynchronizable|https?://'
allow='enablebanking.com/cp|github.com/|github.io/|example.com'
hits=$(grep -rnE "$pattern" Tjugofemte/Sources Packages/BudgetCore/Sources Packages/LocalStore/Sources Tjugofemte/Resources 2>/dev/null | grep -vE "$allow" | grep -v '^\s*//' || true)
if [ -n "$hits" ]; then
  echo "Network allowlist check failed:"
  echo "$hits"
  exit 1
fi
echo "Network allowlist check passed: only EnableBankingKit touches the network."
