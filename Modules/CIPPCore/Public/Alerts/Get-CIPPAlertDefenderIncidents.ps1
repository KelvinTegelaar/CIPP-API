
function Get-CIPPAlertDefenderIncidents {
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

    $IncidentSeverities = $InputValue.IncidentSeverities.value -as [System.Collections.Generic.List[string]]
    try {
        $Incidents = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/security/incidents?`$top=50&`$filter=status eq 'active'" -tenantid $TenantFilter
        $AlertData = foreach ($Incident in $Incidents) {
            # Skip if severity doesn't match filter (unless "All" is selected or no filter)
            if ($IncidentSeverities.Count -gt 0 -and 'All' -notin $IncidentSeverities) {
                if ($Incident.severity -notin $IncidentSeverities) {
                    continue
                }
            }

            [PSCustomObject]@{
                IncidentName   = $Incident.displayName
                Severity       = $Incident.severity
                Classification = $Incident.classification
                Determination  = $Incident.determination
                Summary        = $Incident.summary
                AssignedTo     = $Incident.assignedTo
                CreatedAt      = $Incident.createdDateTime
                IncidentID     = $Incident.id
                IncidentUrl    = $Incident.incidentWebUrl
                Tenant         = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        # Pretty sure this one is gonna be spammy cause of licensing issues, so it's commented out -Bobby
        # Write-AlertMessage -tenant $($TenantFilter) -message "Could not get Defender incident data for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
