#!/bin/bash
set -euo pipefail;
user_name="${1:-tthx}";
user_email="${2:-trinhthaihoa@gmail.com}";
recipes="rust-native libstd-rs-native cargo-native rust-llvm-native";
git config --global user.name "${user_name}";
git config --global user.email "${user_email}";
for i in ${recipes};
do
  devtool upgrade "${i}";
  devtool finish "${i}" meta;
done
