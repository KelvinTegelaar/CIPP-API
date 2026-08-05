function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Compares the caller's reported CIPP version against the latest published release and reports whether the frontend or the API is out of date.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $CIPPVersion = $request.query.LocalVersion

    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Version
        })
}
