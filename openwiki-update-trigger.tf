resource "google_cloudbuild_trigger" "openwiki_update" {
  for_each = local.openwiki_target_repos

  description     = "Openwiki update trigger - generate md file documentation"
  disabled        = false
  ignored_files   = []
  included_files  = []
  location        = var.location
  name            = "openwiki-update-${each.value}"
  project         = var.project
  service_account = "projects/${var.project}/serviceAccounts/${var.openwiki_runner_service_account_email}"
  substitutions = {
    _WORKER_POOL_NAME : "YOUR_POOL_NAME"
    _GIT_USER_EMAIL : "YOUR_EMAIL@example.com"
    _GIT_USER_NAME : "YOUR_NAME"
    _GOOGLE_CLOUD_PROJECT : "YOUR_PROJECT_ID"
    _GOOGLE_CLOUD_LOCATION : "LOCATION"
    _OPENWIKI_PROVIDER : "gemini-enterprise"
    _OPENWIKI_MODEL_ID : "gemini-3.6-flash"
  }
  tags = [
    "openwiki_update",
    "managed_by_terraform",
  ]

  approval_config {
    approval_required = false
  }

  github {
    name  = each.value
    owner = "YOUR_GITHUB"

    push {
      branch = "STAGING-.*$"
    }
  }

  build {
    timeout = "4600s"
    options {
      logging             = "CLOUD_LOGGING_ONLY"
      substitution_option = "ALLOW_LOOSE"
      worker_pool         = "YOUR_POOL_NAME"
    }

    #Configure SSH key
    step {
      name       = "gcr.io/cloud-builders/git"
      id         = "configure-ssh-key"
      entrypoint = "sh"
      secret_env = ["GITHUB_SSH_KEY"]
      volumes {
        name = "ssh"
        path = "/root/.ssh"
      }
      args = [
        "-c",
        <<-EOT
          echo "$$GITHUB_SSH_KEY" >> /root/.ssh/id_rsa
          chmod 400 /root/.ssh/id_rsa
          cat <<EOF >/root/.ssh/config
          Hostname github.com
          IdentityFile /root/.ssh/id_rsa
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
          LogLevel ERROR
          EOF
        EOT
      ]
    }

    # Run OpenWiki
    step {
      name       = "IMAGE_LOCATION/docker/openwiki:latest"
      entrypoint = "sh"
      volumes {
        name = "ssh"
        path = "/root/.ssh"
      }
      env = [
        "GOOGLE_CLOUD_PROJECT=$${_GOOGLE_CLOUD_PROJECT}",
        "GOOGLE_CLOUD_LOCATION=$${_GOOGLE_CLOUD_LOCATION}",
        "OPENWIKI_PROVIDER=$${_OPENWIKI_PROVIDER}",
        "OPENWIKI_MODEL=$${_OPENWIKI_MODEL_ID}"
      ]
      args = [
        "-c",
        <<-EOT
          set -e

          TARGET_BRANCH="$${BRANCH_NAME}"

          if [ -z "$$TARGET_BRANCH" ]; then
            TARGET_BRANCH="$${_HEAD_BRANCH}"
          fi

          echo "Checking out PR source branch: $$TARGET_BRANCH"
          git remote set-url origin "git@github.com:$${REPO_FULL_NAME}.git"
          git fetch origin "$$TARGET_BRANCH"
          git checkout "$$TARGET_BRANCH"

          echo "Running OpenWiki documentation generation..."
          openwiki code --update --print

          git config user.email "$${_GIT_USER_EMAIL}"
          git config user.name "$${_GIT_USER_NAME}"

          git add openwiki
          git commit -m "docs(openwiki): auto-update documentation [skip ci]" || true
          git push origin "$$TARGET_BRANCH"
        EOT
      ]
    }

    available_secrets {
      secret_manager {
        env          = "GITHUB_SSH_KEY"
        version_name = "SECRET_LOCATION"
      }
    }
  }
}

locals {
  openwiki_target_repos = toset([
    "repo-1",
    "repo-2",
    "repo-3",
  ])
}
