function Invoke-CIPPStandardMDMScope {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MDMScope
    .SYNOPSIS
        (Label) Configure MDM user scope
    .DESCRIPTION
        (Helptext) Configures the MDM user scope. This also sets the terms of use, discovery and compliance URL to default URLs.
        (DocsDescription) Configures the MDM user scope. This also sets the terms of use URL, discovery URL and compliance URL to default values.
    .NOTES
        CAT
            Intune Standards
        TAG
        ADDEDCOMPONENT
            {"name":"appliesTo","label":"MDM User Scope?","type":"radio","options":[{"label":"All","value":"all"},{"label":"None","value":"none"},{"label":"Custom Group","value":"selected"}]}
            {"type":"textField","name":"standards.MDMScope.customGroup","label":"Custom Group Name","required":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-02-18
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/intune-standards#low-impact
    #>

    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000?$expand=includedGroups' -tenantid $Tenant

    $StateIsCorrect =   ($CurrentInfo.termsOfUseUrl -eq 'https://portal.manage.microsoft.com/TermsofUse.aspx') -and
                        ($CurrentInfo.discoveryUrl -eq 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc') -and
                        ($CurrentInfo.complianceUrl -eq 'https://portal.manage.microsoft.com/?portalAction=Compliance') -and
                        ($CurrentInfo.appliesTo -eq $Settings.appliesTo) -and
                        ($Settings.appliesTo -ne 'selected' -or ($CurrentInfo.includedGroups.displayName -contains $Settings.customGroup))

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MDM Scope already correctly configured' -sev Info
        } else {
            $GraphParam = @{
                tenantid = $tenant
                Uri = 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000'
                ContentType = 'application/json; charset=utf-8'
                asApp = $false
                type = 'PATCH'
                AddedHeaders = @{'Accept-Language' = 0 }
                Body = @{
                    'termsOfUseUrl' = 'https://portal.manage.microsoft.com/TermsofUse.aspx'
                    'discoveryUrl' = 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc'
                    'complianceUrl' = 'https://portal.manage.microsoft.com/?portalAction=Compliance'
                } | ConvertTo-Json
            }

            try {
                New-GraphPostRequest @GraphParam
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully configured MDM Scope' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to configure MDM Scope." -sev Error -LogData $ErrorMessage
            }

            # Workaround for MDM Scope Assignment error: "Could not set MDM Scope for [TENANT]: Simultaneous patch requests on both the appliesTo and URL properties are currently not supported."
            if ($Settings.appliesTo -ne 'selected') {
                $GraphParam = @{
                    tenantid = $tenant
                    Uri = 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000'
                    ContentType = 'application/json; charset=utf-8'
                    asApp = $false
                    type = 'PATCH'
                    AddedHeaders = @{'Accept-Language' = 0 }
                    Body = @{
                        'appliesTo' = $Settings.appliesTo
                    } | ConvertTo-Json
                }

                try {
                    New-GraphPostRequest @GraphParam
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully assigned $($Settings.appliesTo) to MDM Scope" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to assign $($Settings.appliesTo) to MDM Scope." -sev Error -LogData $ErrorMessage
                }
            } else {
                $GroupID = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=id,displayName&`$filter=displayName eq '$($Settings.customGroup)'" -tenantid $tenant -asApp $true).id
                $GraphParam = @{
                    tenantid = $tenant
                    Uri = 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000/includedGroups/$ref'
                    ContentType = 'application/json; charset=utf-8'
                    asApp = $false
                    type = 'POST'
                    AddedHeaders = @{'Accept-Language' = 0 }
                    Body = @{
                        '@odata.id' = "https://graph.microsoft.com/odata/groups('$GroupID')"
                    } | ConvertTo-Json
                }

                try {
                    New-GraphPostRequest @GraphParam
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully assigned $($Settings.customGroup) to MDM Scope" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to assign $($Settings.customGroup) to MDM Scope" -sev Error -LogData $ErrorMessage
                }
            }
        }
    }

    if ($Settings.alert -eq $true -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MDM Scope is correctly configured' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MDM Scope is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'MDMScope' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
