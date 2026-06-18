function Invoke-ListLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists Microsoft 365 license SKUs and their assigned/available counts for a tenant. For AllTenants queries, consider using ListDBCache for better performance.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $IncludeExcluded = $Request.Query.IncludeExcluded -eq 'true'
    if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter -IncludeExcluded:$IncludeExcluded | ForEach-Object {
            $_
        }
    } else {
        $Table = Get-CIPPTable -TableName cachelicenses
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            $GraphRequest = [PSCustomObject]@{
                Tenant  = 'Loading data for all tenants. Please check back in 1 minute'
                License = 'Loading data for all tenants. Please check back in 1 minute'
            }
            $Tenants = Get-Tenants -IncludeErrors

            if (($Tenants | Measure-Object).Count -gt 0) {
                $Queue = New-CippQueueEntry -Name 'Licenses (All Tenants)' -TotalTasks ($Tenants | Measure-Object).Count
                $Tenants = $Tenants | Select-Object customerId, defaultDomainName, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'ListLicensesQueue' } }, @{Name = 'QueueName'; Expression = { $_.defaultDomainName } }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'ListLicensesOrchestrator'
                    Batch            = @($Tenants)
                    SkipLog          = $true
                }
                #Write-Host ($InputObject | ConvertTo-Json)
                $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
                Write-Host "Started permissions orchestration with ID = '$InstanceId'"
            }
        } else {
            $GraphRequest = $Rows | ForEach-Object {
                $LicenseData = $_.License | ConvertFrom-Json -ErrorAction SilentlyContinue
                foreach ($License in $LicenseData) {
                    $License
                }
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
