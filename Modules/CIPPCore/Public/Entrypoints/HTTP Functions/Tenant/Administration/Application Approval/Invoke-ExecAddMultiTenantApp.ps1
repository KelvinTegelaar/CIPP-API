using namespace System.Net

function Invoke-ExecAddMultiTenantApp {
    <#
    .SYNOPSIS
    Deploy an application to multiple tenants with delegated and application permissions
    
    .DESCRIPTION
    Deploys an application to multiple tenants, supporting both manual and template configuration modes. Handles delegated and application permissions, queueing, and orchestration for batch deployment.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    
    .NOTES
    Group: Application Management
    Summary: Exec Add Multi-Tenant App
    Description: Deploys an application to multiple tenants, supporting both manual and template configuration modes. Handles delegated and application permissions, queueing, and orchestration for batch deployment. Supports copying permissions and template-based deployment.
    Tags: Application,Multi-Tenant,Deployment,Permissions,Queue
    Parameter: configMode (string) [body] - Configuration mode: 'manual' or 'template'
    Parameter: tenantFilter (array) [body] - Array of tenant identifiers to deploy to
    Parameter: permissions (array) [body] - Array of permission objects (delegated/application)
    Parameter: AppId (string) [body] - Application ID to deploy
    Parameter: CopyPermissions (bool) [body] - Whether to copy permissions from another app
    Parameter: selectedTemplate (object) [body] - Template object for template mode
    Response: Returns a response object with the following properties:
    Response: - Results (string): Status message for deployment or error
    Response: On success: Deployment status message
    Response: On error: Error message with HTTP 400/500 status
    Example: {
      "Results": "Deploying 12345678-1234-1234-1234-123456789012 to Contoso, Fabrikam, see the logbook for details"
    }
    Error: Returns error details if the operation fails to deploy the application.
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
            }
            else {
                $Command = 'ExecAddMultiTenantApp'
            }
            if ('allTenants' -in $Request.Body.tenantFilter.value) {
                $TenantFilter = (Get-Tenants).defaultDomainName
            }
            else {
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
            }
            catch {
                $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
                $Results = "Function Error: $ErrorMsg"
            }

            $StatusCode = [HttpStatusCode]::OK
        }
        catch {
            $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
            $Results = "Function Error: $ErrorMsg"
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    }
    elseif ($Request.Body.configMode -eq 'template') {
        Write-Information 'Application Approval - Template Mode'
        if ('allTenants' -in $Request.Body.tenantFilter.value) {
            $TenantFilter = (Get-Tenants).defaultDomainName
        }
        else {
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
        }
        catch {
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
