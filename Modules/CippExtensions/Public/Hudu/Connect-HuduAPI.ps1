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
    # Add logic to check if we're using CloudFlare Tunnel (if Hudu.CFEnabled checkbox is checked from Extensions.json). If the checkbox is checked, pull CloudFlare ClientID and API Key and add as a header
    if ($Configuration.CFEnabled) {
        $CFClientID = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'CloudFlareClientID' -AsPlainText)
        $CFAPIKey = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'CloudFlareAPIKey' -AsPlainText)
        New-HuduCustomHeaders -Headers @{"CF-Access-Client-Id" = "$CFClientID"; "CF-Access-Client-Secret" = "$CFAPIKey"}
    }
    New-HuduBaseURL -BaseURL $Configuration.BaseURL
    New-HuduAPIKey -ApiKey $APIKey
}
