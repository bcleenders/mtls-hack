#!/bin/bash

# Apply changes
kubectl apply -k service-workload/frontend/
kubectl apply -k service-workload/backend/

sleep 0.5

# Restart Pods so configmaps are re-read
kubectl rollout restart deployment -n frontend
kubectl rollout restart deployment -n backend

for i in $(seq 1 5); do
    sleep 2;
    echo "";
    echo "Waited $(($i * 2))s";
    kubectl get pods --all-namespaces | grep -E 'NAMESPACE|backend|frontend'
done
