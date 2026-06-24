function Get-CIPPManagedIdentityResourceId {
    <#
    .SYNOPSIS
        Get the Azure resource ID that the Function App's managed identity belongs to.
    .DESCRIPTION
        Reads the 'xms_mirid' claim from a managed identity access token. For a system-assigned
        identity (which CIPP uses), this claim is the ARM resource ID of the host resource itself
        - i.e. the Function App site, including its resource group:

            /subscriptions/{sub}/resourcegroups/{rg}/providers/Microsoft.Web/sites/{site}

        This is the most reliable in-process source for the site's resource group because it is
        present in every managed identity token, requires no extra ARM/Graph call, and - unlike
        parsing WEBSITE_OWNER_NAME - always names the site's RG rather than the App Service Plan's
        webspace RG.

        Note: for a user-assigned identity, xms_mirid points at the userAssignedIdentities resource
        instead, which may live in a different RG. Callers that need the site's RG should validate
        the returned ID against the expected site (see Get-CIPPFunctionAppResourceGroup).
    .PARAMETER ResourceUrl
        The Azure resource URL to request the token for. Defaults to Azure Resource Manager.
    .EXAMPLE
        Get-CIPPManagedIdentityResourceId
        Returns e.g. /subscriptions/.../resourcegroups/CIPP-myinstance/providers/Microsoft.Web/sites/cippabcde
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ResourceUrl = 'https://management.azure.com/'
    )

    $Token = Get-CIPPAzIdentityToken -ResourceUrl $ResourceUrl
    if (-not $Token) {
        throw 'Could not acquire a managed identity token to read the xms_mirid claim.'
    }

    # JWT payload is the second dot-delimited segment, base64url-encoded.
    $Parts = $Token.Split('.')
    if ($Parts.Count -lt 2) {
        throw 'Managed identity token is not a well-formed JWT.'
    }

    $Payload = $Parts[1].Replace('-', '+').Replace('_', '/')
    switch ($Payload.Length % 4) {
        2 { $Payload += '==' }
        3 { $Payload += '=' }
    }

    $Claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json
    return $Claims.xms_mirid
}
