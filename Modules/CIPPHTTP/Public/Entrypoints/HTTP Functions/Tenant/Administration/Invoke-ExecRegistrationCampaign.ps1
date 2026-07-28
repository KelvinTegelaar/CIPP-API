function Invoke-ExecRegistrationCampaign {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter

    if (-not $TenantFilter) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: tenantFilter is required' }
        }
    }

    if ($null -ne $Request.Body.snoozeDurationInDays -and ([int]$Request.Body.snoozeDurationInDays -lt 0 -or [int]$Request.Body.snoozeDurationInDays -gt 14)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: snoozeDurationInDays must be between 0 and 14' }
        }
    }

    try {
        # Build include/exclude target lists; $null means "keep what is currently configured"
        $IncludeSpecified = ($null -ne $Request.Body.includeAllUsers) -or ($null -ne $Request.Body.includeGroups) -or ($null -ne $Request.Body.includeUsers)
        $IncludeTargets = if ($IncludeSpecified) {
            if ([bool]$Request.Body.includeAllUsers) {
                @(@{ id = 'all_users'; targetType = 'group' })
            } else {
                $Targets = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($GroupId in @($Request.Body.includeGroups)) {
                    if ($GroupId) { $Targets.Add(@{ id = "$GroupId"; targetType = 'group' }) }
                }
                foreach ($UserId in @($Request.Body.includeUsers)) {
                    if ($UserId) { $Targets.Add(@{ id = "$UserId"; targetType = 'user' }) }
                }
                @($Targets)
            }
        } else { $null }

        $ExcludeSpecified = ($null -ne $Request.Body.excludeGroups) -or ($null -ne $Request.Body.excludeUsers)
        $ExcludeTargets = if ($ExcludeSpecified) {
            $Targets = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($GroupId in @($Request.Body.excludeGroups)) {
                if ($GroupId) { $Targets.Add(@{ id = "$GroupId"; targetType = 'group' }) }
            }
            foreach ($UserId in @($Request.Body.excludeUsers)) {
                if ($UserId) { $Targets.Add(@{ id = "$UserId"; targetType = 'user' }) }
            }
            @($Targets)
        } else { $null }

        $CampaignParams = @{
            Tenant                                 = $TenantFilter
            State                                  = $Request.Body.state.value ?? $Request.Body.state
            TargetedAuthenticationMethod           = $Request.Body.targetedAuthenticationMethod.value ?? $Request.Body.targetedAuthenticationMethod
            SnoozeDurationInDays                   = $Request.Body.snoozeDurationInDays
            EnforceRegistrationAfterAllowedSnoozes = $Request.Body.enforceRegistrationAfterAllowedSnoozes
            IncludeTargets                         = $IncludeTargets
            ExcludeTargets                         = $ExcludeTargets
            APIName                                = $APIName
            Headers                                = $Headers
        }
        $Result = Set-CIPPRegistrationCampaign @CampaignParams
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
