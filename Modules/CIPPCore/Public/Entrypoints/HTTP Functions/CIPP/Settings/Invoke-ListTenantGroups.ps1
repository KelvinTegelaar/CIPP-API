function Invoke-ListTenantGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'TenantGroups'
    $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $groupFilter = $Request.Query.groupId ?? $Request.Body.groupId

    switch ($Action) {
        'ListMembers' {
            if (!$groupFilter) {
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = 'groupFilter is required for ListMembers action'
                    })
                return
            }

            $Tenants = Get-Tenants -IncludeErrors
            $Members = Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq '$groupFilter'"
            if (!$Members) {
                $Members = @()
            }

            $Results = $Members | ForEach-Object {
                $Tenant = $Tenants | Where-Object { $_.customerId -eq $_.RowKey }
                if ($Tenant) {
                    @{
                        customerId        = $Tenant.customerId
                        displayName       = $Tenant.displayName
                        defaultDomainName = $Tenant.defaultDomainName
                    }
                }
            }

            $Body = @{ Results = $Results }
        }
        default {
            $Groups = Get-CIPPAzDataTableEntity @Table
            if (!$Groups) {
                $Results = @()
            } else {
                $Results = $Groups | ForEach-Object {
                    @{
                        groupId           = $_.RowKey
                        groupName         = $_.groupName
                        groupDescription  = $_.groupDescription
                        groupMembersCount = (Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq '$($_.RowKey)'" -Property PartitionKey, RowKey).Count
                    }
                }
            }
            $Body = @{ Results = @($Results) }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
