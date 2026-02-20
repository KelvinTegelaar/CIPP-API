
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
        $AlertData = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=complianceState eq 'noncompliant'&`$select=id,deviceName,managedDeviceOwnerType,complianceState,lastSyncDateTime&`$top=999" -tenantid $TenantFilter
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Could not get compliance state for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
