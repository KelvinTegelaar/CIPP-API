function Get-HaloToken {
    [CmdletBinding()]
    param (
        $Configuration
    )
    if ($Configuration.ClientId) {
        $null = Connect-AzAccount -Identity
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $Configuration.ClientId
            client_secret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'HaloPSA' -AsPlainText)
            scope         = 'all'
        }
        if (!([string]::IsNullOrEmpty($Configuration.Tenant))) { $Tenant = "?tenant=$($Configuration.tenant)" }
        $token = Invoke-RestMethod -Uri "$($Configuration.AuthURL)/token$Tenant" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $token
    }
    else {
        throw 'No Halo configuration'
    }
}