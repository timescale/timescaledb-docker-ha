# TimescaleDB Docker image for Kubernetes
This directory contains everything that allows us to create a Docker image with the following pieces of software:

- PostgreSQL
- TimescaleDB, multiple versions
- Backup Software

# Build images
## Build all images
```
make image-all
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
