# Perfect - SQLite Connector

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite)
[![Gitter](https://badges.gitter.im/PerfectlySoft/PerfectDocs.svg)](https://gitter.im/PerfectlySoft/PerfectDocs?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)


This project provides a Swift wrapper around the SQLite 3 library.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not require PerfectLib or any other components.

Ensure you have installed and activated the latest Swift 3.0 tool chain.


## Issues

We are transitioning to using JIRA for all bugs and support related issues, therefore the GitHub issues has been disabled.

If you find a mistake, bug, or any other helpful suggestion you'd like to make on the docs please head over to [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1) and raise it.

A comprehensive list of open issues can be found at [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)

## Linux Build Notes

Ensure that you have installed sqlite3.

```
sudo apt-get install sqlite3
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", versions: Version(0,0,0)..<Version(10,0,0))
```


## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
