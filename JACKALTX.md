# Ansible Collection - jackaltx.solti_containers

This was an experiment to explore how to use an AI to create new container services quickly based on "convention".
The question was,  what kinds of conventions could it learn and keep repeating. In that endeavor there were many "Plan this.." and "Summarize this...". I tried a few Claude slash commands out. Oh, the sounds of learning that came from my
lips!!!

The container project started with a wich to collect data from the solti-monitor testing. It needed to be light weight, quick to setup for testing, and go away.  Containers fit the quick up/down better than VMs for this role.
These containers were for my testing on my development workstation.  I come from a RHEL heritage
and a CYBERSEC heritage, so Podman seemed a good choice.

I wanted to run Podman rootless. Non-privilged containers using [Quadlets](docs/Podman-Quadlet-Article.md). Quadlets allow user systemd control for non-privileges services. This works well.

It was important to me to test, so I developed a [molecule testing strategy](molecule-strategy.md).  

To simplify the testing I created scripts to manage and test the services. To make that easier we developed an
[URL standardization plan](docs/URL-Standardization-Plan.md) which standardizes a container lifecycle.

In full disclosure, I have also been testing Docker on Truenas. Which makes sense for some services. .
However, I run these on my development machine, so it is prudent to keep only what is required for the task at hand..
During the exploration I looked at [how to use SSL](docks/TLS-Architecture-Decision.md) in this environment and
how to handle containers [files](docs/Containdr-Mount-Options.md) and
[namespaces](docs/Podman-User-Namespaces.md) in a SELINUX environment.

I did experiment with PODMAN in the past life.  But allowing Claude develop the a couple of services
was useful as I adapted them to my needs.  Once we had a few of them, a
[pattern](docs/Solti-Container-Pattern.md) emerged. I used the solti-monitoring ansible code to perfom
a few disposable tests using the containers and moved on the other items.  I will be back!

Along the way though about how to expose these services to my lan using [Traefik](Traefik-Label-Consolidation-Pattern.md).
This allows me to remember names and not port numbers.  Not sure that is useful for my current case, but the
concept worked nicely for Docker on Truenas.  

When I started this project there was only chat, so the paragraph below was true...

```
It is trivial to ask an AI to "create me a script to create a Mattermost container.
Yet, I hate one-offs...between entropy and the long cycle times for testing. One
frustrating aspect of working with the AI is absence of box.  It does not see a box,
it has no real way to know if what it produces will fit into the box.  And every
time you ask....new ways will emerge.  For any given flow, it will deviate. Ask it do
duplicate the pattern and watch for the variances.  
```

Claude code helped mature this project and build the follow on docker on truenas project.

This is a decent pattern for creating small ephemeral testing
services using podman. They likely will not work in production.

## Why each Service

Let me address the why for each service.

### Why Mattermost

I want a private collector of notices that can do phone and screen with the ability
to sent out messages.  I can use gist in th wild, but some things need to be private.
Jabber and MQT apeal to me for the "notices", but it seems prudent to have a collector with
with enough details for debugging.

There are many integrations with mattermost, so I want to evaluate collecing test result/reports.
To be honest, the signal to noise on these things leave me cold.  There so many different tools
that support grouping information for technical and business reporting.

The slack model seems to persist, just as IRC still does.

### Why Hashicorp's Vault

Seems every time I need to find a better way to manage secrets, this one come up.
Seems very versatile.  I have sent these up a few times and they work ok.  This will
be my first container version.

The testing and verification of this role is a bit deeper than others. Yet, to date I still
use environment variables because they seem good enough.

### Why Redis

I want a fast Key-Value store to collect my testing reports as they run. File systems
can add too much time in my testing cycle.  

Their license changes may cause me to move on to Valkey. Meh  

### Why Elasticsearch

I have only used it once before and it was impressive as a backend.  Currently I am using
Alloy-Loki for logs. I would like to have an alternative as well as learn how to better use
no-sqls.  My gut says I should look at mongo, but their license worries me.

Over time my desire to test this has waned.

### Why Traefik

This is my first experience.  I have learned much and know so little about container
networking.  I don't like it yet, but this my a love-hate thing.  Another high-maintenance
relastionship.  It reminds of project long ago and far away. This one has layers.

However....container networking still is a fuzzy in my mind

## Why Minio

Who does not need an S3 server?  This one works, but there are version peculiarities.  I see other
containers taking over this roles.

## Where next with this project

Most of thes are useful services.  There could be use in  fuzzers (jepson) and vulnerability assessment tools (rending, trivy).
