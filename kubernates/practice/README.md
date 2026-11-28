# Practice: Workloads, Probes, Volumes (hands-on)

One small YAML per idea. Everything runs in its own namespace **`practice`**, so the student app (`om`) is never touched.
Run every command in **PowerShell** from `A:\Resume\kubernates`. Docker Desktop must be running.

| File | Idea | Real-life picture |
|---|---|---|
| `00-namespace.yaml` | namespace `practice` | a separate room |
| `01-deployment.yaml` | **Deployment** | taxi drivers: any one will do |
| `02-statefulset.yaml` | **StatefulSet** | numbered bank lockers: each has its own contents |
| `03-daemonset.yaml` | **DaemonSet** | one security guard per building |
| `04-probes.yaml` | **startup / liveness / readiness probes** | a doctor checking a patient |
| `05-volume-emptydir.yaml` | **emptyDir** volume | a shared desk drawer, emptied when you leave |
| `06-volume-configmap-secret.yaml` | **ConfigMap / Secret** as files | a notice pinned to the wall |
| `07-volume-pvc.yaml` | **PersistentVolumeClaim** | a rented locker that keeps your stuff |
| `08-metrics-server.yaml` | **metrics-server** (in kube-system) | a thermometer for every pod |
| `09-hpa.yaml` | **HorizontalPodAutoscaler** + a CPU-hungry app | a shop opening more checkout counters |
| `10-load-generator.yaml` | fake visitors (load) | the rush hour |

```powershell
cd A:\Resume\kubernates
kubectl apply -f practice/00-namespace.yaml        # start: create the room
kubectl get pods -n practice -o wide -w            # (optional) live view in a 2nd terminal, Ctrl+C to stop
```

---

## Part 1 – Deployment vs StatefulSet vs DaemonSet

All three **create pods and keep them alive**. The difference is **how many**, **what names**, and **whether each has its own disk**.

