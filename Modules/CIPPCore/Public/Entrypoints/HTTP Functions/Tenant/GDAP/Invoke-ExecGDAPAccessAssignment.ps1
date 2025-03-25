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
                    $RoleCount = ($AccessAssignment.accessDetails.unifiedRoles | Measure-Object).Count
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
                                'id'      = "delete-$($AccessAssignment.id)"
                                'message' = "Deleting access assignment for $($Group.displayName)"
                            })

                    } elseif ($AccessAssignment.status -notin @('deleting', 'deleted', 'error')) {
                        # check for mismatched role definitions (e.g. role in assignment does not match role in mapping)
                        $Mapping = $Mappings | Where-Object { $_.GroupId -eq $AccessAssignment.accessContainer.accessContainerId }
                        $Group = $Groups | Where-Object id -EQ $AccessAssignment.accessContainer.accessContainerId

                        if ($RoleCount -gt 1 -or $AccessAssignment.accessDetails.unifiedRoles.roleDefinitionId -notcontains $Mapping.roleDefinitionId) {
                            Write-Warning "Patching access assignment for $($AccessAssignment.accessContainer.accessContainerId)"
                            $Requests.Add(@{
                                    'id'      = "patch-$($AccessAssignment.id)"
                                    'url'     = "tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments/$($AccessAssignment.id)"
                                    'method'  = 'PATCH'
                                    'body'    = @{
                                        'accessDetails' = @{
                                            'unifiedRoles' = @(
                                                @{
                                                    roleDefinitionId = $Mapping.roleDefinitionId
                                                }
                                            )
                                        }
                                    }
                                    'headers' = @{
                                        'If-Match'     = $AccessAssignment.'@odata.etag'
                                        'Content-Type' = 'application/json'
                                    }
                                })

                            $Messages.Add(@{
                                    'id'      = "patch-$($AccessAssignment.id)"
                                    'message' = "Updating access assignment for $($Group.displayName)"
                                })
                        }
                    }
                }

                foreach ($Mapping in $Mappings) {
                    $DeletedAssignments = $AccessAssignments | Where-Object { $_.accessContainer.accessContainerId -eq $Mapping.GroupId -and $_.status -eq 'deleted' }
                    if (($AccessAssignments.accessContainer.accessContainerId -notcontains $Mapping.GroupId -or $DeletedAssignments.accessContainer.accessContainerId -contains $Mapping.GroupId) -and $Relationship.accessDetails.unifiedRoles.roleDefinitionId -contains $Mapping.roleDefinitionId) {
                        Write-Information "Creating access assignment for $($Mapping.GroupId)"
                        $Requests.Add(@{
                                'id'      = "create-$($Mapping.GroupId)"
                                'url'     = "tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments"
                                'method'  = 'POST'
                                'body'    = @{
                                    'accessDetails'   = @{
                                        'unifiedRoles' = @(
                                            @{
                                                roleDefinitionId = $Mapping.roleDefinitionId
                                            }
                                        )
                                    }
                                    'accessContainer' = @{
                                        'accessContainerId'   = $Mapping.GroupId
                                        'accessContainerType' = 'securityGroup'
                                    }
                                }
                                'headers' = @{
                                    'Content-Type' = 'application/json'
                                }
                            })
                        $Messages.Add(@{
                                'id'      = "create-$($Mapping.GroupId)"
                                'message' = "Creating access assignment for $($Mapping.GroupName)"
                            })
                    }
                }

                if ($Requests) {
                    Write-Warning "Executing $($Requests.Count) access assignment changes"
                    Write-Information ($Requests | ConvertTo-Json -Depth 10)

                    $BulkResults = New-GraphBulkRequest -Requests $Requests -NoAuthCheck $true

                    Write-Warning "Received $($BulkResults.Count) access assignment results"
                    Write-Information ($BulkResults | ConvertTo-Json -Depth 10)
                    $Results = foreach ($Result in $BulkResults) {
                        $Message = $Messages | Where-Object id -EQ $Result.id
                        if ($Result.status -in @('201', '202', '204')) {
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
