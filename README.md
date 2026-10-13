# BIND 9 DNS Appliance for GNS3

Lightweight Alpine-based Docker image optimized for **GNS3 network simulations, demonstrations, and classroom teaching**. Provides a fully featured ISC BIND 9 DNS server configurable entirely via environment variables, with zero-configuration demo defaults, real-time query logging on the console, and built-in network inspection tools.

> **Repository**: [https://github.com/skleber/gns3-bind](https://github.com/skleber/gns3-bind)  
> *Forked from [https://github.com/kazkansouh/gns3-bind](https://github.com/kazkansouh/gns3-bind) by Karim Kanso.*

---

## Features for Demonstrations & Teaching

* **Zero-Config Out-of-the-Box**: Drag into GNS3, hit Start, and the server is immediately operational with a demonstration domain (`lab.local`) and self-configuring NS records.
* **Real-Time Query Logging**: Incoming client queries are logged in real-time to the container console (`QUERY_LOG=yes`), allowing students and instructors to see live DNS resolution traffic.
* **Classroom Toolset Pre-installed**: Equipped with `bash`, `bind-tools` (`dig`, `nslookup`, `host`), `tcpdump`, `iputils` (`ping`), `iproute2`, `curl`, and `nano`.
* **Built-in Helper Commands**:
  * `dns-status`: Displays BIND daemon status, listening sockets (port 53), rndc status, and loaded zone files.
  * `dns-reload`: Validates syntax with `named-checkconf` and reloads zones without restarting the container.
  * `dns-test`: Runs automated local DNS self-tests against all configured zones.
* **Pre-flight Validation**: Automatically validates configurations using `named-checkconf -z` before launching to prevent silent startup failures.
* **GNS3 Appliance File**: Includes `gns3-bind.gns3a` for 1-click import into GNS3.
* **Dual Stack**: Full native support for IPv4 (`A`) and IPv6 (`AAAA`) queries.

---

## GNS3 Quickstart

### Method 1: Import via Appliance Template (Recommended)
1. In GNS3, click **File** &rarr; **Import appliance**.
2. Select [`gns3-bind.gns3a`](file:///D:/Teach/internet-material/GNS3/gns3-bind/gns3-bind.gns3a).
3. The **BIND DNS Server** node will now appear under your **End devices / Guests** palette. GNS3 will automatically pull the container image (`ghcr.io/skleber/gns3-bind:latest`) from GitHub Packages when dragged onto the canvas.

### Method 2: Pull or Build Manually with Docker
To pull the pre-built image from GitHub Container Registry:
```bash
docker pull ghcr.io/skleber/gns3-bind:latest
```
Or build locally from source:
```bash
docker build -t ghcr.io/skleber/gns3-bind:latest .
```
In GNS3: **Edit** &rarr; **Preferences** &rarr; **Docker containers** &rarr; **New** &rarr; Select `ghcr.io/skleber/gns3-bind:latest`.

### Running in a GNS3 Lab Topology
1. Drag the **BIND DNS Server** into your topology and connect `eth0` to a switch or router.
2. Start the node and open its console:
   * You will see the informational banner displaying detected IPs, active zones, and query logging status.
3. Connect a client host (e.g. VPCS, Alpine, or router) with an IP in the same subnet.
4. From the client, test DNS resolution:
   ```bash
   dig @<server-ip> www.lab.local
   # or
   nslookup www.lab.local <server-ip>
   ```
5. Watch the DNS query appear live in the BIND server console window!

---

## Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `DOMAIN_<name>` | *`lab.local` demo* | Space-separated list of `owner,type,rdata` tuples defining a master zone. Underscores in `<name>` map to dots (`DOMAIN_example_com` &rarr; `example.com`). |
| `AUTHORITATIVE` | `self` | Defines root role: `self`, `iana[,forwarder]`, `iana,#`, or `fqdn,type,ip,forwarder`. |
| `QUERY_LOG` | `yes` | Logs all DNS queries in real-time to stderr/console. Set to `no` for silent operation. |
| `INTERFACE` | `eth0` | Network interface to bind and auto-detect self IP addresses from. |
| `NS_IP` | *auto-detected* | Explicit IPv4 address override to advertise for the nameserver `ns` record. |
| `NS_IPV6` | *auto-detected* | Explicit IPv6 address override to advertise for the nameserver `ns` record. |
| `WAIT_IP` | `0` | Set to `1` or `yes` to wait briefly for network link initialization in GNS3 before binding. |
| `OPTIONS` | *none* | Custom BIND directives appended directly into `options { ... }` in `named.conf`. |

---

## Root Authority (`AUTHORITATIVE`)

### 1. Local Roots (`self`)
By default (`AUTHORITATIVE=self`), the image acts as its own authoritative root (`.`) server. It automatically generates `NS` records pointing to its own address. This is ideal for isolated lab topologies without internet access.

```bash
AUTHORITATIVE=self
```

### 2. Forwarding Resolver / Internet Root (`iana`)
To forward recursive queries onto an upstream resolver (such as Google Public DNS, Cloudflare, or a local corporate DNS):

```bash
# Forward unresolved queries to 8.8.8.8
AUTHORITATIVE=iana,8.8.8.8

# Or perform iterative queries directly via internet root servers (no forwarder):
AUTHORITATIVE=iana,#
```

### 3. Delegated Hierarchical Roots
To construct hierarchical delegation topologies (e.g., Root DNS &rarr; `.com` DNS &rarr; `.example.com` DNS):

```
------------          ------------             -------------------
| ns       |          | ns.com   |             | ns.example.com  |
| 1.2.3.4  |          | 1.2.3.5  |             | 1.2.3.6         |
------------          ------------             -------------------
Authoritative: root   Authoritative: .com      Authoritative: .example.com
Root NS: self (ns)    Root NS: ns (1.2.3.4)    Root NS: ns (1.2.3.4)
Forward: N/A          Forward: 1.2.3.4         Forward: 1.2.3.5
Delegate: .com        Delegate: .example.com   Delegate: N/A
```

* For `ns.com`:
  ```bash
  AUTHORITATIVE=ns,A,1.2.3.4,1.2.3.4
  ```
* For `ns.example.com`:
  ```bash
  AUTHORITATIVE=ns,A,1.2.3.4,1.2.3.5
  ```
* If upstream forwarding is not required and iterative resolution is desired, replace the forwarder with `#`:
  ```bash
  AUTHORITATIVE=ns,A,1.2.3.4,#
  ```

---

## Domain Specification (`DOMAIN_<name>`)

For each domain to host, set an environment variable `DOMAIN_<name>`. Underscores in `<name>` are converted to dots.

The value is a space-separated sequence of comma-separated tuples:
* **Standard 3-field tuple (`owner,type,rdata`)**:
  * `owner`: Resource record name (use `@` for zone root).
  * `type`: Record type (`A`, `AAAA`, `CNAME`, `TXT`, `PTR`, `NS`, etc.).
  * `rdata`: Record value or target hostname/IP. Text records with spaces can be enclosed in double quotes (e.g. `"v=spf1 mx ~all"`).
* **MX 4-field tuple (`owner,MX,priority,mailserver`)**:
  * DNS Mail Exchanger (`MX`) records require an integer priority (preference) in addition to the mailserver hostname.
  * Example: `@,MX,10,mail.example.com.` or `@,MX,20,backup.example.com.`

```bash
DOMAIN_name="owner1,type1,rdata1 owner2,MX,priority2,mailserver2"
```

### Example 1: Simple Local Network
```bash
DOMAIN_lab="@,A,192.168.1.1 ns,A,192.168.1.1 router,A,192.168.1.254 www,A,192.168.1.10"
```

### Example 2: Mail Exchange (MX) & Text (TXT) Records
Demonstrating mail server priority and SPF verification records:
```bash
DOMAIN_example_com="@,A,10.0.0.1 mail,A,10.0.0.25 backup,A,10.0.0.26 @,MX,10,mail.example.com. @,MX,20,backup.example.com. @,TXT,\"v=spf1 mx ~all\""
```

Querying this configuration:
* `dig @<server-ip> example.com MX +short` &rarr; `10 mail.example.com.` / `20 backup.example.com.`
* `dig @<server-ip> example.com TXT +short` &rarr; `"v=spf1 mx ~all"`

### Example 3: Dual Stack (IPv4 & IPv6)
```bash
DOMAIN_example_com="@,A,10.0.0.1 @,AAAA,fd00:1::1 www,A,10.0.0.10 www,AAAA,fd00:1::10"
```

### Example 4: Subdomain Delegation with Glue Records
On the parent DNS server for `com`:
```bash
DOMAIN_com="example,NS,ns.example ns.example,A,172.17.0.2 www,A,10.0.0.2"
```
On the child DNS server for `example.com`:
```bash
DOMAIN_example_com="www,A,10.0.0.1 mail,A,10.0.0.2"
AUTHORITATIVE="ns,A,172.17.0.3,172.17.0.3"
```

---

## Classroom Lab Helper Tools

When opening an interactive shell inside the container (`docker exec -it <container> bash` or via GNS3 auxiliary console):

* **`dns-status`**: Displays named daemon PID, listening UDP/TCP ports on interface 53, rndc status, and active zone files.
* **`dns-reload`**: Validates `/etc/bind/named.conf` with `named-checkconf` and reloads without dropping connections.
* **`dns-test`**: Queries local 127.0.0.1 for all SOA, NS, and host records defined in `/var/bind/zones/`.
* **`tcpdump -i any port 53 -n`**: Live packet sniffing for DNS queries and responses.

---

## Authors & License
 
* **Original Author**: Karim Kanso (Copyright (C) 2018–2019) &mdash; [kazkansouh/gns3-bind](https://github.com/kazkansouh/gns3-bind)
* **Maintainer & Contributor**: Stephan Kleber (Copyright (C) 2026) &mdash; [skleber/gns3-bind](https://github.com/skleber/gns3-bind)
 
This program is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License v3.0 (GPLv3)](LICENCE).
