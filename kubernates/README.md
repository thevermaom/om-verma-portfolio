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
├── practice/                         HANDS-ON labs: Deployment / StatefulSet / DaemonSet,
│                                     probes, volumes → see practice/README.md
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

## Grafana Cloud (same monitoring, online)

Local = only on my laptop (`localhost:3000`). Grafana Cloud = a **copy** online at
**https://orangeelephant1089.grafana.net**, opens from any browser, no port-forward.

```
LAPTOP (kind cluster)                                           INTERNET
Prometheus ──remote_write──→ alloy-cloud ──(URL + user + token)──→ Grafana Cloud Prometheus
pod logs ──────────────────→ alloy-cloud ──(URL + user + token)──→ Grafana Cloud Loki
local Prometheus / Loki / Grafana → unchanged
```

| File | What it does |
|---|---|
| `monitoring/11-grafana-cloud.yaml` | **alloy-cloud**: receives metrics from Prometheus + reads pod logs → sends both to Grafana Cloud |
| `monitoring/02-prometheus-config.yaml` | `remote_write` → pushes a copy to alloy-cloud (only dashboard metrics, `om`/`monitoring`) |
| `grafana-cloud/student-app-dashboard.json` | my dashboard, ready to import into Grafana Cloud |
| Secret `grafana-cloud` | URLs, users, token. **Created by hand, never in Git** (repo is public) |

Free plan: ~10k metric series, logs + metrics kept ~14 days. Data is sent **only while Docker Desktop is running**.

### Step 1 – Copy 4 values (browser)

1. Open **https://grafana.com/orgs/orangeelephant1089** (Grafana Cloud Portal).
2. Next to `orangeelephant1089` click **Details** (not *Launch*).
3. **Prometheus** box → **Details** → copy into Notepad:
   - `prom-url` = **Remote Write Endpoint** (ends with `/api/prom/push`)
   - `prom-user` = **Username / Instance ID** (a number)
4. **Loki** box → **Details** → copy:
   - `loki-url` = **URL** **+ type `/loki/api/v1/push` at the end**
   - `loki-user` = **User** (a number)

### Step 2 – Create the token (browser)

1. Same portal, left menu → **SECURITY → Access Policies** → **Create access policy**.
2. Name `laptop` → Scopes: tick **metrics: Write** and **logs: Write** → **Create**.
3. On the new policy → **Add token** → **Create** → copy `glc_...` (**shown only once**).

### Step 3 – Give the values to the cluster (PowerShell)

Replace every `<...>` **including the `< >`**. No spaces after `=`. Keep the `` ` `` at line ends.

```powershell
cd A:\Resume\kubernates
kubectl create secret generic grafana-cloud -n monitoring `
  --from-literal=prom-url=<Remote Write Endpoint> `
  --from-literal=prom-user=<Prometheus username> `
  --from-literal=loki-url=<Loki URL>/loki/api/v1/push `
  --from-literal=loki-user=<Loki user> `
  --from-literal=token=<glc_... token>
# → secret/grafana-cloud created
```

### Step 4 – Start sending

```powershell
kubectl apply -f monitoring/                                        # creates alloy-cloud
kubectl rollout restart deployment/prometheus deployment/alloy-cloud -n monitoring
kubectl get pods -n monitoring                                      # alloy-cloud 1/1 Running
```

### Step 5 – Check it is sending (PowerShell)

```powershell
# a) no errors in the last 5 minutes = good (no output)
kubectl logs -n monitoring deploy/alloy-cloud --since=5m | Select-String "level=error|level=warn"

# b) counters go UP each time you run the 2nd line
kubectl port-forward -n monitoring deploy/alloy-cloud 12345:12345   # terminal 1 (leave open)
curl.exe -s localhost:12345/metrics | Select-String "^loki_write_sent_entries_total|^prometheus_remote_storage_samples_total|status_code=`"204`""
```
Also: open **http://localhost:12345** (Alloy UI) → every component **green = healthy**.

### Step 6 – See it in Grafana Cloud (browser)

Open **https://orangeelephant1089.grafana.net** → **Explore** → time **Last 15 minutes** → **Code** → Run query:

| Data source | Query | Expect |
|---|---|---|
| `grafanacloud-...-prom` | `pg_up` | **1** (DB up) |
| `grafanacloud-...-prom` | `up{cluster="kind-learn"}` | lines at 1 |
| `grafanacloud-...-logs` | `{namespace="om", app="web"}` | website log lines |
| `grafanacloud-...-logs` | `{cluster="kind-learn"} \|= "POST"` | add / edit / delete clicks |

### Step 7 – Import the dashboard (browser)

1. **Dashboards → New → Import**.
2. Click **Upload dashboard JSON file** → `A:\Resume\kubernates\grafana-cloud\student-app-dashboard.json`
   (or paste the file's text in the big box → **Load**). Ignore red "required" messages before uploading.
3. Prometheus → pick **...-prom**, Loki → pick **...-logs** → **Import**.
4. **Dashboards → Student App on Kubernetes** – works from any browser.

### Change / remove

```powershell
# see one stored value (change loki-url to prom-url / prom-user / loki-user; don't print token)
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl get secret grafana-cloud -n monitoring -o jsonpath="{.data.loki-url}")))

