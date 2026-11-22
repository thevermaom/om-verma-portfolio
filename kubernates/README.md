# Local Kubernetes (kind)

A learning cluster that runs **on my laptop inside Docker Desktop**. It costs nothing.

```
Browser → localhost:30080 → Service "web" (namespace om) → 3 nginx pods
                                                            on learn-worker / learn-worker2
Cluster = 3 Docker containers: learn-control-plane (brain) + 2 workers
```

| File | Purpose |
|---|---|
| `kind-config.yaml` | The cluster: 1 control plane + 2 workers, port 30080 opened |
| `app.yaml` | The app: Deployment (3 nginx pods) + Service (NodePort 30080), namespace `om` |

---

## Start / stop

```powershell
cd A:\Resume\kubernates                                      # ALWAYS first
kind create cluster --name learn --config kind-config.yaml   # create cluster (~2 min)
kubectl create namespace om                                  # create namespace
kubectl apply -f app.yaml                                    # deploy app
# open http://localhost:30080
kind delete cluster --name learn                             # delete everything
```

Docker Desktop must be running. One-time install: `winget install Kubernetes.kind`, then reopen the terminal.

---

## Everyday commands

| Task | Command |
|---|---|
| Nodes | `kubectl get nodes -o wide` |
| Everything in om | `kubectl get all -n om` |
| Pods + which node | `kubectl get pods -n om -o wide` |
| Pod details / errors | `kubectl describe pod -n om <pod>` |
| Events | `kubectl get events -n om --sort-by=.lastTimestamp` |
| Logs (all pods) | `kubectl logs -n om -l app=web --prefix --tail=20` |
| Watch my visits live | `kubectl logs -n om -l app=web --prefix -f \| Select-String -NotMatch "kube-probe"` |
| Shell inside a pod | `kubectl exec -it -n om <pod> -- sh` |
| Control plane parts | `kubectl get pods -n kube-system -o wide` |
| API server health | `kubectl get --raw='/readyz?verbose'` |

---

## Experiments

| Try | Learn |
|---|---|
| `kubectl delete pod -n om <pod>` | Self-healing: a new pod appears |
| `kubectl scale deployment web -n om --replicas=6` | Scaling |
| `kubectl set image deployment/web -n om web=nginx:1.28-alpine` | Rolling update |
| `kubectl rollout undo deployment/web -n om` | Rollback |
| `docker stop learn-worker` / `docker start learn-worker` | Node failure: NotReady after ~40 s, pods move after ~5 min |
| `kubectl drain learn-worker --ignore-daemonsets` / `kubectl uncordon learn-worker` | Planned maintenance |

---

## Key ideas

- **Pod** = container wrapper. **Deployment** keeps `replicas: 3` pods alive (like an ASG).
- **Service** = stable address that load-balances across pods (like an ALB).
- **readinessProbe** = health check. That's the `kube-probe` GET every 5 s in the logs.
- **Namespace** = a room in the cluster. `get/logs/describe` need `-n om`. `apply -f` reads it from the file.
- **Nodes and NodePorts** belong to the whole cluster, not a namespace.
- The **YAML file is the truth**: edit it, then `kubectl apply -f app.yaml`.
- Docker Desktop's **Kubernetes tab stays empty**. The kind cluster is in the **Containers** tab.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `path "app.yaml" does not exist` | `cd A:\Resume\kubernates` |
| `kind` not recognized | Reopen the terminal |
| `namespaces "om" not found` | `kubectl create namespace om` |
| `port is already allocated` | Another Service uses 30080 |
| No pods shown | Add `-n om` |
| Wrong cluster | `kubectl config use-context kind-learn` |
| `ImagePullBackOff` | Wrong image name/tag |
| `CrashLoopBackOff` | `kubectl logs -n om <pod> --previous` |
