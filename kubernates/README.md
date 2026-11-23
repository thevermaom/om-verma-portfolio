# Local Kubernetes (kind)

A learning cluster that runs **on my laptop inside Docker Desktop**. It costs nothing.
It runs a small **Student Records** website that stores data in **PostgreSQL**.

```
Browser → localhost:30080 → Service web → 3 student-app pods ─┐ DB settings from
                                                               │ ConfigMap + Secret
                                         Service postgres → postgres-0 (+ 1Gi disk)

Cluster = 3 Docker containers: learn-control-plane (brain) + learn-worker + learn-worker2
```

## Folder

```
kubernates/
├── kind-config.yaml                  the CLUSTER: 1 control plane + 2 workers, port 30080
├── manifests/                        the APP (applied in number order)
│   ├── 00-namespace.yaml             namespace "om"
│   ├── 01-db-configmap.yaml          DB_HOST, DB_PORT, DB_NAME, DB_USER
│   ├── 02-db-secret.yaml             DB_PASSWORD (dummy)
│   ├── 03-postgres-service.yaml      stable name "postgres" (internal only)
│   ├── 04-postgres-statefulset.yaml  the database + its disk
│   ├── 05-web-deployment.yaml        the website, 3 pods
│   └── 06-web-service.yaml           opens localhost:30080
└── student-app/                      website code (Python Flask + HTML)
    ├── app.py                        CREATE / READ / UPDATE / DELETE → SQL
    ├── templates/                    index.html (list, add, search), edit.html
    ├── static/style.css
    ├── Dockerfile
    └── requirements.txt
```

---

## Start / stop

```powershell
cd A:\Resume\kubernates                                      # ALWAYS first
kind create cluster --name learn --config kind-config.yaml   # 1. cluster (~2 min)

cd student-app                                               # 2. build the website image
docker build -t student-app:1.0 .
kind load docker-image student-app:1.0 --name learn          #    copy it into the cluster
cd ..

kubectl apply -f manifests/                                  # 3. deploy everything
kubectl get pods -n om                                       # 4. wait for Running
# open http://localhost:30080

kind delete cluster --name learn                             # delete everything (data too)
```

Docker Desktop must be running. One-time install: `winget install Kubernetes.kind`, then reopen the terminal.

## Update the website code

```powershell
cd A:\Resume\kubernates\student-app
docker build -t student-app:1.1 .                  # new version number every time
kind load docker-image student-app:1.1 --name learn
# edit manifests/05-web-deployment.yaml → image: student-app:1.1
kubectl apply -f ..\manifests\                     # rolling update, no downtime
```

---

## Database

```powershell
kubectl exec -it -n om postgres-0 -- psql -U om_user -d portfolio_db   # open SQL shell
```

```sql
\dt                                            -- list tables
SELECT * FROM students;                        -- read
INSERT INTO students (name, email, course, marks) VALUES ('Test', 't@example.com', 'Maths', 60);
UPDATE students SET marks = 100 WHERE name = 'Test';
SELECT course, COUNT(*), AVG(marks) FROM students GROUP BY course;
DELETE FROM students WHERE name = 'Test';
\q                                             -- quit
```

| Website button | HTTP | SQL |
|---|---|---|
| Page loads / Search | `GET /` , `GET /?q=..` | `SELECT ... WHERE ... ILIKE` |
| Add | `POST /add` | `INSERT` |
| Edit → Save | `POST /edit/<id>` | `UPDATE ... WHERE id =` |
| Delete | `POST /delete/<id>` | `DELETE ... WHERE id =` |

**Is the DB working?**
`kubectl exec -n om postgres-0 -- pg_isready -U om_user -d portfolio_db` → `accepting connections`

**Open it in a DB tool (DBeaver / VS Code):** run `kubectl port-forward -n om svc/postgres 5432:5432`,
then connect to `localhost:5432`, db `portfolio_db`, user `om_user`, password `dummy-password-123`.

---

## Monitoring (Prometheus + Loki + Grafana)

```
numbers: pods / postgres-exporter / kube-state-metrics ─→ Prometheus ─┐
logs:    every pod ─→ Alloy (collector) ─→ Loki ───────────────────────┴→ Grafana (one screen)
```

Files are in `monitoring/` (namespace `monitoring`, plus `postgres-exporter` in `om`).
`09-loki.yaml` stores logs, `10-alloy.yaml` collects them from every pod.

