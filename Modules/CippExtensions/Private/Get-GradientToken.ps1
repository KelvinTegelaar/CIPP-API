function Get-GradientToken {
    param(
        $Configuration
    )
    $partnerApiKey = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "Gradient" -AsPlainText)
    $authorizationToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($configuration.vendorApiKey):$($partnerApiKey)"))

    $headers = @{
        'Accept'         = 'application/json'
        'GRADIENT-TOKEN' = $authorizationToken
    }

    try {
        return $headers
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
