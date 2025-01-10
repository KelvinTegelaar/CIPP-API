function Get-HIBPAuth {
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'HIBP' and RowKey eq 'HIBP'").APIKey
    } else {
        $null = Connect-AzAccount -Identity
        $VaultName = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText
    }

    return @{
        'User-Agent'   = "CIPP-$($ENV:TenantId)"
        'Accept'       = 'application/json'
        'api-version'  = '3'
        'hibp-api-key' = $Secret
    }
}
