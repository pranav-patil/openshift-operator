#!/bin/bash

if oc whoami &>/dev/null; then
  echo "✅ Logged in as $(oc whoami)"
else
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

if kubectl get crd zyroncontainersecurities.container-security.emprovise.com >/dev/null 2>&1; then
  kubectl get zyroncontainersecurities.container-security.emprovise.com --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"\n"}{end}' | while IFS="|" read namespace name; do
    echo "Patching $name in namespace $namespace"
    kubectl patch zyroncontainersecurities.container-security.emprovise.com "$name" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge
    kubectl delete zyroncontainersecurities.container-security.emprovise.com "$name" -n "$namespace" --ignore-not-found
  done
else
  echo "CRD zyroncontainersecurities.container-security.emprovise.com not found."
fi

oc get daemonset -n emprovise-system -o name --ignore-not-found | while read daemon; do
  oc delete "$daemon" -n emprovise-system --grace-period=0 --force --ignore-not-found
done

oc get deployments -n emprovise-system -o name --ignore-not-found | while read deploy; do
  oc scale "$deploy" -n emprovise-system --replicas=0
  oc delete "$deploy" -n emprovise-system --grace-period=0 --force --ignore-not-found
done

kubectl get clusterrole,clusterrolebinding -l "app.kubernetes.io/managed-by=Helm" -A -o name | xargs kubectl delete --ignore-not-found=true
kubectl get scc -o name | grep emprovise-container-security | xargs kubectl delete --ignore-not-found=true
kubectl get serviceaccounts --all-namespaces -o name | grep -E 'emprovise|zyron' | xargs kubectl delete --ignore-not-found=true
kubectl get secrets -n emprovise-system -o name | grep -E 'emprovise|zyron' | xargs kubectl delete -n emprovise-system --ignore-not-found=true

kubectl get crd -o custom-columns=NAME:.metadata.name,PLURAL:.spec.names.plural | grep container-security.emprovise.com | while read -r crd_name plural_name; do
    crd_short_name=$(echo "$crd_name" | sed 's/customresourcedefinition.v1.apiextensions.k8s.io\///')
    echo "Processing CRD: $crd_short_name"

    if [ -z "$plural_name" ]; then
        echo "⚠️ Could not determine the resource plural name for $crd_short_name. Skipping resource deletion."
    else
        echo "🔥 Finding all resources of type '$plural_name' to remove their finalizers..."
        resources=$(kubectl get "$plural_name" --all-namespaces -o name --ignore-not-found)

        if [ -z "$resources" ]; then
          echo "✅ No custom resources of type '$plural_name' found."
        else
          echo "$resources" | xargs -r -n 1 kubectl patch --type='merge' -p '{"metadata":{"finalizers":[]}}'
          echo "Patched resources to remove finalizers. Waiting for deletion..."
          sleep 5
        fi
    fi

    kubectl delete crd "$crd_name" --timeout=5s --ignore-not-found
done

kubectl delete -f config/crd/bases/container-security.emprovise.com_zyroncontainersecurities.yaml --ignore-not-found

operator-sdk cleanup zyron-containersecurity --namespace emprovise-system
kubectl delete -k config/olm --ignore-not-found

kubectl get csv  -n emprovise-system -o name --ignore-not-found | grep '^clusterserviceversion\.operators\.coreos\.com/zyron-containersecurity' | xargs kubectl delete -n emprovise-system --ignore-not-found

kubectl delete -k config/rbac --ignore-not-found
kubectl delete secret docker-registry ecr-secret -n emprovise-system --ignore-not-found
kubectl delete namespace emprovise-system --ignore-not-found

make clean
rm -rf preflight_results
