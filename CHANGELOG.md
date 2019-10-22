# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

These are changes that will probably be included in the next release.

### Added
### Changed
### Removed
### Fixed
* Invoke timescaledb-tune explicitly with the PostgreSQL version we want

## [v0.2.3] - 2019-10-09
### Added
* Install [tsdbadmin](https://github.com/timescale/savannah-tsdbadmin/) scripts into postgres database

## [v0.2.2] - 2019-09-11

### Changed
* TimescaleDB 1.4.2 was released, rebuilding the Docker image to include that version

## [v0.2.1] - 2019-09-06

### Changed
* The default command for the Dockerfile is now "postgres". This ensures we have the same interface as other Docker images out there.

## [v0.2.0] - 2019-08-30

### Added
 * Allow PostgreSQL compile time customizations to be made.

  Some environments benefit from being able to change things like `NAMEDATALEN`.
 * Makefile to aid in building the Docker image
 * Gitlab CI/CD configuration to trigger automated builds
 * Entrypoint for `pgBackRest`
 * The TimescaleDB extension is added to the `template1` and `postgres` database
 * Git context is injected into the Docker image

### Changed
 * Default entrypoint is `docker_entrypoint.sh`.

  This enables the Docker image to also be used in a non-kubernetes environment, allowing
  developers to run the exact same software as production environments.

 * Default Docker repository names
 * Failure of first backup does not fail the database initialization

### Removed
 * Removed many packages to reduce Docker image size without breaking TimescaleDB

### Fixed
 * Only configure a Patroni namespace if a `POD_NAMESPACE`



## [v0.1.0] - 2019-08-30
This is the first stable release of the TimescaleDB HA Docker image.
It was built from the [TimescaleDB Operator](https://github.com/timescale/timescaledb-operator/tree/v0.1.0) before
this repository was split away from it.

### Added
 * A Docker image based on Debian buster

 The basic components of the Docker image are:
  * [TimescaleDB](https://github.com/timescale/timescaledb), all recent releases
  * [PostgreSQL](https://github.com/postgres/postgres)
  * [Patroni](https://github.com/zalando/patroni)
  * [pgBackRest](https://github.com/pgbackrest/pgbackrest)

This Docker image can be used in the same way as the (smaller) public
[TimescaleDB Docker](https://github.com/timescale/timescaledb-docker) image,
however this image has HA built in, which leverages Patroni to do
auto failover of PostgreSQL if needed.
