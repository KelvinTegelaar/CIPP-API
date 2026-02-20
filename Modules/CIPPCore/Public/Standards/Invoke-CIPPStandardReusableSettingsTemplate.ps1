function Invoke-CIPPStandardReusableSettingsTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ReusableSettingsTemplate
    .SYNOPSIS
        (Label) Reusable Settings Template
    .DESCRIPTION
        (Helptext) Deploy and manage Intune reusable settings templates for reuse across multiple policies.
        (DocsDescription) Deploy and manage Intune reusable settings templates for reuse across multiple policies.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-01-11
        EXECUTIVETEXT
            Creates and maintains reusable Intune settings templates that can be referenced by multiple policies, ensuring consistent firewall and configuration rule blocks are centrally managed and updated.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"required":true,"name":"TemplateList","label":"Select Reusable Settings Template","api":{"queryKey":"ListIntuneReusableSettingTemplates","url":"/api/ListIntuneReusableSettingTemplates","labelField":"DisplayName","valueField":"GUID","showRefresh":true,"templateView":{"title":"Reusable Settings","property":"RawJSON","type":"intune"}}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    function Remove-CIPPNullProperties {
        param($InputObject)

        if ($null -eq $InputObject) {
            return $null
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

    $RequiredCapabilities = @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
    $TestResult = Test-CIPPStandardLicense -StandardName 'ReusableSettingsTemplate_general' -TenantFilter $Tenant -RequiredCapabilities $RequiredCapabilities
    if ($TestResult -eq $false) {
        $settings.TemplateList | ForEach-Object {
            $MissingLicenseMessage = "This tenant is missing one or more required licenses for this standard: $($RequiredCapabilities -join ', ')."
            Set-CIPPStandardsCompareField -FieldName "standards.ReusableSettingsTemplate.$($_.value)" -FieldValue $MissingLicenseMessage -Tenant $Tenant
        }
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Exiting as the correct license is not present for this standard. Missing: $($RequiredCapabilities -join ', ')" -sev 'Warn'
        return $true
    }

    $Table = Get-CippTable -tablename 'templates'
    $ExistingReusableSettings = New-GraphGETRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings?$top=999' -tenantid $Tenant

    # Align with other template standards by resolving all selected templates upfront
    $SelectedTemplateIds = @($Settings.TemplateList.value)
    if (-not $SelectedTemplateIds) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No reusable settings templates were selected.' -sev 'Warn'
        return $true
    }

    $AllTemplateEntities = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneReusableSettingTemplate'"
    $TemplateEntities = $AllTemplateEntities |
        Where-Object { ($_.RowKey -in $SelectedTemplateIds) -and (-not [string]::IsNullOrWhiteSpace($_.JSON)) } |
        ForEach-Object { $_.JSON } |
        ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $TemplateEntities) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to resolve reusable settings templates: $($SelectedTemplateIds -join ', ')" -sev 'Error'
        return $true
    }

    $CompareList = foreach ($TemplateEntity in $TemplateEntities) {
        $Compare = $null
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
            templateId  = $TemplateEntity.GUID
            existingId  = $Existing.id
        }
    }

    if ($true -in $Settings.remediate) {
        foreach ($Template in $CompareList | Where-Object -Property remediate -EQ $true) {
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
            $state = $Template.compare ? $Template.compare : $true
            Set-CIPPStandardsCompareField -FieldName "standards.ReusableSettingsTemplate.$id" -FieldValue $state -TenantFilter $Tenant
        }
    }
}
