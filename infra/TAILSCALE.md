# Tailscale Stuff

```bash
tailscale serve --bg --https=443 https+insecure://localhost:30443
tailscale serve --bg --https=8443 https+insecure://localhost:31443
tailscale serve --bg --https=9443 http://localhost:32443
tailscale serve status
```
