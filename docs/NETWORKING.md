# Networking Architecture

This document explains how networking works in the homelab, including DNS resolution, traffic flow, and the role of each component.

## Current Architecture Overview

The homelab uses a **hostNetwork-based** NGINX Ingress Controller due to WiFi networking limitations. This is different from the typical LoadBalancer + MetalLB setup.

### Key Components

1. **NGINX Ingress Controller**: Runs with `hostNetwork: true` mode
2. **nip.io**: Wildcard DNS service (no configuration needed)
3. **MetalLB**: LoadBalancer for non-HTTP services (optional in current setup)
4. **K3s/Kubeadm**: Kubernetes distribution

## Understanding nip.io

### What is nip.io?

**nip.io** is a free wildcard DNS service that automatically resolves hostnames to IP addresses embedded in the domain name.

### How It Works

The magic happens in the hostname itself:

- `prometheus.192.168.100.98.nip.io` → Resolves to `192.168.100.98`
- `grafana.192.168.100.98.nip.io` → Resolves to `192.168.100.98`
- `anything.10.0.0.50.nip.io` → Resolves to `10.0.0.50`

**You don't configure anything!** It's just a DNS trick. The nip.io DNS servers parse the IP from the hostname and return it.

### Why Use nip.io?

1. **No DNS Server Needed**: No need to run your own DNS server
2. **No /etc/hosts Edits**: Works on any device without configuration
3. **Dynamic IPs**: Perfect for homelabs where IPs might change
4. **Multi-Device**: Works on phones, tablets, laptops without setup

### Alternatives to nip.io

If nip.io doesn't work on your network (some corporate networks block it):

1. **Local hosts file** (requires editing on each device):
   ```bash
   # Linux/Mac: /etc/hosts
   # Windows: C:\Windows\System32\drivers\etc\hosts
   192.168.100.98 prometheus.local grafana.local alertmanager.local
   ```

2. **Local DNS server** (Pi-hole, dnsmasq, etc.):
   - Set up wildcard DNS: `*.homelab → 192.168.100.98`

3. **sslip.io**: Alternative service similar to nip.io
   - `grafana.192-168-100-98.sslip.io` (dashes instead of dots)

## Current Setup: hostNetwork Mode

### Why hostNetwork Mode?

From git commit: *"changed service type to cluster ip due to wi-fi networking issues"*

**Problem**: MetalLB L2 mode doesn't work reliably over WiFi interfaces
- L2 mode requires Ethernet-level control
- WiFi adapters often drop or ignore ARP packets needed for L2 advertisement

**Solution**: Use `hostNetwork: true` for NGINX Ingress
- NGINX binds directly to the node's network interface
- Listens on ports 80/443 on the node's actual IP address
- No need for MetalLB for HTTP/HTTPS traffic

### Configuration

**NGINX Ingress values** (`k8s/helm/ingress-nginx/values.yaml`):
```yaml
controller:
  hostNetwork: true              # Bind to node's network
  dnsPolicy: ClusterFirstWithHostNet

  service:
    type: ClusterIP              # Not LoadBalancer (no MetalLB needed)
```

### Node Information

Current cluster setup:
```bash
NAME        INTERNAL-IP      EXTERNAL-IP
spaceship   192.168.100.98   <none>
```

**Your node IP**: `192.168.100.98`

This is the IP where NGINX listens for incoming traffic.

## Traffic Flow

### HTTP/HTTPS Services (via NGINX Ingress)

```
┌─────────────────┐
│  User Browser   │
└────────┬────────┘
         │
         │ 1. DNS query: prometheus.192.168.100.98.nip.io
         ↓
┌─────────────────┐
│  nip.io DNS     │  Returns: 192.168.100.98
└────────┬────────┘
         │
         │ 2. HTTP request to 192.168.100.98:80
         ↓
┌─────────────────┐
│  Node (K3s)     │  IP: 192.168.100.98
│  192.168.100.98 │
└────────┬────────┘
         │
         │ 3. NGINX (hostNetwork mode) listening on port 80/443
         ↓
┌─────────────────┐
│ NGINX Ingress   │  Routes based on hostname
│  Controller     │
└────────┬────────┘
         │
         │ 4. Routes to ClusterIP service
         ↓
┌─────────────────┐
│ Prometheus Svc  │  ClusterIP: 10.43.x.x
│  (ClusterIP)    │
└────────┬────────┘
         │
         │ 5. Load balances to pod
         ↓
┌─────────────────┐
│ Prometheus Pod  │  Running the application
└─────────────────┘
```

