# TimescaleDB Docker image for Kubernetes

This directory contains everything that allows us to create a Docker image with the following pieces of software:

- PostgreSQL
- Some PostgreSQL extensions, most notably PostGIS
- TimescaleDB, multiple versions
- pgBackRest
- scripts to make it all work in a Kubernetes Context

Currently, our base image is Ubuntu, as we require glibc 2.33+.

It's currently pushing the resulting images to: https://hub.docker.com/r/timescale/timescaledb-ha

## Build images

To build an image, run the following make target:

```console
make
```

As building the whole image takes considerably amounts of time, the default will only install 1 timescaledb version:
The head of the `master` branch of the github.com/timescale/timescaledb.

For more robust build runs do:

```console
make build
```

Or, if you only want to exclude Timescale License code you can use the following command:

```console
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

For updating changes in versions for timescaledb, pgvectorscale, or toolkit, update `build_scripts/versions.yaml`

## Verify your work

For every pushed commit to this repository, a Docker Image will be built. Once your commit is pushed, a Docker Image will
be built, and if successful, will be pushed. The tag of this Docker Image will be `cicd-<first 7 chars of commit sha>-amd64`,
for example, for commit `baddcafe...`, the tag will look like:
```text
timescale/timescaledb-ha:cicd-baddcaf-amd64
```

#### Find out tag using commandline

Assuming your current working directory is on the same commit as the one you pushed

```console
echo "timescale/timescaledb-ha:cicd-$(git rev-parse HEAD | cut -c 1-7)"
```

#### Find tag using GitHub Web interface

- Actions
- Click on the **Build branch** Workflow for your commit/branch
- Look at the `Build and push branch summary` for the tag

##### Example output

```text
Checking docker.io/timescale/timescaledb-ha:cicd-8578fce-amd64

amd64: the base image was built 93 seconds ago
...
```

In the above example, your Docker tag is `cicd-8578fce-amd64` and your full image url is:

```text
docker.io/timescale/timescaledb-ha:cicd-8578fce-amd64
```

## Test your Docker Image

```console
docker run --rm -ti -e POSTGRES_PASSWORD=smoketest docker.io/timescale/timescaledb-ha:cicd-baddcaf-amd64
```

## Versioning and Releases

### Release Process

Between releases, we keep track of notable changes in CHANGELOG.md.

When we want to make a release we should update CHANGELOG.md to contain the release notes for the planned release in a section for
the proposed release number. This update is the commit that will be tagged with as the actual release which ensures that each release
contains a copy of it's own release notes.

We should also copy the release notes to the Github releases page, but CHANGELOG.md is the primary place to keep the release notes.

The release commit should be tagged with a signed tag:

```console
git tag -s vx.x.x
git push --tags
```

If you use the release notes in the tag commit message and it will automatically appear in the Github release. On the Github releases
page click `Draft a new release` and then type your tag in the drop down contain `@master`. The release will automatically be created
using the tag commit text.

### Publish the images to Docker Hub and other registries

They will be written under quite a few aliases, for example, for PostgreSQL 15.2 and Timescale 2.10.3, the following images will be built and pushed/overwritten:

- timescale/timescaledb-ha:pg15
- timescale/timescaledb-ha:pg15-all
- timescale/timescaledb-ha:pg15-ts2.10
- timescale/timescaledb-ha:pg15-ts2.10-all
- timescale/timescaledb-ha:pg15.2-ts2.10.3
- timescale/timescaledb-ha:pg15.2-ts2.10.3-all

For `OSS_ONLY` builds, the following tags will be published:
- timescale/timescaledb-ha:pg15-oss
- timescale/timescaledb-ha:pg15-all-oss
- timescale/timescaledb-ha:pg15-ts2.10-oss
- timescale/timescaledb-ha:pg15-ts2.10-all-oss
- timescale/timescaledb-ha:pg15.2-ts2.10.3-oss
- timescale/timescaledb-ha:pg15.2-ts2.10.3-all-oss

The `-all` portion of the tags specifies that the image contains pg15, as well as version 12, 13, and 14. Otherwise, only
the single version of PostgreSQL is included in the image.
