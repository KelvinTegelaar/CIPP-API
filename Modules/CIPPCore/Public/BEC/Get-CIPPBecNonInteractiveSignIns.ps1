function Get-CIPPBecNonInteractiveSignIns {
    <#
    .SYNOPSIS
        Collects the investigated user's non-interactive sign-ins inside the analysis window.
    .DESCRIPTION
        Token replay and adversary-in-the-middle sessions show up as non-interactive sign-ins (refresh
        token use, background token acquisition) rather than in the interactive log. This reads the beta
        signIns endpoint filtered on signInEventTypes nonInteractiveUser and the window start, pages to
        the end, projects the same fields as the interactive list and marks each row as inside or
        outside the user's assigned usage location.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER UsageLocation
        The user's Entra usage location (ISO country code) for the foreign-location comparison.
    .PARAMETER StartDate
        Window start (UTC).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [string]$UsageLocation,
        [Parameter(Mandatory = $true)][datetime]$StartDate
    )

    $SafeId = ConvertTo-CIPPODataFilterValue -Value $UserId -Type Guid
    # Graph rejects tokenProtectionStatusDetails in $select; a full row costs about six times the memory
    $Select = 'id,createdDateTime,appDisplayName,resourceDisplayName,clientAppUsed,conditionalAccessStatus,status,ipAddress,location,userAgent,incomingTokenType,riskLevelDuringSignIn,riskEventTypes_v2,autonomousSystemNumber,deviceDetail,sessionId,uniqueTokenIdentifier,appId'
    # projected as each page arrives, so only the slim rows are held, never Graph's
    $Rows = [System.Collections.Generic.List[object]]::new()
    $StreamError = $null
    try {
        Search-CIPPBecSignIn -TenantFilter $TenantFilter -Filter "userId eq '$SafeId' and signInEventTypes/any(t: t eq 'nonInteractiveUser')" -StartDate $StartDate -Select $Select -Stream | & { process {
                $SignIn = $_
                if (-not $SignIn.id) { return }
                $Country = $SignIn.location.countryOrRegion
                $Foreign = if (-not $UsageLocation -or [string]::IsNullOrWhiteSpace($Country) -or $Country -eq 'Unknown') { $null } else { ($Country -ne $UsageLocation) }
                $Rows.Add([pscustomobject]@{
                        CreatedDateTime       = if ($SignIn.createdDateTime) { ([datetime]$SignIn.createdDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                        id                    = $SignIn.id
                        AppDisplayName        = $SignIn.appDisplayName
                        ResourceDisplayName   = $SignIn.resourceDisplayName
                        ClientAppUsed         = $SignIn.clientAppUsed
                        Status                = if ($SignIn.conditionalAccessStatus -in @('success', 'notApplied') -and $SignIn.status.errorCode -eq 0) { 'Success' } else { 'Failed' }
                        ErrorCode             = $SignIn.status.errorCode
                        FailureReason         = $SignIn.status.failureReason
                        IPAddress             = $SignIn.ipAddress
                        Country               = $Country
                        City                  = $SignIn.location.city
                        UserAgent             = $SignIn.userAgent
                        IncomingTokenType     = $SignIn.incomingTokenType
                        RiskLevelDuringSignIn = $SignIn.riskLevelDuringSignIn
                        RiskEventTypes        = @($SignIn.riskEventTypes_v2)
                        ASN                   = $SignIn.autonomousSystemNumber
                        DeviceCompliant       = $SignIn.deviceDetail.isCompliant
                        DeviceManaged         = $SignIn.deviceDetail.isManaged
                        OperatingSystem       = $SignIn.deviceDetail.operatingSystem
                        # tie audited mailbox and file actions back to this token and session
                        SessionId             = $SignIn.sessionId
                        UniqueTokenId         = $SignIn.uniqueTokenIdentifier
                        AppId                 = $SignIn.appId
                        ForeignLocation       = $Foreign
                        # set by the score step from the final verdicts
                        IPVerdict             = $null
                    })
            } }
    } catch {
        # nothing read is a failed check, as before; a page lost part-way keeps what was read
        if ($Rows.Count -eq 0) { throw }
        $StreamError = "Graph stopped part-way after $($Rows.Count) sign-in(s): $($_.Exception.Message)"
    }
    return New-CIPPBecCollectorResult -Data $Rows.ToArray() -Error $StreamError
}
