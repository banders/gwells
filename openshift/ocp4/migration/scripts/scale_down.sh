#!/bin/bash
# Scales down the gwells application on Pathfinder
# add --revert to end (after test/prod) to scale back to 2 on Pathfinder.
# i.e. ./scale_down.sh test --revert

# Get variables from previous scripts or params
ENVIRONMENT=${ENVIRONMENT:-$1}
. ./params.sh "$ENVIRONMENT"
. ./require_pathfinder_auth.sh

set -euo pipefail
if echo $* | grep -e "--revert" -q
then
	# revert to 2 replicas
    echo "Scaling back to 2 replicas on Pathfinder ($NAMESPACE ; env: $POD_SUFFIX)"

    oc --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" scale "dc/gwells-$POD_SUFFIX" --replicas=2
    echo "Scaled to 2 replicas"

else
    echo "Scaling down on Pathfinder ($NAMESPACE ; env: $POD_SUFFIX)"
    oc --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" scale "dc/gwells-$POD_SUFFIX" --replicas=0
    REPLICAS=$(oc --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" get dc "gwells-$POD_SUFFIX" -o go-template="{{.status.replicas}}")
    while [ "$REPLICAS" != 0 ]
    do
        echo "Waiting for GWELLS to scale down (current replicas: ${REPLICAS})"
        sleep 1
        REPLICAS=$(oc --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" get dc "gwells-$POD_SUFFIX" -o go-template="{{.status.replicas}}")
    done
    echo "Successfully scaled down (current replicas: ${REPLICAS})"
fi