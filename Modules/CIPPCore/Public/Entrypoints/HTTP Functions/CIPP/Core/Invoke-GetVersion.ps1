Function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
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
