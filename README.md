# Publishing a new Docker Image to our Amazon ECR

```
TAG=142548018081.dkr.ecr.us-east-2.amazonaws.com/patroni:dev
docker build --build-arg PG_MAJOR=11 --tag  "${TAG}" .
docker push "${TAG}"
```
