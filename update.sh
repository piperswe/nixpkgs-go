#!/usr/bin/env bash

set -euxo pipefail

curl -o go.json "https://go.dev/dl/?mode=json&include=all"
