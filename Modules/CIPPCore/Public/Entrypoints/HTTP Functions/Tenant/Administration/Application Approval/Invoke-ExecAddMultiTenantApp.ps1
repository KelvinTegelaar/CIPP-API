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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Body.configMode -eq 'manual') {
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
            $Batch = foreach ($Tenant in $TenantFilter) {
                [pscustomobject]@{
                    FunctionName              = $Command
                    Tenant                    = $tenant
                    AppId                     = $Request.Body.AppId
                    applicationResourceAccess = $ApplicationResourceAccess
                    delegateResourceAccess    = $DelegateResourceAccess
                    QueueId                   = $Queue.RowKey
                }
            }

            try {
                $InputObject = @{
                    OrchestratorName = 'ExecMultiTenantAppOrchestrator'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                $null = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                $Results = 'Deploying {0} to {1}, see the logbook for details' -f $Request.Body.AppId, ($Request.Body.tenantFilter.label -join ', ')
            } catch {
                $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
                $Results = "Function Error: $ErrorMsg"
            }

            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
            $Results = "Function Error: $ErrorMsg"
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    } elseif ($Request.Body.configMode -eq 'template') {
        Write-Information 'Application Approval - Template Mode'
        if ('allTenants' -in $Request.Body.tenantFilter.value) {
            $TenantFilter = (Get-Tenants).defaultDomainName
        } else {
            $TenantFilter = $Request.Body.tenantFilter.value
        }
        $TenantCount = ($TenantFilter | Measure-Object).Count
        $Queue = New-CippQueueEntry -Name 'Application Approval (Template)' -TotalTasks $TenantCount

        $Batch = foreach ($Tenant in $TenantFilter) {
            [pscustomobject]@{
                FunctionName = 'ExecAppApprovalTemplate'
                Tenant       = $tenant
                TemplateId   = $Request.Body.selectedTemplate.value
                AppId        = $Request.Body.selectedTemplate.addedFields.AppId
                QueueId      = $Queue.RowKey
            }
        }
        try {
            $InputObject = @{
                OrchestratorName = 'ExecMultiTenantAppOrchestrator'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            $null = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            $Results = 'Deploying {0} to {1}, see the logbook for details' -f $Request.Body.selectedTemplate.label, ($Request.Body.tenantFilter.label -join ', ')
        } catch {
            $Results = "Error queuing application - $($_.Exception.Message)"
        }
        $StatusCode = [HttpStatusCode]::OK
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })

}
