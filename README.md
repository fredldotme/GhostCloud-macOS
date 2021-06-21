# GhostCloud for macOS

A beautiful and featureful sync client for your NextCloud, ownCloud & WebDav


## Description

Allows you to easily access your ownCloud, NextCloud and WebDav instances with a native Free Software application.

It is based on [GhostCloud](https://github.com/fredldotme/harbour-owncloud/), the multi-platform cloud client.


## Building from source

- Download and build [GhostCloud](https://github.com/fredldotme/harbour-owncloud/) common code as a framework, using `CONFIG+=noadditionals` as the `qmake` config.
- Reference the framework within the Xcode project
- Reference Qt (Core, Network, Sql, Xml) within the Xcode project
- Add header paths to `Headers` directories within the referenced frameworks
- Build using Xcode


## Licenses

GhostCloud for macOS is available under the LGPLv2.1 license


## Donations

You can donate to the project through:

PayPal: dev.beidl@gmail.com

Flattr: @beidl