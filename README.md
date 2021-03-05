# TimescaleDB Docker image for Kubernetes
This directory contains everything that allows us to create a Docker image with the following pieces of software:

- PostgreSQL
- Some PostgreSQL extensions, most notably PostGIS
- TimescaleDB, multiple versions
- pgBackRest
- scripts to make it all work in a Kubernetes Context

# Build images

To build an image, run the following make target:
```console
make
```

As building the whole image takes considerably amounts of time, the default will only install 1 timescaledb version:
The head of the `master` branch of the github.com/timescale/timescaledb.

For more robust build runs do:

```
make build
```

Or, if you only want to exclude Timescale License code you can use the following command:
```
make build-oss
```

> For more information about licensing, please read our [blog post](https://blog.timescale.com/blog/how-we-are-building-an-open-source-business-a7701516a480/) about the subject.

By default, the Docker image contains many extensions, including [TimescaleDB](https://github.com/timescale/timescaledb) and [PostGIS](https://postgis.net/).
You can override which version of the extensions are built by setting environment variables, some examples:

```console
# Build without any PostGIS
POSTGIS_VERSIONS="" make build
```

For further environment variables that can be set, we point you to the [Makefile](Makefile) itself.

# Versioning and Releases

## Release Process

Between releases we keep track of notable changes in CHANGELOG.md.

When we want to make a release we should update CHANGELOG.md to contain the release notes for the planned release in a section for
the proposed release number. This update is the commit that will be tagged with as the actual release which ensures that each release
contains a copy of it's own release notes.

We should also copy the release notes to the Github releases page, but CHANGELOG.md is the primary place to keep the release notes.

The release commit should be tagged with a signed tag:

    git tag -s vx.x.x
    git push --tags

If you use the release notes in the tag commit message and it will automatically appear in the Github release. On the Github releases
page click `Draft a new release` and then type your tag in the drop down contain `@master`. The release will automatically be created
using the tag commit text.
## Publish the images to Docker Hub and other registries
Only if you push a tag starting with `v`, for example: `v0.8.3` to the GitHub repository, will new images will be published to docker hub automatically.

They will be written under quite a few aliases, for example, for PostgreSQL 12.6 and Timescale 2.0.1, the following images will be built and pushed/overwritten:

- timescale/timescaledb-ha:pg12-latest
- timescale/timescaledb-ha:pg12-ts2.0-latest
- timescale/timescaledb-ha:pg12.6-ts2.0-latest
- timescale/timescaledb-ha:pg12.6-ts2.0.1-latest

> the `-latest` suffix here indicates the latest docker build, not the latest commit. In particular, images built from a tag will be published with the `-latest` suffix in addition to the tag-based suffix.

In addition, for every build, an immutable image will be created and pushed, which will carry a patch version at the end. These are most suited for production releases, for example:
- timescale/timescaledb-ha:pg12.6-ts2.0.1-p0
