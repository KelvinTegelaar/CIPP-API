function Invoke-ExecRemoveAppAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    .DESCRIPTION
        Removes one assignment from an Intune app and keeps the rest.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Intune app id.
    $AppId = $Request.Body.ID
    # Id of the assignment to remove.
    $AssignmentId = $Request.Body.AssignmentId

    if (-not $AppId -or -not $AssignmentId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID and AssignmentId are required' } })
    }

    try {
        $Existing = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assignments" -tenantid $TenantFilter)
        $Removed = $null
        $Kept = [System.Collections.Generic.List[object]]::new()
        foreach ($Assignment in $Existing) {
            if ($Assignment.id -eq $AssignmentId) { $Removed = $Assignment; continue }
            $Entry = @{
                '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                target        = $Assignment.target
                intent        = $Assignment.intent
            }
            # Graph rejects settings on exclusion targets.
            if ($Assignment.target.'@odata.type' -ne '#microsoft.graph.exclusionGroupAssignmentTarget' -and $null -ne $Assignment.settings) {
                $Entry.settings = $Assignment.settings
            }
            $Kept.Add($Entry)
        }
        if (-not $Removed) {
            throw [System.Management.Automation.ItemNotFoundException]::new("Assignment $AssignmentId was not found on app $AppId. It may already have been removed.")
        }

        $Body = ConvertTo-Json -InputObject @{ mobileAppAssignments = @($Kept) } -Compress -Depth 10
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assign" -tenantid $TenantFilter -type POST -body $Body
        $Result = "Removed the assignment from app $AppId"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove the assignment from app $AppId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
