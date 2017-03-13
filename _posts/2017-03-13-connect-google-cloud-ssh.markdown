---
layout: post
title:  "Connecting to the Google Container Engine (GKE) via SSH"
date:   2017-03-13 +0100
categories: cloud
---
I recently set up a complete environment on the Google Container Engine. One of the questions I stumbled over was how to connect to the development tools (jenkins, nexus) and the staging environments. I did not want to directly expose these services as this would have required to secure them and is error prone.

The solution I found was to use an SSH server in a docker container deployed directly into the cloud environment. That way the SSH server has the same network environment as the pods which is also nice for debugging.

On the client side I'm using an `~.ssh/config`:
```
Host cloud
    HostName dev.mvnzone.net
    User root
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    LocalForward 8002 jenkins-ui.ci:8080
    LocalForward 8003 kubernetes-dashboard.kube-system:80
    LocalForward 8004 nexus.ci:8081
    LocalForward 8005 mysql-proxy.default:3306
    LocalForward 5000 registry.ci:5000

	  LocalForward 8011 elasticsearch.dev:9200
    LocalForward 8012 kibana.dev:5601
    LocalForward 8014 application.dev:8080

    LocalForward 8021 elasticsearch.test:9200
    LocalForward 8022 kibana.test:5601
    LocalForward 8024 application.test:8080

    LocalForward 8031 elasticsearch.prod:9200
    LocalForward 8032 kibana.prod:5601
```

As you can see, I'm mapping all the various services to some port on localhost. After a `ssh cloud` the kubernetes dashboard is reachable under `http://localhost:8003/#/workload?namespace=dev`, the jenkins server under `http://localhost:8002/` and so on.

To simplify such a setup I created a public [docker image](https://hub.docker.com/r/ruediste/sshd/) for the SSH server (`ruediste/sshd`). Checkout the [github repository](https://github.com/ruediste/docker-sshd) and follow the instructions.

Client authentication is performed using authorized keys. This does not give an attacker a chance to guess a weak password. Store the key without password for maximum convenience. The keys are stored in a kubernetes secret for easy administration.

The host keys are also externalized as kubernetes secrets. This allows you to use an unique host key for your server, avoiding Man-In-The-Middle attacks.
