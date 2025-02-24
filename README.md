# Ansible Collection - jackaltx.solti_containers

## Human written forward

I need to collect data from the solti-monitor testing. It needs to be light weight
and easy to setup and go away.  Containers are much better then VM for testing.

I let Claude develop the pattern then adapted it to my needs.  Once we had a few of
them, a pattern emerged. I used the solti-monitoring ansible code jump start this.

It is trivial to ask an AI to "create me a script to create a Mattermost container.
Yet, I hate one-offs...between entropy and the long cycle times for testing. One
frustrating aspect of working with the AI is absence of box.  It does not see a box,
it has no real way to know if what it produces will fit into the box.  And every
time you ask....new ways will emerge.  For any given flow, it will deviate. Ask it do
duplicate the patter and watch for the variances.  

So between us we have created a decent pattern for creating small testing
services using podman.  These are ephemaeral in nature, but I suspect they
move ok.  

Let me address the why for each serice

### Why Mattermost

I want a private collector of notices that can do phone and screen with the ability
to sent out messages.  I can use gist in th wild, but some things need to be private.

### Why Hashicorp's Vault

Seem every time I need to find a better way to manage secrets, this one come up.
Seems very versatile.  I have sent these up a few times and they work ok.  This will
be my first container version.

### Why Redis

I want a fast Key-Value store to collect my testing reports as they run. File systems
can add too much time in my testing cycle.

### Why Elasticsearch

I have only used it once before and it was impressive as a backend.  Currently I am using
Alloy-Loki for logs. I would like to have an alternative.  

## Where next with this project

So far the only one I am missing is a good fuzzer and  s3 storage candidates.

## Solti-Containers documentaiton

Claude create a draft project, include examples and at the end what documentation
standard you choose to use.
