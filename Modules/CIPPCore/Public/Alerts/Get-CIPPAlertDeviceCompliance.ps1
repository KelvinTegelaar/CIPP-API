
function Get-CIPPAlertDeviceCompliance {
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
        $AlertData = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$top=999" -tenantid $TenantFilter | Where-Object -Property complianceState -NE 'compliant' | ForEach-Object {
            $_ | Select-Object -Property id, deviceName, deviceType, complianceState, lastReportedDateTime
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get compliance state for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
