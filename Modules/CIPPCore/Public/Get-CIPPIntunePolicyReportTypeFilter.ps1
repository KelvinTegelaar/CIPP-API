function Get-CIPPIntunePolicyReportTypeFilter {
    <#
    .SYNOPSIS
        Returns the PolicyBaseTypeName filter for getConfigurationPolicyDevicesReport, without outer parentheses.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    (@(
            'Microsoft.Management.Services.Api.DeviceConfiguration'
            'DeviceManagementConfigurationPolicy'
            'DeviceConfigurationAdmxPolicy'
            'Microsoft.Management.Services.Api.DeviceManagementIntent'
        ) | ForEach-Object { "(PolicyBaseTypeName eq '$_')" }) -join ' or '
}
