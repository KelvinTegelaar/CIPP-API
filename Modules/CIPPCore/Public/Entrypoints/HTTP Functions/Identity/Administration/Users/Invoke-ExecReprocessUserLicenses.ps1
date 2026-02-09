function Invoke-ExecReprocessUserLicenses {
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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $UserPrincipalName = $Request.Query.userPrincipalName ?? $Request.Body.userPrincipalName

    try {
        $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$UserID/reprocessLicenseAssignment" -tenantid $TenantFilter -type POST -body '{}' -AsApp $true

        $Result = "Successfully reprocessed license assignments for user $UserPrincipalName. License assignment states will be updated shortly."
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to reprocess license assignments for $UserPrincipalName. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
