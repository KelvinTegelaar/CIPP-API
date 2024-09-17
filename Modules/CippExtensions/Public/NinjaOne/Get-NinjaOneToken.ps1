function Get-NinjaOneToken {
    [CmdletBinding()]
    param (
        $Configuration
    )


    if (!$ENV:NinjaClientSecret) {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $ClientSecret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'NinjaOne' and RowKey eq 'NinjaOne'").APIKey
        } else {
            $null = Connect-AzAccount -Identity
            $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            $ClientSecret = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'NinjaOne' -AsPlainText)
        }
    } else {
        $ClientSecret = $ENV:NinjaClientSecret
    }

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Configuration.ClientId
        client_secret = $ClientSecret
        scope         = 'monitoring management'
    }

    try {

        $token = Invoke-RestMethod -Uri "https://$($Configuration.Instance -replace '/ws','')/ws/oauth/token" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -Message $Message -sev error -API 'NinjaOne'
    }
    return $token

}
