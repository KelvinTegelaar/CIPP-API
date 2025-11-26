function Invoke-ExecAssignApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $appFilter = $Request.Query.ID ?? $Request.Body.ID
    $AssignTo = $Request.Query.AssignTo ?? $Request.Body.AssignTo
    $Intent = $Request.Query.Intent ?? $Request.Body.Intent
    $AppType = $Request.Query.AppType ?? $Request.Body.AppType
    $GroupNamesRaw = $Request.Query.GroupNames ?? $Request.Body.GroupNames
    $GroupIdsRaw = $Request.Query.GroupIds ?? $Request.Body.GroupIds
    $AssignmentMode = $Request.Body.assignmentMode

    $Intent = if ([string]::IsNullOrWhiteSpace($Intent)) { 'Required' } else { $Intent }

    if ([string]::IsNullOrWhiteSpace($AssignmentMode)) {
        $AssignmentMode = 'replace'
    } else {
        $AssignmentMode = $AssignmentMode.ToLower()
        if ($AssignmentMode -notin @('replace', 'append')) {
            throw "Unsupported AssignmentMode value '$AssignmentMode'. Valid options are 'replace' or 'append'."
        }
    }

    function Get-StandardizedAssignmentList {
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

    $GroupNames = Get-StandardizedAssignmentList -InputObject $GroupNamesRaw
    $GroupIds = Get-StandardizedAssignmentList -InputObject $GroupIdsRaw

    if (-not $AssignTo -and $GroupIds.Count -eq 0 -and $GroupNames.Count -eq 0) {
        throw 'No assignment target provided. Supply AssignTo, GroupNames, or GroupIds.'
    }

    # Try to get the application type if not provided. Mostly just useful for ppl using the API that dont know the application type.
    if (-not $AppType) {
        try {
            $AppMetadata = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appFilter" -tenantid $TenantFilter
            $odataType = $AppMetadata.'@odata.type'
            if ($odataType) {
                $AppType = ($odataType -replace '#microsoft.graph.', '') -replace 'App$'
            }
        } catch {
            Write-Warning "Unable to resolve application type for $appFilter. Continuing without assignment settings."
        }
    }

    $targetLabel = if ($AssignTo) {
        $AssignTo
    } elseif ($GroupNames.Count -gt 0) {
        ($GroupNames -join ', ')
    } elseif ($GroupIds.Count -gt 0) {
        "GroupIds: $($GroupIds -join ',')"
    } else {
        'CustomGroupAssignment'
    }

    $setParams = @{
        ApplicationId  = $appFilter
        TenantFilter   = $TenantFilter
        Intent         = $Intent
        APIName        = $APIName
        Headers        = $Headers
        GroupName      = ($AssignTo ? $AssignTo : $targetLabel)
        AssignmentMode = $AssignmentMode
    }

    if ($AppType) {
        $setParams.AppType = $AppType
    }

    if ($GroupIds.Count -gt 0) {
        $setParams.GroupIds = $GroupIds
    }

    try {
        $Result = Set-CIPPAssignedApplication @setParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
