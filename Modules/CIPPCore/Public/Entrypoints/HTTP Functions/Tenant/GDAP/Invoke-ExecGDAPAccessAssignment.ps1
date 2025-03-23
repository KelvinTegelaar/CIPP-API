function Invoke-ExecGDAPAccessAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Action = $Request.Body.Action ?? $Request.Query.Action
    $Id = $Request.Body.Id ?? $Request.Query.Id

    switch ($Action) {
        'ResetMappings' {
            $RoleTemplateId = $Request.Body.RoleTemplateId

            if (-not $RoleTemplateId) {
                $Body = @{
                    Results = @{
                        state      = 'error'
                        resultText = 'RoleTemplateId is required'
                    }
                }
            } else {
                $GDAPRoleTemplatesTable = Get-CIPPTable -TableName 'GDAPRoleTemplates'
                $Mappings = Get-CIPPAzDataTableEntity @GDAPRoleTemplatesTable -Filter "PartitionKey eq 'RoleTemplate' and RowKey eq '$($RoleTemplateId)'" | Select-Object -ExpandProperty RoleMappings | ConvertFrom-Json

                $RelationshipRequests = @(
                    @{
                        'id'     = 'getRelationship'
                        'url'    = "tenantRelationships/delegatedAdminRelationships/$Id"
                        'method' = 'GET'
                    }
                    @{
                        'id'     = 'getAccessAssignments'
                        'url'    = "tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments"
                        'method' = 'GET'
                    }
                )

                $RelationshipResults = New-GraphBulkRequest -Requests $RelationshipRequests -NoAuthCheck $true
                $Relationship = ($RelationshipResults | Where-Object id -EQ 'getRelationship').body
                $AccessAssignments = ($RelationshipResults | Where-Object id -EQ 'getAccessAssignments').body.value

                $Groups = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=id,displayName&`$filter=securityEnabled eq true" -asApp $true -NoAuthCheck $true

                $Requests = [System.Collections.Generic.List[object]]::new()
                $Messages = [System.Collections.Generic.List[object]]::new()

                foreach ($AccessAssignment in $AccessAssignments) {
                    if ($Mappings.GroupId -notcontains $AccessAssignment.accessContainer.accessContainerId -and $AccessAssignment.status -notin @('deleting', 'deleted', 'error')) {
                        Write-Warning "Deleting access assignment for $($AccessAssignment.accessContainer.accessContainerId)"
                        $Group = $Groups | Where-Object id -EQ $AccessAssignment.accessContainer.accessContainerId
                        $Requests.Add(@{
                                'id'      = "delete-$($AccessAssignment.id)"
                                'url'     = "tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments/$($AccessAssignment.id)"
                                'method'  = 'DELETE'
                                'headers' = @{
                                    'If-Match' = $AccessAssignment.'@odata.etag'
                                }
                            })

                        $Messages.Add(@{
                                'id'      = $AccessAssignment.id
                                'message' = "Deleting access assignment for $($Group.displayName)"
                            })

                    }
                }

                foreach ($Mapping in $Mappings) {
                    if ($AccessAssignments.accessContainer.accessContainerId -notcontains $Mapping.GroupId -and $Relationship.accessDetails.unifiedRoles.roleDefinitionId -contains $Mapping.roleDefinitionId) {
                        Write-Information "Creating access assignment for $($Mapping.GroupId)"
                        $Requests.Add(@{
                                'id'     = "create-$($Mapping.GroupId)"
                                'url'    = "tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments"
                                'method' = 'POST'
                                'body'   = @{
                                    'accessDetails'   = @{
                                        'unifiedRoles' = @($Mapping.roleDefinitionId)
                                    }
                                    'accessContainer' = @{
                                        'accessContainerId' = $Mapping.GroupId
                                    }
                                }
                            })
                        $Messages.Add(@{
                                'id'      = $Mapping.GroupId
                                'message' = "Creating access assignment for $($Mapping.GroupName)"
                            })
                    }
                }

                if ($Requests) {
                    Write-Warning "Executing $($Requests.Count) access assignment changes"
                    #Write-Information ($Requests | ConvertTo-Json -Depth 10)

                    $BulkResults = New-GraphBulkRequest -Requests $Requests -NoAuthCheck $true
                    $Results = foreach ($Result in $BulkResults) {
                        $Message = $Messages | Where-Object id -EQ $Result.id
                        if ($Result.status -eq 204) {
                            @{
                                resultText = $Message.message
                                state      = 'success'
                            }
                        } else {
                            @{
                                resultText = "Error: $($Message.message): $($Result.body.error.message)"
                                state      = 'error'
                            }
                        }
                    }

                } else {
                    $Results = @{
                        resultText = 'This relationship already has the correct access assignments'
                        state      = 'success'
                    }
                }

                $Body = @{
                    Results = @($Results)
                }
            }
        }
        default {
            $Body = @{
                Results = @(@{
                        state      = 'error'
                        resultText = 'Invalid action'
                    })
            }
        }
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
