using namespace System.Net

function Invoke-ListIntuneScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $ExecutingUser = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev Debug

    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.Query.TenantFilter
    $Results = [System.Collections.Generic.List[System.Object]]::new()




    $BulkRequests = [PSCustomObject]@(
        @{
            id     = 'Windows'
            method = 'GET'
            url    = '/deviceManagement/deviceManagementScripts'
        }
        @{
            id     = 'MacOS'
            method = 'GET'
            url    = '/deviceManagement/deviceShellScripts'
        }
        @{
            id     = 'Remediation'
            method = 'GET'
            url    = '/deviceManagement/deviceHealthScripts'
        }
        @{
            id     = 'ConfigurationPolicies'
            method = 'GET'
            url    = "/deviceManagement/configurationPolicies?`$expand=assignments&top=1000"
        }
    )

    try {
        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve scripts. Error: $($ErrorMessage.NormalizedError)"
    }

    # Windows
    try {

        $WindowsScripts = ($BulkResults | Where-Object { $_.id -eq 'Windows' }).body.value
        $WindowsScripts | Add-Member -MemberType NoteProperty -Name scriptType -Value 'Windows'
        if ($WindowsScripts.Count -gt 1) {
            $Results.AddRange($WindowsScripts)
        } else {
            $Results.Add($WindowsScripts)
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve Windows scripts. Error: $($ErrorMessage.NormalizedError)"
    }

    # MacOS
    try {
        # $MacOSScripts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts' -tenantid $TenantFilter
        $MacOSScripts | Add-Member -MemberType NoteProperty -Name scriptType -Value 'MacOS'
        if ($MacOSScripts.Count -gt 1) {
            $Results.AddRange($MacOSScripts)
        } else {
            $Results.Add($MacOSScripts)
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve macOS scripts. Error: $($ErrorMessage.NormalizedError)"
    }

    # Remediation
    try {
        $RemediateScripts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts' -tenantid $TenantFilter
        $RemediateScripts | Add-Member -MemberType NoteProperty -Name scriptType -Value 'Remediation'
        if ($RemediateScripts.Count -gt 1) {
            $Results.AddRange($RemediateScripts)
        } else {
            $Results.Add($RemediateScripts)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve remediate scripts. Error: $($ErrorMessage.NormalizedError)"
    }

    # Linux
    try {
        $LinuxScripts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments&top=1000' -tenantid $TenantFilter
        $LinuxScripts = $LinuxScripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' }
        $LinuxScripts | Add-Member -MemberType NoteProperty -Name scriptType -Value 'Linux'
        $LinuxScripts | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name displayName -Value $_.name -Force }
        if ($LinuxScripts.Count -gt 1) {
            $Results.AddRange($LinuxScripts)
        } else {
            $Results.Add($LinuxScripts)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve Linux scripts. Error: $($ErrorMessage.NormalizedError)"
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })

}
