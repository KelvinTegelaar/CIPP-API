function Invoke-AddAssignmentFilterTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $GUID = $Request.Body.GUID ?? (New-Guid).GUID
    try {
        if (!$Request.Body.displayName) {
            throw 'You must enter a displayname'
        }

        if (!$Request.Body.rule) {
            throw 'You must enter a filter rule'
        }

        if (!$Request.Body.platform) {
            throw 'You must select a platform'
        }

        # Normalize field names to handle different casing from various forms
        $displayName = $Request.Body.displayName ?? $Request.Body.Displayname ?? $Request.Body.displayname
        $description = $Request.Body.description ?? $Request.Body.Description
        $platform = $Request.Body.platform
        $rule = $Request.Body.rule
        $assignmentFilterManagementType = $Request.Body.assignmentFilterManagementType ?? 'devices'

        $object = [PSCustomObject]@{
            displayName                     = $displayName
            description                     = $description
            platform                        = $platform
            rule                            = $rule
            assignmentFilterManagementType  = $assignmentFilterManagementType
            GUID                            = $GUID
        } | ConvertTo-Json
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            JSON         = "$object"
            RowKey       = "$GUID"
            PartitionKey = 'AssignmentFilterTemplate'
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created Assignment Filter template named $displayName with GUID $GUID" -Sev 'Debug'

        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Assignment Filter Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Assignment Filter Template Creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
