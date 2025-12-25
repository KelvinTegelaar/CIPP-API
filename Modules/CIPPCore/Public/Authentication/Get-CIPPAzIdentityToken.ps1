function Get-CIPPAzIdentityToken {
    <#
    .SYNOPSIS
        Get the Azure Identity token for Managed Identity
    .DESCRIPTION
        This function retrieves the Azure Identity token using the Managed Identity endpoint for the specified resource.
        Tokens are cached per resource URL until expiration to reduce redundant API calls.
    .PARAMETER ResourceUrl
        The Azure resource URL to get a token for. Defaults to 'https://management.azure.com/' for Azure Resource Manager.

        Common resources:
        - https://management.azure.com/ (Azure Resource Manager - default)
        - https://vault.azure.net (Azure Key Vault)
        - https://api.loganalytics.io (Log Analytics / Application Insights)
        - https://storage.azure.com/ (Azure Storage)
    .PARAMETER SkipCache
        Force a new token to be fetched, bypassing the cache.
    .EXAMPLE
        Get-CIPPAzIdentityToken
        Gets a token for Azure Resource Manager
    .EXAMPLE
        Get-CIPPAzIdentityToken -ResourceUrl 'https://vault.azure.net'
        Gets a token for Azure Key Vault
    .EXAMPLE
        Get-CIPPAzIdentityToken -ResourceUrl 'https://api.loganalytics.io'
        Gets a token for Log Analytics API
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ResourceUrl = 'https://management.azure.com/',
        [switch]$SkipCache
    )

    $Endpoint = $env:IDENTITY_ENDPOINT
    $Secret = $env:IDENTITY_HEADER

    if (-not $Endpoint -or -not $Secret) {
        throw 'Managed Identity environment variables (IDENTITY_ENDPOINT/IDENTITY_HEADER) not found. Is Managed Identity enabled on the Function App?'
    }

    # Build cache key from resource URL
    $TokenKey = "ManagedIdentity-$ResourceUrl"

    try {
        # Check if cached token exists and is still valid
        if ($script:ManagedIdentityTokens.$TokenKey -and [int](Get-Date -UFormat %s -Millisecond 0) -lt $script:ManagedIdentityTokens.$TokenKey.expires_on -and $SkipCache -ne $true) {
            return $script:ManagedIdentityTokens.$TokenKey.access_token
        }

        # Get new token
        $EncodedResource = [System.Uri]::EscapeDataString($ResourceUrl)
        $TokenUri = "$($Endpoint)?resource=$EncodedResource&api-version=2019-08-01"
        $Headers = @{
            'X-IDENTITY-HEADER' = $Secret
        }

        $TokenResponse = Invoke-RestMethod -Method Get -Headers $Headers -Uri $TokenUri -ErrorAction Stop

        # Calculate expiration time
        $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $TokenResponse.expires_in

        # Store in cache (initialize synchronized hash table if needed)
        if (-not $script:ManagedIdentityTokens) {
            $script:ManagedIdentityTokens = [HashTable]::Synchronized(@{})
        }

        # Add expires_on to token response for tracking
        Add-Member -InputObject $TokenResponse -NotePropertyName 'expires_on' -NotePropertyValue $ExpiresOn -Force

        # Cache the token
        $script:ManagedIdentityTokens.$TokenKey = $TokenResponse

        return $TokenResponse.access_token
    } catch {
        throw "Failed to get managed identity token for resource '$ResourceUrl': $($_.Exception.Message)"
    }
}
