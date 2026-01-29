#!/usr/bin/env python3

import jwt
import time
import requests
import json

# Load the private key from the config file
with open('/home/node/clawd/.github_app_config.json', 'r') as f:
    config = json.load(f)

app_id = 351600  # From the instructions
installation_id = 38914879  # From the instructions
private_key = config['privateKey']

# Generate JWT
payload = {
    'iat': int(time.time()),
    'exp': int(time.time()) + (10 * 60),  # 10 minutes expiration
    'iss': str(app_id)
}

jwt_token = jwt.encode(payload, private_key, algorithm='RS256')
print("JWT Token:", jwt_token)

# Get installation access token
headers = {
    'Authorization': f'Bearer {jwt_token}',
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'GitHub-App-Token-Generator'
}

access_token_url = f'https://api.github.com/app/installations/{installation_id}/access_tokens'
response = requests.post(access_token_url, headers=headers)

if response.status_code == 201:
    token_data = response.json()
    access_token = token_data['token']
    print("Installation Access Token:", access_token)
    
    # Test the token by making a request to verify it works
    headers = {
        'Authorization': f'token {access_token}',
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'GitHub-App-Token-Test'
    }
    
    test_response = requests.get('https://api.github.com/installation/repositories', headers=headers)
    if test_response.status_code == 200:
        print("Token is valid and has proper permissions")
        print("Available repositories:", [repo['name'] for repo in test_response.json().get('repositories', [])])
    else:
        print("Token validation failed:", test_response.status_code, test_response.text)
        
else:
    print("Failed to get access token:", response.status_code, response.text)