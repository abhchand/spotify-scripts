#!/bin/bash

# Uses Spotify API to read in a list of tracks and organize them by year
#
# E.g.
#
# INPUT:
#   https://open.spotify.com/track/5kxddRG1RZaZROadk7iC4D
#   https://open.spotify.com/track/72Bz4ciRZPBcVSw0nrZDHi
#   https://open.spotify.com/track/3iVcZ5G6tvkXZkZKlMpIUs
#
# OUTPUT:
#
#   > songs-2007.txt
#   https://open.spotify.com/track/5kxddRG1RZaZROadk7iC4D
#
#   > songs-2015.txt
#   https://open.spotify.com/track/72Bz4ciRZPBcVSw0nrZDHi
#   https://open.spotify.com/track/3iVcZ5G6tvkXZkZKlMpIUs
#
# Uses the Client Credentials flow outlined here:
# https://developer.spotify.com/documentation/general/guides/authorization-guide/#client-credentials-flow
#
# Requires a client_id and client_secret, which are obtained by registering
# a new application:
# https://developer.spotify.com/documentation/general/guides/app-settings/#register-your-app
#

# Usage / Help
read -r -d '' usage << EOF
\n
Usage: $0 filename\n
\n
filename\tfile containing list of spotify tracks in format https://open.spotify.com/track/:id
EOF

if [[ "$1" == "--help" || "$1" == "-h" ]]
then
  echo -e $usage
  exit 1
fi

if [ -z "$1" ]
then
  echo "Please specify a filename"
  echo -e $usage
  exit 1
fi

# Test that values are set

if [ -z `which base64` ]
then
  echo "Utility \`base64\` does not exist"
  exit 1
fi

if [ -z "$SPOTIFY_CLIENT_ID" ]
then
  echo "Please set \$SPOTIFY_CLIENT_ID"
  exit 1
fi

if [ -z "$SPOTIFY_CLIENT_SECRET" ]
then
  echo "Please set \$SPOTIFY_CLIENT_SECRET"
  exit 1
fi

#
# Query for Auth Token
#

# NOTE: `echo` adds a newline! Remove it with `-n`
encoded_credentials=$(echo -n "$SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_SECRET" | base64)

echo "Querying for new auth token"
auth_json=$(curl \
  --silent \
  -X "POST" \
  -H "Authorization: Basic $encoded_credentials" \
  -d grant_type=client_credentials \
  https://accounts.spotify.com/api/token
)

# TODO: This is a terrible way to parse JSON -_-
access_token=$(echo "$auth_json" | sed -En 's/.*access_token\":\"([^\"]+)\".*/\1/p')
expires_at=$((`date +%s` + $(echo "$auth_json" | sed -En 's/.*expires_in\":([0-9]+),.*/\1/p')))

#
# Get data for track
#

input_file=$1
rm songs-*

echo "Reading from $input_file"

while read track; do
  id=$(echo "$track" | sed -En 's/https:\/\/open.spotify.com\/track\/(.*)$/\1/p')

  song_data=$(curl \
    --silent \
    -H "Authorization: Bearer $access_token" \
    https://api.spotify.com/v1/tracks/$id
  )

  release_date=$(echo "$song_data" | sed -En 's/.*release_date\" ?: ?\"([^\"]+)\".*/\1/p')
  year=$(echo $release_date | sed -En 's/^([0-9]{4})\-.*/\1/p')
  filename="songs-$year.txt"

  echo "$track -> $year"

  echo $track >> $filename
done < $input_file
