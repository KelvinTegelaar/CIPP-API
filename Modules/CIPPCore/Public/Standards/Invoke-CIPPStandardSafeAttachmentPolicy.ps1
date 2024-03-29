function Invoke-CIPPStandardSafeAttachmentPolicy {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $SafeAttachmentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeAttachmentPolicy' | 
    Where-Object -Property Name -eq $PolicyName | 
    Select-Object Name, Enable, Action, QuarantineTag, Redirect, RedirectAddress

    $PolicyName = "Default Safe Attachment Policy"
    $StateIsCorrect = if (
        ($SafeAttachmentState.Name -eq $PolicyName) -and
        ($SafeAttachmentState.Enable -eq $true) -and
        ($SafeAttachmentState.QuarantineTag -eq $Settings.QuarantineTag) -and
        ($SafeAttachmentState.Redirect -eq $Settings.Redirect) -and
        ($SafeAttachmentState.RedirectAddress -eq $Settings.RedirectAddress)
    ) { $true } else { $false }

    if ($Settings.remediate) {
        
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy already exists.' -sev Info
        } else {
            $cmdparams = @{
                Enable = $true
                QuarantineTag = $Settings.QuarantineTag
                Redirect = $Settings.Redirect
                RedirectAddress = $Settings.RedirectAddress
            }

            try {
                if ($SafeAttachmentState.Name -eq $PolicyName) {
                    $cmdparams.Add("Identity", $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeAttachmentPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Safe Attachment Policy' -sev Info
                } else {
                    $cmdparams.Add("Name", $PolicyName)
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeAttachmentPolicy' -cmdparams $cmdparams
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Created Safe Attachment Policy' -sev Info
                }
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Safe Attachment Policy. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Safe Attachment Policy is not enabled' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SafeAttachmentPolicy' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant
    }
    
}