function Invoke-ExecGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Create'
    $InviteId = $Request.Body.InviteId
    $Reference = $Request.Body.Reference
    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    $StatusCode = [HttpStatusCode]::OK

    # Extract technician from headers (same logic as Write-LogMessage)
    if ($Headers.'x-ms-client-principal-idp' -eq 'azureStaticWebApps' -or !$Headers.'x-ms-client-principal-idp') {
        $user = $headers.'x-ms-client-principal'
        $Technician = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    } elseif ($Headers.'x-ms-client-principal-idp' -eq 'aad') {
        $ApiClientTable = Get-CIPPTable -TableName 'ApiClients'
        $Client = Get-CIPPAzDataTableEntity @ApiClientTable -Filter "RowKey eq '$($headers.'x-ms-client-principal-name')'"
        $Technician = $Client.AppName ?? 'CIPP-API'
    } else {
        try {
            $user = $headers.'x-ms-client-principal'
            $Technician = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
        } catch {
            $Technician = 'System'
        }
    }

    switch ($Action) {
        'Create' {
            $RoleMappings = $Request.Body.roleMappings
            # Entra role definition id; a role mapped to more than one group is sent to Graph once
            $RoleIds = @($RoleMappings.roleDefinitionId | Where-Object { $_ } | Sort-Object -Unique)

            $Problems = [System.Collections.Generic.List[string]]::new()
            if ($RoleIds.Count -eq 0) {
                $Problems.Add('The role template has no roles.')
            }
            foreach ($Mapping in @($RoleMappings).Where({ -not $_.roleDefinitionId })) {
                $Problems.Add("'$($Mapping.RoleName ?? $Mapping.GroupName)' has no role definition id.")
            }
            if ($RoleIds.Count -gt 0) {
                try {
                    $BuiltInRoleIds = (New-GraphGetRequest -NoAuthCheck $true -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id&$filter=isBuiltIn eq true' -tenantid $env:TenantID).id
                    # Partner Tier1/Tier2 Support exist in every tenant but GDAP cannot delegate them
                    $NotDelegable = @('4ba39ca4-527c-499a-b93d-d9b492c50246', 'e00e864a-17c5-4a4b-9c06-f5b95a8d5bd8')
                    foreach ($RoleId in $RoleIds) {
                        if ($RoleId -notin $BuiltInRoleIds -or $RoleId -in $NotDelegable) {
                            $RoleName = @($RoleMappings).Where({ $_.roleDefinitionId -eq $RoleId }, 'First')[0].RoleName
                            $Problems.Add("'$RoleName' ($RoleId) is not a built-in Entra role that GDAP can delegate.")
                        }
                    }
                } catch {
                    Write-Information "GDAP invite role check skipped: $($_.Exception.Message)"
                }
            }
            if ($Problems.Count -gt 0) {
                $Message = "The role template cannot be used for an invite. Edit the template and fix: $($Problems -join ' ')"
                Write-LogMessage -headers $Headers -API $APIName -tenant $env:TenantID -message $Message -Sev 'Error'
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Message = $Message }
                    })
            }

            if ($RoleIds -contains '62e90394-69f5-4237-9190-012177145e10') {
                $AutoExtendDuration = 'PT0S'
            } else {
                $AutoExtendDuration = 'P180D'
            }

            try {
                $Step = 'Creating GDAP relationship'
                $JSONBody = @{
                    'displayName'        = "CIPP_$((New-Guid).GUID)"
                    'accessDetails'      = @{
                        'unifiedRoles' = @($RoleIds | ForEach-Object { @{ roleDefinitionId = $_ } })
                    }
                    'autoExtendDuration' = $AutoExtendDuration
                    'duration'           = 'P730D'
                } | ConvertTo-Json -Depth 5 -Compress

                $NewRelationship = New-GraphPostRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships' -type POST -body $JSONBody -verbose -tenantid $env:TenantID
                Start-Sleep -Milliseconds 100
                $Count = 0
                do {
                    $CheckActive = New-GraphGetRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($NewRelationship.id)" -tenantid $env:TenantID
                    Start-Sleep -Milliseconds 200
                    $Count++
                } until ($CheckActive.status -eq 'created' -or $Count -gt 5)

                if ($CheckActive.status -eq 'created') {
                    # Lock for approval
                    $JSONBody = @{
                        'action' = 'lockForApproval'
                    } | ConvertTo-Json
                    $Step = 'Locking GDAP relationship for approval'

                    $AddedHeaders = @{
                        'If-Match' = $NewRelationship.'@odata.etag'
                    }

                    $NewRelationshipRequest = New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($NewRelationship.id)/requests" -type POST -body $JSONBody -verbose -tenantid $env:TenantID -AddedHeaders $AddedHeaders

                    if ($NewRelationshipRequest.action -eq 'lockForApproval') {
                        $InviteUrl = "https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/$($NewRelationship.id)"
                        $Hostname = Get-CIPPHostname -Headers $Headers -PreferCustomDomain
                        if ($Hostname) {
                            $OnboardingUrl = "https://$Hostname/tenant/gdap-management/onboarding/start?id=$($NewRelationship.id)"
                        } else {
                            $OnboardingUrl = $null
                        }

                        $InviteEntity = [PSCustomObject]@{
                            'PartitionKey'  = 'invite'
                            'RowKey'        = $NewRelationship.id
                            'InviteUrl'     = $InviteUrl
                            'OnboardingUrl' = $OnboardingUrl
                            'RoleMappings'  = [string](@($RoleMappings) | ConvertTo-Json -Depth 10 -Compress)
                            'Technician'    = [string]$Technician
                            'Reference'     = if ($Reference) { [string]$Reference } else { $null }
                        }

                        Add-CIPPAzDataTableEntity @Table -Entity $InviteEntity

                        $Message = 'GDAP relationship invite created. Log in as a Global Admin in the new tenant to approve the invite.'
                    } else {
                        $Message = 'Error creating GDAP relationship request'
                        $StatusCode = [HttpStatusCode]::InternalServerError
                    }

                    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created GDAP Invite - $InviteUrl" -Sev 'Info'
                }
            } catch {
                $Message = 'Error creating GDAP relationship, failed at step: ' + $Step
                Write-Information "GDAP ERROR: on line $($_.InvocationInfo.PositionMessage) | $(($_ | ConvertTo-Json -Compress))"

                if ($Step -eq 'Creating GDAP relationship' -and $_.Exception.Message -match 'The user (principal) does not have the required permissions to perform the specified action on the resource.') {
                    $Message = 'Error creating GDAP relationship, ensure that all users have MFA enabled and enforced without exception. Please see the Microsoft Partner Security Requirements documentation for more information. https://learn.microsoft.com/en-us/partner-center/security/partner-security-requirements'
                } else {
                    $Message = "$($Message): $($_.Exception.Message)"
                }

                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $env:TenantID -message $Message -Sev 'Error' -LogData (Get-CippException -Exception $_)
                $StatusCode = [HttpStatusCode]::InternalServerError
            }

            $body = @{
                Message = $Message
                Invite  = $InviteEntity
            }
        }
        'Update' {
            $Invite = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'invite' and RowKey eq '$InviteId'"
            if ($Invite) {

                $InviteEntity = [PSCustomObject]@{
                    'PartitionKey' = 'invite'
                    'RowKey'       = $InviteId
                    'Technician'   = $Technician
                    'Reference'    = if ($Reference) { $Reference } else { $null }
                }

                Add-CIPPAzDataTableEntity @Table -Entity $InviteEntity -OperationType 'UpsertMerge'
                $Message = 'Invite updated'
            } else {
                $Message = 'Invite not found'
                $StatusCode = [HttpStatusCode]::NotFound
            }
            $body = @{
                Message = $Message
            }
        }
        'Delete' {
            $Invite = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'invite' and RowKey eq '$InviteId'"
            if ($Invite) {
                Remove-CIPPAzDataTableEntity @Table -Entity $Invite
                $Message = 'Invite deleted'
            } else {
                $Message = 'Invite not found'
                $StatusCode = [HttpStatusCode]::NotFound
            }
            $body = @{
                Message = $Message
            }
        }

    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
