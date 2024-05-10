function Invoke-CIPPStandardSafeAttachmentPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $PolicyName = 'Default Safe Attachment Policy'

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentPolicy' |
        Where-Object -Property Name -EQ $PolicyName |
        Select-Object Name, Enable, Action, QuarantineTag, Redirect, RedirectAddress

    $StateIsCorrect = ($CurrentState.Name -eq $PolicyName) -and
                      ($CurrentState.Enable -eq $true) -and
                      ($CurrentState.QuarantineTag -eq $Settings.QuarantineTag) -and
                      ($CurrentState.Redirect -eq $Settings.Redirect) -and
                      (($null -eq $Settings.RedirectAddress) -or ($CurrentState.RedirectAddress -eq $Settings.RedirectAddress))

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy already correctly configured' -sev Info
        } else {
            $cmdparams = @{
                Enable          = $true
                QuarantineTag   = $Settings.QuarantineTag
                Redirect        = $Settings.Redirect
                RedirectAddress = $Settings.RedirectAddress
            }

            try {
                if ($CurrentState.Name -eq $PolicyName) {
                    $cmdparams.Add('Identity', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Safe Attachment Policy' -sev Info
                } else {
                    $cmdparams.Add('Name', $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Safe Attachment Policy' -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment Policy. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}