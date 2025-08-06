#!/bin/bash

# The tag is passed as the first argument to the script
TAG=$1

# Exit the script if no tag is provided
if [ -z "$TAG" ]; then
  echo "Error: No tag provided."
  exit 1
fi

# Validate the tag format
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: The provided tag ($TAG) is not a valid semantic version (e.g., v1.2.3)."
  exit 1
fi

# Use sed to update the VERSION variable in memo.sh
sed -i "s|^VERSION=.*$|VERSION=$TAG|" memo.sh

echo "Successfully updated VERSION in memo.sh to $TAG."
