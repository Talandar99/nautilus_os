FROM scratch
COPY nautilus/rootfs/ /
ENV USER=root
EXPOSE 8090
EXPOSE 45876
EXPOSE 80
ENTRYPOINT ["/init.sh"]
