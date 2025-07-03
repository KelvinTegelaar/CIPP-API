using namespace System.Net

function Invoke-ListTenants {
    <#
    .SYNOPSIS
    List Microsoft 365 tenants accessible to the current user
    
    .DESCRIPTION
    Retrieves a list of Microsoft 365 tenants with optional filtering, cache management, and portal links
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Tenant Management
    Summary: List Tenants
    Description: Retrieves a list of Microsoft 365 tenants with support for filtering, cache management, refresh triggers, and portal link generation
    Tags: Tenant,Administration,List
    Parameter: tenantFilter (string) [query] - Specific tenant domain to filter results
    Parameter: AllTenantSelector (boolean) [query] - Include "All Tenants" option in results
    Parameter: TriggerRefresh (boolean) [query] - Trigger a tenant refresh operation
    Parameter: Mode (string) [query] - Display mode: TenantList (includes portal links)
    Parameter: ClearCache (boolean) [body] - Clear tenant cache and trigger refresh
    Parameter: TenantsOnly (boolean) [body] - Clear only tenant cache when clearing cache
    Response: Returns an array of tenant objects with the following properties:
    Response: - customerId (string): Tenant's unique customer identifier
    Response: - defaultDomainName (string): Primary domain name for the tenant
    Response: - displayName (string): Tenant's display name
    Response: - domains (string): Comma-separated list of tenant domains
    Response: - GraphErrorCount (number): Number of Graph API errors for this tenant
    Response: When Mode=TenantList, additional portal link properties are included:
    Response: - portal_m365 (string): Microsoft 365 admin center URL
    Response: - portal_exchange (string): Exchange admin center URL
    Response: - portal_entra (string): Entra ID admin center URL
    Response: - portal_teams (string): Teams admin center URL
    Response: - portal_azure (string): Azure portal URL
    Response: - portal_intune (string): Intune admin center URL
    Response: - portal_security (string): Security admin center URL
    Response: - portal_compliance (string): Compliance admin center URL
    Response: - portal_sharepoint (string): SharePoint admin center URL
    Example: [
      {
        "customerId": "12345678-1234-1234-1234-123456789012",
        "defaultDomainName": "contoso.onmicrosoft.com",
        "displayName": "Contoso Corporation",
        "domains": "contoso.com, contoso.onmicrosoft.com",
        "GraphErrorCount": 0,
        "portal_m365": "https://admin.cloud.microsoft/?delegatedOrg=contoso.onmicrosoft.com",
        "portal_exchange": "https://admin.cloud.microsoft/exchange?delegatedOrg=contoso.onmicrosoft.com",
        "portal_entra": "https://entra.microsoft.com/contoso.onmicrosoft.com"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantAccess = Test-CIPPAccess -Request $Request -TenantList
    Write-Host "Tenant Access: $TenantAccess"

    if ($TenantAccess -notcontains 'AllTenants') {
        $AllTenantSelector = $false
    }
    else {
        $AllTenantSelector = $Request.Query.AllTenantSelector
    }

    # Clear Cache
    if ($Request.Body.ClearCache -eq $true) {
        $Results = Remove-CIPPCache -tenantsOnly $Request.Body.TenantsOnly

        $InputObject = [PSCustomObject]@{
            Batch            = @(
                @{
                    FunctionName = 'UpdateTenants'
                }
            )
            OrchestratorName = 'UpdateTenants'
            SkipLog          = $true
        }
        Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

        $GraphRequest = [pscustomobject]@{'Results' = 'Cache has been cleared and a tenant refresh is queued.' }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    Results  = @($GraphRequest)
                    Metadata = @{
                        Details = $Results
                    }
                }
            })
        #Get-Tenants -IncludeAll -TriggerRefresh
        return
    }
    if ($Request.Query.TriggerRefresh) {
        if ($Request.Query.TenantFilter -and $Request.Query.TenantFilter -ne 'AllTenants') {
            Get-Tenants -TriggerRefresh -TenantFilter $Request.Query.TenantFilter
        }
        else {
            $InputObject = [PSCustomObject]@{
                Batch            = @(
                    @{
                        FunctionName = 'UpdateTenants'
                    }
                )
                OrchestratorName = 'UpdateTenants'
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
        }
    }
    try {
        $TenantFilter = $Request.Query.tenantFilter
        $Tenants = Get-Tenants -IncludeErrors -SkipDomains
        if ($TenantAccess -notcontains 'AllTenants') {
            $Tenants = $Tenants | Where-Object -Property customerId -In $TenantAccess
        }

        if ($null -eq $TenantFilter -or $TenantFilter -eq 'null') {
            $TenantList = [system.collections.generic.list[object]]::new()
            if ($AllTenantSelector -eq $true) {
                $TenantList.Add(@{
                        customerId        = 'AllTenants'
                        defaultDomainName = 'AllTenants'
                        displayName       = '*All Tenants'
                        domains           = 'AllTenants'
                        GraphErrorCount   = 0
                    }) | Out-Null

                if (($Tenants).length -gt 1) {
                    $TenantList.AddRange($Tenants) | Out-Null
                }
                elseif ($Tenants) {
                    $TenantList.Add($Tenants) | Out-Null
                }
                $body = $TenantList
            }
            else {
                $Body = $Tenants
            }
            if ($Request.Query.Mode -eq 'TenantList') {
                # add portal link properties
                $Body = $Body | Select-Object *, @{Name = 'portal_m365'; Expression = { "https://admin.cloud.microsoft/?delegatedOrg=$($_.initialDomainName)" } },
                @{Name = 'portal_exchange'; Expression = { "https://admin.cloud.microsoft/exchange?delegatedOrg=$($_.initialDomainName)" } },
                @{Name = 'portal_entra'; Expression = { "https://entra.microsoft.com/$($_.defaultDomainName)" } },
                @{Name = 'portal_teams'; Expression = { "https://admin.teams.microsoft.com?delegatedOrg=$($_.initialDomainName)" } },
                @{Name = 'portal_azure'; Expression = { "https://portal.azure.com/$($_.defaultDomainName)" } },
                @{Name = 'portal_intune'; Expression = { "https://intune.microsoft.com/$($_.defaultDomainName)" } },
                @{Name = 'portal_security'; Expression = { "https://security.microsoft.com/?tid=$($_.customerId)" } },
                @{Name = 'portal_compliance'; Expression = { "https://purview.microsoft.com/?tid=$($_.customerId)" } },
                @{Name = 'portal_sharepoint'; Expression = { "/api/ListSharePointAdminUrl?tenantFilter=$($_.defaultDomainName)" } }
            }

        }
        else {
            $body = $Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter
        }

        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message 'Listed Tenant Details' -Sev 'Debug'
    }
    catch {
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message "List Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{
            'Results'         = "Failed to retrieve tenants: $($_.Exception.Message)"
            defaultDomainName = ''
            displayName       = 'Failed to retrieve tenants. Perform a permission check.'
            customerId        = ''

        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Body)
        })


}
