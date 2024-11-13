Function Invoke-CIPPStandardTeamsEnrollUser {
    <#
    .FUNCTIONALITY
        Internal
    #>

    param($Tenant, $Settings)

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsMeetingPolicy' -CmdParams @{Identity = 'Global' }
    | Select-Object EnrollUserOverride

    if ($null -eq $Settings.EnrollUserOverride) { $Settings.EnrollUserOverride = $CurrentState.EnrollUserOverride }

    $StateIsCorrect = ($CurrentState.EnrollUserOverride -eq $Settings.EnrollUserOverride)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Teams Enroll User Override settings already set to $($Settings.EnrollUserOverride)." -sev Info
        } else {
            $cmdparams = @{
                Identity           = 'Global'
                EnrollUserOverride = $Settings.EnrollUserOverride
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsMeetingPolicy' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Teams Enroll User Override setting to $($Settings.EnrollUserOverride)." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Enroll User Override setting to $($Settings.EnrollUserOverride)." -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Enroll User Override settings is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Enroll User Override settings is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsEnrollUser' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
