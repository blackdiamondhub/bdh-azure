<#
One-time setup so GitHub Actions can deploy infra/main.bicep without stored
credentials. Idempotent; rerun it if anything changes.

Creates:
  - resource group (if missing)
  - Entra app + service principal "bdh-azure-deploy"
  - federated credentials for pushes to main and for pull requests
  - Contributor on the resource group only
  - GitHub repository variables AZURE_CLIENT_ID / AZURE_TENANT_ID /
    AZURE_SUBSCRIPTION_ID / AZURE_RESOURCE_GROUP

Requires: az logged into the target tenant as an Owner of the subscription,
and gh authenticated with admin on the repo.
#>
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [string] $ResourceGroup = 'bdh-ai-rg',
    [string] $Location = 'westus3',
    [string] $Repo = 'blackdiamondhub/bdh-azure',
    [string] $AppName = 'bdh-azure-deploy'
)
$ErrorActionPreference = 'Stop'

function Invoke-Az { $out = az @args; if ($LASTEXITCODE) { throw "az $($args -join ' ') failed" }; $out }

Invoke-Az account set --subscription $SubscriptionId
$tenant = Invoke-Az account show --query tenantId -o tsv

foreach ($ns in 'Microsoft.CognitiveServices', 'Microsoft.Consumption') {
    Invoke-Az provider register --namespace $ns -o none
}

Invoke-Az group create -n $ResourceGroup -l $Location --tags project=blackdiamondhub repo=$Repo -o none
$rgId = Invoke-Az group show -n $ResourceGroup --query id -o tsv

$appId = Invoke-Az ad app list --display-name $AppName --query '[0].appId' -o tsv
if (-not $appId) { $appId = Invoke-Az ad app create --display-name $AppName --query appId -o tsv }
$spId = Invoke-Az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv
if (-not $spId) { $spId = Invoke-Az ad sp create --id $appId --query id -o tsv }

$existing = @(Invoke-Az ad app federated-credential list --id $appId --query '[].name' -o tsv)
$creds = @{
    'github-main' = "repo:${Repo}:ref:refs/heads/main"
    'github-pr'   = "repo:${Repo}:pull_request"
}
foreach ($name in $creds.Keys) {
    if ($existing -contains $name) { continue }
    $f = New-TemporaryFile
    @{ name = $name; issuer = 'https://token.actions.githubusercontent.com'
       subject = $creds[$name]; audiences = @('api://AzureADTokenExchange') } |
        ConvertTo-Json | Set-Content $f -Encoding ascii
    try { Invoke-Az ad app federated-credential create --id $appId --parameters "@$f" -o none }
    finally { Remove-Item $f }
}

$has = Invoke-Az role assignment list --assignee $spId --scope $rgId --role Contributor --query '[0].id' -o tsv
if (-not $has) {
    # A new service principal can take a few seconds to replicate.
    for ($i = 0; ; $i++) {
        az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal `
            --role Contributor --scope $rgId -o none
        if (-not $LASTEXITCODE) { break }
        if ($i -ge 5) { throw 'role assignment failed' }
        Start-Sleep 10
    }
}

gh variable set AZURE_CLIENT_ID -R $Repo -b $appId
gh variable set AZURE_TENANT_ID -R $Repo -b $tenant
gh variable set AZURE_SUBSCRIPTION_ID -R $Repo -b $SubscriptionId
gh variable set AZURE_RESOURCE_GROUP -R $Repo -b $ResourceGroup
Write-Output "Bootstrap done: app $appId, Contributor on $ResourceGroup."
