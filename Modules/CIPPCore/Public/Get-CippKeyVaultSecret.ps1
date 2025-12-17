function Get-CippKeyVaultSecret {
    <#
    .SYNOPSIS
    Retrieves a secret from Azure Key Vault using REST API (no Az.KeyVault module required)

    .DESCRIPTION
    Lightweight replacement for Get-AzKeyVaultSecret that uses REST API directly.
    Significantly faster as it doesn't require loading the Az.KeyVault module.

    .PARAMETER VaultName
    Name of the Key Vault. If not provided, derives from WEBSITE_DEPLOYMENT_ID environment variable.

    .PARAMETER Name
    Name of the secret to retrieve.

    .PARAMETER AsPlainText
    Returns the secret value as plain text instead of SecureString.

    .EXAMPLE
    Get-CippKeyVaultSecret -Name 'ApplicationID' -AsPlainText

    .EXAMPLE
    Get-CippKeyVaultSecret -VaultName 'mykeyvault' -Name 'RefreshToken' -AsPlainText
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )

    try {
        # Derive vault name if not provided
        if (-not $VaultName) {
            if ($env:WEBSITE_DEPLOYMENT_ID) {
                $VaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            } else {
                throw "VaultName not provided and WEBSITE_DEPLOYMENT_ID environment variable not set"
            }
        }

        # Get access token for Key Vault
        $token = Get-CIPPAzIdentityToken -ResourceUrl "https://vault.azure.net"

        # Call Key Vault REST API
        $uri = "https://$VaultName.vault.azure.net/secrets/$Name`?api-version=7.4"
        $response = Invoke-RestMethod -Uri $uri -Headers @{
            Authorization = "Bearer $token"
        } -Method Get -ErrorAction Stop

        # Return based on AsPlainText switch
        if ($AsPlainText) {
            return $response.value
        } else {
            # Return object similar to Get-AzKeyVaultSecret for compatibility
            return @{
                SecretValue = ($response.value | ConvertTo-SecureString -AsPlainText -Force)
                Name = $Name
                VaultName = $VaultName
            }
        }
    } catch {
        Write-Error "Failed to retrieve secret '$Name' from vault '$VaultName': $($_.Exception.Message)"
        throw
    }
}
