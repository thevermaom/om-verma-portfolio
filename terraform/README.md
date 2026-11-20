# Terraform on AWS: Network + Ubuntu Server + Website + S3 Buckets + Load Balancer + Auto Scaling

**What this folder builds (with one command):**
a private network in AWS → an Ubuntu server I can SSH into → my portfolio website on it → some S3 buckets.
Terraform's state file is kept safely in S3.
On top of that (by hand in the console): a **load balancer** and an **Auto Scaling Group** that adds servers when traffic is high (section 9).

Region: **Mumbai (`ap-south-1`)** · AWS login: profile **`terraform`** (IAM user `terraform-user`)

---

## ⚡ Quick start (when I come back after months)

```powershell
cd A:\Resume\terraform
$env:AWS_PROFILE = "terraform"                          # log in to AWS as terraform-user
$ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()   # my current public IP

terraform init                                          # get ready (safe to run anytime)
terraform plan    -var="my_ip=$ip"                      # preview: changes nothing
terraform apply   -var="my_ip=$ip"                      # build/update → type yes
terraform output                                        # show IP, website URL, SSH command
terraform destroy -var="my_ip=$ip"                      # delete everything → type yes
```

| I want to… | Do this |
| --- | --- |
| Log in to the server | `ssh -i ~/.ssh/tf-ec2-key ubuntu@<public_ip>` (**no quotes**) |
| Open the website | `http://load-balancer-1459340471.ap-south-1.elb.amazonaws.com` (**http, not https**). Server IPs are blocked on purpose (see [section 9](#9-load-balancer--auto-scaling)) |
| Update the website | Rebuild the Docker image on server A → new AMI → new launch template version (see section 9) |
| Test auto scaling | Section 9, Part F |
| Add / remove a bucket | Edit the `bucket_names` list in `variable.tf` → `plan` → `apply` |

> ⚠️ When Terraform asks `Enter a value:`, **click inside the terminal first**, then type `yes`. (I once typed `yes` into this README by mistake and wiped it.)

---

## 1. The big picture

| AWS piece | Think of it as | Job |
| --- | --- | --- |
| **VPC** | My fenced plot of land | My private network in AWS |
| **Subnet** | A room in the building | Part of the VPC. **Public** = internet, **private** = no internet |
| **Internet gateway** | The front door | Connects the VPC to the internet |
| **Route table** | Hallway signs | Sends internet traffic to the front door |
| **Security group** | Guard at the door | Firewall: who can connect, on which port |
| **Key pair** | Lock + key | AWS gets the lock (public key), I keep the key (private key) |
| **EC2** | The computer | My Ubuntu server |

```
My laptop ──► Internet Gateway ──► Route Table ──► Public Subnet ──► Security Group ──► Ubuntu EC2
```

**If any link is missing, I can't connect.**

---

## 2. Words to remember

| Word | Meaning |
| --- | --- |
| `resource` | Something Terraform **creates** |
| `data` | Something Terraform **looks up** (e.g. latest Ubuntu image) |
| `variable` | A setting I can change |
| `output` | Info printed after `apply` |
| **CIDR** | IP range. `/16` = 65k addresses, `/24` = 256, `/32` = exactly 1 |
| `0.0.0.0/0` | "Anywhere on the internet" |
| **AMI** | Operating system image (Ubuntu 24.04) |
| Port **22** / **80** | SSH login / website (`http://`) |
| **nginx** | Program on the server that serves web pages |
| **State file** | Terraform's notebook of what it built. Lives in S3. **Never edit or delete it** |

---

## 3. My files

```
terraform/
├── version.tf     ← AWS plugin, region, and S3 backend (where the state lives)
├── variable.tf    ← settings: IP ranges, my_ip, key path, bucket names
├── main.tf        ← S3 buckets: 1 single + many via for_each loop
├── network.tf     ← VPC, subnets, internet gateway, route tables
├── ec2.tf         ← Ubuntu image, security group, key pair, EC2 server
├── website.tf     ← copies my website to the server + sets up nginx
├── output.tf      ← prints public IP, website URL, SSH command
├── index.html, styles.css, script.js, nginx.conf   ← the website
```

Terraform reads **all** `.tf` files together. Splitting is just for tidiness.

---

## 4. One-time setup

**① Tools work?**
```powershell
terraform -version
aws sts get-caller-identity --profile terraform   # must show user/terraform-user
```

**② Permissions.** `terraform-user` needs `AmazonEC2FullAccess` + `AmazonS3FullAccess`.
AWS Console (as root/admin) → IAM → Users → terraform-user → Add permissions → Attach policies directly.
> VPC, subnets, gateways, route tables and security groups all count as **EC2** permissions.

**③ SSH key** (once):
```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\tf-ec2-key" -N '""'
```
`tf-ec2-key` = private (never share) · `tf-ec2-key.pub` = public (goes to AWS).
> If asked `Overwrite (y/n)?` → **`n`**. A new key locks me out of existing servers.

**④ State bucket**: see [section 8](#8-remote-state-state-file-in-s3).

---

## 5. What gets built

Terraform works out the order itself: if B uses `A.id`, A is built first.

| # | Resource | File | Key point |
| --- | --- | --- | --- |
| ① | **VPC** `10.0.0.0/16` | network.tf | DNS on |
| ② | **Public subnet** `10.0.1.0/24` | network.tf | `map_public_ip_on_launch = true`, **or no public IP** |
| ② | **Private subnet** `10.0.2.0/24` | network.tf | No internet (for later) |
| ③ | **Internet gateway** | network.tf | The door to the internet |
| ④ | **Public route table** | network.tf | `0.0.0.0/0 → IGW`, **associated** with public subnet |
| ④ | **Private route table** | network.tf | No internet route |
| ⑤ | **Security group** | ec2.tf | In: 22 from **my IP only**, 80 from anyone. Out: all |
| ⑥ | **Key pair** | ec2.tf | Uploads `tf-ec2-key.pub` |
| ⑦ | **EC2** Ubuntu 24.04, `t3.micro` | ec2.tf | In public subnet |
| ⑧ | **Website** | website.tf | SSH in → copy files → install nginx → restart. Re-runs when a website file changes |

> 🔑 A subnet is "public" only because its route table points `0.0.0.0/0` at the internet gateway **and** is associated with it.

---

## 6. Connect & open the website

**SSH** (wait ~1 min after `apply`):
```powershell
ssh -i ~/.ssh/tf-ec2-key ubuntu@<public_ip>
```
- **No quotes**: `"ssh ..."` just prints text in PowerShell.
- User is **`ubuntu`** (not `ec2-user`, not `root`).
- First time → type `yes`. Success = `ubuntu@ip-10-0-1-xx:~$`. Leave with `exit`.

**Website:** `http://<public_ip>`
- Use **`http://`**. No SSL certificate, so `https` fails.
- Browser keeps switching to https? Use incognito (Ctrl+Shift+N) or Ctrl+F5.

---

## 7. Loops: many S3 buckets with `for_each`

**Idea:** write the block **once**, give a **list of names**, get **one bucket per name**. No copy-paste.

**The list** (`variable.tf`):
```hcl
variable "bucket_names" {
  type = list(string)
  default = [
    "krishna1om2yash3som4-iron-man",
    "krishna1om2yash3som4-krish",
    "krishna1om2yash3som4-spider-man",
  ]
}
```

**The loop** (`main.tf`):
```hcl
resource "aws_s3_bucket" "many" {
  for_each      = toset(var.bucket_names) # repeat for each name
  bucket        = each.value              # the current name
  force_destroy = true                    # allow delete even if not empty
}
```

| Part | Meaning |
| --- | --- |
| `for_each` | "Repeat this block for each item" |
| `toset(...)` | List → set (no duplicates). `for_each` needs a set |
| `each.value` | The name being processed right now |

**Plan shows** each bucket labelled by name:
```
# aws_s3_bucket.many["krishna1om2yash3som4-iron-man"] will be created
```

| To… | Do | `plan` should say |
| --- | --- | --- |
| **Add** buckets | Add names to the list | `N to add` (only the new ones) |
| **Delete** one | Remove its line from the list | `1 to destroy`, **check it's the right one** |

> ⚠️ `force_destroy = true` → deleting a bucket also deletes **its files**. Download first.
> ❌ Don't use `destroy -target` for one bucket. It comes back on the next `apply` because the name is still in the list.

**Name rules:** lowercase, numbers, `-` only · 3–63 chars · unique **worldwide** (hence my prefix).

**Why `for_each`, not `count`?** `count` tracks by **position** (0,1,2). Removing the 2nd shifts the rest and Terraform may recreate the wrong buckets. `for_each` tracks by **name**, so only the removed one is touched.

---

## 8. Remote state: state file in S3

**Why:** on my laptop the state can be lost or corrupted. In S3 it's **safe, versioned, and locked**.

```
Before: A:\Resume\terraform\terraform.tfstate
Now:    s3://omverma-tfstate/resume/terraform.tfstate
```

**① Bucket created by hand** in the AWS Console (Mumbai):

| Setting | Value | Why |
| --- | --- | --- |
| Name | `omverma-tfstate` | |
| Block all public access | ✅ On | State can hold secrets |
| Versioning | ✅ Enabled | Undo history for the state |
| Encryption | SSE-S3 | Default |

> ❗ **Why by hand?** Terraform needs the bucket *before* it can store state. **Never put `omverma-tfstate` in a `.tf` file**, or `destroy` would delete its own notebook.

**② Backend block** inside `terraform { }` in `version.tf`:
```hcl
backend "s3" {
  bucket       = "omverma-tfstate"
  key          = "resume/terraform.tfstate" # path inside the bucket
  region       = "ap-south-1"
  encrypt      = true
  use_lockfile = true                       # stops two applies at once
}
```
> No `var.` allowed here. Plain values only.

**③ Move the state:** back up first, then:
```powershell
Copy-Item terraform.tfstate* A:\Resume\tfstate-old-backup\
terraform init -migrate-state     # answer yes
```

**④ Check:**

| Command | Expected |
| --- | --- |
| `aws s3 ls s3://omverma-tfstate --recursive` | `resume/terraform.tfstate` |
| `terraform state list` | All my resources |
| `terraform plan -var="my_ip=$ip"` | **No changes** |

> 🛑 If `plan` wants to **create everything again**, the state wasn't found. **Don't apply.**

**⑤** Delete the old local `terraform.tfstate*` files. Day-to-day commands don't change.

---

## 9. Load balancer + Auto Scaling

**Goal:** visitors go to **one address** (the load balancer). AWS **adds servers when busy** and **removes them when quiet**.

```
                                      Auto Scaling Group (min 1, max 4)
Visitors ──► Load balancer ──► Target group ──► server 1 (from my AMI)
                                             ├─► server 2 ┐ added automatically
                                             ├─► server 3 ├ when traffic is high,
                                             └─► server 4 ┘ removed when quiet
```

### Words

| Word | Think of it as | Meaning |
| --- | --- | --- |
| **Load balancer (ALB)** | Receptionist | One address; shares visitors between servers |
| **Target group** | Receptionist's staff list | Which servers get visitors + "are you alive?" health check |
| **Docker container** | Sealed lunchbox | Website + nginx packed together |
| **AMI** | Photocopy of a server | New servers start as exact copies |
| **Launch template** | Order form | "Make servers from this AMI, this size, this firewall, this key" |
| **Auto Scaling Group (ASG)** | Manager who hires/fires | Keeps between min and max servers running |
| **Scaling policy** | The manager's rule | "Keep each server at ~500 requests/minute" |

### What's in Terraform vs made by hand

| Terraform | AWS Console (by hand) |
| --- | --- |
| VPC, subnets (incl. `demo-public-subnet-b`), route tables | Load balancer `load-balancer`, target group `group-1` |
| `demo-ec2-sg` (servers' firewall) | `demo-alb-sg` (load balancer's firewall) |
| Server A `demo-web-a` (master copy) | AMI, launch template `portfolio-lt`, ASG `portfolio-asg` |

### Part A: Network for the load balancer (Terraform)

An ALB needs **2 public subnets in 2 zones**. Added `demo-public-subnet-b` (`10.0.3.0/24`, ap-south-1b), linked to the public route table.

> ❌ Don't pick `demo-private-subnet` for the ALB. It has no internet route (`IGW (missing)` warning).

### Part B: Firewalls (2 security groups)

```
Internet ──► demo-alb-sg: port 80 from 0.0.0.0/0 ──► Load balancer
                                                         │
             demo-ec2-sg: port 80 ONLY from demo-alb-sg ◄┘──► Servers
```

| Security group | Port 80 from | Result |
| --- | --- | --- |
| `demo-alb-sg` (console) | `0.0.0.0/0` | Anyone can reach the load balancer |
| `demo-ec2-sg` (Terraform) | `demo-alb-sg` only | Opening a server IP directly is **blocked** ✅ |

In `ec2.tf`, Terraform **looks up** the hand-made group and allows only it:
```hcl
data "aws_security_group" "alb" {   # "data" = find it, don't create it
  name   = "demo-alb-sg"
  vpc_id = aws_vpc.main.id
}
# inside ec2_sg:  security_groups = [data.aws_security_group.alb.id]
```

> ⚠️ The **load balancer** must use `demo-alb-sg`, not `demo-ec2-sg`. Otherwise visitors time out.
> ⚠️ Never edit `demo-ec2-sg` in the console. Terraform undoes it on the next `apply`.

### Part C: One server running Docker (server A)

`ec2.tf` → `for_each = toset(["a"])`. Then on server A:
```bash
sudo systemctl stop nginx && sudo systemctl disable nginx   # free port 80
sudo apt-get install -y docker.io && sudo systemctl enable --now docker
mkdir ~/site && cd ~/site      # index.html, styles.css, script.js, nginx.conf + Dockerfile
sudo docker build -t portfolio .
sudo docker run -d --name portfolio -p 80:80 --restart always portfolio
```
> 🔑 `--restart always` = container starts **by itself on every boot**, so every server made from the AMI runs the website automatically. Test: `sudo reboot`, then `sudo docker ps`.

### Part D: AMI + launch template (console)

1. **AMI:** EC2 → Instances → `demo-web-a` → Actions → Image and templates → **Create image** → `portfolio-doctor-ami` → wait for **Available**.
2. **Launch template** `portfolio-lt`: tick *Auto Scaling guidance* · **My AMIs** → `portfolio-doctor-ami` · `t2.micro` · key `tf-ec2-key` · subnet **Don't include** · security group **`demo-ec2-sg`**.

### Part E: Auto Scaling Group (console)

EC2 → Auto Scaling Groups → **Create**:

| Setting | Value |
| --- | --- |
| Name / template | `portfolio-asg` / `portfolio-lt` |
| VPC / subnets | `demo-vpc` / `demo-public-subnet` + `demo-public-subnet-b` |
| Load balancing | Attach to existing target group **`group-1`** |
| Health checks | ✅ ELB health checks, grace period **120 s** |
| Min / desired / max | **1 / 1 / 4** |
| **Scaling policy** | Target tracking → **ALB request count per target** → **500** → warmup 120 s |

> ❗ **Don't skip the scaling policy.** Without it, the ASG never adds servers. (I forgot it once. Fixed by adding `requests-per-server-500`.)
> 💡 Request count, not CPU: a static website barely uses CPU, so CPU would never trigger scaling.

Then **deregister `demo-web-a`** from `group-1` once the ASG server is healthy. Server A stays only as the master copy.

**Is the site served by the ASG?** `group-1` → Targets shows **only ASG servers**, all **healthy**, and the load balancer URL works.

### Part F: Load test (prove it scales)

From any machine **inside AWS** (CloudShell, or server A):
```bash
sudo apt-get install -y apache2-utils      # CloudShell: sudo dnf install -y httpd-tools
ab -t 900 -n 3000000 -c 50 -k http://load-balancer-1459340471.ap-south-1.elb.amazonaws.com/
```
`-c 50` = 50 fake visitors at once · `-t 900` = run 15 min · keep the `/` at the end.
> ⚠️ `Could not allocate memory` → `-n` too big for a small server. Use `-n 3000000`.

**Watch it:**

| Where | What I'll see |
| --- | --- |
| CloudWatch → Alarms | `…AlarmHigh…` → **In alarm** 🔴 |
| ASG → **Activity** | "Launching a new EC2 instance … desired capacity from 1 to 4" |
| ASG → Instance management | New servers **Pending → InService** |
| Target group → Targets | New servers **healthy** (~1–2 min) |
| Load balancer → Monitoring | Requests spike |

### My result (20 Nov 2026)

| Time | What happened |
| --- | --- |
| +0 min | Test starts → ~**260,000 requests/server/min** (target 500) |
| +4 min | AlarmHigh → ASG **1 → 4 servers** (hit max) |
| +5 min | All 4 servers **healthy** in `group-1` |
| test ends +15 min | AlarmLow → ASG scales **back to 1** |

> AWS waits a few busy minutes before scaling **up**, and ~15 quiet minutes before scaling **down**, so it doesn't overreact.

### Updating the website now

Edit files on server A → `docker build` + `docker run` again → create a **new AMI** → launch template **new version** with that AMI → ASG → **Instance refresh**.
> ⚠️ Don't change website files and `terraform apply`: `website.tf` would turn host nginx back on and fight Docker for port 80.

### Cleanup order (important!)

Hand-made things live inside Terraform's VPC, so delete them **first**:

1. ASG `portfolio-asg` (terminates its servers)
2. Launch template `portfolio-lt`
3. AMI `portfolio-doctor-ami` (Deregister) **+ its snapshot** (EBS → Snapshots)
4. Load balancer `load-balancer`, then target group `group-1`
5. `terraform destroy -var="my_ip=$ip"`
6. Security group `demo-alb-sg` (last: `demo-ec2-sg` points to it until step 5)

---

## 10. Troubleshooting

| What I see | Fix |
| --- | --- |
| `Unable to locate credentials` / `No valid credential sources` | `$env:AWS_PROFILE = "terraform"` |
| `403 UnauthorizedOperation` | Add `AmazonEC2FullAccess` to `terraform-user` |
| `AccessDenied` on S3 | Add `AmazonS3FullAccess` to `terraform-user` |
| SSH `Connection timed out` / `apply` times out at `website` | My IP changed → get new IP → `apply`. Also check route `0.0.0.0/0 → IGW` |
| `public_ip = ""` | `map_public_ip_on_launch = true` on public subnet |
| `Permission denied (publickey)` | Use `ubuntu@` and `-i ~/.ssh/tf-ec2-key` |
| `UNPROTECTED PRIVATE KEY FILE` | `icacls $HOME\.ssh\tf-ec2-key /inheritance:r /grant:r "$($env:USERNAME):R"` |
| Website won't open | `http://` not https · Ctrl+F5 · incognito · port 80 open? |
| `BucketAlreadyExists` | Name taken worldwide. Choose another |
| `InvalidBucketName` | Lowercase, numbers, `-`, 3–63 chars |
| Plan shows nothing new | File not saved. Ctrl+S |
| `Backend configuration changed` | `terraform init -migrate-state` |
| `Error acquiring the state lock` | No other apply running? → `terraform force-unlock <LOCK_ID>` |
| `plan` wants to recreate **everything** | State not found. **Don't apply.** Check backend + profile |
| Load balancer URL times out | Load balancer uses wrong security group → must be `demo-alb-sg` (port 80 from 0.0.0.0/0) |
| `502` / `503` from load balancer | No healthy targets yet. Wait 1–2 min, check target group → Targets |
| Targets **unhealthy** | Container not running → `sudo docker ps`. AMI made without `--restart always`? |
| ASG never adds servers | No scaling policy. ASG → Automatic scaling → add target tracking |
| ALB subnet says `IGW (missing)` | Wrong (private) subnet. Use `demo-public-subnet-b` |
| `ab: Could not allocate memory` | Lower `-n` (e.g. 3000000) |

---

## 11. Golden rules

1. **Always `plan` before `apply`**, and read what will be destroyed.
2. **`destroy` when done**: servers cost money. (It deletes all buckets in `main.tf` and their files, but not the state bucket.)
3. **Never share** `tf-ec2-key` or AWS keys. Never put them in code or git.
4. **Never edit or delete** the state file or the `omverma-tfstate` bucket.
5. **Never commit** `terraform.tfstate*` or `.terraform/` to git.
6. **Delete hand-made AWS things first** (ASG, launch template, AMI, load balancer), **then** `terraform destroy` (see section 9 cleanup order).
7. **Stop servers I'm not using** (e.g. `demo-web-a` after a load test). Stopped = new public IP when started again.
