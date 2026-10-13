# Copyright (C) 2018 Karim Kanso. All Rights Reserved.
# Copyright (C) 2026 Stephan Kleber. All Rights Reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

FROM alpine:latest

LABEL org.opencontainers.image.title="BIND 9 DNS Appliance for GNS3" \
      org.opencontainers.image.description="ISC BIND 9 authoritative and recursive DNS server for GNS3 network simulations and teaching labs" \
      org.opencontainers.image.url="https://github.com/skleber/gns3-bind" \
      org.opencontainers.image.source="https://github.com/skleber/gns3-bind" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

# Install BIND 9, DNS utilities, networking inspection tools, and bash for classroom teaching
RUN apk add --no-cache \
    bind \
    bind-tools \
    bash \
    bash-completion \
    iproute2 \
    iputils \
    tcpdump \
    curl \
    nano

# Set bash as default shell and customize prompt for GNS3 lab usage
ENV SHELL=/bin/bash
RUN echo 'export PS1="\[\033[01;32m\]gns3-bind\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# "' >> /etc/bash.bashrc \
    && echo 'source /etc/bash.bashrc' >> /root/.bashrc

EXPOSE 53/udp
EXPOSE 53/tcp

COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/* 2>/dev/null || true

COPY startup.sh /startup.sh
RUN chmod +x /startup.sh

CMD ["/startup.sh"]
