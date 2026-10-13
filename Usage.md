# BIND DNS Appliance for GNS3: Usage & Configuration Reference

This guide explains how to configure and use the **BIND DNS Server** appliance once it is imported into GNS3.

---

## 1. Setting Environment Variables in GNS3

All DNS zones, server roles, and logging behaviors are configured using container **environment variables**.

### For a Node in Your Topology
1. **Stop the node** if it is currently running (right-click node &rarr; **Stop**).
2. Right-click the node &rarr; select **Configure**.
3. In the **Node properties** dialog, locate the **Environment** text box.
4. Enter your environment variables **one per line** in `KEY=value` format.
   * *Do not* prefix with `export`.
   * *Do not* put outer quotes around the whole line (e.g. use `KEY=value`, not `KEY="value"`).
5. Click **Apply** / **OK**.
6. **Start the node** (right-click &rarr; **Start**).

> [!IMPORTANT]
> Environment variables are applied when the container starts. Any changes made to the Environment text box require stopping and restarting the node.

### Setting Defaults for Future Nodes
To change the default environment variables for all newly placed nodes:
1. Open GNS3 **Preferences** (**Edit** &rarr; **Preferences** or `Ctrl+Shift+P`).
2. Navigate to **Docker** &rarr; **Docker containers**.
3. Select **BIND DNS Server** and click **Edit**.
4. In the **Environment** field, update the default variables and click **OK**.

---

## 2. Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `DOMAIN_<name>` | *`site` or `lab.local`* | Defines a master zone. Dots (`.`) in the zone name must be replaced by underscores (`_`). |
| `AUTHORITATIVE` | `self` | Root authority role: `self`, `iana,<forwarder_ip>`, `iana,#`, or delegation tuple. |
| `QUERY_LOG` | `yes` | Logs all DNS queries live to the container console (`yes` or `no`). |
| `INTERFACE` | `eth0` | Network interface used to auto-detect the server's own IP address. |
| `NS_IP` | *auto-detected* | Explicit IPv4 address override for the nameserver `ns` glue record. |
| `NS_IPV6` | *auto-detected* | Explicit IPv6 address override for the nameserver `ns` glue record. |
| `WAIT_IP` | `0` | Set to `1` or `yes` to wait briefly for network link initialization in GNS3 before binding. |
| `OPTIONS` | *none* | Custom BIND directives appended directly into `options { ... }` in `named.conf`. |

---

## 3. Defining Zones & Records (`DOMAIN_<name>`)

### Zone Naming
The variable name specifies the domain name, replacing all dots (`.`) with underscores (`_`):
* Domain `site` &rarr; `DOMAIN_site`
* Domain `example.com` &rarr; `DOMAIN_example_com`
* Domain `sub.lab.local` &rarr; `DOMAIN_sub_lab_local`

### Record Value Format
The value is a **space-separated** list of **comma-separated** record tuples:

* **Standard Records (`owner,type,rdata`)**:
  * Supported types: `A`, `AAAA`, `CNAME`, `PTR`, `TXT`, `NS`.
  * Use `@` to refer to the zone root/apex.
  * Examples:
    * `@,A,192.168.1.1`
    * `alice,A,192.168.111.17`
    * `www,CNAME,alice.site.`
    * `ipv6host,AAAA,fd00:1::10`
* **MX Records (`owner,MX,priority,mailserver`)**:
  * Include the integer priority and target mail exchanger.
  * Example: `@,MX,10,mail.example.com.`
* **TXT Records with Spaces (`owner,TXT,"text"`)**:
  * Enclose the text string in quotes: `@,TXT,"v=spf1 mx ~all"`

### Automatic Records
* An **SOA** record is generated automatically.
* An **NS** record (`@ NS ns.<domain>`) and glue `A`/`AAAA` records pointing to the server's auto-detected IP address on `eth0` are added automatically unless an explicit `@,NS,...` record is declared.

---

## 4. Root Authority Roles (`AUTHORITATIVE`)

* **`AUTHORITATIVE=self`** *(Default)*:
  * The server acts as its own authoritative root (`.`) server.
  * Ideal for standalone, isolated lab topologies without internet access.
* **`AUTHORITATIVE=iana,<forwarder_ip>`**:
  * Acts as a caching/forwarding resolver.
  * Resolves configured `DOMAIN_*` zones locally and forwards all other queries to the specified upstream forwarder (e.g. `AUTHORITATIVE=iana,8.8.8.8`).
* **`AUTHORITATIVE=iana` or `AUTHORITATIVE=iana,#`**:
  * Performs iterative root queries directly via standard internet root hints (requires internet connectivity).
* **`AUTHORITATIVE=<root_ns>,A,<root_ip>,<forwarder_ip>`**:
  * Configures multi-tier DNS delegation hierarchies in advanced labs (e.g., `AUTHORITATIVE=ns,A,1.2.3.4,1.2.3.4`).

---

## 5. Configuration Examples

### Example 1: Local Single-Label Domain (Classroom Default)
```env
QUERY_LOG=yes
AUTHORITATIVE=self
DOMAIN_site=alice,A,192.168.111.17 bob,A,192.168.111.18 router,A,192.168.111.1
```

### Example 2: Standard FQDN with Web, Mail, SPF and IPv6
```env
QUERY_LOG=yes
AUTHORITATIVE=self
DOMAIN_example_com=@,A,10.0.0.1 www,A,10.0.0.10 mail,A,10.0.0.20 www,AAAA,fd00:1::10 @,MX,10,mail.example.com. @,TXT,"v=spf1 mx ~all"
```

### Example 3: Internal Zone with Internet Forwarding
```env
QUERY_LOG=yes
AUTHORITATIVE=iana,8.8.8.8
DOMAIN_corp_local=@,A,172.16.0.1 www,A,172.16.0.10 gateway,A,172.16.0.254
```

---

## 6. Verification and Testing

### 1. Real-Time Console Banner & Query Logging
* Double-click the node in GNS3 (or right-click &rarr; **Auxiliary console** / **Console**).
* On startup, the console displays an informational banner showing detected IPs, active zones, and query logging status.
* When client queries arrive, each query and response is logged to the console in real-time.

### 2. Testing from a Client Device
From a connected client host or router on the same network:
```bash
dig @<server-ip> alice.site
# or
nslookup www.example.com <server-ip>
```

### 3. Built-in Container Helper Commands
Open a shell in the container (via console or auxiliary console):
* `dns-status`: Displays the `named` PID, listening port 53 sockets, rndc status, and loaded zone files.
* `dns-test`: Performs automated local DNS lookups against all configured zones.
* `dns-reload`: Validates syntax with `named-checkconf` and reloads configuration without stopping the container.
