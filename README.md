# Perfect - SQLite Connector

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-SQLite)

This project provides a Swift wrapper around the SQLite 3 library.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not require PerfectLib or any other components.

Ensure you have installed and activated the latest Swift 3.0 tool chain.

## Linux Build Notes

Ensure that you have installed sqlite3.

```
sudo apt-get install sqlite3
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-SQLite.git", majorVersion: 0, minor: 2)
```
