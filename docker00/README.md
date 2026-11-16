# My Portfolio: Auto-Deploy with Docker + GitHub + AWS

**What this does:** every time I push code to GitHub, my website is automatically packed into a Docker container and put live on my AWS server. I don't have to do anything by hand.

---

## 1. The idea in one picture

```
 Me                GitHub Actions             AWS
 ──                ──────────────             ───
 git push  ──►  1. Build Docker image  ──►  ECR  (stores the image)
                2. Tell the server     ──►  EC2  (pulls the image and runs it)
                                                 │
                                                 ▼
                                       Website live on http://<server-IP>
```

## 2. Words you need to know

| Word | Simple meaning |
| --- | --- |
| **Docker image** | A sealed box holding my website plus everything it needs to run |
| **Container** | That box, switched on and running |
| **Dockerfile** | The recipe for building the box |
| **CI/CD pipeline** | A robot that builds and deploys automatically after every push |
| **GitHub Actions** | GitHub's robot that runs the pipeline |
| **EC2** | A computer (server) rented from AWS |
| **ECR** | AWS's storage for Docker images, like Google Drive for images |
| **IAM** | AWS's place for users, passwords and permissions |
| **Access key** | A username + password that lets a program (GitHub) log in to AWS |
| **SSM** | AWS tool that runs commands on the server for us, so no SSH is needed |

---

## 3. My files

```
Resume/
├── .github/workflows/deploy-ec2.yml   ← the pipeline (robot's instructions)
└── docker00/
    ├── Dockerfile                     ← recipe for the Docker image
    ├── nginx.conf                     ← web server settings
    └── index.html, styles.css, script.js   ← my website
```

**My Dockerfile, line by line:**

```dockerfile
FROM nginx:alpine                    # start from a tiny Linux that has the Nginx web server
COPY index.html styles.css script.js /usr/share/nginx/html/   # put my website inside
COPY nginx.conf /etc/nginx/conf.d/default.conf                # use my web server settings
EXPOSE 80                            # the website runs on port 80
```

---

## 4. The steps I followed (start → end)

### Step 1: Test on my own computer

Install **Docker Desktop**, then open a terminal in the `docker00` folder:

```sh
docker build -t portfolio .            # build the image
docker run --rm -p 8080:80 portfolio   # run it
```

Open <http://localhost:8080>. If the site shows up, the Dockerfile works. Press `Ctrl + C` to stop.

---

### Step 2: Create a place to store images (ECR)

1. Log in to the AWS Console. Top-right, pick the region **Asia Pacific (Mumbai)**.
2. Search **ECR** → **Create repository**.
3. Keep it **Private**, name it `portfolio` → **Create**.

✏️ Write down the **repository name**.

---

### Step 3: Get the server (EC2) ready

**3a. Give the server permission** (so it can download images and accept commands)

1. **IAM → Roles → Create role** → choose **AWS service** → **EC2** → Next.
2. Tick these two policies:
   - `AmazonSSMManagedInstanceCore`
   - `AmazonEC2ContainerRegistryReadOnly`
3. Name it `portfolio-ec2-role` → **Create role**.

**3b. Create the server**

1. **EC2 → Launch instance**.
2. Image: **Amazon Linux 2023**. Size: **t3.micro**.
3. Under **Advanced details → IAM instance profile**, choose `portfolio-ec2-role`.
4. Under **Network settings**, tick **Allow HTTP traffic from the internet** (port 80).
5. Click **Launch**.

✏️ Write down the **Instance ID** (looks like `i-0abc123...`) and the **Public IP**.

**3c. Install Docker on the server**

Select the instance → **Connect** → **Session Manager** → **Connect**, then type:

```sh
sudo dnf install -y docker
sudo systemctl enable --now docker
```

✅ Check: **Systems Manager → Fleet Manager** should show the server as **Online**.

---

### Step 4: Create an access key for GitHub (IAM)

GitHub lives outside AWS, so it needs its own login. I made a separate user just for GitHub. **Never use the root account's keys.**

**4a. Create the user**

1. **IAM → Users → Create user** → name: `github-actions` → Next.
2. Choose **Attach policies directly** and pick:
   - `AmazonEC2ContainerRegistryPowerUser` (lets it push images)
   - `AmazonSSMFullAccess` (lets it send commands to the server)