| | Deployment | StatefulSet | DaemonSet |
|---|---|---|---|
| How many pods | you choose (`replicas: 3`) | you choose (`replicas: 2`) | **1 per node** (automatic) |
| Pod names | random: `hello-67564d987d-x2k4p` | fixed: `counter-0`, `counter-1` | random: `node-agent-gh5mg` |
| Own disk per pod | no | **yes** (`volumeClaimTemplates`) | no (usually reads the node's files) |
| Start order | all at once | in order 0 → 1 → 2 | one per node |
| Pod deleted → | new pod, **new name**, empty | **same name, same disk** | new pod on **the same node** |
| Use it for | websites, APIs (stateless) | databases, Kafka, anything with data | log collectors, monitoring agents, network |
| In my cluster | `web` (om), grafana, loki, prometheus | `postgres` (om) | `kube-proxy`, `kindnet` (kube-system) |

**Rule of thumb:** need one per node → DaemonSet. Needs its own data that must survive → StatefulSet. Everything else → Deployment.

### Lab 1 – Deployment

```powershell
kubectl apply -f practice/01-deployment.yaml
kubectl get pods -n practice -l app=hello -o wide       # 3 pods, random names, spread over nodes
```

| Try | Command | What you'll see |
|---|---|---|
| Self-healing | `kubectl delete pod -n practice <one hello pod>` then `kubectl get pods -n practice -l app=hello` | still 3 pods – a **new one with a new random name** (AGE a few seconds) |
| Scale up | `kubectl scale deployment hello -n practice --replicas=5` | 5 pods |
| Scale down | `kubectl scale deployment hello -n practice --replicas=2` | 2 pods (extra ones are removed) |
| Who owns them | `kubectl get deploy,rs,pods -n practice -l app=hello` | Deployment → ReplicaSet → Pods |

### Lab 2 – StatefulSet

```powershell
kubectl apply -f practice/02-statefulset.yaml
kubectl get pods -n practice -l app=counter -w          # counter-0 starts FIRST, then counter-1 (Ctrl+C)
kubectl get pvc -n practice                              # data-counter-0, data-counter-1 = one disk each
kubectl exec -n practice counter-0 -- cat /data/history.txt   # 1 line
```

Now delete it and watch it come back:

```powershell
kubectl delete pod counter-0 -n practice
kubectl get pods -n practice -l app=counter              # counter-0 is back – SAME NAME
kubectl exec -n practice counter-0 -- cat /data/history.txt   # 2 lines – SAME DISK
kubectl exec -n practice counter-1 -- cat /data/history.txt   # still 1 line – its own separate disk
```

Expected:
```
Wed Nov 25 16:14:55 UTC 2026 - started as counter-0
Wed Nov 25 16:16:05 UTC 2026 - started as counter-0
```
This is exactly why `postgres-0` keeps your students after a restart.

### Lab 3 – DaemonSet

```powershell
kubectl apply -f practice/03-daemonset.yaml
kubectl get pods -n practice -l app=node-agent -o wide   # 3 pods: control-plane, worker, worker2
kubectl logs -n practice -l app=node-agent --prefix --tail=2
kubectl get daemonsets -A                                # also kube-proxy and kindnet: same idea
```

| Try | How | What you'll see |
|---|---|---|
| No replicas field | open `03-daemonset.yaml` | there is **no** `replicas:` – the number = number of nodes |
| Delete one | `kubectl delete pod -n practice <node-agent pod>` | replaced **on the same node** |
| Remove the toleration | delete the 4 `tolerations:` lines, `kubectl delete -f practice/03-daemonset.yaml`, `kubectl apply -f practice/03-daemonset.yaml` | only **2** pods – the control-plane has a "keep out" sign (taint). Put the lines back after. |

---

## Part 2 – Probes (health checks)

Kubernetes can't know if your app is OK just because the process is running. A **probe** is a small check it runs again and again.

| Probe | Question | If it fails | Use it when |
|---|---|---|---|
| **startupProbe** | "Have you finished starting?" | keeps waiting; too long → **restart** | app is slow to start (Java, big DB migration) |
| **livenessProbe** | "Are you alive, not frozen?" | **restart** the container | app can hang/deadlock without crashing |
| **readinessProbe** | "Can you take visitors right now?" | **remove from Service** (no traffic), **no restart** | app is busy / warming up / its DB is down |

```
time →  0s ───────── 20s ────────────────────────────────────────────→
        [startup probe checking...] ✅ started
                                    then liveness + readiness every 5 s
        READY 0/1                   READY 1/1 → Service sends traffic
```

How a probe checks (pick one): `httpGet` (URL returns 200–399), `tcpSocket` (port opens), `exec` (command exits 0).
Timing: `periodSeconds` = how often, `failureThreshold` = how many fails in a row before acting.

**Golden rule:** liveness must check only *this* app. If liveness checked the database, a DB outage would restart every web pod for nothing – that's readiness's job.

In this demo the app is controlled by 3 files: `/tmp/started`, `/tmp/alive`, `/tmp/ready`. Each probe just does `cat` on its file. You "break" the app by deleting a file.

### Lab 4 – Probes

```powershell
kubectl apply -f practice/04-probes.yaml
kubectl get pod probe-demo -n practice -w        # READY 0/1 for ~20 s (startup), then 1/1 (Ctrl+C)
kubectl describe pod probe-demo -n practice | Select-String "Startup|Liveness|Readiness"
```

**A) Readiness fails → no traffic, NO restart**
```powershell
kubectl exec -n practice probe-demo -- rm /tmp/ready
kubectl get pod probe-demo -n practice            # READY 0/1, RESTARTS 0
kubectl get endpoints probe-demo -n practice      # ENDPOINTS empty → Service sends nothing
kubectl exec -n practice probe-demo -- touch /tmp/ready
kubectl get pod probe-demo -n practice            # back to READY 1/1
kubectl get endpoints probe-demo -n practice      # 10.244.x.x:8080 is back
```

**B) Liveness fails → RESTART**
```powershell
kubectl exec -n practice probe-demo -- rm /tmp/alive
kubectl get pod probe-demo -n practice -w         # ~10 s later RESTARTS 1, then 20 s startup again (Ctrl+C)
kubectl get events -n practice --field-selector involvedObject.name=probe-demo
#   → "Container app failed liveness probe, will be restarted"
```

**C) Startup** – edit `04-probes.yaml`: change `sleep 20` to `sleep 90` (longer than the 60 s allowed), then:
```powershell
kubectl delete -f practice/04-probes.yaml; kubectl apply -f practice/04-probes.yaml
kubectl get pod probe-demo -n practice -w         # after 60 s it is restarted again and again
```
Put `sleep 20` back and re-apply.

