#!/bin/bash

# Rollback script for Helm deployments
# This script provides safe rollback capabilities with verification

set -e

NAMESPACE="${NAMESPACE:-production}"
RELEASE_NAME="${RELEASE_NAME:-microservice-app}"
REVISION="${REVISION:-0}"  # 0 means previous revision

echo "🔄 Helm Rollback Script"
echo "======================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Target Revision: $REVISION (0 = previous)"
echo ""

# Function to check deployment health
check_deployment_health() {
    echo "🏥 Checking deployment health..."
    
    # Check if all pods are ready
    READY_PODS=$(kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED_PODS=$(kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo "Ready pods: $READY_PODS/$DESIRED_PODS"
    
    if [ "$READY_PODS" -eq "$DESIRED_PODS" ] && [ "$READY_PODS" -gt 0 ]; then
        echo "✅ Deployment is healthy"
        return 0
    else
        echo "❌ Deployment is unhealthy"
        return 1
    fi
}

# Show current release history
echo "📜 Current release history:"
helm history "$RELEASE_NAME" -n "$NAMESPACE" --max 10

echo ""
echo "🔍 Current deployment status:"
kubectl get deployment "$RELEASE_NAME" -n "$NAMESPACE"

echo ""
read -p "❓ Do you want to proceed with rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Rollback cancelled"
    exit 0
fi

# Perform rollback
echo ""
echo "🔄 Rolling back release..."

if [ "$REVISION" -eq 0 ]; then
    echo "Rolling back to previous revision..."
    helm rollback "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout 5m
else
    echo "Rolling back to revision $REVISION..."
    helm rollback "$RELEASE_NAME" "$REVISION" -n "$NAMESPACE" --wait --timeout 5m
fi

ROLLBACK_EXIT_CODE=$?

if [ $ROLLBACK_EXIT_CODE -ne 0 ]; then
    echo "❌ Rollback command failed with exit code: $ROLLBACK_EXIT_CODE"
    exit $ROLLBACK_EXIT_CODE
fi

# Wait for rollout to complete
echo ""
echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/"$RELEASE_NAME" -n "$NAMESPACE" --timeout=5m

# Verify deployment health
echo ""
if check_deployment_health; then
    echo ""
    echo "✅ Rollback completed successfully!"
    
    # Show new status
    echo ""
    echo "📊 Post-rollback status:"
    helm status "$RELEASE_NAME" -n "$NAMESPACE"
    
    # Show pod status
    echo ""
    echo "🐳 Pod status:"
    kubectl get pods -n "$NAMESPACE" -l app=microservice-app
    
    exit 0
else
    echo ""
    echo "⚠️  Rollback command completed but deployment may be unhealthy"
    echo "Please check the deployment manually:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app=microservice-app --tail=50"
    
    exit 1
fi
