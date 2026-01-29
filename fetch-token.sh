#!/bin/bash

# Configuration
APP_ID="351600"
INSTALLATION_ID="38914879"
PRIVATE_KEY_FILE="/home/node/clawd/.github_app_config.json"

# Extract the private key from the JSON config
PRIVATE_KEY=$(python3 -c "import json; f=open('$PRIVATE_KEY_FILE'); print(json.load(f)['privateKey'].replace('\n', '\\n'))")

# Create JWT header and payload
HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | sed 's/\(.*\)/\1/')
PAYLOAD=$(echo -n "{\"iat\":$(date +%s),\"exp\":$(($(date +%s) + 600)),\"iss\":\"$APP_ID\"}" | base64 | tr -d '=' | tr '/+' '_-' | sed 's/\(.*\)/\1/')

# Create the signature input
SIGNATURE_INPUT="$HEADER.$PAYLOAD"

# Create temporary files
echo -n "$SIGNATURE_INPUT" > /tmp/sign_input.txt

# Sign with the private key
openssl dgst -sha256 -sign <(echo -e "$PRIVATE_KEY") /tmp/sign_input.txt | base64 | tr -d '=' | tr '/+' '_-' | sed 's/\(.*\)/\1/' > /tmp/signature.txt

# Combine to form the JWT
JWT_TOKEN="$SIGNATURE_INPUT.$(cat /tmp/signature.txt)"

echo "JWT Token: $JWT_TOKEN"

# Use curl to get the installation access token
curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens \
  -o /tmp/access_token_response.json

# Check if the request was successful
if [ $? -eq 0 ]; then
    ACCESS_TOKEN=$(python3 -c "import json; f=open('/tmp/access_token_response.json'); print(json.load(f).get('token', 'ERROR'))")
    if [ "$ACCESS_TOKEN" != "ERROR" ]; then
        echo "Installation Access Token: $ACCESS_TOKEN"
        
        # Test the token
        curl -L \
          -H "Accept: application/vnd.github+json" \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          https://api.github.com/installation/repositories \
          -o /tmp/test_token_response.json
        
        if grep -q "repositories" /tmp/test_token_response.json; then
            echo "Token is valid and has proper permissions"
        else
            echo "Token validation failed"
        fi
    else
        echo "Failed to get access token. Response:"
        cat /tmp/access_token_response.json
    fi
else
    echo "Failed to get access token"
    cat /tmp/access_token_response.json
fi

# Clean up
rm -f /tmp/sign_input.txt /tmp/signature.txt /tmp/access_token_response.json /tmp/test_token_response.json