function Invoke-ExecAssignPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with the body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $ID = $request.Body.ID
    $Type = $Request.Body.Type
    $AssignTo = $Request.Body.AssignTo
    $PlatformType = $Request.Body.platformType
    $ExcludeGroup = $Request.Body.excludeGroup
    $GroupIdsRaw = $Request.Body.GroupIds
    $GroupNamesRaw = $Request.Body.GroupNames
    $AssignmentMode = $Request.Body.assignmentMode
    $AssignmentFilterName = $Request.Body.AssignmentFilterName
    $AssignmentFilterType = $Request.Body.AssignmentFilterType

    # Standardize GroupIds input (can be array or comma-separated string)
    function Get-StandardizedList {
        param($InputObject)
        if ($null -eq $InputObject -or ($InputObject -is [string] -and [string]::IsNullOrWhiteSpace($InputObject))) {
            return @()
        }
        if ($InputObject -is [string]) {
            return ($InputObject -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
        if ($InputObject -is [System.Collections.IEnumerable]) {
            return @($InputObject | Where-Object { $_ })
        }
        return @($InputObject)
    }

    $GroupIds = Get-StandardizedList -InputObject $GroupIdsRaw
    $GroupNames = Get-StandardizedList -InputObject $GroupNamesRaw

    # Validate and default AssignmentMode
    if ([string]::IsNullOrWhiteSpace($AssignmentMode)) {
        $AssignmentMode = 'replace'
    }

    $AssignTo = if ($AssignTo -ne 'on') { $AssignTo }

    $Results = try {
        if ($AssignTo -or @($GroupIds).Count -gt 0) {
            $params = @{
                PolicyId       = $ID
                TenantFilter   = $TenantFilter
                GroupName      = $AssignTo
                Type           = $Type
                Headers        = $Headers
                AssignmentMode = $AssignmentMode
            }

            if (@($GroupIds).Count -gt 0) {
                $params.GroupIds = @($GroupIds)
            }

            if (@($GroupNames).Count -gt 0) {
                $params.GroupNames = @($GroupNames)
            }

            if (-not [string]::IsNullOrWhiteSpace($PlatformType)) {
                $params.PlatformType = $PlatformType
            }

            if (-not [string]::IsNullOrWhiteSpace($ExcludeGroup)) {
                $params.ExcludeGroup = $ExcludeGroup
            }

            if (-not [string]::IsNullOrWhiteSpace($AssignmentFilterName)) {
                $params.AssignmentFilterName = $AssignmentFilterName
            }

            if (-not [string]::IsNullOrWhiteSpace($AssignmentFilterType)) {
                $params.AssignmentFilterType = $AssignmentFilterType
            }

            Set-CIPPAssignedPolicy @params
            $StatusCode = [HttpStatusCode]::OK
        } else {
            'No assignments specified. No action taken.'
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results }
        })

}
