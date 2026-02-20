
function Get-CIPPAlertDefenderAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $AlertSeverities = $InputValue.AlertSeverities.value -as [System.Collections.Generic.List[string]]
    try {
        $DefenderAlerts = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/security/alerts_v2?`$top=50&`$filter=status eq 'new'" -tenantid $TenantFilter
        $AlertData = foreach ($Alert in $DefenderAlerts) {
            # Skip if severity doesn't match filter (unless "All" is selected or no filter)
            if ($AlertSeverities.Count -gt 0 -and 'All' -notin $AlertSeverities) {
                if ($Alert.severity -notin $AlertSeverities) {
                    continue
                }
            }

            [PSCustomObject]@{
                Title                 = $Alert.title
                Description           = $Alert.description
                Severity              = $Alert.severity
                Category              = $Alert.category
                ServiceSource         = $Alert.serviceSource
                ProductName           = $Alert.productName
                DetectionSource       = $Alert.detectionSource
                Classification        = $Alert.classification
                Determination         = $Alert.determination
                ThreatDisplayName     = $Alert.threatDisplayName
                ThreatFamilyName      = $Alert.threatFamilyName
                ActorDisplayName      = $Alert.actorDisplayName
                MitreTechniques       = ($Alert.mitreTechniques -join ', ')
                AssignedTo            = $Alert.assignedTo
                FirstActivityDateTime = $Alert.firstActivityDateTime
                LastActivityDateTime  = $Alert.lastActivityDateTime
                CreatedAt             = $Alert.createdDateTime
                RecommendedActions    = $Alert.recommendedActions
                AlertID               = $Alert.id
                IncidentID            = $Alert.incidentId
                AlertUrl              = $Alert.alertWebUrl
                IncidentUrl           = $Alert.incidentWebUrl
                Tenant                = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        # Commented out due to potential licensing spam
        # Write-AlertMessage -tenant $($TenantFilter) -message "Could not get Defender alerts for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
