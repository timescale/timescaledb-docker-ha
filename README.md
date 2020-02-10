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

# Versioning and Releases

## Repository
The repository contains the following branches:

* `master` - contains the entire set of reviewed commits
* `{username}/name` - a feature or hotfix branch started by an engineer
* `{N}.{N}.x` - release branch for a single minor release e.g. `1.4.x`.

Release branches are considered to be frozen and should only be updated with patches for bugs and security issues.

No code should be committed directly to master or release branches. All code should be submitted to review and CI testing by creating a pull request.

## Release Images

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

Create a new release branch for each major or minor release using the pattern `Major.Minor.x`, for example `0.1.x`. This branch will be used
to apply or backport fixes. Patch releases will be based on tagged commits on this branch.

Major and minor releases should tag commits in the `master` branch. Patch releases should tag commits in a release branch.

## Patch process

When a patch needs to be applied to an existing release, first create a feature branch based on the target release branch. Submit a PR
for review as normal. Create a separate PR for applying the patch to master. Both of these changes should update CHANGELOG.md with
information about the bugfix or patch. Once both pull requests are approved, merge to the feature branch and tag the release branch with the
patch number. Draft a new release as described above.