### Non-HTTP Services (via LoadBalancer)

For services that don't use HTTP (databases, etc.), you can still use MetalLB:

```
┌─────────────────┐
│   Application   │
└────────┬────────┘
         │
         │ 1. Connect to 192.168.100.200:5432
         ↓
┌─────────────────┐
│    MetalLB      │  Assigns IP from pool: 192.168.100.200-250
└────────┬────────┘
         │
         │ 2. Routes to LoadBalancer service
         ↓
┌─────────────────┐
│ PostgreSQL Svc  │  Type: LoadBalancer
│  (LoadBalancer) │  External IP: 192.168.100.200
└────────┬────────┘
         │
         │ 3. Routes to pod
         ↓
┌─────────────────┐
│ PostgreSQL Pod  │
└─────────────────┘
```

**MetalLB IP Pool**: `192.168.100.200-192.168.100.250` (configured in `k8s/core/networking/metallb-config.yaml`)

## IP Address Usage

### Current IPs

| IP Address        | Usage                          | Type          |
|-------------------|--------------------------------|---------------|
| 192.168.100.98    | K3s node (spaceship)           | Node IP       |
| 192.168.100.98    | NGINX Ingress (hostNetwork)    | Same as node  |
| 192.168.100.200   | Traefik (K3s default ingress)  | MetalLB       |
| 192.168.100.200-250 | MetalLB IP pool              | Available IPs |

### Which IP Should You Use?

**For web applications (HTTP/HTTPS)**: Use `192.168.100.98` (the node IP)
- All Ingress hostnames should use: `service-name.192.168.100.98.nip.io`
- Examples:
  - `prometheus.192.168.100.98.nip.io`
  - `grafana.192.168.100.98.nip.io`
  - `ollama.192.168.100.98.nip.io`

**For non-HTTP services**: Use MetalLB pool IPs (192.168.100.200+)
- Set service type to `LoadBalancer`
- MetalLB will assign an IP from the pool
- Access directly via the assigned IP

### Wrong IPs in Configs

Some files currently reference `192.168.100.202` - this should be updated to `192.168.100.98`:

```bash
# Files that need updating:
k8s/applications/trackster/trackster-deployment.yaml
k8s/applications/ollama/ollama-deployment.yaml
k8s/ml-stack/jupyterhub/values.yaml
k8s/ml-stack/mlflow/mlflow-deployment.yaml
# ... and others
```

## Ingress Configuration Examples

### Standard Ingress (HTTP only)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: my-namespace
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # HTTP only
spec:
  ingressClassName: nginx
  rules:
  - host: my-app.192.168.100.98.nip.io  # Use node IP
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 8080
```

### Ingress with TLS (HTTPS)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: my-namespace
  annotations:
    cert-manager.io/cluster-issuer: "homelab-ca-issuer"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"  # Force HTTPS
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - my-app.192.168.100.98.nip.io
    secretName: my-app-tls  # cert-manager creates this
  rules:
  - host: my-app.192.168.100.98.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 8080
```

## MetalLB Configuration

MetalLB is configured but primarily used for non-HTTP services since NGINX uses hostNetwork.

### IP Address Pool

**File**: `k8s/core/networking/metallb-config.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.100.200-192.168.100.250  # Your local network range

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
  interfaces:
    - wlp2s0  # Your WiFi interface (check with `ip link`)
```

### Customizing for Your Network

1. **Check your network range**:
   ```bash
   ip addr show
   # Look for your node's IP (e.g., 192.168.1.x or 192.168.100.x)
   ```

2. **Choose an IP range** that doesn't conflict with DHCP:
   ```yaml
   addresses:
     - 192.168.1.200-192.168.1.250  # Example for 192.168.1.x network
   ```

