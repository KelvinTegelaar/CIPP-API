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
    if (!$Request.Body.displayName) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Assignment Filter Template Creation failed: You must enter a displayname' } })
    }

    if (!$Request.Body.rule) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Assignment Filter Template Creation failed: You must enter a filter rule' } })
    }

    if (!$Request.Body.platform) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Assignment Filter Template Creation failed: You must select a platform' } })
    }

    try {
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
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant 'Global' -message "Created Assignment Filter template named $displayName with GUID $GUID" -Sev 'Info'

        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant 'Global' -message "Assignment Filter Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Assignment Filter Template Creation failed: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
