function Invoke-ListCAPolicyImpact {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Shows how a single Conditional Access policy was evaluated against recent interactive sign-ins, like
        the Entra portal's Policy impact view: sign-ins per UTC day split by the policy's result (success,
        failure, not applied and the report-only equivalents), totals for the window, and a capped sample
        of sign-ins per day where the policy's controls were not met. Days is 1, 7 or 30. 
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyId = $Request.Query.GUID ?? $Request.Body.GUID ?? $Request.Query.id ?? $Request.Body.id
    $DaysRaw = $Request.Query.Days ?? $Request.Body.Days ?? 7
    $SegmentRaw = $Request.Query.Segment ?? $Request.Body.Segment
    $SegmentDays = 10

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($PolicyId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter and GUID (policy id) are required.' }
            })
    }

    $Days = 0
    if (-not [int]::TryParse([string]$DaysRaw, [ref]$Days) -or @(1, 7, 30) -notcontains $Days) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Days must be 1, 7 or 30.' }
            })
    }

    $Segment = -1
    if (-not [string]::IsNullOrWhiteSpace([string]$SegmentRaw)) {
        if (-not [int]::TryParse([string]$SegmentRaw, [ref]$Segment) -or $Segment -lt 0 -or ($Segment * $SegmentDays) -ge $Days) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Segment must be a whole number from 0 to $([Math]::Ceiling($Days / $SegmentDays) - 1) for a $Days day window." }
                })
        }
    }

    try {
        $Results = Get-CIPPCAPolicyImpact -TenantFilter $TenantFilter -PolicyId $PolicyId -Days $Days -SegmentIndex $Segment -SegmentDays $SegmentDays
        $Scope = if ($Segment -ge 0) { "segment $Segment of the $Days day" } else { "$Days day" }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Built $Scope usage report for CA policy $($Results.displayName) from $($Results.signInCount) sign-ins" -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to build CA policy usage report: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
