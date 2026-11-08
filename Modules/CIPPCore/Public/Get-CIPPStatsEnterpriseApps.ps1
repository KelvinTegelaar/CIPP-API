function Get-CIPPStatsEnterpriseApps {
    <#
    .SYNOPSIS
    Non-Microsoft enterprise apps and the number of tenants each is found in, for the anonymous stats payload

    .DESCRIPTION
    Reads the cached ServicePrincipals rows for every tenant and keeps the Application-type principals
    (no managed identities, legacy or social identity provider principals) whose owner is not a Microsoft
    tenant in the vendor list (Get-CIPPVendorTenantMap), and that are not CIPP's own app. Apps are keyed
    on appId, which is the same object across tenants, and the count is the number of distinct tenants
    that have it.
    #>
    [CmdletBinding()]
    param()

    try {
        $VendorTenants = Get-CIPPVendorTenantMap
        $CippAppId = [string]$env:ApplicationID
        $Fields = [string[]]@('appId', 'displayName', 'appOwnerOrganizationId', 'servicePrincipalType')
        # Through MethodInfo.Invoke: PowerShell copies a large string passed straight to a method several times per call
        $ParseJson = [CIPP.CippJson].GetMethod('ConvertFromJson', [type[]]@([string], [string[]]))

        $Apps = @{}
        # One tenant at a time: service principal rows are large, and holding every tenant's peaks the heap.
        # Ordinal order, as a table read returns them: an app's display name is the first one seen.
        $Tenants = [string[]]@((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ })
        [Array]::Sort($Tenants, [StringComparer]::Ordinal)
        foreach ($Tenant in $Tenants) {
            foreach ($Row in (Get-CIPPDbItem -Partition $Tenant -Type 'ServicePrincipals')) {
                if (-not $Row.Data) { continue }
                $Parsed = try { $ParseJson.Invoke($null, [object[]]@([string]$Row.Data, $Fields)) } catch { $null }
                foreach ($Sp in @($Parsed)) {
                    $AppId = [string]$Sp.appId
                    if ([string]::IsNullOrWhiteSpace($AppId)) { continue }
                    if ($Sp.servicePrincipalType -ne 'Application') { continue }
                    if ($CippAppId -and $AppId -eq $CippAppId) { continue }
                    $Vendor = $null
                    if ($Sp.appOwnerOrganizationId -and $VendorTenants.TryGetValue([string]$Sp.appOwnerOrganizationId, [ref]$Vendor) -and $Vendor.VendorType -eq 'Microsoft') { continue }

                    if (-not $Apps.ContainsKey($AppId)) {
                        $Apps[$AppId] = @{
                            DisplayName = [string]$Sp.displayName
                            Tenants     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        }
                    }
                    [void]$Apps[$AppId].Tenants.Add([string]$Tenant)
                }
            }
        }

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($AppId in $Apps.Keys) {
            $Results.Add([PSCustomObject]@{
                    ID          = $AppId
                    DisplayName = $Apps[$AppId].DisplayName
                    Count       = $Apps[$AppId].Tenants.Count
                })
        }
        return @($Results | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, 'DisplayName')
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate enterprise app stats: $($_.Exception.Message)" -sev Warning
        return @()
    }
}
