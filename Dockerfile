FROM scratch
# add filesystem
COPY nautilus/rootfs/ /
# default shell
SHELL ["/bin/sh", "-c"]
# get certifocates
RUN wget https://curl.haxx.se/ca/cacert.pem -O /etc/ssl/certs/ca-certificates.crt
# set user as root
ENV USER=root
