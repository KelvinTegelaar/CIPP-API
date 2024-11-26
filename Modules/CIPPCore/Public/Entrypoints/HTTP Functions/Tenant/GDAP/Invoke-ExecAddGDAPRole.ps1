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
    $Groups = $Request.body.gdapRoles

    $CustomSuffix = $Request.body.customSuffix
    $Table = Get-CIPPTable -TableName 'GDAPRoles'

    $Results = [System.Collections.Generic.List[string]]::new()
    $Requests = [System.Collections.Generic.List[object]]::new()
    $ExistingGroups = New-GraphGetRequest -NoAuthCheck $True -uri 'https://graph.microsoft.com/beta/groups' -tenantid $env:TenantID -AsApp $true

    $RoleMappings = foreach ($Group in $Groups) {
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

    if ($Requests) {
        $ReturnedData = New-GraphBulkRequest -Requests $Requests -tenantid $env:TenantID -NoAuthCheck $True -asapp $true
        foreach ($Return in $ReturnedData) {
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
                    roleDefinitionId = $group.ObjectId
                }
                $Results.Add("Created $($GroupName)")
            }
        }
    }

    Add-CIPPAzDataTableEntity @Table -Entity $RoleMappings -Force

    $body = @{Results = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
