function Get-CIPPAzIdentityToken {
    <#
    .SYNOPSIS
        Get the Azure Identity token for Managed Identity
    .DESCRIPTION
        This function retrieves the Azure Identity token using the Managed Identity endpoint
    .EXAMPLE
        Get-CIPPAzIdentityToken
    #>
    [CmdletBinding()]
    param()

    $Endpoint = $env:IDENTITY_ENDPOINT
    $Secret = $env:IDENTITY_HEADER
    $ResourceURI = 'https://management.azure.com/'

    if (-not $Endpoint -or -not $Secret) {
        throw 'Managed Identity environment variables (IDENTITY_ENDPOINT/IDENTITY_HEADER) not found. Is Managed Identity enabled on the Function App?'
    }

    $TokenUri = "$($Endpoint)?resource=$($ResourceURI)&api-version=2019-08-01"
    $Headers = @{
        'X-IDENTITY-HEADER' = $Secret
    }

    $TokenResponse = Invoke-RestMethod -Method Get -Headers $Headers -Uri $TokenUri
    return $TokenResponse.access_token
}
