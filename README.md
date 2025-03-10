Goal:

- [ ] Minikube cluster running SPIRE
- [ ] Run Envoy instances with mTLS
- [ ] Run multi-cluster
- [ ] Call natively (curl or gRPC) to Envoy
- [ ] OIDC integration with Envoy?


Minikube cluster running SPIRE

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

```
