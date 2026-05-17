#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = r'''
---
module: mattermost
short_description: Manage Mattermost resources and actions
description:
    - This module allows you to create users, teams, channels, and post messages in Mattermost.
    - It can also manage system configuration and verify security settings.
    - Supports authentication and stores session tokens for efficient API usage.
options:
    url:
        description:
            - URL of the Mattermost instance (e.g. "http://localhost:8065")
        required: true
        type: str
    username:
        description:
            - Username or email for authentication
        required: false
        type: str
    password:
        description:
            - Password for authentication
        required: false
        type: str
    token:
        description:
            - Authentication token (if already authenticated)
        required: false
        type: str
    action:
        description:
            - Action to perform
        required: true
        choices: ['create_user', 'create_team', 'create_channel', 'post_message', 'verify_security', 'get_config']
        type: str
    team_name:
        description:
            - Name of the team (required for channel operations)
        required: false
        type: str
    channel_name:
        description:
            - Name of the channel (required for posting messages)
        required: false
        type: str
    message:
        description:
            - Message content (required for posting messages)
        required: false
        type: str
    user:
        description:
            - Dictionary containing user details for user creation
        required: false
        type: dict
requirements:
    - requests
author:
    - Your Name (@yourgithub)
'''

EXAMPLES = r'''
# Create a user
- name: Create a test user
  mattermost:
    url: "http://localhost:8065"
    username: "admin@example.com"
    password: "admin_password"
    action: create_user
    user:
      email: "test@example.com"
      username: "testuser"
      password: "userpassword123"
      first_name: "Test"
      last_name: "User"

# Post a message
- name: Post a notification
  mattermost:
    url: "http://localhost:8065"
    token: "{{ saved_token }}"
    action: post_message
    team_name: "main"
    channel_name: "town-square"
    message: "Hello from Ansible!"

# Verify security settings
- name: Verify security configuration
  mattermost:
    url: "http://localhost:8065"
    username: "admin@example.com"
    password: "admin_password"
    action: verify_security
  register: security_result
'''

RETURN = r'''
user:
    description: Details of created user
    returned: When action is create_user
    type: dict
    sample: {
        "id": "abc123",
        "username": "testuser",
        "email": "test@example.com"
    }
team:
    description: Details of created or accessed team
    returned: When action is create_team
    type: dict
channel:
    description: Details of created or accessed channel
    returned: When action is create_channel
    type: dict
message:
    description: Details of posted message
    returned: When action is post_message
    type: dict
    sample: {
        "id": "xyz789",
        "message": "Hello from Ansible!",
        "create_at": 1613487600000
    }
token:
    description: Authentication token for reuse
    returned: When authentication is successful
    type: str
security:
    description: Security verification results
    returned: When action is verify_security
    type: dict
    sample: {
        "user_creation_disabled": true,
        "open_server_disabled": true,
        "tests_passed": true,
        "recommendations": ["Enable MFA", "Set shorter session timeout"]
    }
