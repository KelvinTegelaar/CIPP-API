function Get-GradientToken {
    param(
        $Configuration
    )
    if ($Configuration.vendorKey) {
        $null = Connect-AzAccount -Identity
        $SubscriptionId = $ENV:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
        $null = Set-AzContext -SubscriptionId $SubscriptionId
        $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        $partnerApiKey = (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name 'Gradient' -AsPlainText)
        $authorizationToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($configuration.vendorKey):$($partnerApiKey)"))

        $headers = [hashtable]@{
            'Accept'         = 'application/json'
            'GRADIENT-TOKEN' = $authorizationToken
        }

        try {
            return [hashtable]$headers
        } catch {
            return $false
        }
    } else {
        return $false
    }
}
