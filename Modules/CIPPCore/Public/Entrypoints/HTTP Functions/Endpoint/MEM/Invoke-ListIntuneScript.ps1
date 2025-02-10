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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

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
            id     = 'Linux'
            method = 'GET'
            url    = '/deviceManagement/configurationPolicies'
        }
    )

    try {
        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Host "Failed to retrieve scripts. Error: $($ErrorMessage.NormalizedError)"
    }

    foreach ($scriptId in @('Windows', 'MacOS', 'Remediation', 'Linux')) {
        $scripts = ($BulkResults | Where-Object { $_.id -eq $scriptId }).body.value

        if ($scriptId -eq 'Linux') {
            $scripts = $scripts | Where-Object { $_.platforms -eq 'linux' -and $_.templateReference.templateFamily -eq 'deviceConfigurationScripts' }
            $scripts | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name displayName -Value $_.name -Force }
        }

        $scripts | Add-Member -MemberType NoteProperty -Name scriptType -Value $scriptId
        Write-Host "$scriptId scripts count: $($scripts.Count)"
        $Results.AddRange(@($scripts))
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })

}
