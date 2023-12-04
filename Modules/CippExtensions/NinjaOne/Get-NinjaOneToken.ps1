function Get-NinjaOneToken {
    [CmdletBinding()]
    param (
        $Configuration 
    )


    if (!$ENV:NinjaClientSecret) {
        $null = Connect-AzAccount -Identity
        $ClientSecret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "NinjaOne" -AsPlainText)
    } else {
        $ClientSecret = $ENV:NinjaClientSecret
    }


    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Configuration.ClientId
        client_secret = $ClientSecret
        scope         = 'monitoring management'
    }

    $token = Invoke-RestMethod -Uri "https://$($Configuration.Instance -replace '/ws','')/ws/oauth/token" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $token

}