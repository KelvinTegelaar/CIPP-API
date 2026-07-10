function Set-CippKeyVaultSecret {
    <#
    .SYNOPSIS
    Sets a secret in Azure Key Vault using REST API (no Az.KeyVault module required)

    .DESCRIPTION
    Lightweight replacement for Set-AzKeyVaultSecret that uses REST API directly.
    Significantly faster as it doesn't require loading the Az.KeyVault module.

    .PARAMETER VaultName
    Name of the Key Vault. If not provided, derives from WEBSITE_DEPLOYMENT_ID environment variable.

    .PARAMETER Name
    Name of the secret to set.

    .PARAMETER SecretValue
    The secret value as a SecureString.

    .EXAMPLE
    $secret = ConvertTo-SecureString -String 'mypassword' -AsPlainText -Force
    Set-CippKeyVaultSecret -Name 'MySecret' -SecretValue $secret

    .EXAMPLE
    Set-CippKeyVaultSecret -VaultName 'mykeyvault' -Name 'RefreshToken' -SecretValue $secureToken
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [securestring]$SecretValue
    )

    try {
        # Derive vault name if not provided
        if (-not $VaultName) {
            $VaultName = Get-CippKeyVaultName
            if (-not $VaultName) {
                throw 'VaultName not provided and could not be derived (WEBSITE_SITE_NAME / WEBSITE_DEPLOYMENT_ID not set)'
            }
        }

        # Get access token for Key Vault
        $token = Get-CIPPAzIdentityToken -ResourceUrl "https://vault.azure.net"

        # Convert SecureString to plain text
        $plainText = [System.Net.NetworkCredential]::new('', $SecretValue).Password

        # Prepare request body
        $body = @{ value = $plainText } | ConvertTo-Json

        # Call Key Vault REST API
        $uri = "https://$VaultName.vault.azure.net/secrets/$Name`?api-version=7.4"
        $response = Invoke-CIPPRestMethod -Uri $uri -Headers @{
            Authorization = "Bearer $token"
            'Content-Type' = 'application/json'
        } -Method Put -Body $body -ErrorAction Stop

        # Return object similar to Set-AzKeyVaultSecret for compatibility
        return @{
            Name = $Name
            VaultName = $VaultName
            Id = $response.id
            Enabled = $response.attributes.enabled
            Created = $response.attributes.created
            Updated = $response.attributes.updated
        }
    } catch {
        Write-Error "Failed to set secret '$Name' in vault '$VaultName': $($_.Exception.Message)"
        throw
    }
}