3. **Create user**.

> 💡 These ready-made policies are the easy route. Later, swap them for a custom policy that allows only my one repository and one server (see *Safety rules* at the end).

**4b. Create the key**

1. Open the user → **Security credentials** tab → **Create access key**.
2. Choose **Third-party service** → Next → **Create access key**.
3. Copy **both** values:
   - Access key ID
   - Secret access key ⚠️ *shown only once.* If I lose it, I delete the key and make a new one.

---

### Step 5: Save the key in GitHub

GitHub repo → **Settings** → **Secrets and variables** → **Actions**.

**Secrets tab** (hidden, for passwords) → **New repository secret**:

| Name | Value |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Access key ID from Step 4 |
| `AWS_SECRET_ACCESS_KEY` | Secret access key from Step 4 |

**Variables tab** (visible, normal settings) → **New repository variable**:

| Name | Value |
| --- | --- |
| `AWS_REGION` | `ap-south-1` |
| `ECR_REPOSITORY` | `portfolio` |
| `EC2_INSTANCE_ID` | my instance ID, e.g. `i-0abc123...` |

⚠️ Names must match **exactly** (capital letters and underscores).

---

### Step 6: The pipeline file

The file `.github/workflows/deploy-ec2.yml` tells GitHub what to do on every push to `main`:

| # | Step | In plain words |
| --- | --- | --- |
| 1 | Check out the project | Download my code |
| 2 | Connect to AWS | Log in using my secret key |
| 3 | Log in to ECR | Unlock my image storage |
| 4–5 | Set up QEMU and Buildx | Prepare to build for both Intel and ARM servers |
| 6 | Build and push image | Build the Docker image and upload it to ECR |
| 7 | Deploy to EC2 | Tell the server to download the new image, remove the old container, start the new one and check the site works |

⚠️ **Important:** my website files are inside `docker00/`, so the build step must point there:

```yaml
      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: docker00        # ← must be docker00, not "."
```

---

### Step 7: Push and watch it go live 🚀

```sh
git add .
git commit -m "Update portfolio"
git push origin main
```

1. Open GitHub → **Actions** tab → watch every step turn ✅ green.
2. Open `http://<my-server-public-IP>` in the browser. The site is live!

From now on, **every push to `main` updates the website automatically.**

---

## 5. If something goes wrong

| Error / problem | Fix |
| --- | --- |
| `Credentials could not be loaded` | A secret name is misspelled. Check Step 5. |
| `AccessDenied` | The IAM user is missing a policy (Step 4), or the region is wrong. |
| `failed to read dockerfile` | Set `context: docker00` (Step 6). |
| `InvalidInstanceId` | Server isn't Online in Fleet Manager. Check the role (3a) and the instance ID. |
| Fails at `docker pull` | Docker isn't installed on the server (3c), or the server role is missing a policy (3a). |
| Pipeline green but site won't open | Port 80 isn't open in the security group, or I typed `https://` instead of `http://`. |

**Handy commands on the server** (connect through Session Manager):

```sh
docker ps               # is my container running?
docker logs portfolio   # what did it print?
```

---

## 6. Safety rules 🔒

1. **Never** put access keys in code. Keep them only in GitHub Secrets.
2. If a key leaks: **IAM → Users → github-actions → Security credentials → Deactivate → Delete** right away.
3. Make a new key every few months, then delete the old one.
4. **Make it safer later:** replace the broad policies from Step 4 with a custom one that allows only my ECR repository and my one server. Or use **GitHub OIDC**, which needs no stored keys at all.

---

## 7. Docker commands cheat sheet

```sh
docker build -t NAME .          # build an image
docker images                   # list images
docker run -d -p 8080:80 NAME   # run a container in the background
docker ps                       # list running containers
docker logs NAME                # see what a container printed
docker exec -it NAME sh         # go inside a running container
docker rm -f NAME               # stop and delete a container
```

📚 Learn more: [Docker Get Started](https://docs.docker.com/get-started/) · [Play with Docker (free lab)](https://labs.play-with-docker.com/)
