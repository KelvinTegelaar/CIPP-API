function Invoke-ExecCreateDefaultGroups {
    <#
    .SYNOPSIS
        Create default tenant groups
    .DESCRIPTION
        This function creates a set of default tenant groups that are commonly used
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Groups.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-CippTable -tablename 'TenantGroups'
        $Results = [System.Collections.Generic.List[object]]::new()
        $ExistingGroups = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and Type eq 'dynamic'"
        $DefaultGroups = '[{"PartitionKey":"TenantGroup","RowKey":"369d985e-0fba-48f9-844f-9f793b10a12c","Description":"This group does not have a license for intune, nor a license for Entra ID Premium","Description@type":null,"DynamicRules":"[{\"property\":\"availableServicePlan\",\"operator\":\"notIn\",\"value\":[{\"label\":\"Microsoft Intune\",\"value\":\"INTUNE_A\",\"id\":\"c1ec4a95-1f05-45b3-a911-aa3fa01094f5\"}]},{\"property\":\"availableServicePlan\",\"operator\":\"notIn\",\"value\":[{\"label\":\"Microsoft Entra ID P1\",\"value\":\"AAD_PREMIUM\",\"id\":\"41781fb2-bc02-4b7c-bd55-b576c07bb09d\"}]}]","DynamicRules@type":null,"GroupType":"dynamic","GroupType@type":null,"RuleLogic":"and","RuleLogic@type":null,"Name":"Not Intune and Entra Premium Capable","Name@type":null},{"PartitionKey":"TenantGroup","RowKey":"4dbca08b-7dc5-4e0f-bc25-14a90c8e0941","Description":"This group has atleast one Business Premium License available","Description@type":null,"DynamicRules":"[{\"property\":\"availableLicense\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft 365 Business Premium\",\"value\":\"SPB\"}]},{\"property\":\"availableLicense\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft 365 Business Premium (no Teams)\",\"value\":\"Microsoft_365_ Business_ Premium_(no Teams)\"}]},{\"property\":\"availableLicense\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft 365 Business Premium Donation\",\"value\":\"Microsoft_365_Business_Premium_Donation_(Non_Profit_Pricing)\"}]},{\"property\":\"availableLicense\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft 365 Business Premium EEA (no Teams)\",\"value\":\"Office_365_w\/o_Teams_Bundle_Business_Premium\"}]}]","DynamicRules@type":null,"GroupType":"dynamic","GroupType@type":null,"RuleLogic":"or","RuleLogic@type":null,"Name":"Business Premium License available","Name@type":null},{"PartitionKey":"TenantGroup","RowKey":"703c0e69-84a8-4dcf-a1c2-4986d2ccc850","Description":"This group does have a license for Entra Premium but does not have a license for Intune","Description@type":null,"DynamicRules":"[{\"property\":\"availableServicePlan\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft Entra ID P1\",\"value\":\"AAD_PREMIUM\",\"id\":\"41781fb2-bc02-4b7c-bd55-b576c07bb09d\"}]},{\"property\":\"availableServicePlan\",\"operator\":\"notIn\",\"value\":[{\"label\":\"Microsoft Intune\",\"value\":\"INTUNE_A\",\"id\":\"c1ec4a95-1f05-45b3-a911-aa3fa01094f5\"}]}]","DynamicRules@type":null,"GroupType":"dynamic","GroupType@type":null,"RuleLogic":"and","RuleLogic@type":null,"Name":"Entra Premium Capable, Not Intune Capable","Name@type":null},{"PartitionKey":"TenantGroup","RowKey":"c1dadbc0-f0b4-448c-a2e6-e1938ba102e0","Description":"This group has Intune and Entra ID Premium available","Description@type":null,"DynamicRules":"{\"property\":\"availableServicePlan\",\"operator\":\"in\",\"value\":[{\"label\":\"Microsoft Intune\",\"value\":\"INTUNE_A\"},{\"label\":\"Microsoft Entra ID P1\",\"value\":\"AAD_PREMIUM\"}]}","DynamicRules@type":null,"GroupType":"dynamic","GroupType@type":null,"RuleLogic":"and","RuleLogic@type":null,"Name":"Entra ID Premium and Intune Capable","Name@type":null}]' | ConvertFrom-Json


        foreach ($Group in $DefaultGroups) {
            # Check if group with same name already exists
            $ExistingGroup = $ExistingGroups | Where-Object -Property Name -EQ $group.Name
            if ($ExistingGroup) {
                $Results.Add(@{
                        resultText = "Group '$($Group.Name)' already exists, skipping"
                        state      = 'warning'
                    })
                continue
            }
            $GroupEntity = @{
                PartitionKey = 'TenantGroup'
                RowKey       = $group.RowKey
                Name         = $Group.Name
                Description  = $Group.Description
                GroupType    = $Group.GroupType
                DynamicRules = $Group.DynamicRules
                RuleLogic    = $Group.RuleLogic
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force

            $Results.Add(@{
                    resultText = "Created default group: '$($Group.Name)'"
                    state      = 'success'
                })

            Write-LogMessage -API 'TenantGroups' -message "Created default tenant group: $($Group.Name)" -sev Info
        }

        $Body = @{ Results = $Results }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'TenantGroups' -message "Failed to create default groups: $ErrorMessage" -sev Error
        $Body = @{ Results = "Failed to create default groups: $ErrorMessage" }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $Body
            })
    }
}