3. **Find your network interface**:
   ```bash
   ip link
   # Look for your active interface (eth0, wlp2s0, enp3s0, etc.)
   ```

4. **Update metallb-config.yaml** and apply:
   ```bash
   kubectl apply -f k8s/core/networking/metallb-config.yaml
   ```

## Troubleshooting

### Can't Access Services

1. **Check NGINX is running**:
   ```bash
   kubectl get pods -n ingress-nginx
   ```

2. **Verify node IP**:
   ```bash
   kubectl get nodes -o wide
   # Check INTERNAL-IP column
   ```

3. **Test DNS resolution**:
   ```bash
   nslookup grafana.192.168.100.98.nip.io
   # Should return 192.168.100.98
   ```

4. **Check port binding**:
   ```bash
   # On the K3s node
   sudo netstat -tlnp | grep :80
   # Should show NGINX or containerd listening
   ```

### nip.io Not Working

**Symptoms**: DNS doesn't resolve or times out

**Solutions**:

1. **Try sslip.io instead**:
   - Use `grafana.192-168-100-98.sslip.io` (dashes instead of dots)

2. **Use local hosts file**:
   ```bash
   # Linux/Mac
   sudo nano /etc/hosts

   # Windows (as Administrator)
   notepad C:\Windows\System32\drivers\etc\hosts

   # Add:
   192.168.100.98 prometheus.local grafana.local alertmanager.local
   ```

3. **Check if network blocks external DNS**:
   ```bash
   dig @8.8.8.8 grafana.192.168.100.98.nip.io
   # If this works but regular DNS doesn't, your network might block nip.io
   ```

### Services Not Routing

1. **Check Ingress resource**:
   ```bash
   kubectl get ingress -A
   kubectl describe ingress <ingress-name> -n <namespace>
   ```

2. **Verify service exists**:
   ```bash
   kubectl get svc -n <namespace>
   ```

3. **Check NGINX logs**:
   ```bash
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
   ```

### MetalLB Not Assigning IPs

1. **Check MetalLB pods**:
   ```bash
   kubectl get pods -n metallb-system
   ```

2. **Verify IP pool**:
   ```bash
   kubectl get ipaddresspool -n metallb-system
   ```

3. **Check L2 advertisement**:
   ```bash
   kubectl get l2advertisement -n metallb-system
   ```

4. **WiFi issues**: Remember MetalLB L2 mode may not work reliably over WiFi

## Best Practices

### For HTTP/HTTPS Services

1. **Always use `ingressClassName: nginx`** (not the deprecated annotation)
2. **Use node IP in hostnames**: `app.192.168.100.98.nip.io`
3. **Add ssl-redirect annotation**: Set to `"false"` for HTTP or `"true"` for HTTPS
4. **Set pathType**: Use `Prefix` for most cases
5. **Service type**: Use `ClusterIP` (default) - NGINX will find it

### For Non-HTTP Services

1. **Use LoadBalancer type**: Get a dedicated IP from MetalLB
2. **Check IP pool range**: Ensure it matches your network
3. **Avoid WiFi if possible**: Use Ethernet for better L2 support

### DNS Recommendations

1. **Development**: Use nip.io or sslip.io
2. **Production homelab**: Set up local DNS (Pi-hole, dnsmasq)
3. **Fallback**: Keep hosts file entries as backup

## Additional Resources

- [NGINX Ingress Controller Docs](https://kubernetes.github.io/ingress-nginx/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [nip.io Service](https://nip.io/)
- [sslip.io Alternative](https://sslip.io/)
- [Cert-Manager Docs](https://cert-manager.io/)

## Summary

- **Node IP**: `192.168.100.98` (your K3s node)
- **NGINX Mode**: `hostNetwork: true` (binds to node IP)
- **Service Type**: ClusterIP (not LoadBalancer)
- **DNS**: nip.io automatically resolves `*.192.168.100.98.nip.io` → `192.168.100.98`
- **All Ingress hostnames** should use: `service-name.192.168.100.98.nip.io`
- **MetalLB**: Available for non-HTTP services, IP pool: 192.168.100.200-250
