# docker-spark-base
Creates a customizable base image for working with Apache Spark

## Build Phases
### Download Source Phase
- alpine linux - no-cache
* step 1. Downloads the tar from the official tagged spark release in github
* step 2. untar and clean up

### Maven Building and Packaging Phase
- mvn + jdk11
* step 1. mvn package phase (takes a while, but compiles all the spark packages cleanly)

### Final Image Phase
- openjdk:11-jre-slim
This is the final Spark image. It uses the debian slim buster linux image.

~~~
docker build . \
  --build-arg spark_user=500 \
  --tag `whoami`/docker-spark-base:3.1.2
~~~