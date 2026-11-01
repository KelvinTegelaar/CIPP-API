function Invoke-AddEnrollmentRestrictionTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Autopilot.ReadWrite
    .DESCRIPTION
        Saves an enrollment (device type) restriction template: platform settings, priority and assignment (all users, or group names with wildcards). Pass GUID to update an existing template. Accepts the template form or a row from ListEnrollmentRestrictions, so a tenant's restriction can be saved as a template.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject $Request.Body
        $null = New-CIPPEnrollmentRestrictionBody -Settings $Settings
        if ([string]::IsNullOrWhiteSpace($Settings.displayName)) { throw 'A restriction name is required.' }
        if ($Settings.AssignTo -eq 'customGroup' -and [string]::IsNullOrWhiteSpace($Settings.customGroup)) { throw 'Enter the names of the groups to assign the restriction to.' }
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Enrollment restriction template not saved: $($_.Exception.Message)" }
            })
    }

    try {
        $GUID = "$($Request.Body.GUID)"
        if ([string]::IsNullOrWhiteSpace($GUID)) { $GUID = (New-Guid).Guid }
        $Settings | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            JSON         = "$(ConvertTo-Json -InputObject $Settings -Depth 10 -Compress)"
            RowKey       = $GUID
            PartitionKey = 'EnrollmentRestrictionTemplate'
        }
        $Result = "Saved enrollment restriction template '$($Settings.displayName)'"
        Write-LogMessage -Headers $Headers -API $APIName -tenant 'Global' -message "$Result with GUID $GUID" -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to save enrollment restriction template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
