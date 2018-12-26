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

CREDS_FILE="spotify.creds"

# A dead simple json parser that takes two arguments
#   1. JSON to be parsed
#   2. Key to be returned
parse_json_for_key () {
  input=$1
  key=$2

  echo $input | sed -En "s/.*$key\":\"?([^\",}]+)\"?.*/\1/p"
}

request_new_auth_token () {
  # NOTE: `echo` adds a newline! Remove it with `-n`
  encoded_credentials=$(echo -n "$SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_SECRET" | base64)

  auth_json=$(curl \
    --silent \
    -X "POST" \
    -H "Authorization: Basic $encoded_credentials" \
    -d grant_type=client_credentials \
    https://accounts.spotify.com/api/token
  )

  # Spotify returns a JSON object of the format:
  #
  #     {
  #        "access_token": "NgCXRKc...MzYjw",
  #        "token_type": "bearer",
  #        "expires_in": 3600,
  #     }
  #
  # Parse the `access_token` and `expires_in`, converting the latter to an
  # actual epoch timestamp in the process.
  access_token=$(parse_json_for_key $auth_json 'access_token')
  expires_in=$(parse_json_for_key $auth_json 'expires_in')

  expires_at=$((`date +%s` + $expires_in))

  # Store the new credentials, also in JSON
  json="{\"access_token\":\"$access_token\",\"expires_at\":$expires_at}"
  echo $json > $CREDS_FILE

  echo $json
}

read_credentials_file () {
  # Check if file even exists
  if [ ! -f "$CREDS_FILE" ]
  then
    return
  fi

  # Parse file
  json=$(cat $CREDS_FILE)

  # Check if token still valid
  expires_at=$(parse_json_for_key $json 'expires_at')
  now=$(date +%s)

  if (($expires_at < $now))
  then
    return
  fi

  # If still valid, return the JSON
  echo $json
}

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

# Ensure dependencies exist

if [ -z `which base64` ]
then
  echo "Utility \`base64\` does not exist"
  exit 1
fi

# Test that values are set

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
# Get Auth Token
#

echo "Trying to read cached credentials from $CREDS_FILE..."
json=$(read_credentials_file)

if [ -z "$json" ]
then
  echo "Querying for new auth token"
  json=$(request_new_auth_token)
else
  echo "Succesfully read cached credentials"
fi

if [ -z "$json" ]
then
  echo "Something went wrong, exiting"
  exit 1
fi

access_token=$(parse_json_for_key $json 'access_token')

if [ -z "$access_token" ]
then
  echo "Something went wrong, exiting"
  exit 1
fi

#
# Get data for each track
#

input_file=$1
rm songs-*

echo "Reading song list from $input_file"

while read track; do
  id=$(echo "$track" | sed -En 's/https:\/\/open.spotify.com\/track\/(.*)$/\1/p')

  song_data=$(curl \
    --silent \
    -H "Authorization: Bearer $access_token" \
    https://api.spotify.com/v1/tracks/$id
  )

  release_date=$(echo "$song_data" | sed -En 's/.*release_date\" ?: ?\"([^\"]+)\".*/\1/p')
  year=$(echo $release_date | sed -En 's/^([0-9]{4}).*/\1/p')
  filename="songs-$year.txt"

  echo "$release_date,$track" >> $filename

  echo -e "\t$track -> $release_date"
done < $input_file

#
# Sort each file by release date
#

echo "Sorting files by release date"
tempfile="songs.sorted"

\ls songs-* | while read file
do
  cat $file | sort -k 1,1 | cut -d',' -f2 > $tempfile
  cat $tempfile > $file
done

rm $tempfile
