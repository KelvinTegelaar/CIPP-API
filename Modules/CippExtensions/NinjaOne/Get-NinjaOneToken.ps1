function Get-NinjaOneToken {
    [CmdletBinding()]
    param (
        $Configuration 
    )
    ################## TO DO CONVERT TO KEY VAULT BEFORE COMMIT ###################################
    #$null = Connect-AzAccount -Identity
    #$body = @{
    #    grant_type    = 'client_credentials'
    #    client_id     = $Configuration.ClientId
    #    client_secret = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "NinjaOne" -AsPlainText)
    #    scope         = 'monioring management'
    #}

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Configuration.ClientId
        client_secret = $Configuration.TEMPSECRETCHANGEME
        scope         = 'monitoring management'
    }

    $token = Invoke-RestMethod -Uri "https://$($Configuration.Instance -replace '/ws','')/ws/oauth/token" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $token

}