FROM debian:buster-slim AS builder
RUN true

## Create a smaller Docker image from the builder image
FROM scratch
COPY --from=builder / /