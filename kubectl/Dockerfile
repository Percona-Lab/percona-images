FROM centos

ENV KUBECTL_VERSION=v1.13.1
ENV KUBECTL_MD5SUM=5cbe45fdb1e59466eea77a3ba34d1f23

RUN curl -o /usr/bin/kubectl \
		https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
	&& chmod +x /usr/bin/kubectl \
    && echo "${KUBECTL_MD5SUM} /usr/bin/kubectl" | md5sum -c -

USER nobody