My real app uses only **readinessProbe** (web `/healthz`, postgres `pg_isready`, prometheus `/-/ready`, ...).

---

## Part 3 – Volumes (how files get into a container)

A container's own files are **thrown away** when it restarts. A **volume** is a folder that comes from outside the container.

Every volume needs **2 parts**, joined by the same `name`:

```yaml
spec:
  volumes:                    # 1) WHAT: the storage (pod level)
    - name: shared            #        ← same name
      emptyDir: {}
  containers:
    - volumeMounts:           # 2) WHERE: folder inside the container
        - name: shared        #        ← same name
          mountPath: /shared
```

| Type | Lives as long as | Use it for | Lab |
|---|---|---|---|
| `emptyDir` | the **pod** | scratch / cache / share files between containers | 5 |
| `configMap` | the ConfigMap object | config files (prometheus.yml, loki.yaml...) | 6 |
| `secret` | the Secret object | passwords, keys, certificates as files | 6 |
| `persistentVolumeClaim` | **until you delete the PVC** | databases, uploads, anything important | 7 (and 2) |
| `hostPath` | the node | reading the node's own files (DaemonSets). Avoid for apps. | – |

| What survives? | container restart | pod deleted | `kind delete cluster` |
|---|---|---|---|
| files inside the container (no volume) | ❌ | ❌ | ❌ |
| emptyDir | ✅ | ❌ | ❌ |
| configMap / secret | ✅ | ✅ (comes from the object) | ❌ |
| PVC | ✅ | ✅ | ❌ |

### Lab 5 – emptyDir (2 containers share one folder)

```powershell
kubectl apply -f practice/05-volume-emptydir.yaml
kubectl get pod volume-emptydir -n practice                   # READY 2/2 = two containers
kubectl logs -n practice volume-emptydir -c reader --tail=3   # reader shows what writer wrote
kubectl exec -n practice volume-emptydir -c reader -- wc -l /shared/log.txt
kubectl delete pod volume-emptydir -n practice
kubectl apply -f practice/05-volume-emptydir.yaml
kubectl exec -n practice volume-emptydir -c reader -- wc -l /shared/log.txt   # back to ~1 line: emptyDir was wiped
```

### Lab 6 – ConfigMap and Secret as files

```powershell
kubectl apply -f practice/06-volume-configmap-secret.yaml
kubectl exec -n practice volume-config -- ls /etc/app /etc/secret      # each key = one file
kubectl exec -n practice volume-config -- cat /etc/app/settings.yaml
kubectl exec -n practice volume-config -- cat /etc/secret/password
kubectl logs -n practice volume-config --tail=2                         # "greeting = Hello from a ConfigMap!"
```

Change the ConfigMap **while the pod runs**:
```powershell
kubectl edit configmap app-settings -n practice      # change greeting.txt text, save, close Notepad
kubectl logs -n practice volume-config -f            # within ~1 min the new text appears – no restart! (Ctrl+C)
```
(Env variables from `envFrom` do **not** update like this – the pod must be restarted.)

### Lab 7 – PVC (a disk that survives)

```powershell
kubectl apply -f practice/07-volume-pvc.yaml
kubectl get pvc,pv -n practice                        # notes-disk Bound → a PV pvc-xxxx was made for it
kubectl exec -n practice volume-pvc -- cat /data/notes.txt          # 1 line
kubectl delete pod volume-pvc -n practice
kubectl apply -f practice/07-volume-pvc.yaml
kubectl exec -n practice volume-pvc -- cat /data/notes.txt          # 2 lines – data survived
```

The chain: **Pod** → `claimName: notes-disk` → **PVC** (request 50Mi) → **StorageClass** `standard` → **PV** (real folder on the node).

---

## Part 4 – Autoscaling (metrics-server + HorizontalPodAutoscaler)

**Problem:** with `replicas: 3` you guess the number. Too few → slow site at rush hour. Too many → wasted CPU/money at night.
**HPA:** Kubernetes changes `replicas` **by itself**, based on how busy the pods are.

```
            every 15 s                     every 15 s
 kubelet ───────────────→ metrics-server ───────────→ HPA ──"replicas: 4"──→ Deployment ──→ pods
 (each node: CPU/RAM      (the thermometer,           (the manager:          (makes / removes
  of every pod)            keeps only "now")           compares with goal)     pods)
```

