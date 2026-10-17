function Get-CIPPCAPolicyImpact {
    <#
    .SYNOPSIS
        Summarises how one Conditional Access policy was evaluated against recent interactive sign-ins.
    .DESCRIPTION
        Builds the equivalent of the Entra portal "Policy impact" view from the sign-in log. The portal's own
        report function (reports/conditionalAccess/getConditionalAccessPerPolicyImpactSummary) answers
        "Requested resource does not exist" to every caller except the portal's first-party app, so the
        numbers here come from auditLogs/signIns filtered on appliedConditionalAccessPolicies for this policy.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [ValidateSet(1, 7, 30)]
        [int]$Days = 7,

        [ValidateRange(-1, 30)]
        [int]$SegmentIndex = -1,

        [ValidateRange(1, 30)]
        [int]$SegmentDays = 10,

        [ValidateRange(1, 20)]
        [int]$BatchSize = 10,

        [ValidateRange(1, 200)]
        [int]$SamplesPerDay = 20
    )

    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    if ($PolicyId -notmatch $GuidPattern) {
        throw "PolicyId '$PolicyId' is not a GUID."
    }

    # Graph's appliedConditionalAccessPolicyResult enum. Everything is bucketed so the caller can decide
    # which results to show for an enforced policy versus a report-only one.
    $ResultKeys = @(
        'success', 'failure', 'notApplied', 'notEnabled', 'unknown',
        'reportOnlySuccess', 'reportOnlyFailure', 'reportOnlyNotApplied', 'reportOnlyInterrupted'
    )
    $NotMetResults = @('failure', 'reportOnlyFailure', 'reportOnlyInterrupted')
    $IsoFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

    $Policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$PolicyId`?`$select=id,displayName,state" -tenantid $TenantFilter -ErrorAction Stop

    $Now = [datetime]::UtcNow
    $WindowStart = $Now.AddDays(-$Days)
    if ($SegmentIndex -ge 0) {
        $EndDateTime = $Now.AddDays(-($SegmentIndex * $SegmentDays))
        $StartDateTime = $EndDateTime.AddDays(-$SegmentDays)
        if ($StartDateTime -lt $WindowStart) { $StartDateTime = $WindowStart }
        if ($EndDateTime -le $WindowStart) {
            throw "Segment $SegmentIndex lies outside the $Days day window."
        }
    } else {
        $EndDateTime = $Now
        $StartDateTime = $WindowStart
    }

    # One request per 24 hour slice, newest first, the last one clipped to the window start.
    $Select = 'id,createdDateTime,userDisplayName,userPrincipalName,userId,appDisplayName,appId,ipAddress,clientAppUsed,status,appliedConditionalAccessPolicies'
    $Requests = [System.Collections.Generic.List[object]]::new()
    $SliceEnd = $EndDateTime
    while ($SliceEnd -gt $StartDateTime) {
        $SliceStart = $SliceEnd.AddDays(-1)
        if ($SliceStart -lt $StartDateTime) { $SliceStart = $StartDateTime }
        $Filter = "createdDateTime ge $($SliceStart.ToString($IsoFormat)) and createdDateTime lt $($SliceEnd.ToString($IsoFormat)) and appliedConditionalAccessPolicies/any(p:p/id eq '$PolicyId')"
        $SliceUrl = ('/auditLogs/signIns?$top=999&$select={0}&$filter={1}' -f $Select, [System.Uri]::EscapeDataString($Filter))
        $SliceRequest = @{
            id     = [string]$Requests.Count
            method = 'GET'
            url    = $SliceUrl
        }
        $Requests.Add($SliceRequest)
        $SliceEnd = $SliceStart
    }

    # day -> @{ result -> count }
    $DayBuckets = @{}
    # day -> List of sample rows
    $DaySamples = @{}
    $SignInCount = 0
    $Partial = $false
    $PartialReasons = [System.Collections.Generic.List[string]]::new()
    $OldestSeen = $null
    $BatchCalls = 0

    for ($Offset = 0; $Offset -lt $Requests.Count; $Offset += $BatchSize) {
        $Chunk = $Requests.GetRange($Offset, [Math]::Min($BatchSize, $Requests.Count - $Offset)).ToArray()
        $Responses = @(New-GraphBulkRequest -Requests $Chunk -tenantid $TenantFilter -Version beta -ErrorAction Stop)
        $BatchCalls++

        foreach ($Response in $Responses) {
            $Status = $Response.status -as [int]
            if ($Status -ge 400) {
                $GraphMessage = $Response.body.error.message ?? $Response.body.error.code ?? "status $Status"
                throw "Graph returned $Status while reading sign-ins: $GraphMessage"
            }
            if ($Response.PagingIncomplete) {
                $Partial = $true
                if ($Response.PagingError) { $PartialReasons.Add([string]$Response.PagingError) }
            }

            foreach ($SignIn in @($Response.body.value)) {
                if ($null -eq $SignIn) { continue }
                $Entry = @($SignIn.appliedConditionalAccessPolicies).Where({ $_.id -eq $PolicyId }) | Select-Object -First 1
                $Result = if ($Entry -and -not [string]::IsNullOrWhiteSpace($Entry.result)) { [string]$Entry.result } else { 'unknown' }
                if ($ResultKeys -notcontains $Result) { $Result = 'unknown' }

                $Created = ([datetime]$SignIn.createdDateTime).ToUniversalTime()
                $Day = $Created.ToString('yyyy-MM-dd')
                if ($null -eq $OldestSeen -or $Created -lt $OldestSeen) { $OldestSeen = $Created }

                if (-not $DayBuckets.ContainsKey($Day)) {
                    $Bucket = @{}
                    foreach ($Key in $ResultKeys) { $Bucket[$Key] = 0 }
                    $DayBuckets[$Day] = $Bucket
                }
                $DayBuckets[$Day][$Result]++
                $SignInCount++

                if ($NotMetResults -contains $Result) {
                    if (-not $DaySamples.ContainsKey($Day)) {
                        $DaySamples[$Day] = [System.Collections.Generic.List[object]]::new()
                    }
                    if ($DaySamples[$Day].Count -lt $SamplesPerDay) {
                        $DaySamples[$Day].Add([pscustomobject]@{
                                id                          = $SignIn.id
                                createdDateTime             = $Created.ToString($IsoFormat)
                                day                         = $Day
                                userDisplayName             = $SignIn.userDisplayName
                                userPrincipalName           = $SignIn.userPrincipalName
                                userId                      = $SignIn.userId
                                appDisplayName              = $SignIn.appDisplayName
                                appId                       = $SignIn.appId
                                ipAddress                   = $SignIn.ipAddress
                                clientAppUsed               = $SignIn.clientAppUsed
                                policyResult                = $Result
                                conditionsSatisfied         = @(([string]$Entry.conditionsSatisfied -split ',').Where({ $_ -and $_ -ne 'none' }))
                                conditionsNotSatisfied      = @(([string]$Entry.conditionsNotSatisfied -split ',').Where({ $_ -and $_ -ne 'none' }))
                                enforcedGrantControls       = @($Entry.enforcedGrantControls)
                                enforcedSessionControls     = @($Entry.enforcedSessionControls)
                                sessionControlsNotSatisfied = @($Entry.sessionControlsNotSatisfied)
                                signInErrorCode             = $SignIn.status.errorCode
                                signInFailureReason         = $SignIn.status.failureReason
                            })
                    }
                }
            }
        }
    }

    # One row per UTC day across the segment, so the chart has no gaps on quiet days.
    $DayRows = [System.Collections.Generic.List[object]]::new()
    $Totals = [ordered]@{}
    foreach ($Key in $ResultKeys) { $Totals[$Key] = 0 }
    $Cursor = $StartDateTime.Date
    $LastDay = $EndDateTime.Date
    while ($Cursor -le $LastDay) {
        $Day = $Cursor.ToString('yyyy-MM-dd')
        $Row = [ordered]@{ date = $Day }
        $DayTotal = 0
        foreach ($Key in $ResultKeys) {
            $Count = if ($DayBuckets.ContainsKey($Day)) { [int]$DayBuckets[$Day][$Key] } else { 0 }
            $Row[$Key] = $Count
            $Totals[$Key] = $Totals[$Key] + $Count
            $DayTotal += $Count
        }
        $Row['total'] = $DayTotal
        $DayRows.Add([pscustomobject]$Row)
        $Cursor = $Cursor.AddDays(1)
    }
    $Totals['total'] = $SignInCount

    $Samples = [System.Collections.Generic.List[object]]::new()
    foreach ($Day in ($DaySamples.Keys | Sort-Object -Descending)) {
        foreach ($Sample in $DaySamples[$Day]) { $Samples.Add($Sample) }
    }

    return [pscustomobject]@{
        id               = $Policy.id
        displayName      = $Policy.displayName
        state            = $Policy.state
        windowDays       = $Days
        segmentIndex     = $SegmentIndex
        segmentDays      = $SegmentDays
        startDateTime    = $StartDateTime.ToString($IsoFormat)
        endDateTime      = $EndDateTime.ToString($IsoFormat)
        source           = 'signInLogs'
        signInCount      = $SignInCount
        sliceCount       = $Requests.Count
        batchCalls       = $BatchCalls
        partial          = $Partial
        partialReason    = if ($PartialReasons.Count -gt 0) { ($PartialReasons | Select-Object -Unique) -join '; ' } else { $null }
        oldestSignInSeen = if ($OldestSeen) { $OldestSeen.ToString($IsoFormat) } else { $null }
        samplesPerDay    = $SamplesPerDay
        days             = $DayRows.ToArray()
        totals           = [pscustomobject]$Totals
        samples          = $Samples.ToArray()
    }
}
