function Invoke-CIPPStandardSensitiveInfoTypeTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SensitiveInfoTypeTemplate
    .SYNOPSIS
        (Label) Sensitive Information Type Template
    .DESCRIPTION
        (Helptext) Deploy custom Microsoft Purview Sensitive Information Types from CIPP templates. Existing custom SITs with the same name are overwritten in place.
        (DocsDescription) Deploy custom Sensitive Information Types from CIPP templates. Supports the simple-mode template (Name + Pattern + Confidence — backend synthesizes the rule pack XML) and the advanced-mode template (caller-supplied FileDataBase64 rule pack). If a SIT with the same name already exists, its rule pack is updated in place via Set-DlpSensitiveInformationType. Built-in Microsoft SITs cannot be modified and will be skipped.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-05-10
        EXECUTIVETEXT
            Deploys custom Sensitive Information Types so DLP policies can detect organization-specific identifiers — employee IDs, project codenames, internal account numbers — across tenants consistently.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"sensitiveInfoTypeTemplate","label":"Select Sensitive Information Type Templates","api":{"url":"/api/ListSensitiveInfoTypeTemplates","labelField":"name","valueField":"GUID","queryKey":"ListSensitiveInfoTypeTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $TemplateSelection = $Settings.sensitiveInfoTypeTemplate ?? $Settings.TemplateList ?? $Settings.'standards.SensitiveInfoTypeTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitiveInfoTypeTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates resolved from the selected IDs.' -sev Error
        return
    }

    try {
        $ExistingSits = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object Name, Publisher
    } catch {
        $ExistingSits = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing sensitive information types: $($_.Exception.Message)" -sev Warning
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            try {
                $FileDataBytes = $null
                if ($Template.FileDataBase64) {
                    $FileDataBytes = [System.Convert]::FromBase64String($Template.FileDataBase64)
                } elseif ($Template.Pattern) {
                    $Xml = New-CIPPSitRulePackXml `
                        -Name $TemplateName `
                        -Description ($Template.Description ?? '') `
                        -Pattern $Template.Pattern `
                        -Confidence ([int]($Template.Confidence ?? 85)) `
                        -PatternsProximity ([int]($Template.PatternsProximity ?? 300)) `
                        -Locale ($Template.Locale ?? 'en-us') `
                        -PublisherName ($Template.PublisherName ?? 'CIPP')
                    $FileDataBytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sensitive Information Type template '$TemplateName' is missing both 'Pattern' and 'FileDataBase64' — skipping." -sev Error
                    continue
                }

                $Existing = $ExistingSits | Where-Object { $_.Name -eq $TemplateName } | Select-Object -First 1

                if ($Existing) {
                    if ($Existing.Publisher -like 'Microsoft*') {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sensitive Information Type '$TemplateName' is a built-in Microsoft type and cannot be overwritten — skipping." -sev Warning
                        continue
                    }

                    $SetParams = @{
                        Identity = $TemplateName
                        FileData = $FileDataBytes
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Description)) { $SetParams['Description'] = $Template.Description }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Locale)) { $SetParams['Locale'] = $Template.Locale }

                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-DlpSensitiveInformationType' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Sensitive Information Type '$TemplateName' in place" -sev Info
                } else {
                    $NewParams = @{
                        Name     = $TemplateName
                        FileData = $FileDataBytes
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Description)) { $NewParams['Description'] = $Template.Description }
                    if (-not [string]::IsNullOrWhiteSpace([string]$Template.Locale)) { $NewParams['Locale'] = $Template.Locale }

                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $NewParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Sensitive Information Type '$TemplateName'" -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Sensitive Information Type '$TemplateName'. Error: $ErrorMessage" -sev Error
            }
        }
    }

    $MissingSits = @(foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if (-not ($ExistingSits | Where-Object { $_.Name -eq $TemplateName })) { $TemplateName }
        })

    if ($Settings.alert -eq $true) {
        if ($MissingSits.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected Sensitive Information Type templates are deployed.' -sev Info
        } else {
            $AlertMessage = "Sensitive Information Types not deployed in tenant: $($MissingSits -join ', ')"
            Write-StandardsAlert -message $AlertMessage -object @{ MissingSensitiveInfoTypes = $MissingSits } -tenant $Tenant -standardName 'SensitiveInfoTypeTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{ MissingSensitiveInfoTypes = $MissingSits }
        $ExpectedValue = @{ MissingSensitiveInfoTypes = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.SensitiveInfoTypeTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SensitiveInfoTypeTemplate' -FieldValue ($MissingSits.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
