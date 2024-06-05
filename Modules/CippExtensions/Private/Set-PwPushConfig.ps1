function Set-PwPushConfig {
    param(
        $Configuration
    )
    $InitParams = @{}
    if ($Configuration.BaseUrl) {
        $InitParams.BaseUrl = $Configuration.BaseUrl
    }
    if ($Configuration.EmailAddress) {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $ApiKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'PWPush' and RowKey eq 'PWPush'").APIKey
        } else {
            $null = Connect-AzAccount -Identity
            $ApiKey = Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'PWPush' -AsPlainText
        }
        if ($ApiKey) {
            $InitParams.APIKey = $ApiKey
            $InitParams.EmailAddress = $Configuration.EmailAddress
        }
    }
    Initialize-PassPushPosh @InitParams
}