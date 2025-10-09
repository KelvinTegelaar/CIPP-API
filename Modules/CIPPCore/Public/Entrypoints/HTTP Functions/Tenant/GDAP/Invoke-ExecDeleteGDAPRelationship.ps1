Function Invoke-ExecDeleteGDAPRelationship {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $GDAPID = $Request.Query.GDAPId ?? $Request.Body.GDAPId
    try {
        $DELETE = New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($GDAPID)/requests" -type POST -body '{"action":"terminate"}' -tenantid $env:TenantID
        $Results = [pscustomobject]@{'Results' = "Success. GDAP relationship for $($GDAPID) been revoked" }
        Write-LogMessage -headers $Headers -API $APIName -message "Success. GDAP relationship for $($GDAPID) been revoked" -Sev 'Info'

    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
