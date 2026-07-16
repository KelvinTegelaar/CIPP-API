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
    $ExcludeGroupIdsRaw = $Request.Body.ExcludeGroupIds
    $ExcludeGroupNamesRaw = $Request.Body.ExcludeGroupNames
    $GroupIdsRaw = $Request.Body.GroupIds
    $GroupNamesRaw = $Request.Body.GroupNames
    $AssignmentMode = $Request.Body.assignmentMode
    $AssignmentDirection = $Request.Body.assignmentDirection
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
    $ExcludeGroupIds = Get-StandardizedList -InputObject $ExcludeGroupIdsRaw
    $ExcludeGroupNames = Get-StandardizedList -InputObject $ExcludeGroupNamesRaw

    # Validate and default AssignmentMode
    if ([string]::IsNullOrWhiteSpace($AssignmentMode)) {
        $AssignmentMode = 'append'
    }

    $AssignTo = if ($AssignTo -ne 'on') { $AssignTo }

    # assignmentDirection is sent only by the Custom Group action and switches that request to
    # direction-scoped Replace (preserve the other direction + All Users/All Devices broad targets).
    if (-not [string]::IsNullOrWhiteSpace($AssignmentDirection)) {
        $AssignmentDirection = $AssignmentDirection.ToLower()
        if ($AssignmentDirection -notin @('include', 'exclude')) {
            $AssignmentDirection = $null
        }
    } else {
        $AssignmentDirection = $null
    }

    # 'Clear all exclusions' is a Custom Group Exclude + Replace request with no groups selected.
    $IsClearExclusions = ($AssignmentDirection -eq 'exclude') -and ($AssignmentMode -eq 'replace')

    # Safety net for legacy/API callers (no assignmentDirection): an exclude-only request in
    # 'replace' mode would post just the exclusion target and wipe every existing assignment. The
    # Custom Group action sends assignmentDirection and uses direction-scoped Replace instead.
    $IsExcludeOnly = (-not $AssignTo -and @($GroupIds).Count -eq 0 -and @($GroupNames).Count -eq 0) -and
    (@($ExcludeGroupIds).Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ExcludeGroup))
    if ($IsExcludeOnly -and $AssignmentMode -eq 'replace' -and -not $AssignmentDirection) {
        $AssignmentMode = 'append'
    }

    $Results = try {
        if ($AssignTo -or @($GroupIds).Count -gt 0 -or @($ExcludeGroupIds).Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ExcludeGroup) -or $IsClearExclusions) {
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

            if (@($ExcludeGroupIds).Count -gt 0) {
                $params.ExcludeGroupIds = @($ExcludeGroupIds)
            }

            if (@($ExcludeGroupNames).Count -gt 0) {
                $params.ExcludeGroupNames = @($ExcludeGroupNames)
            }

            if ($AssignmentDirection) {
                $params.AssignmentDirection = $AssignmentDirection
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
