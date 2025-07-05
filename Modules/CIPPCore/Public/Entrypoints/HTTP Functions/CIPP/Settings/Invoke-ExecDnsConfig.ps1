using namespace System.Net

function Invoke-ExecDnsConfig {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # List of supported resolvers
    $ValidResolvers = @(
        'Google'
        'Cloudflare'
        'Quad9'
    )

    $StatusCode = [HttpStatusCode]::OK
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

        switch ($Request.Query.Action) {
            'SetConfig' {
                if ($Request.Body.Resolver) {
                    $Resolver = $Request.Body.Resolver
                    if ($ValidResolvers -contains $Resolver) {
                        try {
                            $Config.Resolver = $Resolver
                        } catch {
                            $Config = @{
                                Resolver = $Resolver
                            }
                        }
                        $updated = $true
                    }
                }
                if ($updated) {
                    Add-CIPPAzDataTableEntity @ConfigTable -Entity $Config -Force
                    Write-LogMessage -API $APINAME -tenant 'Global' -headers $Headers -message 'DNS configuration updated' -Sev 'Info'
                    $Body = [pscustomobject]@{'Results' = 'Success: DNS configuration updated.' }
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = [pscustomobject]@{'Results' = 'Error: No DNS resolver provided.' }
                }
            }
            'SetDkimConfig' {
                $Domain = $Request.Query.Domain
                $Selector = ($Request.Query.Selector).trim() -split '\s*,\s*'
                $DomainTable = Get-CIPPTable -Table 'Domains'
                $Filter = "RowKey eq '{0}'" -f $Domain
                $DomainInfo = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter
                $DkimSelectors = [string]($Selector | ConvertTo-Json -Compress)
                if ($DomainInfo) {
                    $DomainInfo.DkimSelectors = $DkimSelectors
                } else {
                    $DomainInfo = @{
                        'RowKey'         = $Request.Query.Domain
                        'PartitionKey'   = 'ManualEntry'
                        'TenantId'       = 'NoTenant'
                        'MailProviders'  = ''
                        'TenantDetails'  = ''
                        'DomainAnalyser' = ''
                        'DkimSelectors'  = $DkimSelectors
                    }
                }
                Add-CIPPAzDataTableEntity @DomainTable -Entity $DomainInfo -Force
            }
            'GetConfig' {
                $Body = [pscustomobject]$Config
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message 'Retrieved DNS configuration' -Sev 'Debug'
            }
            'RemoveDomain' {
                $Filter = "RowKey eq '{0}'" -f $Request.Query.Domain
                $DomainRow = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter -Property PartitionKey, RowKey
                Remove-AzDataTableEntity -Force @DomainTable -Entity $DomainRow
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Headers -message "Removed Domain - $($Request.Query.Domain) " -Sev 'Info'
                $Body = [pscustomobject]@{ 'Results' = "Domain removed - $($Request.Query.Domain)" }
            }
        }
    } catch {
        Write-LogMessage -API $APIName -tenant $($name) -headers $Headers -message "DNS Config API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return @{
        StatusCode = $StatusCode
        Body       = $Body
    }

}
