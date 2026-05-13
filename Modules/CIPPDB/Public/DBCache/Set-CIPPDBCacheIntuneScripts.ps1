function Set-CIPPDBCacheIntuneScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneScriptsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping scripts cache' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune scripts' -sev Debug
        $BulkRequests = @(
            @{
                id     = 'Groups'
                method = 'GET'
                url    = '/groups?$top=999&$select=id,displayName'
            }
            @{
                id     = 'Windows'
                method = 'GET'
                url    = '/deviceManagement/deviceManagementScripts?$expand=assignments'
            }
            @{
                id     = 'MacOS'
                method = 'GET'
                url    = '/deviceManagement/deviceShellScripts?$expand=assignments'
            }
            @{
                id     = 'Remediation'
                method = 'GET'
                url    = '/deviceManagement/deviceHealthScripts?$expand=assignments'
            }
            @{
                id     = 'Linux'
                method = 'GET'
                url    = '/deviceManagement/configurationPolicies?$expand=assignments'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value
        if (-not $Groups) { $Groups = @() }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneScriptGroups' -Data @($Groups)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneScriptGroups' -Data @($Groups) -Count

        $TypeMap = @{
            Windows     = 'IntuneWindowsScripts'
            MacOS       = 'IntuneMacOSScripts'
            Remediation = 'IntuneRemediationScripts'
            Linux       = 'IntuneLinuxScripts'
        }

        foreach ($scriptId in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
            $BulkResult = $BulkResults | Where-Object { $_.id -eq $scriptId }
            $Scripts = @()
            if ($BulkResult.status -eq 200) {
                $Scripts = @($BulkResult.body.value)
                if ($scriptId -eq 'Linux') {
                    $Scripts = @($Scripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' })
                }
            } elseif ($BulkResult) {
                $ErrorMessage = if (Test-Json $BulkResult.body.error.message) {
                    ($BulkResult.body.error.message | ConvertFrom-Json).Message
                } else {
                    $BulkResult.body.error.message
                }
                $Scripts = @([PSCustomObject]@{
                        displayName = $ErrorMessage
                    })
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $TypeMap[$scriptId] -Data @($Scripts)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type $TypeMap[$scriptId] -Data @($Scripts) -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(($Scripts | Measure-Object).Count) $scriptId scripts" -sev Debug
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune scripts: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