```powershell
kubectl apply -f monitoring/                                    # deploy (once)
kubectl port-forward -n monitoring svc/grafana 3000:3000        # terminal 1 → http://localhost:3000  (admin / admin123)
kubectl port-forward -n monitoring svc/prometheus 9090:9090     # terminal 2 → http://localhost:9090
```

Grafana → Dashboards → Kubernetes → **Student App on Kubernetes**.
Prometheus → Status → **Targets**: all should be `UP`.

| Panel | PromQL |
|---|---|
| Web pods ready | `kube_deployment_status_replicas_available{namespace="om",deployment="web"}` |
| Database up | `pg_up` |
| Students in table | `pg_stat_user_tables_n_live_tup{relname="students"}` |
| CPU per pod | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="om",container!=""}[2m]))` |

**Logs:** Grafana → **Explore** → pick **Loki** → switch to **Code** → type a LogQL query → Run query.

| Want | LogQL |
|---|---|
| All website logs | `{namespace="om", app="web"}` |
| Only POST requests (add/edit/delete) | `{namespace="om", app="web"} \|= "POST"` |
| Errors anywhere | `{namespace=~".+"} \|~ "(?i)error"` |
| Database logs | `{namespace="om", app="postgres"}` |
| Requests per minute | `sum(count_over_time({namespace="om", app="web"} \|= "GET" [1m]))` |

`{...}` picks the streams (by label), `|= "x"` keeps lines containing x, `|~` uses a regex.
After changing `06-grafana-config.yaml`: `kubectl rollout restart deployment/grafana -n monitoring`.

Remove: `kubectl delete -f monitoring/`

---

## Everyday commands

| Task | Command |
|---|---|
| Everything in om | `kubectl get all -n om` |
| Pods + which node | `kubectl get pods -n om -o wide` |
| Pod details / errors | `kubectl describe pod -n om <pod>` |
| Events | `kubectl get events -n om --sort-by=.lastTimestamp` |
| Website logs (live) | `kubectl logs -n om -l app=web --prefix -f` |
| Database logs | `kubectl logs -n om postgres-0` |
| Nodes | `kubectl get nodes -o wide` |
| Control plane parts | `kubectl get pods -n kube-system -o wide` |

## Experiments

| Try | Learn |
|---|---|
| `kubectl delete pod -n om <web-pod>` | Self-healing: a new pod appears |
| `kubectl delete pod -n om postgres-0` | StatefulSet: same name, same disk, data still there |
| `kubectl scale deployment web -n om --replicas=6` | Scaling |
| `kubectl rollout undo deployment/web -n om` | Rollback to the previous image |
| `kubectl scale statefulset postgres -n om --replicas=0` | DB off → website errors. `--replicas=1` to fix |
| `docker stop learn-worker` / `docker start learn-worker` | Node failure |

---

## Key ideas

- **Deployment** keeps N identical pods alive (like an ASG). **StatefulSet** is for databases: fixed name + own disk.
- **Service** = stable name/address in front of pods (like an ALB).
- **ConfigMap** = normal settings, **Secret** = passwords. Pods get them as env variables (`envFrom`).
- **Namespace** `om`: `get/logs/describe` need `-n om`. `apply -f` reads it from the file.
- The **YAML files are the truth**: edit them, then `kubectl apply -f manifests/`.
- Kind nodes can't see laptop images → always `kind load docker-image` after `docker build`.
- PostgreSQL reads the password **only on first start**. Changing it later breaks the login.
- Docker Desktop's **Kubernetes tab stays empty**. The kind cluster is in the **Containers** tab.

## Troubleshooting

| Problem | Fix |
|---|---|
| `path ... does not exist` | `cd A:\Resume\kubernates` |
| Browser still shows an old page | Hard refresh: **Ctrl+Shift+R** |
| `Unable to connect to the server` | Docker Desktop is closed → start it, wait ~1 min |
| `ErrImageNeverPull` / `ImagePullBackOff` on web | Forgot `kind load docker-image ...` or wrong tag |
| Web pod stuck `Init:0/1` | Waiting for the database → check `postgres-0` |
| `password authentication failed` | Password changed after DB was created |
| `CrashLoopBackOff` | `kubectl logs -n om <pod> --previous` |
| No pods shown | Add `-n om` |
| Wrong cluster | `kubectl config use-context kind-learn` |
