#! /bin/sh

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

CONF_FILE=/etc/bind/named.conf
ZONEDIR=/var/bind/zones

mkdir -p /etc/bind /var/bind /var/run/named "${ZONEDIR}"

## 1. Create main config file
cat - > "${CONF_FILE}" <<EOF
options {
        directory "/var/bind";
        listen-on { any; };
        listen-on-v6 { any; };
        allow-transfer {
                none;
        };
        dnssec-validation no;

        pid-file "/var/run/named/named.pid";

        allow-recursion { 0.0.0.0/0; };
        allow-query { any; };
        querylog ${QUERY_LOG:-yes};
        ${OPTIONS}
EOF

## 2. Configure Authoritative Root / Forwarding
case "${AUTHORITATIVE:-self}" in
    iana | iana,#)
        echo "[*] Role: Root resolver using IANA root hints (iterative mode)"
        cat - >> "${CONF_FILE}" <<EOF
};
zone "." IN {
        type hint;
        file "named.ca";
};
EOF
    ;;
    iana,*)
        FORWARDER=${AUTHORITATIVE#iana,}
        echo "[*] Role: Forwarding resolver with upstream forwarder: ${FORWARDER}"
        cat - >> "${CONF_FILE}" <<EOF
        forwarders {
              ${FORWARDER};
        };
};
zone "." IN {
        type hint;
        file "named.ca";
};
EOF
    ;;
    self)
        echo "[*] Role: Standalone authoritative root server (.)"
        echo '};' >> "${CONF_FILE}"
        if test -z "${DOMAIN__}" ; then
            DOMAIN__=
        fi
    ;;
    *,A,*,* | *,AAAA,*,*)
        ROOT_NAME=${AUTHORITATIVE%%,*}
        FORWARDER=${AUTHORITATIVE##*,}
        AUTHORITATIVE=${AUTHORITATIVE%,*}
        echo "[*] Role: Authoritative root set to \"${ROOT_NAME}\""
        if test -n "${FORWARDER}" && test "${FORWARDER}" != "#" ; then
            echo "    Upstream forwarder: ${FORWARDER}"
            cat - >> "${CONF_FILE}" <<EOF
        forwarders {
              ${FORWARDER};
        };
EOF
        fi
        cat - >> "${CONF_FILE}" <<EOF
};
zone "." IN {
        type hint;
        file "custom.ca";
};
EOF
        cat - >> /var/bind/custom.ca <<EOF
$(echo -en '.\tNS\t')${ROOT_NAME}.
$(echo "${AUTHORITATIVE}" | awk 'BEGIN {RS=" "; FS=","; OFS="\t"} {print $1 ".",$2,$3}')
EOF
    ;;
    *)
        1>&2 echo "=========================================================="
        1>&2 echo "[ERROR] AUTHORITATIVE should be one of:"
        1>&2 echo "  * iana (iterative root lookup via public hints)"
        1>&2 echo "  * iana,forwarder (forward recursion to specific upstream)"
        1>&2 echo "  * self (default standalone authoritative root)"
        1>&2 echo "  * fqdn,A,ipv4addr,forwarder"
        1>&2 echo "  * fqdn,AAAA,ipv6addr,forwarder"
        1>&2 echo ""
        1>&2 echo "Example: AUTHORITATIVE=iana,8.8.8.8"
        1>&2 echo "=========================================================="
        1>&2 echo "Pausing 10s before dropping into diagnostic shell..."
        sleep 10
        exec /bin/bash
    ;;
esac

## 3. Setup self-referencing resource records (IP detection)
if test -z "${INTERFACE}" ; then
    INTERFACE=eth0
fi

# Detect IPv4 and IPv6 addresses on INTERFACE (with retry if network link is initializing)
for i in 1 2 3 ; do
    IPv4=$(ip -4 addr show dev "${INTERFACE}" 2>/dev/null | awk '/ inet /{split($2,a,"/"); print a[1];}')
    IPv6=$(ip -6 addr show dev "${INTERFACE}" 2>/dev/null | awk '/ inet6 ([^fF]|[fF][^eE]|[fF][eE][^8]|[fF][eE]8[^0])/{split($2,a,"/"); print a[1];}')
    if test -n "${IPv4}" || test -n "${IPv6}" ; then
        break
    fi
    if test "${WAIT_IP:-0}" = "1" || test "${WAIT_IP:-0}" = "yes" ; then
        sleep 1
    fi
done

# Allow manual IP override via environment variables
if test -n "${NS_IP}" ; then
    IPv4="${NS_IP}"
fi
if test -n "${NS_IPV6}" ; then
    IPv6="${NS_IPV6}"
fi

# Fallback: scan any other active interface (excluding loopback)
if test -z "${IPv4}" && test -z "${IPv6}" ; then
    IPv4=$(ip -4 addr show 2>/dev/null | awk '/ inet / && $NF != "lo" {split($2,a,"/"); print a[1]; exit;}')
fi

# Graceful fallback to 127.0.0.1 to prevent invalid zone glue if unconfigured
if test -z "${IPv4}" && test -z "${IPv6}" ; then
    echo "[!] Warning: No IP address detected on '${INTERFACE}'. Defaulting self-NS glue to 127.0.0.1."
    IPv4="127.0.0.1"
fi

