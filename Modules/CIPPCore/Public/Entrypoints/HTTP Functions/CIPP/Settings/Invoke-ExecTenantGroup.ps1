function Invoke-ExecTenantGroup {
    <#
    .SYNOPSIS
        Entrypoint for tenant group management
    .DESCRIPTION
        This function is used to manage tenant groups in CIPP
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'TenantGroups'
    $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'
    $Action = $Request.Body.Action
    $groupId = $Request.Body.groupId ?? [guid]::NewGuid().ToString()
    $groupName = $Request.Body.groupName
    $groupDescription = $Request.Body.groupDescription
    $members = $Request.Body.members

    switch ($Action) {
        'AddEdit' {
            $Results = [System.Collections.Generic.List[object]]::new()
            # Update group details
            $GroupEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$groupId'"
            if ($GroupEntity) {
                if ($groupName) {
                    $GroupEntity.Name = $groupName
                }
                if ($groupDescription) {
                    $GroupEntity.Description = $groupDescription
                }
                Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force
            } else {
                $GroupEntity = @{
                    PartitionKey = 'TenantGroup'
                    RowKey       = $groupId
                    Name         = $groupName
                    Description  = $groupDescription
                }
                Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force
            }

            $CurrentMembers = Get-CIPPAzDataTableEntity @MembersTable -Filter "GroupId eq '$groupId'"

            $Adds = [System.Collections.Generic.List[string]]::new()
            $Removes = [System.Collections.Generic.List[string]]::new()
            # Add members
            foreach ($member in $members) {
                if ($CurrentMembers) {
                    $CurrentMember = $CurrentMembers | Where-Object { $_.customerId -eq $member.value }
                    if ($CurrentMember) {
                        continue
                    }
                }
                $MemberEntity = @{
                    PartitionKey = 'Member'
                    RowKey     = '{0}-{1}' -f $groupId, $member.value
                    GroupId    = $groupId
                    customerId = $member.value
                }
                Add-CIPPAzDataTableEntity @MembersTable -Entity $MemberEntity -Force
                $Adds.Add('Added member {0}' -f $member.label)
            }

            if ($CurrentMembers) {
                foreach ($CurrentMember in $CurrentMembers) {
                    if ($members.value -notcontains $CurrentMember.customerId) {
                        Remove-AzDataTableEntity @MembersTable -Entity $CurrentMember -Force
                        $Removes.Add('Removed member {0}' -f $CurrentMember.customerId)
                    }
                }
            }
            $Results.Add(@{
                    resultText = "Group '$groupName' saved successfully"
                    state      = 'success'
                })
            foreach ($Add in $Adds) {
                $Results.Add(@{
                        resultText = $Add
                        state      = 'success'
                    })
            }
            foreach ($Remove in $Removes) {
                $Results.Add(@{
                        resultText = $Remove
                        state      = 'success'
                    })
            }

            $Body = @{ Results = $Results }
        }
        'Delete' {
            # Delete group
            $GroupEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$groupId'"
            if ($GroupEntity) {
                Remove-AzDataTableEntity @Table -Entity $GroupEntity -Force
                $Body = @{ Results = "Group '$($GroupEntity.Name)' deleted successfully" }
            } else {
                $Body = @{ Results = "Group '$groupId' not found" }
            }
        }
        default {
            $Body = @{ Results = 'Invalid action' }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
