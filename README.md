Goal:

- [x] Minikube cluster running SPIRE
- [ ] Run Envoy instances with mTLS
- [ ] Run multi-cluster
- [ ] Call natively (curl or gRPC) to Envoy
- [ ] OIDC integration with Envoy?


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

