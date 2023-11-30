using namespace System.Net

Function Invoke-ExecIncidentsListAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        
    Get-Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        $Table = Get-CIPPTable -TableName 'cachealertsandincidents'

        try {
            $incidents = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/incidents' -tenantid $domainName -AsApp $true
            $GraphRequest = foreach ($incident in $incidents) {    
                $GUID = (New-Guid).Guid
                $GraphRequest = @{
                    Incident     = [string]($incident | ConvertTo-Json -Depth 10)
                    RowKey       = [string]$GUID
                    PartitionKey = 'Incident'
                    Tenant       = [string]$domainName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
            } 

        } catch {
            $GUID = (New-Guid).Guid
            $AlertText = ConvertTo-Json -InputObject @{
                Tenant         = $domainName
                displayName    = "Could not connect to Tenant: $($_.Exception.Message)"
                comments       = @{
                    createdDateTime      = (Get-Date).ToString('s')
                    createdbyDisplayName = 'CIPP'
                    comment              = 'Could not connect'
                }
                classification = 'Unknown'
                determination  = 'Unknown'
                severity       = 'CIPP'
            }
            $GraphRequest = @{
                Incident     = [string]$AlertText 
                RowKey       = [string]$GUID
                PartitionKey = 'Incident'
                Tenant       = [string]$domainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null


        }
    }

}
