#!/bin/bash

# Create the ansible collections directory structure if it doesn't exist
mkdir -p ~/.ansible/collections/ansible_collections/jackaltx/

# Create the symlink
ln -s $(pwd) ~/.ansible/collections/ansible_collections/jackaltx/solti_containers

