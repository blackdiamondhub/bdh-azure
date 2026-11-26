// BlackDiamondHub cloud AI: one Azure AI Services account with the model
// deployments the hub assistant uses. Deployed at resource-group scope by
// .github/workflows/deploy.yml.

@description('Azure region. Must offer the realtime models as GlobalStandard.')
param location string = resourceGroup().location

@description('Globally unique account name; also the endpoint subdomain.')
param accountName string

@description('Model deployments. The deployment name is what apps select in their settings.')
param deployments array

@description('Monthly cost budget for this resource group (USD). 0 disables it.')
param monthlyBudget int = 0

@description('First day of the budget period (yyyy-MM-01). Fixed so redeploys do not move it.')
param budgetStartDate string = '2026-11-01'

@description('Email addresses notified at 50/80/100% of the budget.')
param budgetEmails array = []

var tags = {
  project: 'blackdiamondhub'
  repo: 'blackdiamondhub/bdh-azure'
}

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  tags: tags
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    // Hub apps authenticate with an account key stored as an app secret.
    disableLocalAuth: false
  }
}

// Deployments on one account must be created one at a time.
@batchSize(1)
resource modelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [
  for d in deployments: {
    parent: account
    name: d.name
    sku: {
      name: d.?sku ?? 'GlobalStandard'
      capacity: d.capacity
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: d.model
        version: d.version
      }
      versionUpgradeOption: 'NoAutoUpgrade'
    }
  }
]

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = if (monthlyBudget > 0 && !empty(budgetEmails)) {
  name: 'bdh-ai-monthly'
  properties: {
    category: 'Cost'
    amount: monthlyBudget
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: budgetEmails
      }
      actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: budgetEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: budgetEmails
      }
    }
  }
}

output endpoint string = account.properties.endpoint
output realtimeEndpoint string = 'wss://${accountName}.openai.azure.com/openai/realtime'
output deploymentNames array = [for d in deployments: d.name]
