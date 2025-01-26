using namespace System.Net

Function Invoke-ExecAddGDAPRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $CippDefaults = @(
        @{ label = 'Application Administrator'; value = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' },
        @{ label = 'User Administrator'; value = 'fe930be7-5e62-47db-91af-98c3a49a38b1' },
        @{ label = 'Intune Administrator'; value = '3a2c62db-5318-420d-8d74-23affee5d9d5' },
        @{ label = 'Exchange Administrator'; value = '29232cdf-9323-42fd-ade2-1d097af3e4de' },
        @{ label = 'Security Administrator'; value = '194ae4cb-b126-40b2-bd5b-6091b380977d' },
        @{ label = 'Cloud App Security Administrator'; value = '892c5842-a9a6-463a-8041-72aa08ca3cf6' },
        @{ label = 'Cloud Device Administrator'; value = '7698a772-787b-4ac8-901f-60d6b08affd2' },
        @{ label = 'Teams Administrator'; value = '69091246-20e8-4a56-aa4d-066075b2a7a8' },
        @{ label = 'Sharepoint Administrator'; value = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' },
        @{ label = 'Authentication Policy Administrator'; value = '0526716b-113d-4c15-b2c8-68e3c22b9f80' },
        @{ label = 'Privileged Role Administrator'; value = 'e8611ab8-c189-46e8-94e1-60213ab1f814' },
        @{ label = 'Privileged Authentication Administrator'; value = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' }
    )

    $Groups = $Request.body.gdapRoles ?? $CippDefaults

    $CustomSuffix = $Request.body.customSuffix
    $Table = Get-CIPPTable -TableName 'GDAPRoles'

    $Results = [System.Collections.Generic.List[string]]::new()
    $Requests = [System.Collections.Generic.List[object]]::new()
    $ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID -AsApp $true

    $ExistingRoleMappings = foreach ($Group in $Groups) {
        $RoleName = $Group.label ?? $Group.Name
        $Value = $Group.value ?? $Group.ObjectId

        if ($CustomSuffix) {
            $GroupName = "M365 GDAP $($RoleName) - $CustomSuffix"
            $MailNickname = "M365GDAP$(($RoleName).replace(' ',''))$($CustomSuffix.replace(' ',''))"
        } else {
            $GroupName = "M365 GDAP $($RoleName)"
            $MailNickname = "M365GDAP$(($RoleName).replace(' ',''))"
        }

        if ($GroupName -in $ExistingGroups.displayName) {
            @{
                PartitionKey     = 'Roles'
                RowKey           = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName).id
                RoleName         = $RoleName
                GroupName        = $GroupName
                GroupId          = ($ExistingGroups | Where-Object -Property displayName -EQ $GroupName).id
                roleDefinitionId = $Value
            }
            $Results.Add("$GroupName already exists")
        } else {
            $Requests.Add(@{
                    id      = $Value
                    url     = '/groups'
                    method  = 'POST'
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                    body    = @{
                        displayName     = $GroupName
                        description     = "This group is used to manage M365 partner tenants at the $($RoleName) level."
                        securityEnabled = $true
                        mailEnabled     = $false
                        mailNickname    = $MailNickname
                    }
                })
        }
    }
    if ($ExistingRoleMappings) {
        Add-CIPPAzDataTableEntity @Table -Entity $ExistingRoleMappings -Force
    }

    if ($Requests) {
        $ReturnedData = New-GraphBulkRequest -Requests $Requests -tenantid $env:TenantID -NoAuthCheck $True -asapp $true
        $NewRoleMappings = foreach ($Return in $ReturnedData) {
            if ($Return.body.error) {
                $Results.Add("Could not create GDAP group: $($Return.body.error.message)")
            } else {
                $GroupName = $Return.body.displayName
                @{
                    PartitionKey     = 'Roles'
                    RowKey           = $Return.body.id
                    RoleName         = $Return.body.displayName -replace '^M365 GDAP ', '' -replace " - $CustomSuffix$", ''
                    GroupName        = $Return.body.displayName
                    GroupId          = $Return.body.id
                    roleDefinitionId = $Return.id
                }
                $Results.Add("Created $($GroupName)")
            }
        }
        Write-Information ($NewRoleMappings | ConvertTo-Json -Depth 10 -Compress)
        if ($NewRoleMappings) {
            Add-CIPPAzDataTableEntity @Table -Entity $NewRoleMappings -Force
        }
    }

    $RoleMappings = [System.Collections.Generic.List[object]]::new()
    if ($ExistingRoleMappings) {
        $RoleMappings.AddRange(@($ExistingRoleMappings))
    }
    if ($NewRoleMappings) {
        $RoleMappings.AddRange(@($NewRoleMappings))
    }

    if ($Request.Body.templateId) {
        Add-CIPPGDAPRoleTemplate -TemplateId $Request.Body.templateId -RoleMappings ($RoleMappings | Select-Object -Property RoleName, GroupName, GroupId, roleDefinitionId)
        $Results.Add("Added role mappings to template $($Request.Body.templateId)")
    }

    $body = @{Results = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
