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
        $headers = @{
            Authorization  = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        $response = Invoke-CIPPRestMethod -Uri $uri -Headers $headers -Method Put -Body $body -SkipHttpErrorCheck -StatusCodeVariable KvStatus -ErrorAction Stop

        if ($KvStatus -eq 409) {
            # Soft delete (mandatory on all vaults) reserves a deleted secret's name
            # for the retention window, and the PUT 409s until it is recovered or
            # purged. This is exactly what re-running setup hits after an instance
            # reset deleted the SAM secrets. Recover the deleted secret, then retry
            # the write - recovery is asynchronous, so poll until the name is live.
            Write-Information "Secret '$Name' is soft-deleted and blocking the write - recovering it"
            $null = Invoke-CIPPRestMethod -Uri "https://$VaultName.vault.azure.net/deletedsecrets/$Name/recover?api-version=7.4" -Headers $headers -Method Post -ErrorAction Stop
            $Deadline = [DateTime]::UtcNow.AddSeconds(60)
            do {
                Start-Sleep -Seconds 3
                $response = Invoke-CIPPRestMethod -Uri $uri -Headers $headers -Method Put -Body $body -SkipHttpErrorCheck -StatusCodeVariable KvStatus -ErrorAction Stop
            } while ($KvStatus -eq 409 -and [DateTime]::UtcNow -lt $Deadline)
        }

        if ($KvStatus -ge 400) {
            $KvError = $response.error.message ?? ($response | ConvertTo-Json -Depth 5 -Compress)
            throw "Key Vault returned $KvStatus for secret '$Name': $KvError"
        }

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
        # ErrorDetails carries the response body (Invoke-CIPPRestMethod attaches it),
        # which holds the actual Key Vault error - the exception message alone is
        # just the status line
        $Detail = $_.ErrorDetails.Message ?? $_.Exception.Message
        Write-Error "Failed to set secret '$Name' in vault '$VaultName': $Detail"
        throw
    }
}
