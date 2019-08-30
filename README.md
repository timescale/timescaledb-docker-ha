# TimescaleDB Docker image for Kubernetes
This directory contains everything that allows us to create a Docker image with the following pieces of software:

- PostgreSQL
- TimescaleDB, multiple versions
- Backup Software

# Build images
## Build all images
```
make build-all
```

## Push all images
```
make push-all
```

## Customizations
To allow source customizations of PostgreSQL, you can add a script to the `customizations` directory
and build the Docker image with a `TS_CUSTOMIZATION` build argument, e.g.:

```
docker build --tag test --build-arg TS_CUSTOMIZATION=nov-namedatalen.sh .
```

As we can only support a limited amount of customization in the Docker build process, this is what is available to
the script once called:

- Build tools
- A PostgreSQL source directory (from a pgdg source package)

From the script you can do whatever you want, afterwards the packages will be built from this directory and installed.

Installing the software as PostgreSQL packages ensures the dependencies of other required packages will be satisfied.

# Release Images

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

