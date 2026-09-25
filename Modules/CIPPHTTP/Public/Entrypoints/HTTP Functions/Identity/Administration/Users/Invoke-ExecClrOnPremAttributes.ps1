function Invoke-ExecClrOnPremAttributes {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    # Object ID of the cloud-only user whose on-premises attributes should be cleared
    $UserID = $Request.Body.ID
    # On-premises attributes to clear (onPremisesImmutableId, onPremisesDistinguishedName, ...), as plain names or {label,value} objects. Omit to clear every clearable attribute.
    $Attributes = @($Request.Body.Attributes | ForEach-Object { $_.value ?? $_ } | Where-Object { $_ })

    try {
        $Result = Clear-CIPPOnPremisesAttributes -UserID $UserID -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Attributes $Attributes
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{'Results' = $Result } })
}
