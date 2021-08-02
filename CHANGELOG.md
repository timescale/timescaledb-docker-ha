# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

These are changes that will probably be included in the next release.
### Added
### Changed
### Removed
### Fixed


## [v0.4.17] - 2021-08-02
### Fixed
 * Skip building timescaledb 2.4+ for PostgreSQL 11

## [v0.4.15] - 2021-08-02
### Changed
 * Include and default to Timescale 2.4.0
### Fixed
 * Silence warnings about missing Cargo files
 * Build process

## [v0.4.14] - 2021-07-29
### Fixed
 * Fix building some extensions for non-default Postgres version

## [v0.4.13] - 2021-07-06
### Changed
 * Include downgrade scripts if available

## [v0.4.12] - 2021-07-06
### Changed
 * Include and default to Timescale 2.3.1
 * Bump `hot_forge` to 0.1.20

## [v0.4.10] - 2021-07-05
### Changed
 * Bump `hot_forge` to 0.1.18
 * Upgrade promscale extension to version 0.2.0
 * Rename Analytics to Toolkit and up to 1.0.0 (#129)

## [v0.4.9] - 2021-06-28
### Changed
 * Bump `hot_forge` to 0.1.14

## [v0.4.8] - 2021-06-28
### Changed
 * Bump `hot_forge` to 0.1.13

## [v0.4.7] - 2021-06-23
### Added
 * `hot_forge`: A private Timescale Project allowing hot patching of containers
### Changed
 * Bump `timescale_analytics` to 0.3.0
 * Make all compiled extensions owned by `postgres`: Allows hot-patching
### Removed
 * `sqlite_fdw`: The potential use case switched to using `file_fdw`

## [v0.4.6] - 2021-05-25
### Changed
 * Include and default to Timescale 2.3.0

## [v0.4.5] - 2021-05-18
### Added
 * `gdb` and `gdbserver` to aid in debugging
 * [pg\_stat\_kcache](https://github.com/powa-team/pg_stat_kcache) extension: Gathers statistics about real reads and writes done by the filesystem layer
### Changed
 * Label Docker Image with all minor PostgreSQL versions


## [v0.4.4] - 2021-05-13
### Changed
 * PostgreSQL 12.7 and 13.3 [have been released](https://www.postgresql.org/about/news/postgresql-133-127-1112-1017-and-9622-released-2210/)

## [v0.4.3] - 2021-05-05
### Changed
 * Include and default to Timescale 2.2.1

## [v0.4.2] - 2021-04-13
### Changed
 * Include and default to Timescale 2.2.0

## [v0.4.1] - 2021-04-12
### Added
 * Bump [promscale\_extension](https://github.com/timescale/promscale_extension) to 0.1.2 and build for PostgreSQL 13

## [v0.4.0] - 2021-04-09

### Added
 * PostgreSQL 13 images
 * [pg\_repack](https://github.com/reorg/pg_repack) extension: Reorganize tables in PostgreSQL databases with minimal locks
 * [hypopg](https://github.com/HypoPG/hypopg) extension: HypoPG is a PostgreSQL extension adding support for hypothetical indexes.
### Changed
 * [timescale\_analytics](https://github.com/timescale/timescale-analytics) was upgraded
### Removed
 * PostgreSQL 11 images

## [v0.3.6] - 2021-03-26

### Added
 * Allow additional extensions to be added to a running container

   If enabled, this allows one to create new extension libraries and new supporting files
   in their respective directories.
   Files that are part of the Docker Image are guarded against mutations, so only *new* files
   can be added.
### Changed
 * Include and default to Timescale 2.1.1
 * CI/CD has moved from gitlab to GitHub actions
 * Images now get pushed to `timescale/timescaledb-ha` (used to be `timescaledev/timescaledb-ha`)
 * Built images also get labeled with the available TimescaleDB versions in the image, for example:
        "com.timescaledb.image.timescaledb.available_versions": "1.7.0,1.7.1,1.7.2,1.7.3,1.7.4,1.7.5,2.0.0,2.0.0-rc3,2.0.0-rc4,2.0.1,2.0.2,2.1.0"
### Removed
 * timescale-prometheus (superseeded by (promscale)[https://github.com/timescale/promscale])
 * [pg\_prometheus](https://github.com/timescale/pg_prometheus): Was already excluded from being built for a long while

## [v0.3.4] - 2021-02-22
### Changed
 * Include Timescale 2.0.2 and 2.1.0 and default to 2.1.0

## [v0.3.3] - 2021-02-16
### Added
 * Include Extension [pg\_auth\_mon](https://github.com/RafiaSabih/pg_auth_mon)
 * Include Extension [logerrors](https://github.com/munakoiso/logerrors)
### Changed
 * TimescaleDB [1.7.5](https://github.com/timescale/timescaledb/releases/tag/1.7.5) was released

## [v0.3.2] - 2021-01-28
### Changed
 * TimescaleDB [2.0.1](https://github.com/timescale/timescaledb/releases/tag/2.0.1) was released

## [v0.3.1] - 2021-01-28
### This release failed the build and was never published

## [v0.3.0] - 2021-01-04
### Changed
 * Default to Timescale 2.0.0

## [v0.2.30] - 2020-12-21
### Changed
 * Include (but not default to) Timescale 2.0.0

## [v0.2.29] - 2020-12-13
### Changed
 * Include (but not default to) Timescale 2.0.0-rc4

## [v0.2.28] - 2020-11-13
### Changed
 * Include (but not default to) Timescale 2.0.0-rc3

## [v0.2.27] - 2020-11-13
### Changed
 * PostgreSQL 11.10 and 12.5 [have been released](https://www.postgresql.org/about/news/postgresql-131-125-1110-1015-9620-and-9524-released-2111/)

## [v0.2.26] - 2020-10-28
### Added
 * Include libraries for Timescale 2.0.0-rc2

## [v0.2.25] - 2020-09-29
### Added
 * Include [promscale](https://github.com/timescale/promscale_extension) extension
### Removed
 * Remove Rust build directories from the final image

## [v0.2.24] - 2020-09-07
### Changed
 * TimescaleDB [1.7.4](https://github.com/timescale/timescaledb/releases/tag/1.7.4) was released

## [v0.2.22] - 2020-09-07
### Added
 * Include [pgrouting](https://pgrouting.org/) in the Docker Image
### Changed
 * Timescale-Prometheus [0.1.0-beta.4](https://github.com/timescale/timescale-prometheus/releases/tag/0.1.0-beta.4) was released

## [v0.2.21] - 2020-08-28
### Added
 * Include [hll](https://github.com/citusdata/postgresql-hll) extension
### Changed
 * TimescaleDB [1.7.3](https://github.com/timescale/timescaledb/releases/tag/1.7.3) was released
 * Timescale-Prometheus [0.1.0-beta.3](https://github.com/timescale/timescale-prometheus/releases/tag/0.1.0-beta.3) was released

## [v0.2.20] - 2020-08-14
### Changed
 * PostgreSQL 11.9 and 12.4 are released

## [v0.2.19] - 2020-08-03
### Added
 * Upgrade `timescale_prometheus` to version `0.1.0-beta.1`

## [v0.2.18] - 2020-07-27

### Added
 * [`pgBouncer`](https://www.pgbouncer.org/) as part of the image

## [v0.2.17] - 2020-07-17

### Changed
 * `tsdb_admin` 0.1.1 was released

## [v0.2.16] - 2020-07-08

### Changed
 * TimescaleDB 1.7.2 was released

## [v0.2.15] - 2020-06-30

### Changed
 * Docker Image tag names, all images which are mutable are postfixed with `-latest`

## [v0.2.14] - 2020-06-24

### Fixed
 * Ensure builder is built for every new tagged release

## [v0.2.13] - 2020-06-23

### Added
 * Include `psutils` to allow some process troubleshooting inside the container
 * Include custom timescaledb scripts for pgextwlist
 * `lz4` support, which can be used by pgBackRest
 * `tsdb_admin` can be included in the image
 * `timescale_prometheus` is now included in the image
### Changed
 * GitLab CI/CD will now publish Docker images to Docker hub on version tags

## [v0.2.12] - 2020-05-19
### Changed
 * TimescaleDB 1.7.1 is released
 * PostgreSQL 11.8 and 12.3 are released

## [v0.2.11] - 2020-05-14

These are changes that will probably be included in the next release.

### Added
 * Include the [timescale-prometheus](https://github.com/timescale/timescale-prometheus) extension by default
### Changed
 * Allow restore from backup even when no master is running
 * Deprecate including the `pg_prometheus` extension, it is not built by default anymore
 * PostgreSQL minor patches are released
### Fixed
 * Backup parameters

## [v0.2.10] - 2020-04-20

### Added
 * Support PostgreSQL 12
 * Support for TimescaleDB 1.7 (PostgreSQL 11 & PostgreSQL 12)
 * Remove stale pidfile if it exists
 * Include `strace` for debugging
### Changed
 * Build 2 sets of Docker images in CI/CD (PostgreSQL 11 & PostgreSQL 12)
### Fixed
 * Fail build if a single item in a loop fails
### Removed
 * Some perl dependencies of `pgBackRest`, which are no longer needed
     as `pgBackRest` is now fully written in C


## [v0.2.9] - 2020-02-13

### Changed
 * PostgreSQL 11.7 was released
 * PostGIS is now included in all the Docker images

     This reduces the number of images that need to be built, maintained and supported

#### Build process
 * Add Labels to the Docker images, in line with the Open Container Initiative
 [Annotations Rules](https://github.com/opencontainers/image-spec/blob/master/annotations.md#rules) for their Image Format Specification.

     These labels can be used to identify exact version information of TimescaleDB, PostgreSQL and some
     other extensions, as well as the default labels for `created`, `revision` and `source`.

     This deprecates adding  the `scm-source.json` that was added to the Docker Images.
 * Improve build & release process


## [v0.2.8] - 2020-01-15

### Added
 * Create a additional Docker image including PostGIS
### Changed
 * TimescaleDB 1.6.0 was released

## [v0.2.7] - 2019-11-14

### Changed
 * PostgreSQL 11.6 was released
 * TimescaleDB 1.5.1 was released


## [v0.2.6] - 2019-11-06

### Changed
 * Reduce log output during installation of tsdbadmin scripts

## [v0.2.5] - 2019-10-31

### Added
 * Include pgextwlist to allow extension whitelisting
 * Possibility to build a Docker image for a given repository and/or tag
 * TimescaleDB 1.5.0 was released and is now included

## [v0.2.4] - 2019-10-29

### Added
 * pg_prometheus is now part of the Docker image
### Changed
 * Pass on all PostgreSQL parameters to Patroni
### Fixed
 * timescaledb-tune runs with the PG_MAJOR version

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
