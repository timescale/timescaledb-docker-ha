# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

These are changes that will probably be included in the next release.

## [future release]

## [v1.5.16] - 2022-11-21

* Include Toolkit [1.12.1](https://github.com/timescale/timescaledb-docker-ha/pull/327)

## [v1.5.15] - 2022-11-10

* Update patroni, [add fix for creating k8s svc](https://github.com/timescale/timescaledb-docker-ha/pull/319)
* Minor PostgreSQL version upgrade (fetching latest distro packages): 14.6 and 13.9
* Include Toolkit [1.12.0](https://github.com/timescale/timescaledb-docker-ha/pull/325)

## [v1.5.14] - 2022-11-04

* Upgrade OpenSSL to 3.0.7 (fetching latest distro packages)

## [v1.5.13] - 2022-10-24

* [Upgrade OOMGuard](https://github.com/timescale/timescaledb-docker-ha/pull/320)

## [v1.5.12] - 2022-10-11

* Upgrade Promscale extension to 0.7.0

## [v1.5.11] - 2022-10-06

* Include and default to [TimescaleDB 2.8.1](https://github.com/timescale/timescaledb/releases/tag/2.8.1)

## [v1.5.10] - 2022-09-29

* Bump `hot_forge` to 0.1.39 for AWS Security Token Service

## [v1.5.9] - 2022-09-29

* Switch from docker API v1 to v2 for determining immutable tag names

## [v1.5.8] - 2022-09-28

* Upgrade TimescaleDB Toolkit extension to [1.11.0](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.11.0)
* Include timescaledb\_cloudutils v1.1.7

## [v1.5.7] - 2022-09-02

* Include [timescaledb-tune 0.14.1](https://github.com/timescale/timescaledb-tune/releases/tag/v0.14.1)

## [v1.5.6] - 2022-08-31

* Include and default to [TimescaleDB 2.8.0](https://github.com/timescale/timescaledb/releases/tag/2.8.0)

## [v1.5.5] - 2022-08-24

* Upgrade the Promscale extension to 0.6.0

## [v1.5.2] - 2022-08-24

* Include patroni-k8s-sync in non-oss images

## [v1.5.1] - 2022-08-23

* Upgrade TimescaleDB Toolkit extension to [1.10.1](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.10.1)

## [v1.5.0] - 2022-08-11

* [PostgreSQL 14.5](https://www.postgresql.org/docs/release/14.5/) was now actually released
* [PostgreSQL 13.8](https://www.postgresql.org/docs/release/13.8/) was now actually released

## [v1.4.9] - 2022-07-25

* Include and default to [TimescaleDB 2.7.2](https://github.com/timescale/timescaledb/releases/tag/2.7.2)

## [v1.4.8] - 2022-07-19

* Upgrade Promscale extension to 0.5.4
* [Use binary packages for promscale and toolkit](https://github.com/timescale/timescaledb-docker-ha/pull/277)

## [v1.4.7] - 2022-07-14

* [Update OOMGuard](https://github.com/timescale/timescaledb-docker-ha/pull/279)

## [v1.4.6] - 2022-07-07

* Include and default to [TimescaleDB 2.7.1](https://github.com/timescale/timescaledb/releases/tag/2.7.1)
* Upgrade TimescaleDB Toolkit extension to [1.8.0](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.8.0)

## [v1.4.5] - 2022-06-23

* Upgrade Promscale extension to 0.5.2

## [v1.4.4] - 2022-06-17

* [PostgreSQL 14.4](https://www.postgresql.org/docs/release/14.4/) was now actually released
    as debian packages

## [v1.4.3] - 2022-06-16

This release reintroduces all minor versions of TimescaleDB that were dropped when 1.4.0 was
released. We received multiple reports from users of this Docker Image that they rely on
older (minor) versions of TimescaleDB.

## [v1.4.2] - 2022-06-14

* [PostgreSQL 14.4](https://www.postgresql.org/docs/release/14.4/) was released

## [v1.4.1] - 2022-06-14

### Changed

* Upgrade Promscale extension to version 0.5.1
* Patroni was updated to [2.1.4](https://patroni.readthedocs.io/en/latest/releases.html#version-2-1-4)

## [v1.4.0] - 2022-06-09

This release removes a lot of minor versions of TimescaleDB. We keep the following versions for
compatibility with older Docker Images:

* 1.7.5 - This version is the final version 1.x.x version of TimescaleDB.for PostgreSQL 11 users.
    This version is only available for PostgreSQL 12.
    Having this version in the Docker Image allows this Image to be a stepping stone in a migration
    from PostgreSQL 11 and/or TimescaleDB 1.7.5, using `pg_dump` and `pg_restore` for example.
* 2.6.1 - The final point release for the previous minor release
* 2.7.0 - The latest TimescaleDB release

For those users that are currently running a TimescaleDB version that is removed from this image,
they are adviced to update their TimescaleDB extension to 2.7.0 *prior* to using the newer Docker
Image.

The latest Docker Image that allows you to run many previous minor versions to 2.7.0 is:

```shell
timescale/timescaledb-ha:pg14.3-ts2.7.0-p1
```

This release also deprecates versions of `timescaledb_toolkit`. The same advice applies for this
extension as for the `timescaledb` extension, to update the extension to 1.7.0 *prior* to using the
newer Docker Image.

### Removed

* TimescaleDB versions:
  * 2.1.0
  * 2.1.1
  * 2.2.0
  * 2.2.1
  * 2.3.0
  * 2.3.1
  * 2.4.0
  * 2.4.1
  * 2.4.2
  * 2.5.0
  * 2.5.1
  * 2.5.2
  * 2.6.0

* TimescaleDB Toolkit versions:
  * forge-stable-1.3.1
  * 1.5.1-cloud

## [v1.3.4] - 2022-06-03

* Include timescaledb\_cloudutils v1.1.6

## [v1.3.3] - 2022-05-24

### Changed

* Include and default to [TimescaleDB 2.7.0](https://github.com/timescale/timescaledb/releases/tag/2.7.0)

## [v1.3.2] - 2022-05-20

### Changed

* Ensure experimental Patroni image also supports PostgreSQL 12 and 13

## [v1.3.1] - 2022-05-20

### Changed

* Upgrade TimescaleDB Toolkit extension to [1.7.0](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.7.0)
* Upgrade Oom Guard to 1.2.0

## [v1.3.0-beta.0] - 2022-05-18

### Changed

* Patroni has been updated to support a new static primary configuration pattern which
  is optimized to ensure that a single-node Patroni cluster is able to maintain maximum
  uptime.

## [v1.2.8] - 2022-05-12

### Changed

* PostgreSQL [12.11](https://www.postgresql.org/docs/12/release-12-11.html),
    [13.7](https://www.postgresql.org/docs/13/release-13-7.html) have been released, and
    [14.3](https://www.postgresql.org/docs/14/release-14-3.html) have been released

## [v1.2.7] - 2022-05-12

### Changed

* Install timescaledb_toolkit extension by default

## [v1.2.6] - 2022-05-11

### Changed

* Upgrade promscale extension to version 0.5.0
* Upgrade Timescale Cloudutils to 1.1.5

## [v1.2.5] - 2022-04-26

### Changed

* Use Ubuntu 22.04 LTS as a base image instead of Ubuntu 21.10
* Bump `hot_forge` to 0.1.37
* Include Timescale Cloudutils 1.1.4

## [v1.2.4] - 2022-04-20

### Changed

* Include Timescale Cloudutils 1.1.3

## [v1.2.3] - 2022-04-11

### Changed

* Include and default to [TimescaleDB 2.6.1](https://github.com/timescale/timescaledb/releases/tag/2.6.1)
* Include Cloudutils v1.1.2

## [v1.2.2] - 2022-04-06

* Upgrade TimescaleDB Toolkit extension to [1.6.0](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.6.0)
* pgBackRest is upgraded to [2.38](https://pgbackrest.org/release.html#2.38)

## [v1.2.1] - 2022-03-21

### Changed

* Upgrade promscale extension to version 0.3.2

## [v1.2.0] - 2022-03-11

Minor release bump as we change Ubuntu to 21.10, which includes a higher
version of `glibc`.

### Changed

* Use Ubuntu 21.10 as a base image instead of Ubuntu 21.04
* Patroni was updated to [2.1.3](<https://patroni.readthedocs.io/en/latest/releases.html#version-2-1-3>)

## [v1.1.9] - 2022-02-23

### Changed

* ~Patroni was updated to [2.1.3]~ Due to packaging problems, Patroni was still at 2.1.2 for this release.

## [v1.1.8] - 2022-02-17

### Changed

* Include and default to [TimescaleDB 2.6.0](https://github.com/timescale/timescaledb/releases/tag/2.6.0)

## [v1.1.7] - 2022-02-17

### Changed

* Include Timescale Cloudutils 1.1.1
* Include TimescaleDB Toolkit 1.5.1
* Fix `search_path` for TimescaleDB < 2.5.2
* Use Docker Secrets during building

## [v1.1.6] - 2022-02-10

### Changed

* PostgreSQL [12.10](https://www.postgresql.org/docs/12/release-12-10.html),
    [13.6](https://www.postgresql.org/docs/13/release-13-6.html) have been released, and
    [14.2](https://www.postgresql.org/docs/14/release-14-2.html) have been released

## [v1.1.5] - 2022-02-10

### Changed

* Include and default to [TimescaleDB 2.5.2](https://github.com/timescale/timescaledb/releases/tag/2.5.2)
* Include PostgreSQL in the image labeled with PostgreSQL 14 to allow `pg_upgrade` from version 12 to version 14

## [v1.1.4] - 2022-02-08

### Changed

* Use Rust 1.58.1 to allow
    [Rust 2021 edition](https://doc.rust-lang.org/edition-guide/rust-2021/index.html)
    projects to be included
* Build fewer versions of Toolkit to improve build time
* Switch to using Docker Secrets with the
    [`--secret`](https://docs.docker.com/engine/reference/commandline/build/#options) option
    this also requires the use of
    [Docker BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/)

## [v1.1.3] - 2022-02-07

### Added

* Include [`pg_stat_monitor`](https://github.com/percona/pg_stat_monitor)

### Changed

* Include Timescale Cloudutils 1.1.0, this includes support for PostgreSQL 14
* Retain PostgreSQL 12 support in the builder/compiler images

## [v1.1.2] - 2021-12-17

### Changed

* Include Timescale Cloudutils 1.0.3
* Upgrade Oom Guard to 1.1.1
* Include Hot Forge v0.1.36

### Added

* [`pldebugger`](https://github.com/EnterpriseDB/pldebugger) is now included (from packages)

## [v1.1.1] - 2021-12-08

### Added

* Include TimescaleDB 1.7.5 to allow users of TimescaleDB 1.x to keep using this
   image in combination with PostgreSQL 12 databases.

## [v1.1.0] - 2021-12-02

This release marks the point where we no longer publish images containing
PostgreSQL 11.

As every Docker Image we release contains the PostgreSQL version of the tag,
but also of the major PostgreSQL version before the tag, that means you can
use the following images:

* `pg13*`: Supports running PostgreSQL 13 and 12
* `pg14*`: Supports running PostgreSQL 14 and 13

For those that used to use the Docker Images tagged with pg12 with PostgreSQL 12
you can now use the `pg13` tagged images.

> NOTICE: the `pg13` images do have their PATH default to PostgreSQL 13 binaries, so
be sure to configure the PATH environment variable correctly in the container
that you use.

For example, the `timescaledb-single` Helm Chart configures the path based
upon the user input in [`values.yaml`](https://github.com/timescale/timescaledb-kubernetes/blob/a12dd47a2339ce1bbacde728f3eeb94309ce0e6f/charts/timescaledb-single/templates/statefulset-timescaledb.yaml#L253-L254)

### Removed

* We no longer build images containing PostgreSQL 12 and PostgreSQL 11

### Added

* We now also build PostgreSQL 14 Docker Images, they include PostgreSQL 14 and 13.

### Changed

* Include and default to Timescale 2.5.1
* Include Timescale Cloudutils 1.4.0
* Upgrade promscale extension to version 0.3.0

## [v1.0.8] - 2021-11-11

### Changed

* PostgreSQL [12.9](https://www.postgresql.org/docs/12/release-12-9.html) and [13.5](https://www.postgresql.org/docs/13/release-13-5.html) have been released
* Include dependencies to support native Raft support for Patroni [PySyncObj](https://github.com/bakwc/PySyncObj)

## [v1.0.7] - 2021-10-27

### Changed

* Include and default to Timescale 2.4.2
* Include Timescale Cloudutils 1.0.2
* Update Toolkit to 1.3.1

## [v1.0.4] - 2021-10-08

### Changed

* Include Hot Forge v0.1.35

## [v1.0.3] - 2021-10-07

### Changed

* Include `timescaledb_cloudutils` v1.0.1
* Include Hot Forge v0.1.33

### Added

* `pg_cron`

## [v1.0.2] - 2021-09-20

### Changed

* Include and default to Timescale 2.4.2

## [v1.0.1] - 2021-09-17

### Fixed

* Build of `timescaledb_cloudutils`

## [v1.0.0] - 2021-09-16

This is a major release, as the base Docker Image has changed from Debian to Ubuntu.
Our tests have not yet shown any issues with this update. We would advice anyone
that consumes these images to test that the new images also work for them in their
environment.

As this Docker Image has been in production for a while, it seems awkward to still not
be on version 1.0.0+, therefore, we mark this occasion with releasing version 1.0.0.

### Added

* Installation of rust compiler inside the Dockerfile

### Changed

* Base the Docker Image on `ubuntu` (21.04) instead of `rust:debian`
* Bump `timescaledb_toolkit` to version [1.2.0](https://github.com/timescale/timescaledb-toolkit/releases/tag/1.2.0)

### Removed

* Support for PostGIS 2.5

### Fixed

## [v0.4.29] - 2021-09-08

### Changed

* Bump `hot_forge` to 0.1.32

## [v0.4.28] - 2021-09-07

### Changed

* Bump `hot_forge` to 0.1.31 for publishing

## [v0.4.27] - 2021-09-07

### Changed

* Bump `hot_forge` to 0.1.31

## [v0.4.26] - 2021-09-07

### Fixed

* `timescaledb_cloudutils` now actually builds

### Changed

## [v0.4.25] - 2021-09-06

### Added

* `timescaledb_cloudutils` for non-oss builds

### Changed

* Bump `hot_forge` to 0.1.18

## [v0.4.24] - 2021-08-24

### Changed

* Download precompiled hot-forge instead of building from source
* Switch to rust Docker Image base (which is based on Debian itself)

## [v0.4.22] - 2021-08-19

### Changed

* Include and default to Timescale 2.4.1

## [v0.4.19] - 2021-08-12

### Changed

* PostgreSQL [12.8](https://www.postgresql.org/docs/12/release-12-8.html) and [13.4](https://www.postgresql.org/docs/13/release-13-4.html) have been released

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

* timescale-prometheus [superseeded by (promscale](https://github.com/timescale/promscale))
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
