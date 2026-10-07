function Invoke-CIPPBaselineRetentionPolicyTag {
    <#
    .SYNOPSIS
        RetentionPolicyTag executor: upserts the CIPP Deleted Items tag and links it into
        the Default MRM Policy.
    .DESCRIPTION
        Two writes, both the classic's: Set- when the tag exists, New- (with the fixed
        DeletedItems type) otherwise; then the MRM policy link, which must resend the FULL
        existing link list with ours appended - Set-RetentionPolicy replaces the whole list,
        and sending only the new tag would unlink every other retention tag in the tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $TagName = 'CIPP Deleted Items'
    $Params = @{
        RetentionEnabled     = $true
        AgeLimitForRetention = [int]"$($Remediate.ageLimitForRetention)"
        RetentionAction      = 'PermanentlyDelete'
    }
    if ($Current.tagExists -eq $true) {
        $Params['Identity'] = $TagName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionPolicyTag' -cmdParams $Params -useSystemMailbox $true
    } else {
        $Params['Name'] = $TagName
        $Params['Type'] = 'DeletedItems'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionPolicyTag' -cmdParams $Params -useSystemMailbox $true
    }

    if ($Current.linkedToPolicy -ne $true) {
        $Links = @(@($Current.existingLinks | Where-Object { $_ }) + $TagName)
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionPolicy' -cmdParams @{
            Identity = 'Default MRM Policy'; RetentionPolicyTagLinks = $Links
        } -useSystemMailbox $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied the $TagName retention tag at $($Params.AgeLimitForRetention) days." -Sev 'Info'
}
