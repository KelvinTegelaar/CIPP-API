function Invoke-ExecCIPPDBCache {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter
    $Name = $Request.Query.Name

    Write-Information "ExecCIPPDBCache called with Name: '$Name', TenantFilter: '$TenantFilter'"

    try {
        if ([string]::IsNullOrEmpty($Name)) {
            throw 'Name parameter is required'
        }

        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter parameter is required'
        }

        # Validate the function exists
        $FunctionName = "Set-CIPPDBCache$Name"
        $Function = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
        if (-not $Function) {
            throw "Cache function '$FunctionName' not found"
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name" -sev Info

        # Handle AllTenants - create a batch for each tenant
        if ($TenantFilter -eq 'AllTenants') {
            $TenantList = Get-Tenants -IncludeErrors
            $Batch = $TenantList | ForEach-Object {
                [PSCustomObject]@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = $Name
                    TenantFilter = $_.defaultDomainName
                }
            }
            
            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = "CIPPDBCache_${Name}_AllTenants"
                SkipLog          = $false
            }
            
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name across $($TenantList.Count) tenants" -sev Info
        } else {
            # Single tenant
            $InputObject = [PSCustomObject]@{
                Batch            = @([PSCustomObject]@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $Name
                        TenantFilter = $TenantFilter
                    })
                OrchestratorName = "CIPPDBCache_${Name}_$TenantFilter"
                SkipLog          = $false
            }
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Started CIPP DB cache orchestrator for $Name with instance ID: $InstanceId" -sev Info

        $Body = [PSCustomObject]@{
            Results  = "Successfully started cache operation for $Name$(if ($TenantFilter -eq 'AllTenants') { ' for all tenants' } else { " on tenant $TenantFilter" })"
            Metadata = @{
                Name       = $Name
                Tenant     = $TenantFilter
                InstanceId = $InstanceId
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to start CIPP DB cache for $Name : $ErrorMessage" -sev Error
        $Body = [PSCustomObject]@{
            Results = "Failed to start cache operation: $ErrorMessage"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
