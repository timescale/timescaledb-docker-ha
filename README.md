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

For updating changes in versions for timescaledb, pgvectorscale, or toolkit, update `build_scripts/versions.yaml`.

Installing the timescaledb and toolkit versions takes most of the build time. CI builds each version once per
PostgreSQL major and architecture, and keeps the tarball in the CI artifacts bucket `timescale-ci-artifacts` under
`timescaledb-docker-ha/extension-tarballs/<base image>/<arch>/<inputs>/`: the file
`<extension>-<version>-pg<major>.tar.gz.sha256` holds the sha256 of the tarball, and `sha256/<sha256>.tar.gz` holds
the tarball. `<inputs>` is a hash of the Dockerfile up to the `builder` stage, of `build_scripts/` without
`versions.yaml`, of the `Makefile` and of the workflows. A change to one of them, such as a new PostgreSQL minor or
Rust version, rebuilds every tarball. A new version in `build_scripts/versions.yaml` adds tarballs and does not
change the hash. `make extension-artifacts` fetches the tarballs into `build_artifacts/<arch>/` and checks them
against their sha256. It builds the missing ones from the `timescaledb-artifact` and `toolkit-artifact` Dockerfile
stages. Only the "Publish images" workflow on master stores tarballs in the bucket, with `make
extension-artifacts-upload`. The other builds only read them. The repository variables `EXTENSION_ARTIFACTS_BUCKET`
and `EXTENSION_ARTIFACTS_ROLE_ARN` turn the reads and the upload on. On master, the "Publish images" workflow stops
before the build when one of them is empty. `make extension-artifacts` removes the local
tarballs when the base image or the hash changes. The image build unpacks the tarballs it finds and installs the
rest itself. It stops if a tarball does not match its sha256, or has a file outside the extension files of its
PostgreSQL major. It unpacks a tarball as an unprivileged user and copies only those files into place. The first scheduled publish of each month rebuilds
every tarball, because the hash does not include the unpinned packages of the base stage. To rebuild every tarball
for another reason, such as a change to the entry of an existing version in `versions.yaml`, run the
"Publish images" workflow with "rebuild_extension_artifacts". Locally, `EXTENSION_ARTIFACTS_REBUILD=true` does the same and also removes the build cache of the current Docker builder. Without `EXTENSION_ARTIFACTS=true`, such as a
local build, the image installs every version itself.

The scripts outside the image need `yq`, `jq` and `shellcheck`. `mise install` installs the pinned versions from
`mise.toml`.

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

The `-all` portion of the tags specifies that the image contains pg15, as well as version 13, and 14. Otherwise, only
the single version of PostgreSQL is included in the image.
