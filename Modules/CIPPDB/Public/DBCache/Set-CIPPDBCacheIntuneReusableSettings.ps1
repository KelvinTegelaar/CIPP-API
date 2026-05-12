function Set-CIPPDBCacheIntuneReusableSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneReusableSettingsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping reusable settings cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune reusable settings' -sev Debug
        $SelectFields = @(
            'id'
            'settingInstance'
            'displayName'
            'description'
            'settingDefinitionId'
            'version'
            'referencingConfigurationPolicyCount'
            'createdDateTime'
            'lastModifiedDateTime'
        )
        $SelectQuery = '?$select=' + ($SelectFields -join ',')
        $Settings = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings$SelectQuery" -tenantid $TenantFilter
        if (-not $Settings) { $Settings = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' -Data @($Settings)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' -Data @($Settings) -Count

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Settings | Measure-Object).Count) reusable settings" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache reusable settings: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
