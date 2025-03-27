# Distributed SPIRE setup

Application order:

## Terraform setup
```sh
# Create the clusters
pushd terraform
terraform apply
popd

# Load cluster contexts
gcloud container clusters list --format="value[delimiter=' '](name,zone)" | \
    xargs -n 2 sh -c 'gcloud container clusters get-credentials $1 --region=$2 --dns-endpoint' sh

    # Fetching cluster endpoint and auth data.
    # kubeconfig entry generated for mtls-hack-0.
    # Fetching cluster endpoint and auth data.
    # kubeconfig entry generated for mtls-hack-1.

kubectl config rename-context gke_my-project_europe-west4-b_mtls-hack-0 mtls-hack-0
kubectl config rename-context gke_my-project_europe-west4-b_mtls-hack-1 mtls-hack-1
```

## Deploy SPIRE on each cluster

```sh
cd ./k8s-config

# In this demo we'll use cluster 0 and 1
export last_cluster=1;

for i in `seq 0 1 $last_cluster`; do
    kubectl --context=mtls-hack-$i apply -k spire-installation/overlays/cluster-$i
done
```

Note: you may have to run this a few times... I didn't pay attention to the ordering yet.

## Setting up federation

Somewhat summarising, we are:

1. Fetching the public keys of all spire servers (CAs).
2. Pushing them to all (other) clusters, as "trusted".

So the data we are dealing with is not secret, but its integrity is very important!

The below script is adopted from [these docs](https://github.com/spiffe/spire-controller-manager/blob/main/demo/scripts/make-cluster-federated-trust-domain.sh).

Create all trust bundles:

```sh
export last_cluster=1;

rm -Rf .tmp
mkdir .tmp/

for i in `seq 0 1 $last_cluster`; do
    endpointIp=$(kubectl --context=mtls-hack-$i -n spire \
        get service spire-server-bundle-endpoint -ojson \
        | jq -r '.status.loadBalancer.ingress[0].ip') \
    endpointAddr="$endpointIp:8443" \
    bundleContents=$(kubectl --context=mtls-hack-$i -n spire \
        exec statefulset/spire-server -c spire-server -- \
            /opt/spire/bin/spire-server bundle show --format=spiffe) \
    trustDomain="cluster-$i.k8s.spire.cxcc.nl" \
    resourceName="cluster-$i" \
    bundleEndpointURL="https://${endpointAddr}" \
    endpointSPIFFEID="spiffe://cluster-$i.k8s.spire.cxcc.nl/spire/server" \
    yq eval -n '{
        "apiVersion": "spire.spiffe.io/v1alpha1",
        "kind": "ClusterFederatedTrustDomain",
        "metadata": {
            "name": strenv(resourceName)
        },
        "spec": {
            "trustDomain": strenv(trustDomain),
            "bundleEndpointURL": strenv(bundleEndpointURL),
            "bundleEndpointProfile": {
                "type": "https_spiffe",
                "endpointSPIFFEID": strenv(endpointSPIFFEID)
            },
            "trustDomainBundle": strenv(bundleContents)
        }
    } | . headComment=("Apply to all clusters, except " + strenv(resourceName))' \
    > ./.tmp/cluster-$i-trust-bundle.yaml;
done
```

Now apply the trust bundles to all clusters (except the cluster that the trust bundle was for):

```sh
for from in `seq 0 1 $last_cluster`; do
    for to in `seq 0 1 $last_cluster`; do
        if [ $from -ne $to ]; then
            echo "Applying trust bundle of cluster-$from to cluster-$to";
            kubectl --context=mtls-hack-$to apply -f .tmp/cluster-$from-trust-bundle.yaml
        fi
    done
done
```

## Create some workloads

```sh
# Create
for i in `seq 0 1 $last_cluster`; do
    kubectl --context=mtls-hack-$i apply -k ./spire-installation/overlays/cluster-$i
    kubectl --context=mtls-hack-$i apply -k ./service-workload/overlays/cluster-$i
done

# Delete
for i in `seq 0 1 $last_cluster`; do
    kubectl --context=mtls-hack-$i delete -k ./spire-installation/overlays/cluster-$i
    kubectl --context=mtls-hack-$i delete -k ./service-workload/overlays/cluster-$i
done
```

## Debugging...

### Viewing logs
```sh
# Backend
kubectl --context=mtls-hack-0 -n backend logs -f -l app=backend -c envoy --tail -1
# Frontend
kubectl --context=mtls-hack-1 -n frontend logs -f -l app=frontend -c envoy --tail -1
```

```sh
kubectl --context=mtls-hack-0 exec -n playground pod test-pod

apt -qq update; apt -qq install -y curl

# Hit frontend
curl -v frontend.frontend.svc.cluster.local:8080/

# Hit frontend -> backend (this may be cross-cluster!)
curl -v frontend.frontend.svc.cluster.local:8080/backend/
```

Additional work:
- Added A records for the trust domains to point to the external LBs, created in the `spire-server-bundle-endpoint` Service.