# wrong value or new token → re-create the Secret, then restart the sender
kubectl delete secret grafana-cloud -n monitoring
kubectl create secret generic grafana-cloud -n monitoring ...      # Step 3 again
kubectl rollout restart deployment/alloy-cloud -n monitoring

# stop sending to the cloud (local monitoring keeps working)
kubectl delete -f monitoring/11-grafana-cloud.yaml
```

### Grafana Cloud not working? Check in this order

```
① Docker Desktop → ② pods running → ③ alloy-cloud sending → ④ Grafana Cloud showing
```
The first step that fails is the problem.

| Step | Command / where | ✅ OK | ❌ Problem → fix |
|---|---|---|---|
| ① Cluster on | `kubectl get nodes` | 3 nodes `Ready` | `Unable to connect` → open Docker Desktop, wait ~1 min |
| ② Pods | `kubectl get pods -n monitoring` | all `1/1 Running` (esp. `alloy-cloud`, `prometheus`) | `CrashLoopBackOff` / `CreateContainerConfigError` → `kubectl describe pod ...` |
| ③ Sender | `kubectl logs -n monitoring deploy/alloy-cloud --since=5m \| Select-String "level=error\|level=warn"` | no output | see table below |
| ④ Cloud | Explore, time = **Last 15 minutes** | `-prom`: `up{cluster="kind-learn"}` = 1 · `-logs`: `{cluster="kind-learn"}` shows recent lines | nothing → go back to ③ |

| Word in the log | Meaning | Fix |
|---|---|---|
| `401` / `unauthorized` | token wrong or expired | new token → re-create Secret → restart `alloy-cloud` |
| `404` | wrong URL in Secret | copy URLs again from grafana.com → stack → Details |
| `429` / `rate limit` | too much data for free plan | send fewer metrics (`write_relabel_configs` in `02`) |
| `TLS handshake timeout` / `no such host` | laptop slept / internet blip | fixes itself; check again in 2 min (that minute of data is missing) |

**Panels empty after Docker restart, but alloy-cloud has no errors?** Prometheus → Status → Targets shows
`kube-state-metrics` / `postgres` **DOWN** = the nodes lost the network route to each other.

```powershell
docker exec learn-worker ip route | Select-String "10.244"     # each OTHER node's 10.244.X.0/24 must be listed
kubectl rollout restart daemonset/kindnet -n kube-system       # kindnet rebuilds the routes
kubectl get pods -n om                                         # pods stuck "Unknown" → delete them, they come back
kubectl delete pod -n om <pod> --grace-period=0 --force
```

**Looks broken but isn't:**
- Time range too short (e.g. *Last 5 minutes* after laptop sleep) → use **Last 1 hour**.
- Wrong data source → use the ones ending **-prom** and **-logs** (not `-usage`).
- Laptop off / Docker closed → nothing is sent → gap in graphs. Normal.

### Reading the dashboard correctly

| Panel | Why it can look wrong |
|---|---|
| **Pod restarts = 5 (red)** | Not students. Docker was closed once → 3 web + postgres + exporter each restarted once. Red at ≥ 1. |
| **Students in table** | Uses Postgres's *estimate* (`n_live_tup`), not `COUNT(*)`. After Docker is closed suddenly the estimate resets. Fix: `kubectl exec -n om postgres-0 -- psql -U om_user -d portfolio_db -c "ANALYZE students;"` |
| **DB connections = 2** | Both are postgres-exporter: one connection always open + one opened during each scrape. The website connects per click and closes in ms, so it rarely shows. 3+ = busy website or someone in `psql`/DBeaver. |

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


# Artifacts for understanding Kubernates/monitoring 

https://claude.ai/artifact/MxE6JuQ8QN8BdUMo9aBozL


# Workloads , probes and volumes 

https://claude.ai/artifact/HXSsaupzfoYRxkbH3dmoZC#probes




