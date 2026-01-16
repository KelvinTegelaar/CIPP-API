function Invoke-CIPPStandardAssignmentFilterTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AssignmentFilterTemplate
    .SYNOPSIS
        (Label) Assignment Filter Template
    .DESCRIPTION
        (Helptext) Deploy and manage assignment filter templates.
        (DocsDescription) Deploy and manage assignment filter templates.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-10-04
        EXECUTIVETEXT
            Creates standardized assignment filters with predefined settings. These templates ensure consistent assignment filter configurations across the organization, streamlining assignment management.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"assignmentFilterTemplate","label":"Select Assignment Filter Template","api":{"url":"/api/ListAssignmentFilterTemplates","labelField":"Displayname","altLabelField":"displayName","valueField":"GUID","queryKey":"ListAssignmentFilterTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AssignmentFilterTemplate'
    $existingFilters = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $tenant

    $Settings.assignmentFilterTemplate ? ($Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.assignmentFilterTemplate) : $null

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'AssignmentFilterTemplate' and (RowKey eq '$($Settings.TemplateList.value -join "' or RowKey eq '")')"
    $AssignmentFilterTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    $ExpectedValue = [PSCustomObject]@{ state = 'Configured correctly' }
    $MissingFilters = $AssignmentFilterTemplates | Where-Object {
        $CheckExisting = $existingFilters | Where-Object { $_.displayName -eq $_.displayName }
        if (!$CheckExisting) {
            $_.displayName
        }
    }
    $CurrentValue = if ($MissingFilters.Count -eq 0) { [PSCustomObject]@{'state' = 'Configured correctly' } } else { [PSCustomObject]@{'MissingFilters' = @($MissingFilters) } }

    if ($Settings.remediate -eq $true) {
        Write-Host "Settings: $($Settings.TemplateList | ConvertTo-Json)"
        foreach ($Template in $AssignmentFilterTemplates) {
            Write-Information "Processing template: $($Template.displayName)"
            try {
                $filterobj = $Template

                # Check if filter already exists
                $CheckExisting = $existingFilters | Where-Object -Property displayName -EQ $filterobj.displayName

                if (!$CheckExisting) {
                    Write-Information 'Creating assignment filter'
                    $ActionType = 'create'

                    # Use the centralized New-CIPPAssignmentFilter function
                    $Result = New-CIPPAssignmentFilter -FilterObject $filterobj -TenantFilter $tenant -APIName 'Standards' -ExecutingUser 'CIPP-Standards'

                    if (!$Result.Success) {
                        Write-Information "Failed to create assignment filter $($filterobj.displayName): $($Result.Message)"
                        continue
                    }
                } else {
                    $ActionType = 'update'

                    # Compare existing filter with template to determine what needs updating
                    $PatchBody = [PSCustomObject]@{}
                    $ChangesNeeded = [System.Collections.Generic.List[string]]::new()

                    # Check description
                    if ($CheckExisting.description -ne $filterobj.description) {
                        $PatchBody | Add-Member -NotePropertyName 'description' -NotePropertyValue $filterobj.description
                        $ChangesNeeded.Add("description: '$($CheckExisting.description)' → '$($filterobj.description)'")
                    }

                    # Check platform
                    if ($CheckExisting.platform -ne $filterobj.platform) {
                        $PatchBody | Add-Member -NotePropertyName 'platform' -NotePropertyValue $filterobj.platform
                        $ChangesNeeded.Add("platform: '$($CheckExisting.platform)' → '$($filterobj.platform)'")
                    }

                    # Check rule
                    if ($CheckExisting.rule -ne $filterobj.rule) {
                        $PatchBody | Add-Member -NotePropertyName 'rule' -NotePropertyValue $filterobj.rule
                        $ChangesNeeded.Add("rule: '$($CheckExisting.rule)' → '$($filterobj.rule)'")
                    }

                    # Check assignmentFilterManagementType
                    if ($CheckExisting.assignmentFilterManagementType -ne $filterobj.assignmentFilterManagementType) {
                        $PatchBody | Add-Member -NotePropertyName 'assignmentFilterManagementType' -NotePropertyValue $filterobj.assignmentFilterManagementType
                        $ChangesNeeded.Add("assignmentFilterManagementType: '$($CheckExisting.assignmentFilterManagementType)' → '$($filterobj.assignmentFilterManagementType)'")
                    }

                    # Only patch if there are actual changes
                    if ($ChangesNeeded.Count -gt 0) {
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($CheckExisting.id)" -tenantid $tenant -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10)
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Updated Assignment Filter '$($filterobj.displayName)' - Changes: $($ChangesNeeded -join ', ')" -Sev Info
                    } else {
                        Write-Information "Assignment Filter '$($filterobj.displayName)' already matches template - no update needed"
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to $ActionType assignment filter $($filterobj.displayName). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true) {
        # Check if all filters.displayName are in the existingFilters, if not $fieldvalue should contain all missing filters, else it should be true.
        $MissingFilters = foreach ($Filter in $AssignmentFilterTemplates) {
            $CheckExisting = $existingFilters | Where-Object { $_.displayName -eq $Filter.displayName }
            if (!$CheckExisting) {
                $Filter.displayName
            }
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.AssignmentFilterTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
