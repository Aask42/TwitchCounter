# GitHub Secrets and Environment Variables Guide

This guide explains how to set up GitHub secrets and environment variables for the Twitch Word Counter deployment.

## Setting Up GitHub Secrets

GitHub secrets are encrypted environment variables that you can create for a repository. They allow you to store sensitive information securely.

### Using the GitHub Web Interface

1. Go to your GitHub repository
2. Click on "Settings" tab
3. In the left sidebar, click on "Secrets and variables" > "Actions"
4. Click "New repository secret"
5. Enter the name and value for your secret
6. Click "Add secret"

### Using the GitHub CLI (gh)

If you prefer using the command line, you can use the GitHub CLI:

1. Install the GitHub CLI if you haven't already:
   ```bash
   # macOS
   brew install gh
   
   # Windows
   winget install --id GitHub.cli
   
   # Linux
   sudo apt install gh  # Debian/Ubuntu
   ```

2. Login to GitHub:
   ```bash
   gh auth login
   ```

3. Add secrets to your repository:
   ```bash
   # Set AWS access key
   gh secret set AWS_ACCESS_KEY_ID --body "your-access-key-id"
   
   # Set AWS secret key
   gh secret set AWS_SECRET_ACCESS_KEY --body "your-secret-access-key"
   
   # Set AWS region
   gh secret set AWS_REGION --body "us-east-1"
   
   # Set Namecheap domain
   gh secret set NAMECHEAP_DOMAIN --body "your-domain.com"
   
   # Set Namecheap DDNS password
   gh secret set NAMECHEAP_DDNS_PASSWORD --body "your-ddns-password"
   ```

4. Verify your secrets:
   ```bash
   gh secret list
   ```

## Required Secrets for Twitch Counter

For the Twitch Counter deployment, you need to set the following secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| AWS_ACCESS_KEY_ID | Your AWS access key ID | AKIAIOSFODNN7EXAMPLE |
| AWS_SECRET_ACCESS_KEY | Your AWS secret access key | wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY |
| AWS_REGION | Your AWS region | us-east-1 |
| NAMECHEAP_DOMAIN | Your Namecheap domain | example.com |
| NAMECHEAP_DDNS_PASSWORD | Your Namecheap DDNS password | a1b2c3d4e5f6 |

## Setting Environment Variables in GitHub Actions

There are two ways to set environment variables in GitHub Actions:

### 1. Using the `env` key in your workflow file

You can set environment variables at different levels in your workflow:

- Workflow level (applies to all jobs)
- Job level (applies to all steps in a job)
- Step level (applies only to that step)

Example:

```yaml
name: Deploy to AWS

# Workflow-level environment variables
env:
  DEFAULT_AWS_REGION: us-east-1

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    # Job-level environment variables
    env:
      DEPLOYMENT_ENV: production
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v2
      
    - name: Example step with environment variables
      # Step-level environment variables
      env:
        STEP_VAR: example-value
      run: |
        echo "Using AWS region: $DEFAULT_AWS_REGION"
        echo "Deployment environment: $DEPLOYMENT_ENV"
        echo "Step variable: $STEP_VAR"
```

### 2. Using GitHub Environment Variables

GitHub Actions provides default environment variables that are available to every workflow run. You can also set custom environment variables in the GitHub UI.

To set custom environment variables:

1. Go to your GitHub repository
2. Click on "Settings" tab
3. In the left sidebar, click on "Environments"
4. Click "New environment" or select an existing one
5. Add environment variables under "Environment variables"

## Using Environment Variables in Our Workflow

In our workflow, we've set up the AWS region with a default value:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v1
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION || 'us-east-1' }}
```

This means:
- If you've set the `AWS_REGION` secret, it will use that value
- If not, it will default to 'us-east-1'

## Troubleshooting

If you encounter issues with secrets or environment variables:

1. Check that your secrets are correctly set:
   ```bash
   gh secret list
   ```

2. Verify that your workflow is using the correct secret names:
   ```yaml
   aws-region: ${{ secrets.AWS_REGION }}  # Must match exactly
   ```

3. Remember that secrets are case-sensitive

4. If you update a secret, the new value will only be available in future workflow runs

5. Secrets are not passed to workflows that are triggered by a pull request from a fork