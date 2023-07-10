function Get-HaloToken {
    [CmdletBinding()]
    param (
        $Configuration 
    )
    $null = Connect-AzAccount -Identity
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Configuration.ClientId
        client_secret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "HaloPSA" -AsPlainText)
        scope         = 'all'
    }
    $token = Invoke-RestMethod -Uri "$($Configuration.AuthURL)/token?tenant=$($Configuration.tenant)" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $token

}