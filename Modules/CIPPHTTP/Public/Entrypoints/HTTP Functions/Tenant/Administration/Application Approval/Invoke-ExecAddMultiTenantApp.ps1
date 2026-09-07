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
                $null = Start-CIPPOrchestrator -InputObject $InputObject
                $Results = 'Deploying {0} to {1}, see the logbook for details' -f $Request.Body.AppId, ($Request.Body.tenantFilter.label -join ', ')
                Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info'
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Results = "Function Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
            }

            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results = "Function Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
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
            $null = Start-CIPPOrchestrator -InputObject $InputObject
            $Results = 'Deploying {0} to {1}, see the logbook for details' -f $Request.Body.selectedTemplate.label, ($Request.Body.tenantFilter.label -join ', ')
            Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results = "Error queuing application - $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        }
        $StatusCode = [HttpStatusCode]::OK
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })

}
