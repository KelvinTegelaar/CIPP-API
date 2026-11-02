function Invoke-CIPPStandardReusableSettingsTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ReusableSettingsTemplate
    .SYNOPSIS
        (Label) Reusable Settings Template
    .DESCRIPTION
        (Helptext) Deploy and maintain Intune reusable settings templates that can be referenced by multiple policies.
        (DocsDescription) Deploy and maintain Intune reusable settings templates that can be referenced by multiple policies.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2026-01-02
        EXECUTIVETEXT
            Creates and keeps reusable Intune settings templates consistent so common firewall and configuration blocks can be reused across many policies.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"required":true,"name":"TemplateList","label":"Select Reusable Settings Template","api":{"queryKey":"ListIntuneReusableSettingTemplates","url":"/api/ListIntuneReusableSettingTemplates","labelField":"displayName","valueField":"GUID","showRefresh":true,"templateView":{"title":"Reusable Settings","property":"RawJSON","type":"intune"}}}
        POWERSHELLEQUIVALENT

        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>
    param($Tenant, $Settings)

    function Remove-CIPPNullProperties {
        param($InputObject)

        if ($null -eq $InputObject) {
            return $null
        }

        # Dictionaries first: a Hashtable is IEnumerable, but foreach over one yields the hashtable
        # itself, so the array branch below would recurse on identical input until the depth blows.
        if ($InputObject -is [System.Collections.IDictionary]) {
            $CleanMap = [ordered]@{}
            foreach ($Key in @($InputObject.Keys)) {
                if ($null -ne $InputObject[$Key]) {
                    $CleanMap[$Key] = Remove-CIPPNullProperties -InputObject $InputObject[$Key]
                }
            }
            return [pscustomobject]$CleanMap
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $CleanArray = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $InputObject) {
                $CleanArray.Add((Remove-CIPPNullProperties -InputObject $item))
            }
            return $CleanArray
        }

        if ($InputObject -is [psobject]) {
            $Output = [ordered]@{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                if ($null -ne $prop.Value) {
                    $Output[$prop.Name] = Remove-CIPPNullProperties -InputObject $prop.Value
                }
            }
            return [pscustomobject]$Output
        }

        return $InputObject
    }

    $TestResult = Test-CIPPStandardLicense -StandardName 'ReusableSettingsTemplate_general' -TenantFilter $Tenant -Preset Intune
    if ($TestResult -eq $false) {
        $settings.TemplateList | ForEach-Object {
            $MissingLicenseMessage = 'License Missing: This tenant is missing the required Intune license for this standard.'
            Set-CIPPStandardsCompareField -FieldName "standards.ReusableSettingsTemplate.$($_.value)" -FieldValue $MissingLicenseMessage -LicenseAvailable $false -TenantFilter $Tenant
        }
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Exiting as the correct license is not present for this standard.' -sev 'Warning'
        return $true
    }

    $Table = Get-CippTable -tablename 'templates'
    # The list endpoint omits settingInstance unless explicitly selected, which would make every compare fail
    $ExistingReusableSettings = New-GraphGETRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings?$top=999&$select=id,displayName,description,settingDefinitionId,settingInstance,version' -tenantid $Tenant

    # Align with other template standards by resolving all selected templates upfront
    $SelectedTemplateIds = @($Settings.TemplateList.value)
    if (-not $SelectedTemplateIds) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No reusable settings templates were selected.' -sev 'Warning'
        return $true
    }

    $AllTemplateEntities = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneReusableSettingTemplate'"
    $EntityByRowKey = @{}
    foreach ($Entity in @($AllTemplateEntities)) {
        if ($Entity.RowKey) { $EntityByRowKey[[string]$Entity.RowKey] = $Entity }
    }

    # Iterate the selected ids, not the rows that resolved. Alignment emits a key for every id in
    # TemplateList, and a key with no compare row reports NOT FOUND and can never be cleared.
    $CompareList = foreach ($TemplateId in $SelectedTemplateIds) {
        $Compare = $null
        $Entity = $EntityByRowKey[[string]$TemplateId]
        $TemplateEntity = if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) {
            $Entity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        } else {
            $null
        }

        if (-not $TemplateEntity) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to resolve reusable settings template $TemplateId." -sev 'Error'
            [pscustomobject]@{
                MatchFailed = $true
                displayname = $TemplateId
                compare     = [pscustomobject]@{
                    MatchFailed = $true
                    Difference  = 'The selected reusable settings template no longer exists in CIPP.'
                }
                rawJSON     = $null
                remediate   = $Settings.remediate
                alert       = $Settings.alert
                report      = $Settings.report
                templateId  = $TemplateId
                existingId  = $null
                Unresolved  = $true
            }
            continue
        }

        $displayName = $TemplateEntity.DisplayName ?? $TemplateEntity.Name
        $RawJSON = $TemplateEntity.RawJSON ?? $TemplateEntity.JSON
        $BodyObject = $RawJSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        $BodyObjectClean = Remove-CIPPNullProperties -InputObject $BodyObject
        $Existing = $ExistingReusableSettings | Where-Object -Property displayName -EQ $displayName | Select-Object -First 1

        if ($Existing) {
            try {
                $ExistingSanitized = $Existing | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context'
                $ExistingClean = Remove-CIPPNullProperties -InputObject $ExistingSanitized
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $BodyObjectClean -DifferenceObject $ExistingClean -compareType 'ReusablePolicySetting' -ErrorAction SilentlyContinue
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "ReusableSettingsTemplate: compare failed for $displayName. $($_.Exception.Message)" -sev 'Error'
            }
        } else {
            $Compare = [pscustomobject]@{
                MatchFailed = $true
                Difference  = 'Reusable setting is missing in this tenant.'
            }
        }

        $CompareClean = if ($Compare) { Remove-CIPPNullProperties -InputObject $Compare } else { $Compare }

        [pscustomobject]@{
            MatchFailed = [bool]$Compare
            displayname = $displayName
            compare     = $CompareClean
            rawJSON     = $RawJSON
            remediate   = $Settings.remediate
            alert       = $Settings.alert
            report      = $Settings.report
            # The id the picker sent (the RowKey), never the GUID inside the stored JSON -
            # alignment keys off TemplateList.value.
            templateId  = $TemplateId
            existingId  = $Existing.id
            Unresolved  = $false
        }
    }

    if ($true -in $Settings.remediate) {
        # Unresolved templates carry no body, so the create branch below would POST a null one.
        foreach ($Template in $CompareList | Where-Object { $_.remediate -eq $true -and -not $_.Unresolved }) {
            $Body = $Template.rawJSON

            if ($Template.existingId) {
                try {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$($Template.existingId)" -tenantid $Tenant -type PUT -body $Body
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated reusable setting $($Template.displayName)" -sev 'Info'
                } catch {
                    $errorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update reusable setting $($Template.displayName). Error: $errorMessage" -sev 'Error'
                }
            } else {
                try {
                    $CreateRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings' -tenantid $Tenant -type POST -body $Body
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created reusable setting $($Template.displayName)" -sev 'Info'
                } catch {
                    $createError = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create reusable setting $($Template.displayName). Error: $createError" -sev 'Error'
                }
            }
        }
    }

    if ($true -in $Settings.alert) {
        foreach ($Template in $CompareList | Where-Object -Property alert -EQ $true) {
            $AlertObj = $Template | Select-Object -Property displayName, compare, existingId
            if ($Template.compare) {
                Write-StandardsAlert -message "Reusable setting $($Template.displayName) does not match the expected configuration." -object $AlertObj -tenant $Tenant -standardName 'ReusableSettingsTemplate' -standardId $Template.templateId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Reusable setting $($Template.displayName) is out of compliance." -sev info
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Reusable setting $($Template.displayName) is compliant." -sev Info
            }
        }
    }

    if ($true -in $Settings.report) {
        foreach ($Template in $CompareList | Where-Object { $_.report -eq $true -or $_.remediate -eq $true }) {
            $id = $Template.templateId
            $CurrentValue = @{
                displayName = $Template.displayname
                isCompliant = if ($Template.compare) { $false } else { $true }
            }
            $ExpectedValue = @{
                displayName = $Template.displayname
                isCompliant = $true
            }
            Set-CIPPStandardsCompareField -FieldName "standards.ReusableSettingsTemplate.$id" -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        }
    }
}
