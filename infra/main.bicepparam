using './main.bicep'

param location = 'westus3'
param accountName = 'bdh-ai-lodge'

// capacity is in thousands of tokens per minute.
param deployments = [
  {
    // Default voice model (speech in/out, function calling).
    name: 'gpt-realtime-2.1-mini'
    model: 'gpt-realtime-2.1-mini'
    version: '2026-07-07'
    capacity: 5
  }
  {
    // Higher quality voice model, selectable in the voice app settings.
    name: 'gpt-realtime-2.1'
    model: 'gpt-realtime-2.1'
    version: '2026-07-07'
    capacity: 2
  }
  {
    // Text chat and the supervisor agent.
    name: 'gpt-4.1-mini'
    model: 'gpt-4.1-mini'
    version: '2025-04-14'
    capacity: 50
  }
]

param monthlyBudget = 50
param budgetStartDate = '2026-11-01'
// Set from the BUDGET_EMAILS repository variable (comma separated) so no
// address is committed to this public repo.
param budgetEmails = empty(readEnvironmentVariable('BUDGET_EMAILS', '')) ? [] : split(readEnvironmentVariable('BUDGET_EMAILS', ''), ',')
