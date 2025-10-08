Function Invoke-ListLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $RawGraphRequest = if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter | ForEach-Object {
            $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
            $_.TermInfo = $TermInfo
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
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Host "Started permissions orchestration with ID = '$InstanceId'"
            }
        } else {
            $GraphRequest = $Rows | Where-Object { $_.License } | ForEach-Object {
                if ($_.TermInfo) {
                    $TermInfo = $_.TermInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $_.TermInfo = $TermInfo
                } else {
                    $_ | Add-Member -NotePropertyName TermInfo -NotePropertyValue $null
                }
                $_
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
