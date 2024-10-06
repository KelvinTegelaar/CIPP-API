function Get-GradientToken {
    param(
        $Configuration
    )
    if ($Configuration.vendorKey) {
        $null = Connect-AzAccount -Identity
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
            Write-Error $_.Exception.Message
        }
    } catch {
        throw 'No Gradient configuration'
    }
}
