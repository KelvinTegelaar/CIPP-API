Function Invoke-ExecExcludeTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # $username = $Request.Headers.'x-ms-client-principal-name'
    $Username = $Headers.'x-ms-client-principal-name' ?? ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    Write-Host ($Username | ConvertTo-Json -Depth 10)
    $Date = (Get-Date).ToString('yyyy-MM-dd')
    $TenantsTable = Get-CippTable -tablename Tenants

    if ($Request.Query.List) {
        $ExcludedFilter = "PartitionKey eq 'Tenants' and Excluded eq true"
        $ExcludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter
        Write-LogMessage -API $APIName -headers $Headers -message 'got excluded tenants list' -Sev 'Debug'
        $body = @($ExcludedTenants)
    } elseif ($Request.Query.ListAll) {
        $ExcludedTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants'" | Sort-Object -Property displayName
        Write-LogMessage -API $APIName -headers $Headers -message 'got excluded tenants list' -Sev 'Debug'
        $body = @($ExcludedTenants)
    }
    try {
        # Interact with query parameters or the body of the request.
        $Name = $Request.Query.tenantFilter
        if ($Request.Query.AddExclusion) {
            $Tenants = Get-Tenants -IncludeAll | Where-Object { $Request.body.value -contains $_.customerId }

            $Excluded = foreach ($Tenant in $Tenants) {
                $Tenant.Excluded = $true
                $Tenant.ExcludeUser = $Username
                $Tenant.ExcludeDate = $Date
                $Tenant
            }
            Update-AzDataTableEntity -Force @TenantsTable -Entity ([pscustomobject]$Excluded)
            Write-LogMessage -API $APIName -tenant $($Name) -headers $Headers -message "Added exclusion for customer(s): $($Excluded.defaultDomainName -join ',')" -Sev 'Info'
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
            Write-LogMessage -API $APIName -tenant $($Name) -headers $Headers -message "Removed exclusion for customer $($Name)" -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Success. We've removed $Name from the excluded tenants." }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $($Name) -headers $Headers -message "Exclusion API failed. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
    }
    if (!$body) { $body = @() }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
