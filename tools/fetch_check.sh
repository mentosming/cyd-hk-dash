#!/bin/sh
# Sanity-check the three data.gov.hk endpoints CYD-DASH depends on.
set -e
for url in \
  "https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml" \
  "https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv" \
  "https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv"; do
  printf '%s\n' "$url"
  curl -sI "$url" | grep -iE "^(HTTP|last-modified|content-length|etag)" | sed 's/^/  /'
done
