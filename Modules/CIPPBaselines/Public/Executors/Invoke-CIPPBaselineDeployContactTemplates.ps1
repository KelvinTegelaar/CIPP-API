function Invoke-CIPPBaselineDeployContactTemplates {
    <#
    .SYNOPSIS
        DeployContactTemplates executor: creates the mail contact or brings it in line.
    .DESCRIPTION
        Create is the classic's two-pass write: New-MailContact carries only the identity
        fields (display name, email, first/last name), then Set-Contact and Set-MailContact
        apply the extended properties - Exchange rejects them on the New- call.

        Update writes the same property sets against the existing contact. Template fields
        with no value are never written, mirroring the compare: an empty template field
        expresses no opinion and must not blank operator data. hidefromGAL is boolean and
        is always written on update so it can be turned OFF as well as on - the compare
        grades it in both directions.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Template = $Current.templateBody
    if (-not $Template) { return }
    $ContactName = "$($Template.displayName)"

    if ($Current.deployed -eq $true) {
        $Identity = "$($Current.existingContact.Identity)"
    } else {
        $NewParams = @{
            displayName          = $ContactName
            name                 = $ContactName
            ExternalEmailAddress = "$($Template.email)"
        }
        if (-not [string]::IsNullOrWhiteSpace("$($Template.firstName)")) { $NewParams.FirstName = "$($Template.firstName)" }
        if (-not [string]::IsNullOrWhiteSpace("$($Template.lastName)")) { $NewParams.LastName = "$($Template.lastName)" }
        $NewContact = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-MailContact' -cmdParams $NewParams -UseSystemMailbox $true
        $Identity = "$($NewContact.Identity ?? $ContactName)"
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created mail contact '$ContactName'." -Sev 'Info'
    }

    if ($Current.deployed -eq $true) {
        # Email and names live on different cmdlets; write both like the classic did.
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailContact' -cmdParams @{
            Identity             = $Identity
            ExternalEmailAddress = "$($Template.email)"
        } -UseSystemMailbox $true
        $NameParams = @{ Identity = $Identity }
        if (-not [string]::IsNullOrWhiteSpace("$($Template.firstName)")) { $NameParams.FirstName = "$($Template.firstName)" }
        if (-not [string]::IsNullOrWhiteSpace("$($Template.lastName)")) { $NameParams.LastName = "$($Template.lastName)" }
        if ($NameParams.Count -gt 1) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Contact' -cmdParams $NameParams -UseSystemMailbox $true
        }
    }

    # Extended properties: only the ones the template specifies.
    $SetContactParams = @{ Identity = $Identity }
    $PropertyMap = @{
        'Company'         = $Template.companyName
        'StateOrProvince' = $Template.state
        'StreetAddress'   = $Template.streetAddress
        'Phone'           = $Template.businessPhone
        'WebPage'         = $Template.website
        'Title'           = $Template.jobTitle
        'City'            = $Template.city
        'PostalCode'      = $Template.postalCode
        'CountryOrRegion' = $Template.country
        'MobilePhone'     = $Template.mobilePhone
    }
    foreach ($Property in $PropertyMap.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace("$($Property.Value)")) { $SetContactParams[$Property.Key] = "$($Property.Value)" }
    }
    if ($SetContactParams.Count -gt 1) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Contact' -cmdParams $SetContactParams -UseSystemMailbox $true
    }

    $MailContactParams = @{ Identity = $Identity }
    $MailContactParams.HiddenFromAddressListsEnabled = [bool]$Template.hidefromGAL
    if (-not [string]::IsNullOrWhiteSpace("$($Template.mailTip)")) { $MailContactParams.MailTip = "$($Template.mailTip)" }
    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailContact' -cmdParams $MailContactParams -UseSystemMailbox $true

    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied contact template to '$ContactName'." -Sev 'Info'
}
