function Get-HaloToken {
    [CmdletBinding()]
    param (
        $Configuration
    )
    if (![string]::IsNullOrEmpty($Configuration.ClientID)) {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'HaloPSA' and RowKey eq 'HaloPSA'").APIKey
        } else {
            $null = Connect-AzAccount -Identity
            $VaultName = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HaloPSA' -AsPlainText
        }
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $Configuration.ClientID
            client_secret = $Secret
            scope         = 'all'
        }
        Write-Host ($body | ConvertTo-Json)
        if ($Configuration.Tenant -ne 'None') { $Tenant = "?tenant=$($Configuration.Tenant)" }
        $token = Invoke-RestMethod -Uri "$($Configuration.AuthURL)/token$Tenant" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $token
    } else {
        throw 'No Halo configuration'
    }
}