| Piece | Job | Without it |
|---|---|---|
| **metrics-server** | measures CPU / memory of every pod *right now* | `kubectl top` → "Metrics API not available", HPA shows `<unknown>` |
| **resources.requests.cpu** | the "100%" mark: `200m` request → 100m used = 50% | HPA can't calculate a % → never scales |
| **HPA** | compares CPU % with the goal, changes `replicas` | you scale by hand (`kubectl scale`) |

**The formula** (every 15 s):
```
wanted pods = current pods × (current CPU % ÷ goal %)      → rounded UP, kept between min and max
example:      1 pod × (250% ÷ 50%) = 5 pods
```

| Words | Meaning |
|---|---|
| Horizontal | **more pods** (this lab). *Vertical* = bigger pods (more CPU each) – a different tool (VPA) |
| `minReplicas` / `maxReplicas` | the floor and the ceiling. Max protects your laptop / cloud bill |
| `averageUtilization: 50` | the goal: average CPU across pods = 50% of the request |
| scale up | fast (within ~15–30 s) |
| scale down | slow on purpose: waits `stabilizationWindowSeconds` (default **5 min**, 60 s here) so it doesn't flap up/down |
| Prometheus vs metrics-server | Prometheus = **history** for graphs. metrics-server = **only now**, for `kubectl top` + HPA. Different jobs. |

### Lab 8 – Install the thermometer (once per cluster)

```powershell
kubectl apply -f practice/08-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system
kubectl top nodes                      # wait ~1 min if it says "not available yet"
kubectl top pods -n om                 # CPU / memory of your student app pods
```

### Lab 9 – App + autoscaler

```powershell
kubectl apply -f practice/00-namespace.yaml
kubectl apply -f practice/09-hpa.yaml
kubectl get hpa -n practice            # first ~1 min: cpu: <unknown>/50%  (normal – no reading yet)
                                       # then:        cpu: 0%/50%   REPLICAS 1
```

### Lab 10 – Rush hour: watch it scale

Open **2 terminals**:
```powershell
# terminal 1 – live view (Ctrl+C to stop)
kubectl get hpa cpu-app -n practice -w

# terminal 2 – start the fake visitors
kubectl apply -f practice/10-load-generator.yaml
kubectl get pods -n practice -l app=cpu-app -w       # new pods appear
kubectl top pods -n practice                         # CPU per pod
```

What happened when I tested it:
```
time  | CPU now / goal | pods
  0s  |   0% / 50%     | 1
 34s  | 161% / 50%     | 1 → creating more
 51s  | 250% / 50%     | 4        ← 1 × 250/50 = 5 wanted
 68s  | 145% / 50%     | 5        ← maxReplicas reached
141s  |  55% / 50%     | 5        ← work shared by 5 pods → back near the goal
```

Stop the rush hour and watch it shrink:
```powershell
kubectl delete -f practice/10-load-generator.yaml
kubectl get hpa cpu-app -n practice -w        # CPU → 0%, ~60–90 s later 5 → 2 → 1 pods
kubectl describe hpa cpu-app -n practice      # Events: "New size: 5 ... New size: 1; All metrics below target"
```

| Try | Change in `09-hpa.yaml` → `kubectl apply -f practice/09-hpa.yaml` | Expect |
|---|---|---|
| Higher ceiling | `maxReplicas: 8` | goes up to 8 pods under load |
| Easier goal | `averageUtilization: 80` | fewer pods needed for the same load |
| No request | delete `requests: cpu: 200m` | HPA shows `<unknown>` – can't scale |

`FailedGetResourceMetric` warnings in the first minute = metrics-server had no reading yet. Normal.

---

## Clean up

```powershell
kubectl delete namespace practice      # deletes EVERYTHING in practice, including the PVC disks
kubectl get pv                         # practice disks disappear too (reclaimPolicy Delete)
kubectl delete -f practice/08-metrics-server.yaml   # only if you also want to remove metrics-server (kube-system)
```

Start again: apply the files **one by one** as in the labs.
(`kubectl apply -f practice/` would also start the load generator → CPU stays busy until you delete it.)

Visual explainer (diagrams + simulators): https://claude.ai/artifact/HXSsaupzfoYRxkbH3dmoZC
