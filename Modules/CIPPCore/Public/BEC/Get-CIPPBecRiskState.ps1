function Get-CIPPBecRiskState {
    <#
    .SYNOPSIS
        Collects the investigated user's Identity Protection risk state and recent risk detections.
    .DESCRIPTION
        Reads identityProtection/riskyUsers/{id} (a 404 means the user is not listed as risky) and the
        risk detections for the user inside the window. Identity Protection needs Entra ID P2; a
        licence or permission error is reported as an incomplete collector, never as "not risky".
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER StartDate
        Window start (UTC) for detections.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][datetime]$StartDate
    )

    $SafeId = ConvertTo-CIPPODataFilterValue -Value $UserId -Type Guid
    $State = [ordered]@{
        Listed                  = $false
        RiskLevel               = $null
        RiskState               = $null
        RiskDetail              = $null
        RiskLastUpdatedDateTime = $null
        IsProcessing            = $null
        Detections              = @()
    }
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Skipped = $false
    $Requirement = $null

    try {
        $RiskyUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers/$SafeId" -tenantid $TenantFilter -noPagination $true
        if ($RiskyUser.id) {
            $State.Listed = $true
            $State.RiskLevel = $RiskyUser.riskLevel
            $State.RiskState = $RiskyUser.riskState
            $State.RiskDetail = $RiskyUser.riskDetail
            $State.IsProcessing = $RiskyUser.isProcessing
            $State.RiskLastUpdatedDateTime = if ($RiskyUser.riskLastUpdatedDateTime) { ([datetime]$RiskyUser.riskLastUpdatedDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
        }
    } catch {
        $Message = [string](Get-NormalizedError -message $_.Exception.Message)
        if ($Message -notmatch '(?i)not ?found|404|does not exist|Request_ResourceNotFound') {
            if ($Message -match '(?i)UnknownError|Authorization_RequestDenied|premium|licen') {
                $Skipped = $true
                $Requirement = 'requires Entra ID P2 (Identity Protection)'
                $Errors.Add('Identity Protection is not available for this tenant (Entra ID P2 licence or consent missing)')
            } else {
                $Errors.Add("riskyUsers: $Message")
            }
        }
    }

    try {
        $Start = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Detections = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/identityProtection/riskDetections?`$filter=userId eq '$SafeId' and detectedDateTime ge $Start&`$orderby=detectedDateTime desc" -tenantid $TenantFilter)
        $State.Detections = @(foreach ($Detection in $Detections) {
                if (-not $Detection.id) { continue }
                [pscustomobject]@{
                    id                = $Detection.id
                    DetectedDateTime  = if ($Detection.detectedDateTime) { ([datetime]$Detection.detectedDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    RiskEventType     = $Detection.riskEventType
                    RiskLevel         = $Detection.riskLevel
                    RiskState         = $Detection.riskState
                    RiskDetail        = $Detection.riskDetail
                    DetectionTiming   = $Detection.detectionTimingType
                    Activity          = $Detection.activity
                    IPAddress         = $Detection.ipAddress
                    Country           = $Detection.location.countryOrRegion
                    City              = $Detection.location.city
                    Source            = $Detection.source
                }
            })
    } catch {
        $DetMessage = [string](Get-NormalizedError -message $_.Exception.Message)
        if ($DetMessage -match '(?i)UnknownError|Authorization_RequestDenied|premium|licen') {
            $Skipped = $true
            if (-not $Requirement) { $Requirement = 'requires Entra ID P2 (Identity Protection)' }
        }
        $Errors.Add("riskDetections: $DetMessage")
    }

    $ErrorText = if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null }
    $Result = New-CIPPBecCollectorResult -Data ([pscustomobject]$State) -Complete ($Errors.Count -eq 0) -Error $ErrorText -Skipped $Skipped -Requirement $Requirement -Count (@($State.Detections).Count)
    return $Result
}
