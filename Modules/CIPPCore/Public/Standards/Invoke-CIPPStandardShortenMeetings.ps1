function Invoke-CIPPStandardShortenMeetings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ShortenMeetings
    .SYNOPSIS
        (Label) Set shorten meetings state
    .DESCRIPTION
        (Helptext) Sets the shorten meetings settings on a tenant level. This will shorten meetings by the selected amount of minutes. Valid values are 0 to 29. Short meetings are under 60 minutes, long meetings are over 60 minutes.
        (DocsDescription) Sets the shorten meetings settings on a tenant level. This will shorten meetings by the selected amount of minutes. Valid values are 0 to 29. Short meetings are under 60 minutes, long meetings are over 60 minutes.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.ShortenMeetings.ShortenEventScopeDefault","options":[{"label":"Disabled/None","value":"None"},{"label":"End early","value":"EndEarly"},{"label":"Start late","value":"StartLate"}]}
            {"type":"number","name":"standards.ShortenMeetings.DefaultMinutesToReduceShortEventsBy","label":"Minutes to reduce short calendar events by (Default is 5)","defaultValue":5}
            {"type":"number","name":"standards.ShortenMeetings.DefaultMinutesToReduceLongEventsBy","label":"Minutes to reduce long calendar events by (Default is 10)","defaultValue":10}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-05-27
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -ShortenEventScopeDefault -DefaultMinutesToReduceShortEventsBy -DefaultMinutesToReduceLongEventsBy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>

    param($Tenant, $Settings)
    Write-Host "ShortenMeetings: $($Settings | ConvertTo-Json -Compress)"
    # Get state value using null-coalescing operator
    $scopeDefault = $Settings.ShortenEventScopeDefault.value ? $Settings.ShortenEventScopeDefault.value : $Settings.ShortenEventScopeDefault

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | Select-Object -Property ShortenEventScopeDefault, DefaultMinutesToReduceShortEventsBy, DefaultMinutesToReduceLongEventsBy
    $CorrectState = if ($CurrentState.ShortenEventScopeDefault -eq $scopeDefault -and
        $CurrentState.DefaultMinutesToReduceShortEventsBy -eq $Settings.DefaultMinutesToReduceShortEventsBy -and
        $CurrentState.DefaultMinutesToReduceLongEventsBy -eq $Settings.DefaultMinutesToReduceLongEventsBy) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CorrectState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Shorten meetings settings are already in the correct state. ' -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ShortenEventScopeDefault = $scopeDefault ; DefaultMinutesToReduceShortEventsBy = $Settings.DefaultMinutesToReduceShortEventsBy; DefaultMinutesToReduceLongEventsBy = $Settings.DefaultMinutesToReduceLongEventsBy }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Shorten meetings settings have been set to the following state. State: $($scopeDefault), Short:$($Settings.DefaultMinutesToReduceShortEventsBy), Long: $($Settings.DefaultMinutesToReduceLongEventsBy)" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set shorten meetings settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CorrectState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Shorten meetings settings are already in the correct state. Current state: $($CurrentState.ShortenEventScopeDefault), Short:$($CurrentState.DefaultMinutesToReduceShortEventsBy), Long: $($CurrentState.DefaultMinutesToReduceLongEventsBy)" -sev Info
        } else {
            Write-StandardsAlert -message 'Shorten meetings settings are not in the correct state.' -object $CurrentState -tenant $Tenant -standardName 'ShortenMeetings' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Shorten meetings settings are not in the correct state. Current state: $($CurrentState.ShortenEventScopeDefault), Short:$($CurrentState.DefaultMinutesToReduceShortEventsBy), Long: $($CurrentState.DefaultMinutesToReduceLongEventsBy)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $BPAField = @{
            FieldName  = 'ShortenMeetings'
            FieldValue = $CorrectState
            Tenant     = $Tenant
        }

        if ($CorrectState -eq $true) {
            Add-CIPPBPAField @BPAField -StoreAs bool
        } else {
            Add-CIPPBPAField @BPAField -StoreAs json
        }

        if ($CorrectState -eq $true) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.ShortenMeetings' -FieldValue $FieldValue -Tenant $Tenant
    }
}
