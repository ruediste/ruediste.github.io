---
layout: post
title:  "Quickly Publishing Maven artifacts"
date:   2017-02-22 06:33:54 +0100
categories: maven
---

Compared to npm or bower, publishing Maven artifacts to maven central is a very complicated process. The first time you want to publish something you have to reserve a group id which takes a day or two. Then you have to make sure your project follows all the rules (javadoc, sources, pgp signature ...) and you have to configure your build correctly.

So I felt it's time for a simpler public repository and built [Mvnzone](https://www.mvnzone.net).

Usage is simpe: First sign up with your github account. Then you can claim your group ids and manage access tokens. To publish something, simply add the following to your `pom.xml`:

    <distributionManagement>
      <repository>
        <id>mvnzone</id>
        <url>https://repo.mvnzone.net/repo</url>
      </repository>
      <snapshotRepository>
        <id>mvnzone</id>
        <url>https://repo.mvnzone.net/repo</url>
      </snapshotRepository>
    </distributionManagement>

and the following to your `~/.m2/settings.xml`:

    <?xml version="1.0" encoding="UTF-8"?>
    <settings>
      <servers>
        <server>
          <id>mvnzone</id>
          <username>mvn</username>
          <password>YOUR TOKEN</password>
        </server>
        ...
      </servers>
      ...
    </settings>

That's it! A simple `mvn clean deploy` publishes your artifacts.

In order to use the published artifacts, consumers have to add the following to their `pom.xml`:

    <repositories>
      <repository>
        <id>mvnzone</id>
        <url>https://repo.mvnzone.net/repo</url>
      </repository>
    </repositories>

Happy sharing !!!
