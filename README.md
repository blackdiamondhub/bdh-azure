# bdh-azure

Azure resources for BlackDiamondHub's cloud AI (the voice/chat assistant and
the supervisor agent). Everything here is deployed by CI from
[`infra/main.bicep`](infra/main.bicep); don't create or change these resources
by hand in the portal.

## What it deploys

Resource group `bdh-ai-rg` (westus3) in Stefan's Visual Studio Enterprise
subscription:

| Resource | Purpose |
|---|---|
| Azure AI Services account `bdh-ai-lodge` | Endpoint `https://bdh-ai-lodge.openai.azure.com/` |
| Deployment `gpt-realtime-2.1-mini` | Default voice model (speech in/out + function calling) |
| Deployment `gpt-realtime-2.1` | Higher-quality voice model, selectable in the voice app |
| Deployment `gpt-4.1-mini` | Text chat and the supervisor agent |
| Budget `bdh-ai-monthly` | $50/month; emails at 50% and 80% actual and 100% forecast |

Deployment names are what hub apps put in their "model" setting. To add or
swap a model, edit `deployments` in [`infra/main.bicepparam`](infra/main.bicepparam)
and open a PR. Check availability first:

```powershell
az cognitiveservices model list -l westus3 -o json | ConvertFrom-Json |
  ? { $_.model.name -like 'gpt-realtime*' } | % { "$($_.model.name) $($_.model.version)" }
```

## CI

[`deploy.yml`](.github/workflows/deploy.yml):

- **Pull requests** build the Bicep and post an `az deployment group what-if` to the job summary.
- **Pushes to `main`** (and manual runs) deploy.

CI signs in with GitHub OIDC as the `bdh-azure-deploy` service principal, which
only has Contributor on `bdh-ai-rg`. No Azure secrets are stored in GitHub.
Repository variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_RESOURCE_GROUP`, `BUDGET_EMAILS` (comma-separated, kept out of the repo).

## One-time bootstrap

Creates the resource group, the deploy identity, its federated credentials and
role assignment, and the repository variables. It's idempotent.

```powershell
az login --tenant <tenant-id>    # an Owner of the subscription
./scripts/bootstrap.ps1 -SubscriptionId <subscription-id>
gh variable set BUDGET_EMAILS -R blackdiamondhub/bdh-azure -b "you@example.com"
```

## Giving the hub the key

Hub apps authenticate with an account key, stored as an app secret in the hub
(never committed, never in this repo):

```powershell
az cognitiveservices account keys list -g bdh-ai-rg -n bdh-ai-lodge --query key1 -o tsv
```

Paste it into the app's secret setting (for example, the Voice app's
"Azure OpenAI key") in the hub's admin Settings. Rotate with
`az cognitiveservices account keys regenerate --key-name key1` (switch the app
to `key2` first to avoid downtime).
