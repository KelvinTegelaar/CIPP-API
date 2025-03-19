using namespace System.Net

function Invoke-ExecAddMultiTenantApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $DelegateResources = $request.body.permissions | Where-Object -Property origin -EQ 'Delegated' | ForEach-Object { @{ id = $_.id; type = 'Scope' } }
    $DelegateResourceAccess = @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = $DelegateResources }
    $ApplicationResources = $request.body.permissions | Where-Object -Property origin -EQ 'Application' | ForEach-Object { @{ id = $_.id; type = 'Role' } }
    $ApplicationResourceAccess = @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = $ApplicationResources }

    $Results = try {
        if ($Request.Body.CopyPermissions -eq $true) {
            $Command = 'ExecApplicationCopy'
        } else {
            $Command = 'ExecAddMultiTenantApp'
        }
        if ('allTenants' -in $Request.Body.tenantFilter.value) {
            $TenantFilter = (Get-Tenants).defaultDomainName
        } else {
            $TenantFilter = $Request.Body.tenantFilter.value
        }

        $TenantCount = ($TenantFilter | Measure-Object).Count
        $Queue = New-CippQueueEntry -Name 'Application Approval' -TotalTasks $TenantCount
        foreach ($Tenant in $TenantFilter) {
            try {
                $InputObject = @{
                    OrchestratorName = 'ExecMultiTenantAppOrchestrator'
                    Batch            = @([pscustomobject]@{
                            FunctionName              = $Command
                            Tenant                    = $tenant
                            AppId                     = $Request.Body.AppId
                            applicationResourceAccess = $ApplicationResourceAccess
                            delegateResourceAccess    = $DelegateResourceAccess
                            QueueId                   = $Queue.RowKey
                        })
                    SkipLog          = $true
                }
                $null = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                "Queued application to tenant $Tenant. See the logbook for deployment details"
            } catch {
                "Error queuing application to tenant $Tenant - $($_.Exception.Message)"
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })

}
