using namespace System.Net

Function Invoke-ExecExcludeTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $username = $Request.Headers.'x-ms-client-principal-name'
    $date = (Get-Date).tostring('yyyy-MM-dd')
    $TenantsTable = Get-CippTable -tablename Tenants

    if ($Request.Query.List) {
        $ExcludedFilter = "PartitionKey eq 'Tenants' and Excluded eq true"
        $ExcludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter
        Write-LogMessage -API $APINAME -headers $Request.Headers -message 'got excluded tenants list' -Sev 'Debug'
        $body = @($ExcludedTenants)
    } elseif ($Request.query.ListAll) {
        $ExcludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -filter "PartitionKey eq 'Tenants'" | Sort-Object -Property displayName
        Write-LogMessage -API $APINAME -headers $Request.Headers -message 'got excluded tenants list' -Sev 'Debug'
        $body = @($ExcludedTenants)
    }
    try {
        # Interact with query parameters or the body of the request.
        $name = $Request.Query.TenantFilter
        if ($Request.Query.AddExclusion) {
            $Tenants = Get-Tenants -IncludeAll | Where-Object { $Request.body.value -contains $_.customerId }

            $Excluded = foreach ($Tenant in $Tenants) {
                $Tenant.Excluded = $true
                $Tenant.ExcludeUser = $username
                $Tenant.ExcludeDate = $date
                $Tenant
            }
            Update-AzDataTableEntity -Force @TenantsTable -Entity ([pscustomobject]$Excluded)
            Write-LogMessage -API $APINAME -tenant $($name) -headers $Request.Headers -message "Added exclusion for customer(s): $($Excluded.defaultDomainName -join ',')" -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Success. Added exclusions for customer(s): $($Excluded.defaultDomainName -join ',')" }
        }

        if ($Request.Query.RemoveExclusion) {
            $Tenants = Get-Tenants -IncludeAll | Where-Object { $Request.body.value -contains $_.customerId }
            foreach ($Tenant in $Tenants) {
                $Tenant.Excluded = $false
                $Tenant.ExcludeUser = ''
                $Tenant.ExcludeDate = ''
                Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
            }
            Write-LogMessage -API $APINAME -tenant $($name) -headers $Request.Headers -message "Removed exclusion for customer $($name)" -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Success. We've removed $name from the excluded tenants." }
        }
    } catch {
        Write-LogMessage -API $APINAME -tenant $($name) -headers $Request.Headers -message "Exclusion API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }
    if (!$body) { $body = @() }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
