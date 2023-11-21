using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# List of supported resolvers
$ValidResolvers = @(
    'Google'
    'Cloudflare'
    'Quad9'
)

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

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
            if ($Request.Query.Resolver) {
                $Resolver = $Request.Query.Resolver
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
                Write-LogMessage -API $APINAME -tenant 'Global' -user $request.headers.'x-ms-client-principal' -message 'DNS configuration updated' -Sev 'Info'
                $body = [pscustomobject]@{'Results' = 'Success: DNS configuration updated.' }
            } else {
                $StatusCode = [HttpStatusCode]::BadRequest
                $body = [pscustomobject]@{'Results' = 'Error: No DNS resolver provided.' }
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
            $body = [pscustomobject]$Config
            Write-LogMessage -API $APINAME -tenant 'Global' -user $request.headers.'x-ms-client-principal' -message 'Retrieved DNS configuration' -Sev 'Info'
        }
        'RemoveDomain' {
            $Filter = "RowKey eq '{0}'" -f $Request.Query.Domain
            $DomainRow = Get-CIPPAzDataTableEntity @DomainTable -Filter $Filter -Property PartitionKey, RowKey
            Remove-AzDataTableEntity @DomainTable -Entity $DomainRow
            Write-LogMessage -API $APINAME -tenant 'Global' -user $request.headers.'x-ms-client-principal' -message "Removed Domain - $($Request.Query.Domain) " -Sev 'Info'
            $body = [pscustomobject]@{ 'Results' = "Domain removed - $($Request.Query.Domain)" }
        }
    }
} catch {
    Write-LogMessage -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "DNS Config API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    $StatusCode = [HttpStatusCode]::BadRequest
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    })
