function Invoke-ExecDnsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        Tenant.Domains.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # List of supported resolvers
    $ValidResolvers = @(
        'Google'
        'Cloudflare'
    )


    $StatusCode = [HttpStatusCode]::OK
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $Domain = $Request.Query.Domain ?? $Request.Body.Domain
    $Resolver = $Request.Query.Resolver ?? $Request.Body.Resolver
    $Selector = $Request.Query.Selector ?? $Request.Body.Selector
    try {
        $ConfigTable = Get-CippTable -tablename Config
        $Filter = "PartitionKey eq 'Domains' and RowKey eq 'Domains'"
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter

        $DomainTable = Get-CippTable -tablename 'Domains'

        if ($ValidResolvers -notcontains $Config.Resolver) {
            $Config = @{
                PartitionKey = 'Domains'
                RowKey       = 'Domains'
                Resolver     = 'Google'
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
        }

        $updated = $false

        switch ($Action) {
            'SetConfig' {
                $Config = @{
                    PartitionKey     = 'Domains'
                    RowKey           = 'Domains'
                    Resolver         = $Config.Resolver
                    DomainExclusions = $Config.DomainExclusions ?? '[]'
                }
                if ($Resolver -and $ValidResolvers -contains $Resolver) {
                    $Config.Resolver = $Resolver
                    $updated = $true
                }
                # Wildcard patterns (*.voice.example.com) the Domain Analyser and DKIM baseline skip, comma or newline separated
                $ExclusionPatterns = $Request.Body.ExclusionPatterns
                if ($null -ne $ExclusionPatterns) {
                    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
                    if ($AllowedTenants -notcontains 'AllTenants') {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::Forbidden
                                Body       = [pscustomobject]@{'Results' = 'Domain exclusions apply to every tenant, so changing them needs access to all tenants.' }
                            })
                    }
                    $Patterns = @(@($ExclusionPatterns) -split '[,\s]+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
                    $Invalid = $Patterns.Where({ $_ -notmatch '^[a-z0-9*.-]+$' -or $_ -notlike '*.*' -or ($_ -replace '[*.]').Length -lt 2 })
                    if ($Invalid.Count -gt 0) {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body       = [pscustomobject]@{'Results' = "Error: not a valid domain pattern: $($Invalid -join ', '). Use a domain with optional wildcards, for example *.voice.example.com." }
                            })
                    }
                    $Config.DomainExclusions = [string](ConvertTo-Json -InputObject $Patterns -Compress)
                    $updated = $true
                }
                if ($updated) {
                    Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
                    Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message 'DNS configuration updated' -Sev 'Info'
                    $body = [pscustomobject]@{'Results' = 'Success: DNS configuration updated.' }
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $body = [pscustomobject]@{'Results' = 'Error: No DNS resolver or domain exclusions provided.' }
                }
            }
            'SetDkimConfig' {
                $Domain = $Domain
                $Selector = ($Selector).trim() -split '\s*,\s*'
                $DomainTable = Get-CIPPTable -Table 'Domains'
                $Filter = "RowKey eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $Domain)
                $DomainInfo = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter

                # AnyTenant: restricted callers may only edit domains whose every row is for a tenant in scope
                $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
                if ($AllowedTenants -notcontains 'AllTenants' -and (@($DomainInfo).Count -eq 0 -or @($DomainInfo | Select-CippAllowedTenantData -TenantProperty 'TenantGUID', 'TenantId').Count -lt @($DomainInfo).Count)) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body       = [pscustomobject]@{'Results' = "$Domain belongs to a tenant your roles don't include." }
                        })
                }

                $DkimSelectors = [string]($Selector | ConvertTo-Json -Compress)
                if ($DomainInfo) {
                    $DomainInfo.DkimSelectors = $DkimSelectors
                } else {
                    $DomainInfo = @{
                        'RowKey'         = $Domain
                        'PartitionKey'   = 'ManualEntry'
                        'TenantId'       = 'NoTenant'
                        'MailProviders'  = ''
                        'TenantDetails'  = ''
                        'DomainAnalyser' = ''
                        'DkimSelectors'  = $DkimSelectors
                    }
                }
                Add-CIPPAzDataTableEntity @DomainTable -Entity $DomainInfo -Force
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "Updated DKIM selectors for domain: $Domain - Selectors: $($Selector -join ', ')" -Sev 'Info'
                $body = [pscustomobject]@{ 'Results' = "Success: DKIM selectors updated for $Domain. Selectors: $($Selector -join ', ')" }
            }
            'GetConfig' {
                $body = [pscustomobject]@{
                    Resolver          = $Config.Resolver
                    ExclusionPatterns = @(if ($Config.DomainExclusions) { ConvertFrom-Json -InputObject $Config.DomainExclusions })
                }
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message 'Retrieved DNS configuration' -Sev 'Debug'
            }
            'RemoveDomain' {
                $Filter = "RowKey eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $Domain)
                $DomainRow = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter -Property PartitionKey, RowKey, TenantGUID, TenantId

                # AnyTenant: restricted callers may only remove domains whose every row is for a tenant in scope
                $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
                if ($AllowedTenants -notcontains 'AllTenants' -and (@($DomainRow).Count -eq 0 -or @($DomainRow | Select-CippAllowedTenantData -TenantProperty 'TenantGUID', 'TenantId').Count -lt @($DomainRow).Count)) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body       = [pscustomobject]@{'Results' = "$Domain belongs to a tenant your roles don't include." }
                        })
                }

                Remove-CIPPAzDataTableEntity -Force @DomainTable -Entity $DomainRow
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "Removed Domain - $Domain " -Sev 'Info'
                $body = [pscustomobject]@{ 'Results' = "Domain removed - $Domain" }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "DNS Config API failed. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
