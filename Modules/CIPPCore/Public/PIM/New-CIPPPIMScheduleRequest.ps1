function New-CIPPPIMScheduleRequest {
    <#
    .SYNOPSIS
        Builds the body for a PIM role eligibility / role assignment schedule request.

    .DESCRIPTION
        The ONLY place in CIPP that constructs roleEligibilityScheduleRequests and
        roleAssignmentScheduleRequests bodies. It exists so that the security rule "CIPP can never
        create a permanent (no-expiration) assignment or eligibility" is enforced in one function
        that every caller - endpoints, standards, scheduled tasks - has to go through.

        Every request that creates, updates, extends or renews a schedule MUST carry an expiration,
        expressed either as an ISO 8601 duration (-Duration) or an absolute end (-EndDateTime).
        There is deliberately no parameter that produces scheduleInfo.expiration.type
        'noExpiration'; asking for it by any spelling throws. adminRemove is the one action that
        needs no schedule.

        -MaxDuration caps the effective lifetime. Callers pass the tightest applicable limit
        (role policy maximum, JIT maximum duration setting, the PIM ceiling) and the builder refuses
        anything longer rather than clamping it, so the user sees why a request was rejected.

    .PARAMETER Kind
        Eligibility -> roleEligibilityScheduleRequests; Assignment -> roleAssignmentScheduleRequests.

    .PARAMETER Action
        adminAssign | adminUpdate | adminExtend | adminRenew | adminRemove. Self-service actions
        (selfActivate, selfDeactivate, ...) are not offered: they can only be performed by the
        principal, so CIPP uses time-bound active assignments instead.

    .PARAMETER Duration
        ISO 8601 duration, e.g. PT8H, P1D, P6M, P1Y. Mutually exclusive with -EndDateTime.

    .PARAMETER EndDateTime
        Absolute end. Must be in the future. Mutually exclusive with -Duration.

    .PARAMETER StartDateTime
        Optional start; defaults to now (UTC).

    .PARAMETER MaxDuration
        ISO 8601 duration cap. The effective lifetime (Duration, or EndDateTime - start) may not
        exceed it.

    .OUTPUTS
        PSCustomObject: Uri (v1.0 Graph endpoint), Body (ordered hashtable ready for ConvertTo-Json),
        Kind, Action, ExpirationType, StartDateTime, EndDateTime (UTC, $null for adminRemove).

    .EXAMPLE
        $Req = New-CIPPPIMScheduleRequest -Kind Assignment -Action adminAssign -PrincipalId $Id -RoleDefinitionId $Role -Duration 'PT4H' -Justification 'Ticket 1234' -MaxDuration 'PT8H'
        New-GraphPOSTRequest -uri $Req.Uri -body ($Req.Body | ConvertTo-Json -Depth 10) -tenantid $Tenant -AsApp $true

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Eligibility', 'Assignment')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [ValidateSet('adminAssign', 'adminUpdate', 'adminExtend', 'adminRenew', 'adminRemove')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PrincipalId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleDefinitionId,

        [string]$DirectoryScopeId = '/',

        [string]$Justification,

        [string]$Duration,

        [datetime]$EndDateTime,

        [datetime]$StartDateTime,

        [string]$MaxDuration,

        [string]$TicketNumber,

        [string]$TicketSystem
    )

    $Uri = if ($Kind -eq 'Eligibility') {
        'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleRequests'
    } else {
        'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests'
    }

    if ([string]::IsNullOrWhiteSpace($DirectoryScopeId)) { $DirectoryScopeId = '/' }

    $Body = [ordered]@{
        action           = $Action
        principalId      = $PrincipalId
        roleDefinitionId = $RoleDefinitionId
        directoryScopeId = $DirectoryScopeId
    }
    if (-not [string]::IsNullOrWhiteSpace($Justification)) {
        $Body.justification = $Justification
    }
    if (-not [string]::IsNullOrWhiteSpace($TicketNumber)) {
        $Body.ticketInfo = @{ ticketNumber = $TicketNumber; ticketSystem = $TicketSystem }
    }

    if ($Action -eq 'adminRemove') {
        return [PSCustomObject]@{
            Uri            = $Uri
            Body           = $Body
            Kind           = $Kind
            Action         = $Action
            ExpirationType = $null
            StartDateTime  = $null
            EndDateTime    = $null
        }
    }

    # Everything below creates or changes a schedule, so it has to end.
    $PermanentPattern = '^\s*(noExpiration|permanent|never|none|unlimited)\s*$'
    if ($Duration -match $PermanentPattern) {
        throw "Refusing to build a $Kind $Action request: '$Duration' asks for a permanent (no-expiration) schedule, which CIPP never creates. Supply an ISO 8601 duration such as PT8H or P1Y."
    }

    $HasDuration = -not [string]::IsNullOrWhiteSpace($Duration)
    $HasEnd = $PSBoundParameters.ContainsKey('EndDateTime') -and $null -ne $EndDateTime
    if (-not $HasDuration -and -not $HasEnd) {
        throw "Refusing to build a $Kind $Action request without an expiration: CIPP never creates permanent (no-expiration) role schedules. Supply -Duration (ISO 8601) or -EndDateTime."
    }
    if ($HasDuration -and $HasEnd) {
        throw 'Specify either -Duration or -EndDateTime, not both.'
    }

    $NowUtc = [datetime]::UtcNow
    $Start = if ($PSBoundParameters.ContainsKey('StartDateTime') -and $null -ne $StartDateTime) {
        $StartDateTime.ToUniversalTime()
    } else {
        $NowUtc
    }

    if ($HasDuration) {
        try {
            $DurationSpan = [System.Xml.XmlConvert]::ToTimeSpan($Duration)
        } catch {
            throw "'$Duration' is not a valid ISO 8601 duration (expected a value such as PT8H, P1D, P6M or P1Y)."
        }
        if ($DurationSpan -le [timespan]::Zero) {
            throw "Duration '$Duration' must be greater than zero."
        }
        $EffectiveSpan = $DurationSpan
        $ComputedEnd = $Start.Add($DurationSpan)
        $Expiration = [ordered]@{
            type     = 'afterDuration'
            duration = $Duration
        }
        $ExpirationType = 'afterDuration'
    } else {
        $EndUtc = $EndDateTime.ToUniversalTime()
        if ($EndUtc -le $NowUtc) {
            throw "EndDateTime $($EndUtc.ToString('o')) is not in the future."
        }
        if ($EndUtc -le $Start) {
            throw "EndDateTime $($EndUtc.ToString('o')) is not after the start $($Start.ToString('o'))."
        }
        $EffectiveSpan = $EndUtc - $Start
        $ComputedEnd = $EndUtc
        $Expiration = [ordered]@{
            type        = 'afterDateTime'
            endDateTime = $EndUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $ExpirationType = 'afterDateTime'
    }

    if (-not [string]::IsNullOrWhiteSpace($MaxDuration)) {
        try {
            $MaxSpan = [System.Xml.XmlConvert]::ToTimeSpan($MaxDuration)
        } catch {
            throw "MaxDuration '$MaxDuration' is not a valid ISO 8601 duration."
        }
        if ($EffectiveSpan -gt $MaxSpan) {
            $Requested = [math]::Round($EffectiveSpan.TotalHours, 2)
            $Allowed = [math]::Round($MaxSpan.TotalHours, 2)
            throw "Requested $Kind lifetime ($Requested hours) exceeds the maximum allowed ($MaxDuration = $Allowed hours). Shorten the request; CIPP does not extend limits."
        }
    }

    $Body.scheduleInfo = [ordered]@{
        startDateTime = $Start.ToString('yyyy-MM-ddTHH:mm:ssZ')
        expiration    = $Expiration
    }

    return [PSCustomObject]@{
        Uri            = $Uri
        Body           = $Body
        Kind           = $Kind
        Action         = $Action
        ExpirationType = $ExpirationType
        StartDateTime  = $Start
        EndDateTime    = $ComputedEnd
    }
}
