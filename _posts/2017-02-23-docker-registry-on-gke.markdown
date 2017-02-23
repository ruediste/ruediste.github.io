---
layout: post
title:  "Deploying a Private Docker Registry on the Google Container Engine"
date:   2017-02-23 21:51:54 +0100
categories: cloud
---

I had access control issues with the private docker registry provided by the google cloud, so I decided to roll my own on kubernetes. The deployment of the registry itself is straight forward:

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: registry
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
      - name: master
        image: registry:2
        ports:
        - containerPort: 5000
        volumeMounts:
        - mountPath: /var/lib/registry
          name: registry-data
      volumes:
      - name: registry-data
        gcePersistentDisk:
          pdName: registry-data
          fsType: ext4
```

This makes the registry available from within the pods of the cluster. But the docker daemons of the cluster nodes have to be able to access the registry. Using a daemon set allows to deploy one pod on every node of the cluster (one pod per node). The pod we are deploying opens a host port and forwards to the single instance of the registry:

```
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: registry-proxy
  namespace: ci
spec:
  template:
    metadata:
      labels:
        app: registry-proxy
    spec:
      containers:
      - name: registry-proxy
        image: demandbase/docker-tcp-proxy
        env:
        - name: BACKEND_HOST
          value: registry
        - name: BACKEND_PORT
          value: "5000"
        ports:
        - name: registry
          containerPort: 5000
          hostPort: 5000
```

Now the registry is accessible from `127.0.0.1:5000` on every node. Thus you can do

    docker tag YOUR_IMAGE 127.0.0.1:500/YOUR_IMAGE
    docker push 127.0.0.1:500/YOUR_IMAGE

and so on. Important: `localhost:5000` does not work! Trust me, I tried...
