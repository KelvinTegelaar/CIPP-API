function Get-GradientToken {
    param(
        $Configuration
    )
    $null = Connect-AzAccount -Identity
    $partnerApiKey = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "Gradient" -AsPlainText)
    $authorizationToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($configuration.vendorKey):$($partnerApiKey)"))

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
