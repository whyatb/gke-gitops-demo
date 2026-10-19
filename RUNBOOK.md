# Runbook: setting up and tearing down

The step-by-step procedure for creating this environment from scratch, deploying the service, checking it works, and removing everything afterwards. [README.md](README.md) explains *what* the system is and *why* it's built this way; this document is the *how*.

Every command is written for [Cloud Shell](https://shell.cloud.google.com) and can be pasted as-is. Each step says what you should see, so you can tell whether it worked before moving on.

| Phase | Where | Time |
|---|---|---|
| [Setup](#setup), steps 1–6 | Cloud Shell | about 20 minutes, mostly waiting for the cluster |
| [Connect GitHub and deploy](#7-connect-github-actions-to-google-cloud), steps 7–9 | GitHub, then Cloud Shell | about 5 minutes |
| [Teardown](#teardown) | Cloud Shell | about 15 minutes |

## Before you start

You need:

- **A Google Cloud project** with a billing account linked to it. Credits only apply to a billing account that is linked to the project; step 1 checks this.
- **A public GitHub repository** containing this code on `main`. Argo CD reads it without credentials.

Running your own copy under a different project or repository? Change these files first and push them:

| File | Change |
|---|---|
| `argocd/project.yaml` | `sourceRepos` to your repository URL |
| `argocd/hello-api.yaml` | `repoURL` to your repository URL |
| `k8s/kustomization.yaml` | the project ID in `newName` (optional: CI rewrites it on the first release) |

## Start of every Cloud Shell session

Cloud Shell disconnects when idle and reopens as a fresh shell in your home folder, forgetting variables and the current directory. Run this block at the start of **every** session, including after a reconnect. Change the first two values if you're running your own copy.

```bash
export PROJECT_ID=acdtkgha
export GITHUB_REPO=whyatb/gke-gitops-demo
export REPO_DIR="$HOME/${GITHUB_REPO#*/}"
export PATH="$HOME/bin:$PATH"
gcloud config set project "$PROJECT_ID"
```

## Setup

### 1. Check billing

```bash
gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)'
```

**Expect:** `True`.

If it prints `False` or nothing, link a billing account. List yours, copy the `ACCOUNT_ID` of one where `OPEN` is `True`, and link it:

```bash
gcloud billing accounts list
gcloud billing projects link "$PROJECT_ID" --billing-account=ACCOUNT_ID
```

If the list is empty, set up billing in the console first: https://console.cloud.google.com/billing

### 2. Install Terraform (first time only)

Cloud Shell doesn't include Terraform. This installs it into `~/bin`, which survives Cloud Shell restarts, and does nothing if it's already there.

```bash
command -v terraform > /dev/null || {
  mkdir -p ~/bin
  curl -fsSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.16.6/terraform_1.16.6_linux_amd64.zip
  unzip -o /tmp/terraform.zip terraform -d ~/bin
}
terraform version
```

**Expect:** `Terraform v1.16.6` (any version from 1.5 works).

### 3. Get the code

```bash
[ -d "$REPO_DIR" ] || git clone "https://github.com/$GITHUB_REPO.git" "$REPO_DIR"
cd "$REPO_DIR" && git pull
```

### 4. Prepare the project

Turns on the Google Cloud APIs Terraform needs in order to run, and creates a versioned bucket for Terraform's state: its record of everything it has built.

```bash
cd "$REPO_DIR"
scripts/bootstrap.sh "$PROJECT_ID"
```

**Expect:** `Creating gs://<project>-tfstate/...` the first time, or `State bucket ... already exists` on a re-run. Both are fine.

### 5. Configure Terraform

```bash
cd "$REPO_DIR/terraform"
cat > terraform.tfvars <<EOF
project_id        = "$PROJECT_ID"
github_repository = "$GITHUB_REPO"
EOF
terraform init -backend-config="bucket=$PROJECT_ID-tfstate"
```

**Expect:** `Terraform has been successfully initialized!`

> **Rebuilding within 30 days of a teardown?** Google keeps a deleted GitHub sign-in pool for 30 days and won't let its name be reused. Give the new one a different name by adding this line to `terraform.tfvars` (use `github-3` next time, and so on):
>
> ```bash
> echo 'workload_identity_pool_id = "github-2"' >> terraform.tfvars
> ```

### 6. Create the infrastructure

```bash
terraform apply
```

Terraform first prints what it will create. Check the summary line reads **`Plan: 24 to add, 0 to change, 0 to destroy.`**, then type `yes`.

It runs for about 10–15 minutes, roughly in this order:

1. Turns on APIs (about a minute)
2. Creates the network, Cloud NAT, image registry, service accounts and GitHub sign-in (a few seconds each)
3. Creates the GKE cluster (5–8 minutes)
4. Creates the node pool (2–4 minutes)
5. Installs Argo CD and points it at this repository (1–2 minutes)

**Expect:** `Apply complete! Resources: 24 added, 0 changed, 0 destroyed.`

**If Cloud Shell disconnects during `apply`:** reconnect, run the [session block](#start-of-every-cloud-shell-session), then:

```bash
cd "$REPO_DIR/terraform"
terraform state list | wc -l
```

`25` means the apply finished: 24 resources plus one data lookup. Anything less, run `terraform apply` again. It's always safe to re-run; it only creates what's missing.

### 7. Connect GitHub Actions to Google Cloud

```bash
terraform output github_actions_variables
```

This prints three values. Add each one as a repository **variable** (not a secret) on GitHub:

1. Open `https://github.com/<owner>/<repo>/settings/variables/actions`. For this repository: https://github.com/whyatb/gke-gitops-demo/settings/variables/actions
2. Make sure the **Variables** tab is selected.
3. Click **New repository variable** once per value:

| Name | Value from the output | Changes between rebuilds? |
|---|---|---|
| `GCP_CI_SERVICE_ACCOUNT` | `github-ci@<project>.iam.gserviceaccount.com` | No |
| `GCP_WIF_PROVIDER` | `projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/github-actions` | Only if you changed `workload_identity_pool_id` |
| `IMAGE_REPOSITORY` | `us-central1-docker.pkg.dev/<project>/apps/hello-api` | No |

On a rebuild in the same project, the variables are still there from last time. Only update `GCP_WIF_PROVIDER` if you renamed the pool.

### 8. Deploy

1. Open `https://github.com/<owner>/<repo>/actions/workflows/app.yaml`. For this repository: https://github.com/whyatb/gke-gitops-demo/actions/workflows/app.yaml
2. Click **Run workflow**, leave the branch as `main`, and click the green **Run workflow** button.

**Expect:** three green jobs after about 2–3 minutes:

| Job | What it does |
|---|---|
| `test` | `go vet` and the unit tests |
| `build` | signs in to Google Cloud without a key, builds the image and pushes it, tagged with the commit SHA |
| `release` | commits the new tag to `k8s/kustomization.yaml` as `github-actions[bot]` |

Argo CD notices the release commit within 1–2 minutes and rolls it out.

The bot commits to `main`, so run `git pull` before pushing your own changes.

### 9. Verify

```bash
cd "$REPO_DIR/terraform"
$(terraform output -raw get_credentials_command)
kubectl -n argocd get applications
kubectl -n hello-api get pods,svc
curl -s "http://$(kubectl -n hello-api get svc hello-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/"
```

**Expect** (from a real run):

```
NAME        SYNC STATUS   HEALTH STATUS
hello-api   Synced        Healthy
root        Synced        Healthy

NAME                            READY   STATUS    RESTARTS   AGE
pod/hello-api-dbf5f5d6b-gw6tn   1/1     Running   0          27s
pod/hello-api-dbf5f5d6b-qrtvv   1/1     Running   0          23s

NAME                TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
service/hello-api   LoadBalancer   10.30.12.248   35.193.193.147   80:30784/TCP   60m

{"message":"Hello from GKE","service":"hello-api","version":"792ad3422f708752d2e4c3ed9a0a35c1c4f835e9"}
```

`version` is the commit the running image was built from. The service also answers at `http://<EXTERNAL-IP>/` from any browser.

If the pods show `ImagePullBackOff`, Argo CD hasn't picked up the release commit yet: wait a minute and re-run the last three commands.

You're set up. [README.md → Things to try](README.md#things-to-try) has changes to demonstrate the pipeline with.

### Optional: open the Argo CD dashboard

Print the admin password, then forward the dashboard to port 8080:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

In Cloud Shell, click **Web Preview** (the eye icon at the top of the terminal) → **Preview on port 8080**. On your own computer, open http://localhost:8080. Log in as `admin` with the password printed above.

`port-forward` keeps running until you press **Ctrl+C**.

## Teardown

Order matters. Delete the app through Argo CD **first**, so Kubernetes removes the Google Cloud load balancer it created. A leftover load balancer keeps the network in use and makes `terraform destroy` fail.

Run the [session block](#start-of-every-cloud-shell-session) first if this is a new Cloud Shell session.

### 1. Remove the app

```bash
cd "$REPO_DIR/terraform"
$(terraform output -raw get_credentials_command)
kubectl -n argocd delete application root
kubectl -n argocd delete application hello-api
```

Deleting `root` first stops Argo CD from recreating `hello-api`. The second command waits until the app's namespace and load balancer are gone.

**Expect:** two `application.argoproj.io "..." deleted` lines.

Check the load balancer is gone:

```bash
kubectl get namespace hello-api
gcloud compute forwarding-rules list
```

**Expect:** `Error from server (NotFound)` and `Listed 0 items.`

### 2. Destroy the infrastructure

```bash
terraform destroy
```

Check the summary reads **`Plan: 0 to add, 0 to change, 24 to destroy.`**, then type `yes`. It takes about 10–12 minutes: the node pool and the cluster take roughly 5 minutes each.

**Expect:** `Destroy complete! Resources: 24 destroyed.`

A warning that three `CustomResourceDefinition`s "were kept due to the resource policy" is expected. Argo CD keeps those on purpose, and they were inside the cluster, which is now gone.

### 3. Delete the state bucket

**Only after** `Destroy complete!`. Terraform needs the state to know what to destroy, so deleting the bucket earlier would leave resources it can no longer track.

```bash
gcloud storage rm -r "gs://$PROJECT_ID-tfstate"
```

### 4. Confirm nothing is left running

```bash
gcloud container clusters list
gcloud compute instances list
gcloud compute forwarding-rules list
gcloud artifacts repositories list --location=us-central1
```

**Expect:** `Listed 0 items.` for each.

At this point nothing in the project is billed. A few things remain, all free:

- the enabled APIs
- the deleted GitHub sign-in pool, kept by Google for 30 days
- the repository variables on GitHub
- Terraform and the repository clone in Cloud Shell

If you won't use the project again, `gcloud projects delete "$PROJECT_ID"` shuts it down completely.

## Rebuilding later

Follow [Setup](#setup) again from the session block. Differences from the first time:

- **Within 30 days of a teardown**, rename the sign-in pool in step 5, and update `GCP_WIF_PROVIDER` on GitHub in step 7.
- **The image registry was deleted with everything else**, so the tag in `k8s/kustomization.yaml` no longer exists. Argo CD will show `ImagePullBackOff` until you run the workflow in step 8, which builds and releases a fresh image.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `bootstrap.sh`: "The billing account for the owning project is disabled" | No billing account is linked. Do [step 1](#1-check-billing). |
| `terraform: command not found` | Run the [session block](#start-of-every-cloud-shell-session), which adds `~/bin` to `PATH`. If that's not enough, run [step 2](#2-install-terraform-first-time-only). |
| A command fails with `[200~` in front of it | The terminal garbled the paste. Paste it again. |
| "Output ... not found" or "No configuration files" | You're not in the `terraform` folder: `cd "$REPO_DIR/terraform"`. |
| `apply`: "API has not been used in project ... or it is disabled" | A newly enabled API hasn't finished switching on. Wait a minute and run `terraform apply` again. |
| `apply`: "service account ... does not exist" | A just-created service account hasn't reached every Google system yet. Run `terraform apply` again. |
| `apply`: "Error acquiring the state lock" | An earlier run was interrupted. If you're certain no other `apply` is running, run `terraform force-unlock <ID>` with the ID from the error, then try again. |
| `apply`: workload identity pool "already exists" | You're rebuilding within 30 days of a teardown. Set a new `workload_identity_pool_id` (see [step 5](#5-configure-terraform)). |
| Workflow fails at "Log in to Artifact Registry" | Check the three GitHub variables. `github_repository` in `terraform.tfvars` must match the repository's owner and name exactly, including capitalization. |
| `build` and `release` jobs are skipped | `IMAGE_REPOSITORY` isn't set on GitHub. Do [step 7](#7-connect-github-actions-to-google-cloud). |
| Argo CD `root` application shows "repository not found" | The repository must be public, and the URLs in `argocd/` must match it. |
| Pods in `ImagePullBackOff` | No image has been released for this registry yet. Run the workflow ([step 8](#8-deploy)). |
| `destroy`: network "is already being used by" another resource | A load balancer was left behind because the app wasn't removed first. Delete what the error names, for example with `gcloud compute forwarding-rules list` then `gcloud compute forwarding-rules delete <name> --region us-central1`, then run `terraform destroy` again. |
