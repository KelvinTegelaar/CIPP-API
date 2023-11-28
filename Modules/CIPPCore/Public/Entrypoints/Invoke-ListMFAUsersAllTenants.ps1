using namespace System.Net

Function Invoke-ListMFAUsersAllTenants {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        

    Write-Information "Item: $QueueItem"
    Write-Information ($TriggerMetadata | ConvertTo-Json)

    try {
        Update-CippQueueEntry -RowKey $QueueItem -Status 'Running'

        $GraphRequest = Get-Tenants | ForEach-Object -Parallel { 
            $domainName = $_.defaultDomainName
            Import-Module '.\GraphHelper.psm1'
            Import-Module '.\modules\CippCore'
            Import-Module '.\Modules\AzBobbyTables'

            $Table = Get-CIPPTable -TableName cachemfa
            Try {
                $GraphRequest = Get-CIPPMFAState -TenantFilter $domainName -ErrorAction Stop
            } catch { 
                $GraphRequest = $null 
            }
            if (!$GraphRequest) {
                $GraphRequest = @{
                    Tenant          = [string]$tenantName
                    UPN             = [string]$domainName
                    AccountEnabled  = 'none'
                    PerUser         = [string]'Could not connect to tenant'
                    MFARegistration = 'none'
                    CoveredByCA     = [string]'Could not connect to tenant'
                    CoveredBySD     = 'none'
                    RowKey          = [string]"$domainName"
                    PartitionKey    = 'users'
                }
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
        }
    } catch {
        $Table = Get-CIPPTable -TableName cachemfa
        $GraphRequest = @{
            Tenant          = [string]$tenantName
            UPN             = [string]$domainName
            AccountEnabled  = 'none'
            PerUser         = [string]'Could not connect to tenant'
            MFARegistration = 'none'
            CoveredByCA     = [string]'Could not connect to tenant'
            CoveredBySD     = 'none'
            RowKey          = [string]"$domainName"
            PartitionKey    = 'users'
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    } finally {
        Update-CippQueueEntry -RowKey $QueueItem -Status 'Completed'
    }

}
