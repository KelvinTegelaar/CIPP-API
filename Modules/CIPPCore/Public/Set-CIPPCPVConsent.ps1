function Set-CIPPCPVConsent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $APIName = 'CPV Consent',
        $Headers,
        [bool]$ResetSP = $false
    )
    $Results = [System.Collections.Generic.List[string]]::new()
    $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1
    $TenantName = $Tenant.displayName
    $User = $Request.Headers

    if ($TenantFilter -eq $env:TenantID) {
        return @('Cannot modify CPV consent on partner tenant')
    }
    if ($Tenant.customerId -ne $TenantFilter) {
        return @('Not a valid tenant')
    }

    if ($ResetSP) {
        try {
            if ($PSCmdlet.ShouldProcess($ENV:ApplicationID, "Delete Service Principal from $TenantName")) {
                $null = New-GraphPostRequest -Type DELETE -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents/$($ENV:ApplicationID)" -scope 'https://api.partnercenter.microsoft.com/.default' -tenantid $env:TenantID
            }
            $Results.add("Deleted Service Principal from $TenantName")
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $Results.add("Error deleting SP - $($ErrorMessage)")
        }
    }

    try {
        $AppBody = @{
            ApplicationId     = $($ENV:ApplicationID)
            ApplicationGrants = @(
                @{
                    EnterpriseApplicationId = '00000003-0000-0000-c000-000000000000'
                    Scope                   = @(
                        'DelegatedPermissionGrant.ReadWrite.All',
                        'Directory.ReadWrite.All',
                        'AppRoleAssignment.ReadWrite.All'
                    ) -Join ','
                }
            )
        } | ConvertTo-Json

        if ($PSCmdlet.ShouldProcess($ENV:ApplicationID, "Add Service Principal to $TenantName")) {
            $null = New-GraphpostRequest -body $AppBody -Type POST -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents" -scope 'https://api.partnercenter.microsoft.com/.default' -tenantid $env:TenantID
            $Table = Get-CIPPTable -TableName cpvtenants
            $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            $GraphRequest = @{
                LastApply     = "$unixtime"
                applicationId = "$($ENV:ApplicationID)"
                Tenant        = "$($tenantfilter)"
                PartitionKey  = 'Tenant'
                RowKey        = "$($tenantfilter)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force
        }
        $Results.add("Successfully added CPV Application to tenant $($TenantName)") | Out-Null
        Write-LogMessage -Headers $User -API $APINAME -message "Added our Service Principal to $($TenantName)" -Sev 'Info' -tenant $Tenant.defaultDomainName -tenantId $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($ErrorMessage.NormalizedError -like '*Permission entry already exists*') {
            $Table = Get-CIPPTable -TableName cpvtenants
            $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            $GraphRequest = @{
                LastApply     = "$unixtime"
                applicationId = "$($ENV:ApplicationID)"
                Tenant        = "$($tenantfilter)"
                PartitionKey  = 'Tenant'
                RowKey        = "$($tenantfilter)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force
            return @("We've already added our Service Principal to $($TenantName)")
        }
        Write-LogMessage -Headers $User -API $APINAME -message "Could not add our Service Principal to the client tenant $($TenantName): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $Tenant.defaultDomainName -tenantId $TenantFilter -LogData $ErrorMessage
        return @("Could not add our Service Principal to the client tenant $($TenantName). Error: $($ErrorMessage.NormalizedError)")
    }
    return $Results
}
