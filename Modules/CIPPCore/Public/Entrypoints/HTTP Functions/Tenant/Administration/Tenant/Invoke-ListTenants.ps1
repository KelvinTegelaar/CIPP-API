using namespace System.Net

function Invoke-ListTenants {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
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
    } else {
        $AllTenantSelector = $Request.Query.AllTenantSelector
    }

    $IncludeOffboardingDefaults = $Request.Query.IncludeOffboardingDefaults

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
        } else {
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

        # If offboarding defaults are requested, fetch them
        if ($IncludeOffboardingDefaults -eq 'true' -and $Tenants) {
            $PropertiesTable = Get-CippTable -TableName 'TenantProperties'

            # Get all offboarding defaults for all tenants in one query for performance
            $AllOffboardingDefaults = Get-CIPPAzDataTableEntity @PropertiesTable -Filter "RowKey eq 'OffboardingDefaults'"

            # Add offboarding defaults to each tenant
            foreach ($Tenant in $Tenants) {
                $TenantDefaults = $AllOffboardingDefaults | Where-Object { $_.PartitionKey -eq $Tenant.customerId }
                if ($TenantDefaults) {
                    try {
                        $Tenant | Add-Member -MemberType NoteProperty -Name 'offboardingDefaults' -Value ($TenantDefaults.Value | ConvertFrom-Json) -Force
                    } catch {
                        Write-LogMessage -headers $Headers -API $APIName -message "Failed to parse offboarding defaults for tenant $($Tenant.customerId): $($_.Exception.Message)" -Sev 'Warning'
                        $Tenant | Add-Member -MemberType NoteProperty -Name 'offboardingDefaults' -Value $null -Force
                    }
                } else {
                    $Tenant | Add-Member -MemberType NoteProperty -Name 'offboardingDefaults' -Value $null -Force
                }
            }
        }

        if ($null -eq $TenantFilter -or $TenantFilter -eq 'null') {
            $TenantList = [system.collections.generic.list[object]]::new()
            if ($AllTenantSelector -eq $true) {
                $AllTenantsObject = @{
                    customerId        = 'AllTenants'
                    defaultDomainName = 'AllTenants'
                    displayName       = '*All Tenants'
                    domains           = 'AllTenants'
                    GraphErrorCount   = 0
                }

                # Add offboarding defaults to AllTenants object if requested
                if ($IncludeOffboardingDefaults -eq 'true') {
                    $AllTenantsObject.offboardingDefaults = $null
                }

                $TenantList.Add($AllTenantsObject) | Out-Null

                if (($Tenants).length -gt 1) {
                    $TenantList.AddRange($Tenants) | Out-Null
                } elseif ($Tenants) {
                    $TenantList.Add($Tenants) | Out-Null
                }
                $body = $TenantList
            } else {
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
                @{Name = 'portal_sharepoint'; Expression = { "/api/ListSharePointAdminUrl?tenantFilter=$($_.defaultDomainName)" } },
                @{Name = 'portal_platform'; Expression = { "https://admin.powerplatform.microsoft.com/account/login/$($_.customerId)" } },
                @{Name = 'portal_bi'; Expression = { "https://app.powerbi.com/admin-portal?ctid=$($_.customerId)" } }
            }

        } else {
            $body = $Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter
        }

        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message 'Listed Tenant Details' -Sev 'Debug'
    } catch {
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
