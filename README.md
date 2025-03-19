Goal:

- [x] Minikube cluster running SPIRE
- [x] Run Envoy instances with mTLS
- [ ] Run multi-cluster
- [ ] Call natively to Envoy with client side auth
  - [ ] with curl
  - [ ] with gRPC
- [ ] OIDC integration with Envoy?

## Keeping me sane

<details>
<summary>Environment setup</summary>

```
apt update
git config --global core.editor "vim
apt install -y fzf curl
echo "source /usr/share/doc/fzf/examples/key-bindings.bash" >> ~/.bashrc; source ~/.bashrc
```

</details>

## Minikube cluster running SPIRE

Running through [the getting started on k8s docs](https://spiffe.io/docs/latest/try/getting-started-k8s/).

```bash
minikube start  --driver=virtualbox \
                --extra-config=apiserver.authorization-mode=Node,RBAC \
                --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
                --extra-config=apiserver.service-account-key-file=/var/lib/minikube/certs/sa.pub \
                --extra-config=apiserver.service-account-issuer=api \
                --extra-config=apiserver.api-audiences=api,spire-server \
                -p spirecluster-1

minikube profile list
minikube status -p spirecluster-1

git clone https://github.com/spiffe/spire-tutorials

kubectl apply -f spire-tutorials/k8s/quickstart/spire-namespace.yaml

# Create spire server (StatefulSet)
kubectl apply \
    -f spire-tutorials/k8s/quickstart/server-account.yaml \
    -f spire-tutorials/k8s/quickstart/spire-bundle-configmap.yaml \
    -f spire-tutorials/k8s/quickstart/server-cluster-role.yaml
kubectl apply \
    -f spire-tutorials/k8s/quickstart/server-configmap.yaml \
    -f spire-tutorials/k8s/quickstart/server-statefulset.yaml \
    -f spire-tutorials/k8s/quickstart/server-service.yaml

# Create spire agent (DaemonSet)
kubectl apply \
    -f spire-tutorials/k8s/quickstart/agent-account.yaml \
    -f spire-tutorials/k8s/quickstart/agent-cluster-role.yaml
kubectl apply \
    -f spire-tutorials/k8s/quickstart/agent-configmap.yaml \
    -f spire-tutorials/k8s/quickstart/agent-daemonset.yaml

# Register workloads
kubectl exec -n spire spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -spiffeID spiffe://example.org/ns/spire/sa/spire-agent \
    -selector k8s_sat:cluster:demo-cluster \
    -selector k8s_sat:agent_ns:spire \
    -selector k8s_sat:agent_sa:spire-agent \
    -node
    # Entry ID         : dbbbbd28-48ae-48e8-8420-b9a588e44301
    # SPIFFE ID        : spiffe://example.org/ns/spire/sa/spire-agent
    # Parent ID        : spiffe://example.org/spire/server
    # Revision         : 0
    # X509-SVID TTL    : default
    # JWT-SVID TTL     : default
    # Selector         : k8s_sat:agent_ns:spire
    # Selector         : k8s_sat:agent_sa:spire-agent
    # Selector         : k8s_sat:cluster:demo-cluster

kubectl exec -n spire spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -spiffeID spiffe://example.org/ns/default/sa/default \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -selector k8s:ns:default \
    -selector k8s:sa:default
    # Entry ID         : 34741d11-3fb7-46ca-93fa-b876a5d14457
    # SPIFFE ID        : spiffe://example.org/ns/default/sa/default
    # Parent ID        : spiffe://example.org/ns/spire/sa/spire-agent
    # Revision         : 0
    # X509-SVID TTL    : default
    # JWT-SVID TTL     : default
    # Selector         : k8s:ns:default
    # Selector         : k8s:sa:default

# Create workloads
kubectl apply -f spire-tutorials/k8s/quickstart/client-deployment.yaml

kubectl exec -it $(kubectl get pods -o=jsonpath='{.items[0].metadata.name}' -l app=client) \
    -- /opt/spire/bin/spire-agent api fetch -socketPath /run/spire/sockets/agent.sock
```

## Run Envoy instances with mTLS

Following [Configure Envoy to Perform X.509 SVID Authentication
](https://github.com/spiffe/spire-tutorials/blob/main/k8s/envoy-x509/README.md).

First, let's create a frontend and a backend, where the frontend forwards a request to the backend.
Later we'll secure this call.

```bash
# After much debugging, this should "just work":
./create-workload-registrations.sh
kubectl apply -k service-workload/frontend/
kubectl apply -k service-workload/backend/
```

Iterating quickly to debug:

```bash
kubectl apply -f service-workload/test-pod.yaml

# Frontend
kubectl apply -k service-workload/frontend/
kubectl rollout restart deployment -n frontend
kubectl -n default exec -ti test-pod -- curl http://frontend.frontend.svc.cluster.local

# Backend
kubectl apply -k service-workload/backend/
kubectl rollout restart deployment -n backend
# This works in commit 2f12a8e6 but starts to fail when enabling mTLS:
kubectl -n default exec -ti test-pod -- curl http://backend.backend.svc.cluster.local
kubectl -n frontend logs -f -l app=frontend -c frontend

# Frontend calling backend
# This goes: user -> frontend Envoy -> frontend nginx -(proxy_pass)-> backend Envoy -> backend nginx
kubectl -n default exec -ti test-pod -- curl http://frontend.frontend.svc.cluster.local/backend/
```

### Proxying via Envoy

The above worked without authentication, but going forward we're adding authentication to the backend.

This means plain http requests will fail because the backend only serves https (`curl: (52) Empty reply from server`).

Clients that do not do mTLS but regular https will fail because the client did not authenticate:

```bash
# Note this:
# - uses https (since mTLS is/requires https) - failure to do errors with "curl: (52) Empty reply from server"
# - disables certificate checking (we are using our own CA)
kubectl -n default exec -ti test-pod -- curl -v -k https://backend.backend.svc.cluster.local:80/
# Returns:
# curl: (56) OpenSSL SSL_read: OpenSSL/3.0.13: error:0A00045C:SSL routines::tlsv13 alert certificate required, errno 0
```

We can now only call the backend via the frontend:

```bash
kubectl -n default exec -ti test-pod -- curl http://frontend.frontend.svc.cluster.local:80/backend/
  # <html>
  #   <body>
  #     <h1>Hello, world!</h1>
  #     <p>This is the backend instance!</p>
  #   </body>
  # </html>
```

Diagram:

```
         .                                         .
         .                Frontend                 .                  Backend
         .                                         .
         .    -----------        -----------       .      -----------        -----------
client <---> |   nginx   | <--> |   Envoy   | <--------> |   Envoy   | <--> |   nginx   |
        http  -----------  http  -----------     mTLS     -----------  http  -----------
         .                            |            .           |
         .                        sds |            .           | sds
         .                            |            .           |
         .                      -------------      .     -------------
         .                     | SPIRE agent |     .    | SPIRE agent |
         .                      -------------      .     -------------
         .                                         .
```

## Run multi-cluster

## Call natively to Envoy with client side auth

### Call natively to Envoy with client side auth with curl

### Call natively to Envoy with client side auth with gRPC

## OIDC integration with Envoy
