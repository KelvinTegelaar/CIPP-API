function Remove-CippKeyVaultSecret {
    <#
    .SYNOPSIS
    Deletes a secret from Azure Key Vault using REST API (no Az.KeyVault module required)

    .DESCRIPTION
    Lightweight replacement for Remove-AzKeyVaultSecret that uses REST API directly.

    .PARAMETER VaultName
    Name of the Key Vault. If not provided, derives from WEBSITE_DEPLOYMENT_ID environment variable.

    .PARAMETER Name
    Name of the secret to delete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        if (-not $VaultName) {
            if ($env:WEBSITE_DEPLOYMENT_ID) {
                $VaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            } else {
                throw 'VaultName not provided and WEBSITE_DEPLOYMENT_ID environment variable not set'
            }
        }

        $token = Get-CIPPAzIdentityToken -ResourceUrl 'https://vault.azure.net'
        $uri = "https://$VaultName.vault.azure.net/secrets/$Name`?api-version=7.4"

        $response = Invoke-CIPPRestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Method Delete -ErrorAction Stop

        return @{
            Name      = $Name
            VaultName = $VaultName
            Id        = $response.recoveryId
            Deleted   = $true
        }
    } catch {
        if ($_.Exception.Message -match '404|NotFound') {
            return @{
                Name      = $Name
                VaultName = $VaultName
                Id        = $null
                Deleted   = $false
                Status    = 'NotFound'
            }
        }

        Write-Error "Failed to delete secret '$Name' from vault '$VaultName': $($_.Exception.Message)"
        throw
    }
}
