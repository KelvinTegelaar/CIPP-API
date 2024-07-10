function Connect-HuduAPI {
    [CmdletBinding()]
    param (
        $Configuration
    )

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $APIKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Hudu' and RowKey eq 'Hudu'").APIKey
    } else {
        $null = Connect-AzAccount -Identity
        $APIKey = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'Hudu' -AsPlainText)
    }
    New-HuduBaseURL -BaseURL $Configuration.BaseURL
    New-HuduAPIKey -ApiKey $APIKey
}