function Invoke-CIPPStandardUserPreferredLanguage {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) UserPreferredLanguage
    .SYNOPSIS
        (Label) Preferred language for all users
    .DESCRIPTION
        (Helptext) Sets the preferred language property for all users in the tenant. This will override the user's language settings.
        (DocsDescription) Sets the preferred language property for all users in the tenant. This will override the user's language settings.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.UserPreferredLanguage.preferredLanguage","label":"Preferred Language","api":{"url":"/languageList.json","labelField":"language","valueField":"tag"}}
        IMPACT
            High Impact
        ADDEDDATE
            2025-02-26
        POWERSHELLEQUIVALENT
            Update-MgUser -UserId user@domain.com -BodyParameter @{preferredLanguage='en-US'}
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)

    $preferredLanguage = $Settings.preferredLanguage.value
    $IncorrectUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=userPrincipalName,displayName,preferredLanguage,userType,onPremisesSyncEnabled&`$filter=preferredLanguage ne '$preferredLanguage' and userType eq 'Member' and onPremisesSyncEnabled ne true&`$count=true&ConsistencyLevel=eventual" -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        if (($IncorrectUsers | Measure-Object).Count -gt 0) {
            try {
                ForEach ($user in $IncorrectUsers) {
                    $cmdparams = @{
                        tenantid    = $Tenant
                        uri         = "https://graph.microsoft.com/beta/users/$($user.userPrincipalName)"
                        AsApp       = $true
                        Type        = 'PATCH'
                        Body        = @{
                            preferredLanguage = $preferredLanguage
                        } | ConvertTo-Json
                        ContentType = 'application/json; charset=utf-8'
                    }
                    $null = New-GraphPOSTRequest @cmdparams
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Preferred language for $($user.userPrincipalName) has been set to $preferredLanguage" -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set preferred language to $preferredLanguage for all users." -sev Error -LogData $ErrorMessage
            }
        }
    }

    If ($Settings.alert -eq $true) {
        if (($IncorrectUsers.userPrincipalName | Measure-Object).Count -gt 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The following accounts do not have the preferred language set to $preferredLanguage : $($IncorrectUsers.userPrincipalName -join ', ')" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No accounts do not have the preferred language set to the preferred language' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'IncorrectUsers' -FieldValue $IncorrectUsers -StoreAs json -Tenant $tenant
    }
}
