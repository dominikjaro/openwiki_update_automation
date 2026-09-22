---
title: "📚 Automating Repository Documentation with OpenWiki and GCP Cloud Build"
date: 2026-09-22
description: "How I automated code documentation generation across application repositories using OpenWiki, GCP Cloud Build triggers, Terraform, and Gemini."
categories: ["Infrastructure as Code", "CI/CD"]
tags: ["GCP", "Cloud Build", "OpenWiki", "Terraform", "Gemini", "Automation"]
image: "openwiki.png"
---

Keeping repository documentation up to date is a task that often gets deprioritized as codebases evolve. To solve this, I recently automated our documentation workflow across several application repositories using **[OpenWiki](https://github.com/langchain-ai/openwiki)**. 

For our initial rollout, we opted to skip the OpenWiki visualizer and focus strictly on generating and committing updated `.md` files directly inside the repositories whenever changes land on our staging branch.

Here is how I designed and built this pipeline using **GCP Cloud Build**, **Terraform**, and **Gemini Enterprise**.

---

## 🏗️ Architecture & Security Setup

When implementing LLM-powered tools into CI/CD pipelines, cost tracking and access control are critical considerations.

* **Dedicated GCP Project:** Since OpenWiki doesn't currently support custom resource labels on API calls (I’ve submitted a feature request for this on the OpenWiki repo), I isolated this setup into its own dedicated GCP project. This ensures clean cost attribution and isolated billing metrics.
* **Model Selection:** The pipeline uses the `gemini-enterprise 3.6-flash` model for lightweight, fast, and cost-effective documentation generation.
* **Least Privilege IAM:** The project runs on a dedicated Service Account with strictly scoped permissions required only for Cloud Build execution and API access.

---

## 🛠️ Step-by-Step Implementation

### 1. Custom Docker Container
OpenWiki needs both its CLI dependencies and Git to interact with the repository. I built a lightweight, specialized Docker image containing both `openwiki` and `git-cli` to keep the pipeline execution fast.

### 2. Infrastructure as Code (Terraform)
Using Terraform, I provisioned:
* The isolated GCP Project and enabled required APIs (Vertex AI / Cloud Build).
* The dedicated Service Account and IAM roles following the principle of least privilege.
* Inline **GCP Cloud Build triggers** attached to our application repositories.

### 3. The Cloud Build Pipeline
The Cloud Build trigger fires automatically whenever code is pushed to or created on our staging branch. The pipeline step checks out the target branch, runs OpenWiki, and commits the updated `.md` documentation back to origin.

Here is the core inline build step used in the Cloud Build trigger:

```yaml
- name: 'gcr.io/your-project/openwiki-runner:latest'
  entrypoint: 'sh'
  args:
    - '-c'
    - |
      set -e

      TARGET_BRANCH="${BRANCH_NAME}"

      if [ -z "$TARGET_BRANCH" ]; then
        TARGET_BRANCH="${_HEAD_BRANCH}"
      fi

      echo "Checking out PR source branch: $TARGET_BRANCH"
      git remote set-url origin "git@github.com:${REPO_FULL_NAME}.git"
      git fetch origin "$TARGET_BRANCH"
      git checkout "$TARGET_BRANCH"

      echo "Running OpenWiki documentation generation..."
      openwiki code --update --print

      git config user.email "${_GIT_USER_EMAIL}"
      git config user.name "${_GIT_USER_NAME}"

      git add openwiki
      git commit -m "docs(openwiki): auto-update documentation [skip ci]" || true
      git push origin "$TARGET_BRANCH"
```

(Note: SSH key provisioning and GitHub authentication details are handled separately outside of this build step.)

## 🎯 Key Takeaways

**Zero Developer Friction:** Developers don't need to manually run CLI commands to update docs—it happens automatically in CI/CD on staging pushes.

**Cost Isolation:** Until OpenWiki supports granular labeling natively, running LLM tasks in a dedicated GCP project is a clean workaround for cost management.

**Preventing Infinite Loops:** Adding [skip ci] to the automated commit message prevents Cloud Build from recursively triggering itself on doc updates.
