function Set-CIPPGDAPInviteGroups {
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param($Relationship)
    $Table = Get-CIPPTable -TableName 'GDAPInvites'

    if ($Relationship) {
        $Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Relationship.id)'"
        $APINAME = 'GDAPInvites'
        $RoleMappings = $Invite.RoleMappings | ConvertFrom-Json
        $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($Relationship.id)/accessAssignments"
        foreach ($Role in $RoleMappings) {
            # Skip mapping if group is present in relationship
            if ($AccessAssignments.id -and $AccessAssignments.accessContainer.accessContainerid -contains $Role.GroupId ) { continue }
            try {
                $Mappingbody = ConvertTo-Json -Depth 10 -InputObject @{
                    'accessContainer' = @{
                        'accessContainerId'   = "$($Role.GroupId)"
                        'accessContainerType' = 'securityGroup'
                    }
                    'accessDetails'   = @{
                        'unifiedRoles' = @(@{
                                'roleDefinitionId' = "$($Role.roleDefinitionId)"
                            })
                    }
                }
                if ($PSCmdlet.ShouldProcess($Relationship.id, "Map group $($Role.GroupName) to customer $($Relationship.customer.displayName)")) {
                    $null = New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($Relationship.id)/accessAssignments" -tenantid $env:TenantID -type POST -body $MappingBody -verbose
                    Start-Sleep -Milliseconds 100
                }
            } catch {
                Write-LogMessage -API $APINAME -message "GDAP Group mapping failed for $($Relationship.customer.displayName) - Group: $($role.GroupId) - Exception: $($_.Exception.Message)" -Sev Error -LogData (Get-CippException -Exception $_)
                return $false
            }
        }

        if ($PSCmdlet.ShouldProcess($Relationship.id, "Remove invite entry for $($Relationship.customer.displayName)")) {
            Write-LogMessage -API $APINAME -message "Groups mapped for GDAP Relationship: $($Relationship.customer.displayName) - $($Relationship.customer.displayName)" -Sev Info
            Remove-AzDataTableEntity @Table -Entity $Invite
        }
        return $true
    } else {
        $InviteList = Get-CIPPAzDataTableEntity @Table
        if (($InviteList | Measure-Object).Count -gt 0) {
            $Activations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'"

            $Batch = foreach ($Activation in $Activations) {
                if ($InviteList.RowKey -contains $Activation.id) {
                    Write-Information "Mapping groups for GDAP relationship: $($Activation.customer.displayName) - $($Activation.id)"
                    $Activation | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'ExecGDAPInviteQueue'
                    $Activation
                }
            }
            if (($Batch | Measure-Object).Count -gt 0) {
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'GDAPInviteOrchestrator'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                #Write-Information ($InputObject | ConvertTo-Json)
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Information "Started GDAP Invite orchestration with ID = '$InstanceId'"
            }
        }
    }
}