'''

import json
import traceback

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False


class MattermostModule:
    def __init__(self, module):
        self.module = module
        self.url = module.params['url'].rstrip('/')
        self.username = module.params.get('username')
        self.password = module.params.get('password')
        self.token = module.params.get('token')
        self.action = module.params['action']
        self.team_name = module.params.get('team_name')
        self.channel_name = module.params.get('channel_name')
        self.message = module.params.get('message')
        self.user = module.params.get('user', {})
        
        self.headers = {
            'Content-Type': 'application/json',
        }
        
        # Add token to headers if provided
        if self.token:
            self.headers['Authorization'] = f'Bearer {self.token}'
        
    def authenticate(self):
        """Authenticate with Mattermost and get token"""
        if not self.username or not self.password:
            self.module.fail_json(msg="Username and password are required for authentication")
            
        auth_url = f"{self.url}/api/v4/users/login"
        data = {
            'login_id': self.username,
            'password': self.password
        }
        
        try:
            response = requests.post(auth_url, json=data)
            if response.status_code in [200, 201]:
                # Get token from headers
                self.token = response.headers.get('Token') or response.headers.get('token')
                if not self.token:
                    self.module.fail_json(msg="Authentication succeeded but no token was returned")
                    
                self.headers['Authorization'] = f'Bearer {self.token}'
                return True
            else:
                self.module.fail_json(msg=f"Authentication failed: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Authentication error: {str(e)}", exception=traceback.format_exc())
    
    def create_user(self):
        """Create a new user"""
        required_fields = ['email', 'username', 'password']
        for field in required_fields:
            if field not in self.user:
                self.module.fail_json(msg=f"Missing required field for user creation: {field}")
        
        user_url = f"{self.url}/api/v4/users"
        try:
            response = requests.post(user_url, headers=self.headers, json=self.user)
            if response.status_code in [200, 201]:
                return {
                    'changed': True,
                    'user': response.json(),
                    'token': self.token
                }
            elif response.status_code == 400 and 'already exists' in response.text:
                return {
                    'changed': False,
                    'msg': f"User {self.user['username']} already exists",
                    'token': self.token
                }
            else:
                self.module.fail_json(msg=f"User creation failed: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"User creation error: {str(e)}", exception=traceback.format_exc())
    
    def get_team_id(self):
        """Get team ID from team name"""
        if not self.team_name:
            self.module.fail_json(msg="Team name is required")
            
        team_url = f"{self.url}/api/v4/teams/name/{self.team_name}"
        try:
            response = requests.get(team_url, headers=self.headers)
            if response.status_code == 200:
                return response.json()['id']
            else:
                self.module.fail_json(msg=f"Failed to get team: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Team retrieval error: {str(e)}", exception=traceback.format_exc())
    
    def get_channel_id(self, team_id):
        """Get channel ID from channel name and team ID"""
        if not self.channel_name:
            self.module.fail_json(msg="Channel name is required")
            
        channel_url = f"{self.url}/api/v4/teams/{team_id}/channels/name/{self.channel_name}"
        try:
            response = requests.get(channel_url, headers=self.headers)
            if response.status_code == 200:
                return response.json()['id']
            else:
                self.module.fail_json(msg=f"Failed to get channel: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Channel retrieval error: {str(e)}", exception=traceback.format_exc())
    
    def post_message(self):
        """Post a message to a channel"""
        if not self.message:
            self.module.fail_json(msg="Message content is required")
            
        team_id = self.get_team_id()
        channel_id = self.get_channel_id(team_id)
        
        post_url = f"{self.url}/api/v4/posts"
        data = {
            'channel_id': channel_id,
            'message': self.message
        }
        
        try:
            response = requests.post(post_url, headers=self.headers, json=data)
            if response.status_code in [200, 201]:
                return {
                    'changed': True,
                    'message': response.json(),
                    'token': self.token
                }
            else:
                self.module.fail_json(msg=f"Message posting failed: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Message posting error: {str(e)}", exception=traceback.format_exc())
    
    def verify_security(self):
        """Verify security settings"""
        config_url = f"{self.url}/api/v4/config"
        try:
            response = requests.get(config_url, headers=self.headers)
            if response.status_code == 200:
                config = response.json()
                
                # Check critical security settings
                user_creation_disabled = not config['TeamSettings']['EnableUserCreation']
                open_server_disabled = not config['TeamSettings']['EnableOpenServer']
                
                security_results = {
                    'user_creation_disabled': user_creation_disabled,
                    'open_server_disabled': open_server_disabled,
                    'tests_passed': user_creation_disabled and open_server_disabled,
                    'session_length_days': config['ServiceSettings'].get('SessionLengthInDays', 'unknown'),
                    'timeout_minutes': config['ServiceSettings'].get('SessionTimeoutInMinutes', 'unknown'),
                    'recommendations': []
                }
                
                # Add recommendations based on settings
                if not user_creation_disabled:
                    security_results['recommendations'].append("Disable user creation")
                if not open_server_disabled:
                    security_results['recommendations'].append("Disable open server")
                if not config.get('ServiceSettings', {}).get('EnableMultifactorAuthentication', False):
                    security_results['recommendations'].append("Enable multi-factor authentication")
                
                return {
                    'changed': False,
                    'security': security_results,
                    'token': self.token
                }
            else:
                self.module.fail_json(msg=f"Security verification failed: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Security verification error: {str(e)}", exception=traceback.format_exc())
    
    def get_config(self):
        """Get Mattermost configuration"""
        config_url = f"{self.url}/api/v4/config"
        try:
            response = requests.get(config_url, headers=self.headers)
            if response.status_code == 200:
                return {
                    'changed': False,
                    'config': response.json(),
                    'token': self.token
                }
            else:
                self.module.fail_json(msg=f"Config retrieval failed: {response.status_code} - {response.text}")
        except Exception as e:
            self.module.fail_json(msg=f"Config retrieval error: {str(e)}", exception=traceback.format_exc())
    
    def execute(self):
        """Execute the requested action"""
        # Authenticate if token not provided
        if not self.token and self.action != 'get_version':
            self.authenticate()
            
        if self.action == 'create_user':
            return self.create_user()
        elif self.action == 'post_message':
            return self.post_message()
        elif self.action == 'verify_security':
            return self.verify_security()
        elif self.action == 'get_config':
            return self.get_config()
        else:
            self.module.fail_json(msg=f"Unsupported action: {self.action}")


def main():
    module_args = dict(
        url=dict(type='str', required=True),
        username=dict(type='str', required=False),
        password=dict(type='str', required=False, no_log=True),
        token=dict(type='str', required=False, no_log=True),
        action=dict(type='str', required=True, choices=['create_user', 'create_team', 'create_channel', 'post_message', 'verify_security', 'get_config']),
        team_name=dict(type='str', required=False),
        channel_name=dict(type='str', required=False),
        message=dict(type='str', required=False),
        user=dict(type='dict', required=False)
    )
    
    module = AnsibleModule(
        argument_spec=module_args,
        required_if=[
            ('action', 'post_message', ['team_name', 'channel_name', 'message']),
            ('action', 'create_user', ['user'])
        ],
        required_one_of=[
            ['username', 'token']
        ],
        required_together=[
            ['username', 'password']
        ]
    )
    
    if not HAS_REQUESTS:
        module.fail_json(msg="The 'requests' module is required for this module")
    
    mattermost = MattermostModule(module)
    result = mattermost.execute()
    
    module.exit_json(**result)


from ansible.module_utils.basic import AnsibleModule

if __name__ == '__main__':
    main()