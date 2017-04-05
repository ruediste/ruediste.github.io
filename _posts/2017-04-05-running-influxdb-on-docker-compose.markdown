---
layout: post
title:  "Running InfluxDB on Docker Compose"
date:   2017-04-05 +0100
categories: cloud
---
I started playing around with InfluxDB. It took me a few moments to dig through the website and find out about the various front end tools. In the end I decided to go with Chronograf. The following is the `docker-compose.yaml` I use on my local machine for testing:

```
version: '2'
services:
  influxdb:
    image: influxdb:1.2.2
    ports:
      - 8086:8086
      - 8083:8083
  chronograf:
    image: chronograf:0.13.0
    ports:
      - 10000:10000
    links:
      - influxdb:influxdb
    volumes:
      - ./chronograf:/var/lib/chronograf
```

As you can see, the data directory of chronograf is mapped to a host directory, to avoid accidentially loosing the visualizations.
