function Invoke-ExecPIMRoleAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .SYNOPSIS
        Change a directory role assignment through PIM in the secure direction only.
    .DESCRIPTION
        Converts a permanent assignment to eligible, grants a time-bound active assignment, extends or renews a time-bound assignment or eligibility, or removes an assignment. Every request must carry an expiration (a duration or an end date); permanent / no-expiration assignments are refused, as are changes to group-inherited rows, the CIPP-SAM application and the last active Global Administrator. Requires Entra ID P2.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    # ConvertToEligible | GrantActive | Extend | Renew | Remove
    $Action = $Request.Body.Action.value ?? $Request.Body.Action
    # Object id of the user, group or service principal.
    $PrincipalId = $Request.Body.PrincipalId.value ?? $Request.Body.PrincipalId
    # Role template id (roleDefinitionId as PIM reports it).
    $RoleDefinitionId = $Request.Body.RoleDefinitionId.value ?? $Request.Body.RoleDefinitionId
    # '/' for the whole directory or '/administrativeUnits/{id}'.
    $DirectoryScopeId = $Request.Body.DirectoryScopeId.value ?? $Request.Body.DirectoryScopeId
    # The row's current assignment type: Permanent | Active | ActivatedFromEligible | Eligible
    $AssignmentType = $Request.Body.AssignmentType.value ?? $Request.Body.AssignmentType
    # ISO 8601 lifetime such as PT4H or P1Y. Use either Duration or EndDateTime, not both.
    $Duration = $Request.Body.Duration.value ?? $Request.Body.Duration
    # The dialog's "Custom end date" option carries no lifetime of its own; EndDateTime does.
    if ("$Duration" -eq 'custom') { $Duration = $null }
    # Absolute end (unix seconds or ISO 8601). Use either Duration or EndDateTime, not both.
    $EndDateTimeRaw = $Request.Body.EndDateTime.value ?? $Request.Body.EndDateTime
    # IANA time zone of the browser (e.g. Australia/Perth); only used to word the end time in the result.
    $TimeZone = [string]($Request.Body.TimeZone.value ?? $Request.Body.TimeZone)
    # Reason recorded on the PIM request and in the CIPP logbook.
    $Justification = $Request.Body.Justification

    $Fail = {
        param([string]$Message, [HttpStatusCode]$Status = [HttpStatusCode]::BadRequest)
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error'
        return [HttpResponseContext]@{
            StatusCode = $Status
            Body       = @{ Results = @(@{ resultText = $Message; state = 'error' }) }
        }
    }

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($Action) -or [string]::IsNullOrWhiteSpace($PrincipalId) -or [string]::IsNullOrWhiteSpace($RoleDefinitionId)) {
        return (& $Fail 'tenantFilter, Action, PrincipalId and RoleDefinitionId are required.')
    }
    if ($Action -notin @('ConvertToEligible', 'GrantActive', 'Extend', 'Renew', 'Remove')) {
        return (& $Fail "Action '$Action' is not supported. Use ConvertToEligible, GrantActive, Extend, Renew or Remove.")
    }
    if ([string]::IsNullOrWhiteSpace($Justification)) {
        return (& $Fail 'A justification is required.')
    }
    if ("$Duration" -match '^\s*(noExpiration|permanent|never|none|unlimited)\s*$' -or "$EndDateTimeRaw" -match '^\s*(noExpiration|permanent|never|none|unlimited)\s*$') {
        return (& $Fail 'Permanent (no-expiration) assignments cannot be created through CIPP. Supply a duration or an end date.')
    }

    $EndDateTime = $null
    if (-not [string]::IsNullOrWhiteSpace("$EndDateTimeRaw")) {
        try {
            $EndDateTime = if ("$EndDateTimeRaw" -match '^\d{9,11}$') {
                ([System.DateTimeOffset]::FromUnixTimeSeconds([int64]$EndDateTimeRaw)).UtcDateTime
            } else {
                ([datetime]$EndDateTimeRaw).ToUniversalTime()
            }
        } catch {
            return (& $Fail "EndDateTime '$EndDateTimeRaw' is not a valid date.")
        }
    }

    if ($Action -ne 'Remove' -and $Action -ne 'ConvertToEligible' -and [string]::IsNullOrWhiteSpace($Duration) -and $null -eq $EndDateTime) {
        return (& $Fail "$Action requires a Duration or an EndDateTime; CIPP never creates permanent assignments.")
    }
    if (-not [string]::IsNullOrWhiteSpace($Duration) -and $null -ne $EndDateTime) {
        return (& $Fail 'Supply either Duration or EndDateTime, not both.')
    }

    $Params = @{
        TenantFilter     = $TenantFilter
        Action           = $Action
        PrincipalId      = $PrincipalId
        RoleDefinitionId = $RoleDefinitionId
        DirectoryScopeId = if ([string]::IsNullOrWhiteSpace($DirectoryScopeId)) { '/' } else { $DirectoryScopeId }
        Justification    = $Justification
        Headers          = $Headers
        APIName          = $APIName
    }
    if ($AssignmentType -in @('Permanent', 'Active', 'ActivatedFromEligible', 'Eligible')) { $Params.AssignmentType = $AssignmentType }
    if (-not [string]::IsNullOrWhiteSpace($Duration)) { $Params.Duration = $Duration }
    if ($null -ne $EndDateTime) { $Params.EndDateTime = $EndDateTime }
    if (-not [string]::IsNullOrWhiteSpace($TimeZone)) { $Params.TimeZone = $TimeZone }

    try {
        $Result = Invoke-CIPPPIMAssignmentAction @Params
        $StatusCode = [HttpStatusCode]::OK
        $Results = @(@{ resultText = $Result.resultText; state = 'success' })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "PIM $Action failed for $PrincipalId on $RoleDefinitionId`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Results = @(@{ resultText = $Message; state = 'error' })
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
