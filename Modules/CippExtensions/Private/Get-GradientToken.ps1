function Get-GradientToken {
    param(
        $Configuration
    )
    $null = Connect-AzAccount -Identity
    $partnerApiKey = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "Gradient" -AsPlainText)
    $authorizationToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($configuration.vendorApiKey):$($partnerApiKey)"))
    Write-Host "Partnerapikey: $partnerApiKey"
    Write-Host "configuration: $($Configuration | ConvertTo-Json -Compress)"
    $headers = [hashtable]@{
        'Accept'         = 'application/json'
        'GRADIENT-TOKEN' = $authorizationToken
    }

    try {
        return [hashtable]$headers
    }
    catch {
        Write-Error $_.Exception.Message
    }
}
