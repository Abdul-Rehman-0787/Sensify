FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    flex bison gcc g++ make clang diffutils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
CMD ["bash"]