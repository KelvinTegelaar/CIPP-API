
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
    try {
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/security/incidents?`$top=50&`$filter=status eq 'active'" -tenantid $TenantFilter | ForEach-Object {
            [PSCustomObject]@{
                IncidentID   = $_.id
                CreatedAt    = $_.createdDateTime
                Severity     = $_.severity
                IncidentName = $_.displayName
                IncidentUrl  = $_.incidentWebUrl
                Tenant       = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        # Pretty sure this one is gonna be spammy cause of licensing issues, so it's commented out -Bobby
        # Write-AlertMessage -tenant $($TenantFilter) -message "Could not get Defender incident data for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