echo "Detected IP address(es) on ${INTERFACE}:"
for a in ${IPv4} ${IPv6} ; do
    echo "  -> ${a}"
done

SELF_ADDRESS_RR=$(
    for a in ${IPv4} ; do
        echo -e "ns\tA\t${a}"
    done
    for a in ${IPv6} ; do
        echo -e "ns\tAAAA\t${a}"
    done
)

## 4. Setup domains
DOMAINS=$(set | grep -o ^DOMAIN_[^=]\\\+ | sed s/DOMAIN_//)
USER_DOMAINS=$(echo "${DOMAINS}" | grep -v '^_$')

# Zero-configuration default demo domain for GNS3 classroom labs
if test -z "${USER_DOMAINS}" ; then
    if echo "${AUTHORITATIVE:-self}" | grep -q "^iana" ; then
        echo "[*] Caching/recursive resolver mode active (no local master zones)."
    else
        echo "[i] No user DOMAIN_* specified."
        echo "[i] Initializing default demonstration domain: 'lab.local'..."
        PRIMARY_IP=$(echo "${IPv4}" | awk '{print $1}')
        DOMAIN_lab_local="@,A,${PRIMARY_IP:-10.0.0.1} ns,A,${PRIMARY_IP:-10.0.0.1} router,A,10.0.0.254 www,A,10.0.0.10 mail,A,10.0.0.20 client,A,10.0.0.100"
        export DOMAIN_lab_local
        DOMAINS=$(echo "${DOMAINS} lab_local" | tr ' ' '\n' | grep -v '^$')
    fi
fi

for D in ${DOMAINS} ; do
    eval records=\$DOMAIN_$D
    D_NAME=$(echo -n "$D" | tr _ \.)
    echo "Processing domain \"${D_NAME}\" with records: ${records}"
    D_ZONE="${ZONEDIR}/${D_NAME}.zone"

    # Check if a custom NS record is specified
    if echo "${records}" | grep -E '( +|^)@ *, *NS *, *[^ ]+( +|$)' >/dev/null ; then
        NS=$(echo "${records}" | sed -E 's/^.*@ *, *NS *, *([^ ]+).*$/\1/')
        cat - > "${D_ZONE}" <<EOF
\$TTL 1W
@       SOA     ${NS} root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
EOF
    else
        cat - > "${D_ZONE}" <<EOF
\$TTL 1W
@       SOA     ns root (
                                      1          ; Serial
                                      28800      ; Refresh
                                      14400      ; Retry
                                      604800     ; Expire - 1 week
                                      86400 )    ; Minimum
@       NS      ns
${SELF_ADDRESS_RR}
EOF
    fi

    # Append resource records
    echo "${records}" | awk 'BEGIN {RS=" "; FS=","; OFS="\t"} {print $1,$2,$3}' >> "${D_ZONE}"

    cat - >> "${CONF_FILE}" <<EOF
zone "${D_NAME}" IN {
        type master;
        file "zones/${D_NAME}.zone";
        forwarders { };
};
EOF
done

## 5. Adjust permissions
chown -R named:named /var/bind /var/run/named 2>/dev/null || true

## 6. Validate BIND configuration
echo "Validating BIND configuration..."
if ! named-checkconf -z "${CONF_FILE}" ; then
    1>&2 echo "=========================================================="
    1>&2 echo " [ERROR] BIND configuration check failed!"
    1>&2 echo " Please verify your DOMAIN_* or OPTIONS syntax."
    1>&2 echo "=========================================================="
    1>&2 echo "Dropping into shell for diagnostics..."
    exec /bin/bash
fi

## 7. Informational Demonstration Banner
DISP_ZONES=$(echo "${DOMAINS}" | grep -v '^_$' | tr _ \. | tr '\n' ' ')
FIRST_ZONE=$(echo "${DOMAINS}" | grep -v '^_$' | head -n 1 | tr _ \.)
PRIMARY_IP=$(echo "${IPv4}" | awk '{print $1}')
echo "======================================================================"
echo "            GNS3 BIND 9 DNS Appliance - Online & Ready                "
echo "======================================================================"
echo "  Role:           ${AUTHORITATIVE:-self}"
echo "  Interface:      ${INTERFACE} (${IPv4:-none})"
if test -n "${IPv6}" ; then
echo "  IPv6:           ${IPv6}"
fi
echo "  Query Logging:  ${QUERY_LOG:-yes} (queries logged in real-time)"
if test -n "${DISP_ZONES}" ; then
echo "  Hosted Zones:   ${DISP_ZONES}"
else
echo "  Hosted Zones:   none (recursive caching mode)"
fi
echo "----------------------------------------------------------------------"
echo "  Quick Lab Test Commands:"
if test -n "${FIRST_ZONE}" ; then
echo "    dig @${PRIMARY_IP:-127.0.0.1} ${FIRST_ZONE}"
echo "    nslookup ${FIRST_ZONE} ${PRIMARY_IP:-127.0.0.1}"
else
echo "    dig @${PRIMARY_IP:-127.0.0.1} google.com"
fi
echo "  Helper Tools:"
echo "    dns-status    - Display BIND process, port 53 & zone status"
echo "    dns-reload    - Validate config and reload BIND via rndc"
echo "    dns-test      - Run automated local resolution tests"
echo "======================================================================"

echo "Starting named daemon..."
exec named -u named -g
