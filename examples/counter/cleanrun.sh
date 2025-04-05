#!/bin/sh

set -e

rm -rf _build deps
mix deps.get
mix clean
mix deps.compile
mix compile
rm -rf node_modules
npm cache clean --force
npm i
mix phx.server

