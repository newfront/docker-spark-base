ARG java_image_tag=11-jre-slim

# build layer 1
FROM alpine:3.14 as source

WORKDIR /sources

RUN set -ex && \
  apk add --no-cache --virtual .build-deps \
  wget \
  tar \
  && wget https://github.com/apache/spark/archive/refs/tags/v3.1.2.tar.gz \
  && tar -xvzf v3.1.2.tar.gz \
  && rm -r v3.1.2.tar.gz \
  && apk del .build-deps

# build layer 2
FROM maven:3.6.3-jdk-11-slim@sha256:68ce1cd457891f48d1e137c7d6a4493f60843e84c9e2634e3df1d3d5b381d36c AS build
COPY --from=source /sources/spark-3.1.2 /spark
WORKDIR /spark
# This run command will take a while (30 minutes or more)
# Note: This build doesn't include pyspark/r
RUN ./dev/change-scala-version.sh 2.12 && \
  mvn -ntp \
  -Pscala-2.12 \
  -Phadoop-3.2 \
  -Phadoop-cloud \
  -Dhadoop.version=3.2.0 \
  -Pkubernetes \
  -Phive \
  -Phive-thriftserver \
  -DskipTests clean package

# When this run command completes all of the spark jars will be built. They are located in the assembly dir.
# ./spark/assembly/target/scala-2.12/jars/
# We will be copying the assembly/target/scala-2.12/jars to the final image, along with the conf templates

FROM openjdk:${java_image_tag}

ARG spark_uid=185

RUN set -ex && \
    sed -i 's/http:\/\/deb.\(.*\)/https:\/\/deb.\1/g' /etc/apt/sources.list && \
    apt-get update && \
    ln -s /lib /lib64 && \
    apt install -y bash tini libc6 libpam-modules krb5-user libnss3 procps && \
    mkdir -p /opt/spark && \
    mkdir -p /opt/spark/conf && \
    mkdir -p /opt/spark/examples && \
    mkdir -p /opt/spark/app && \
    mkdir -p /opt/spark/work-dir && \
    touch /opt/spark/RELEASE && \
    rm /bin/sh && \
    ln -sv /bin/bash /bin/sh && \
    echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su && \
    chgrp root /etc/passwd && chmod ug+rw /etc/passwd && \
    rm -rf /var/cache/apt/*

COPY --from=build /spark/assembly/target/scala-2.12/jars /opt/spark/jars
COPY --from=build /spark/bin /opt/spark/bin
COPY --from=build /spark/conf /opt/spark/conf
COPY --from=build /spark/sbin /opt/spark/sbin
COPY --from=build /spark/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/entrypoint.sh /opt/
COPY --from=build /spark/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/decom.sh /opt/

ENV SPARK_HOME /opt/spark

WORKDIR /opt/spark/work-dir
RUN chmod g+w /opt/spark/work-dir
RUN chmod a+x /opt/decom.sh

ENTRYPOINT [ "/opt/entrypoint.sh" ]

# Specify the User that the actual main process will run as
USER ${spark_uid}
