# Terraform on AWS: Network + Ubuntu Server + Website + S3 Buckets

**What this folder builds (with one command):**
a private network in AWS → an Ubuntu server I can SSH into → my portfolio website on it → some S3 buckets.
Terraform's state file is kept safely in S3.

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
| Open the website | `http://<public_ip>` (**http, not https**) |
| Update the website | Edit HTML/CSS/JS → save → `apply` |
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

## 9. Troubleshooting

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

---

## 10. Golden rules

1. **Always `plan` before `apply`**, and read what will be destroyed.
2. **`destroy` when done**: servers cost money. (It deletes all buckets in `main.tf` and their files, but not the state bucket.)
3. **Never share** `tf-ec2-key` or AWS keys. Never put them in code or git.
4. **Never edit or delete** the state file or the `omverma-tfstate` bucket.
5. **Never commit** `terraform.tfstate*` or `.terraform/` to git.
