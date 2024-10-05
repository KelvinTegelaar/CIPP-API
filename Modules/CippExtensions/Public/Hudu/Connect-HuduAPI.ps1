function Connect-HuduAPI {
    [CmdletBinding()]
    param (
        $Configuration
    )

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $APIKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Hudu' and RowKey eq 'Hudu'").APIKey
    } else {
        $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        $null = Connect-AzAccount -Identity
        $APIKey = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'Hudu' -AsPlainText)
    }
    New-HuduBaseURL -BaseURL $Configuration.BaseURL
    New-HuduAPIKey -ApiKey $APIKey
}
