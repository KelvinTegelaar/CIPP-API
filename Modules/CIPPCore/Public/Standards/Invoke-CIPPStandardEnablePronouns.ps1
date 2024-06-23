function Invoke-CIPPStandardEnablePronouns {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param ($Tenant, $Settings)

    $Uri = 'https://graph.microsoft.com/v1.0/admin/people/pronouns'
    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get CurrentState for Pronouns. Error: $ErrorMessage" -sev Error
        Return
    }
    Write-Host $CurrentState

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are already enabled.' -sev Info
        } else {
            $CurrentState.isEnabledInOrganization = $true
            try {
                $Body = ConvertTo-Json -InputObject $CurrentState -Depth 10 -Compress
                New-GraphPostRequest -Uri $Uri -tenantid $Tenant -Body $Body -type PATCH
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled pronouns.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable pronouns. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'PronounsEnabled' -FieldValue $CurrentState.isEnabledInOrganization -StoreAs bool -Tenant $tenant
    }
}
