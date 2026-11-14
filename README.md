# Om Verma — Portfolio

## Open the website

**[Click here to open Om's portfolio](https://thevermaom.github.io/om-verma-portfolio/)**

No downloads or setup are needed. The first time it is published, GitHub may take a few minutes to make the page available.

## Open it on your computer

1. Download this project from GitHub using the green **Code** button and **Download ZIP**.
2. Extract the ZIP file.
3. Open the extracted `Resume` folder and double-click `index.html`.

## Run locally with Python (optional)

If Python is installed, open a terminal in this folder and run:

```sh
python -m http.server 8080
```

Then open [http://localhost:8080](http://localhost:8080) in your browser. Stop the server by pressing `Ctrl+C` in the terminal.

## Run with Docker (optional)

From this directory, build the image and start the site:

```sh
docker build -t om-verma-portfolio .
docker run --rm -p 8080:80 om-verma-portfolio
```

Open [http://localhost:8080](http://localhost:8080).

## Deploy the Docker image to EC2 with GitHub Actions

The workflow in `.github/workflows/deploy-ec2.yml` builds a multi-architecture
Docker image on a GitHub-hosted runner, pushes it to Amazon ECR, and asks AWS
Systems Manager (SSM) to update the EC2 container when code is pushed to `main`.

Before the first run:

1. Create an ECR repository in the AWS region used by the EC2 instance.
2. Attach an EC2 instance role with `AmazonSSMManagedInstanceCore` and
   `AmazonEC2ContainerRegistryReadOnly`. Confirm the instance is online in
   Systems Manager and has Docker, AWS CLI, and SSM Agent installed.
3. Create a dedicated IAM user for GitHub Actions with permission to push to
   this ECR repository and send/check SSM commands for the target instance.
   Do not use root account access keys.
4. In **Settings → Secrets and variables → Actions**, add these repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

   Add these repository variables:
   - `AWS_REGION` (for example, `ap-southeast-2`)
   - `ECR_REPOSITORY` (the ECR repository name)
   - `EC2_INSTANCE_ID` (the target instance ID)
5. Allow inbound HTTP on TCP port 80 in the instance's security group. The
   workflow deploys the container through SSM, so the GitHub runner does not
   need inbound SSH access to the instance.

The workflow replaces the container named `portfolio` and serves it on port 80.
The host Nginx service is stopped if it is active so it does not conflict with
the container's port mapping.

This is a static, responsive portfolio built with plain HTML, CSS, and JavaScript. It does not need a database, backend, build step, or JavaScript packages.
