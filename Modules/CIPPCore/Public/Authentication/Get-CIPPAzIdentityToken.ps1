function Get-CIPPAzIdentityToken {
    <#
    .SYNOPSIS
        Get the Azure Identity token for Managed Identity
    .DESCRIPTION
        This function retrieves the Azure Identity token using the Managed Identity endpoint for the specified resource
    .PARAMETER ResourceUrl
        The Azure resource URL to get a token for. Defaults to 'https://management.azure.com/' for Azure Resource Manager.

        Common resources:
        - https://management.azure.com/ (Azure Resource Manager - default)
        - https://vault.azure.net (Azure Key Vault)
        - https://api.loganalytics.io (Log Analytics / Application Insights)
        - https://storage.azure.com/ (Azure Storage)
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
        [string]$ResourceUrl = 'https://management.azure.com/'
    )

    $Endpoint = $env:IDENTITY_ENDPOINT
    $Secret = $env:IDENTITY_HEADER

    if (-not $Endpoint -or -not $Secret) {
        throw 'Managed Identity environment variables (IDENTITY_ENDPOINT/IDENTITY_HEADER) not found. Is Managed Identity enabled on the Function App?'
    }

    $EncodedResource = [System.Uri]::EscapeDataString($ResourceUrl)
    $TokenUri = "$($Endpoint)?resource=$EncodedResource&api-version=2019-08-01"
    $Headers = @{
        'X-IDENTITY-HEADER' = $Secret
    }

    $TokenResponse = Invoke-RestMethod -Method Get -Headers $Headers -Uri $TokenUri
    return $TokenResponse.access_token
}
